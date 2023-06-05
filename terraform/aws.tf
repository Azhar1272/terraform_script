resource "aws_s3_bucket" "data_transfer_bucket" {
  bucket = "data-transfer-nexgen-snowpipe-${lower(var.ENV_NAME)}"
  tags = {
    CreatedBy = "Terraform"
  }

}

###############################################
# VARIABLE Settings defined per-environment
############################################
# Environments: prod, sandbox

locals {
  RDS_INSTANCE_NAME = lower(var.ENV_NAME) == "prod" ? "nexgen" : "nexgen-asm"
  # RDS_SECRET_PREFIX = lower(var.ENV_NAME) == "prod" ? "dms_user" : "nexgen-asm"
  
  # DMS Replication instance class:
  # Production: initial load, successfully tested with dms.c5.2xlarge -> Anything lower will throw OOM errors
  # Production: CDC only, successfully tested with dms.t3.medium
  replication_instance_class_val  = lower(var.ENV_NAME) == "prod" ? "dms.t3.medium" : "dms.t3.medium"  # dms.c5.2xlarge for prod initial load

}

# data "aws_vpc" "default" {
#   default = true
# }

# data "aws_subnet" "default" {
#   filter {
#     name   = "vpc-id"
#     values = [data.aws_vpc.default.id]
#   }

#   filter {
#     name   = "default-for-az"
#     values = ["true"]
#   }
# }

# Fetch RDS instance information
data "aws_db_instance" "nexgen_asm" {
  db_instance_identifier = "${local.RDS_INSTANCE_NAME}"
}

# Fetch DB Subnet Group information
data "aws_db_subnet_group" "default" {
  name = data.aws_db_instance.nexgen_asm.db_subnet_group
}

# Fetch VPC information
data "aws_vpc" "default" {
  id = data.aws_db_subnet_group.default.vpc_id
}

data "aws_subnet" "default" {
  for_each = toset(data.aws_db_subnet_group.default.subnet_ids)
  id       = each.key
}

resource "aws_dms_replication_subnet_group" "default" {
  replication_subnet_group_id          = "custom"
  replication_subnet_group_description = "Custom DMS replication subnet group"
  subnet_ids                           = [for s in data.aws_subnet.default : s.id]

  tags = {
    CreatedBy = "Terraform"
  }

}

resource "aws_security_group" "dms_sg" {
  name        = "dms_sg"
  description = "Security group for DMS replication instance"
  # TODO: Change this and put a precise port here: 3306?

  # vpc_id = data.aws_vpc.default.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "dms_sg"
    CreatedBy = "Terraform"
  }
}



resource "aws_dms_replication_instance" "nexgen_replication" {
  replication_instance_id          = "nexgen-replication-instance"
  replication_instance_class       = local.replication_instance_class_val
  allocated_storage                = 500
  multi_az                         = false
  publicly_accessible              = true
  vpc_security_group_ids           = [aws_security_group.dms_sg.id]
  replication_subnet_group_id      = aws_dms_replication_subnet_group.default.id
  apply_immediately                = true
  auto_minor_version_upgrade       = true
  preferred_maintenance_window     = "sun:10:30-sun:14:30"
  tags = {
    CreatedBy = "Terraform"
  }
}


data "aws_secretsmanager_secret_version" "mysql_creds_secret" {
  secret_id = "dms_user/${local.RDS_INSTANCE_NAME}/MySQL"
}


# Decommissioned this in favor of secret hardcoding
#########

# data "aws_secretsmanager_secret_version" "mysql_creds_secret" {
#   secret_id = "RW/${local.RDS_INSTANCE_NAME}/MySQL"
# }

# resource "aws_dms_endpoint" "source" {
#   endpoint_id                 = "${local.RDS_INSTANCE_NAME}-endpoint"
#   endpoint_type               = "source"
#   engine_name                 = "mysql"
#   database_name               = "nexgen"
#   ssl_mode                    = "none"
#   secrets_manager_arn         = data.aws_secretsmanager_secret_version.mysql_creds_secret.arn
#   secrets_manager_access_role_arn = aws_iam_role.dms.arn
#   tags = {
#     CreatedBy = "Terraform"
#   }

# }



resource "aws_dms_endpoint" "source" {
  endpoint_id                 = "${local.RDS_INSTANCE_NAME}-endpoint"
  endpoint_type               = "source"
  engine_name                 = jsondecode(data.aws_secretsmanager_secret_version.mysql_creds_secret.secret_string).engine
  database_name               = jsondecode(data.aws_secretsmanager_secret_version.mysql_creds_secret.secret_string).dbname
  ssl_mode                    = "none"
  username                    = jsondecode(data.aws_secretsmanager_secret_version.mysql_creds_secret.secret_string).username
  password                    = jsondecode(data.aws_secretsmanager_secret_version.mysql_creds_secret.secret_string).password
  server_name                 = jsondecode(data.aws_secretsmanager_secret_version.mysql_creds_secret.secret_string).host
  port                        = 3306

  tags = {
    CreatedBy = "Terraform"
  }
}


resource "aws_dms_endpoint" "target" {
  endpoint_id   = "data-transfer-nexgen-${aws_s3_bucket.data_transfer_bucket.bucket}"
  endpoint_type = "target"
  engine_name   = "s3"

  s3_settings {
    service_access_role_arn = aws_iam_role.dms_s3_access.arn
    bucket_name             = aws_s3_bucket.data_transfer_bucket.bucket
    timestamp_column_name   = replace("updated_${aws_s3_bucket.data_transfer_bucket.bucket}", "-", "_")
    date_partition_enabled = false
    # date_partition_sequence = "YYYYMMDD"
    # date_partition_delimiter = "SLASH"
    data_format = "parquet"
    compression_type = "GZIP"
    parquet_version = "parquet-2-0"
    preserve_transactions = false
    cdc_path = false
  }
  tags = {
    CreatedBy = "Terraform"
  }

}

# Create an S3 event notification that triggers the SQS queue
resource "aws_s3_bucket_notification" "s3_snowpipe_sqs_notification" {
  bucket = aws_s3_bucket.data_transfer_bucket.bucket

  queue {
    queue_arn = var.SNOWFLAKE_EXTERNAL_SQS_ARN
    events    = ["s3:ObjectCreated:*"]
    filter_prefix = "nexgen/"
    filter_suffix = ".parquet"
  }
}


resource "aws_cloudwatch_log_group" "dms_replication_task" {
  name = "/aws/dms/replication-task/nexgen-to-s3"
}



resource "aws_dms_replication_task" "migration_task" {
  replication_task_id          = "nexgen-to-s3"
  migration_type               = "full-load-and-cdc"
  replication_instance_arn     = aws_dms_replication_instance.nexgen_replication.replication_instance_arn
  source_endpoint_arn          = aws_dms_endpoint.source.endpoint_arn
  target_endpoint_arn          = aws_dms_endpoint.target.endpoint_arn
  replication_task_settings    = file("migration_settings.json")
  table_mappings               = file("dms_dynamic_table_mapping.json")
  start_replication_task = true
  # timestamp_column_name = "updated"
  # change_processing_tuning {
  #   timestamp_column_name = "updated"
  # }

  tags = {
    CreatedBy = "Terraform"
  }

  # table_mappings = jsonencode({
  #   rules = [
  #     {
  #       rule_type = "selection"
  #       rule_action = "include"
  #       object_locators = [
  #         {
  #           schema_name = "%"
  #           table_name = "%"
  #         }
  #       ]
  #     }
  #   ]
  # })

}

resource "aws_iam_role" "dms" {
  name = "dms_role_nexgen"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
      },
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dms.${lower(var.AWS_DEFAULT_REGION)}.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "dms_policy" {
  name = "dms_policy_nexgen"

  role = aws_iam_role.dms.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "rds:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:*"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = ["*"]
        Effect   = "Allow"
        Resource = "${data.aws_secretsmanager_secret_version.mysql_creds_secret.arn}"
      },
      {
        Action = [
          "s3:*"
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.data_transfer_bucket.arn,
          "${aws_s3_bucket.data_transfer_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role" "dms_s3_access" {
  name = "dms_s3_access_nexgen"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dms.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "dms_s3_access_policy" {
  name = "dms_s3_access_policy_nexgen"

  role = aws_iam_role.dms_s3_access.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
          "s3:ListMultipartUploadParts",
          "s3:GetObject",
          "s3:PutObject",
          "s3:AbortMultipartUpload",
          "s3:DeleteObject"
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.data_transfer_bucket.arn,
          "${aws_s3_bucket.data_transfer_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Create the ECR repo
resource "aws_ecr_repository" "snowpipe_scheduling" {
  name = "snowpipe-scheduling"
  tags = {
    CreatedBy = "Terraform"
  }

}


# Create the AWS IAM Snowflake S3 access user + rights
resource "aws_iam_user" "snowflake_s3_access_user" {
  name = "snowflake-s3-access-user"
}

resource "aws_iam_policy" "s3_access_policy" {
  name        = "s3_access_policy"

  description = "Allows full read access to the S3 bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "s3:Get*",
          "s3:List*",
          "s3:HeadBucket"
        ]
        Resource = [
          "${aws_s3_bucket.data_transfer_bucket.arn}",
          "${aws_s3_bucket.data_transfer_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "s3_access_policy_attachment" {
  user       = aws_iam_user.snowflake_s3_access_user.name

  policy_arn = aws_iam_policy.s3_access_policy.arn
}

# Create and generate a key pair
resource "aws_iam_access_key" "snowflake_s3_access_key" {
  user = aws_iam_user.snowflake_s3_access_user.name

}

resource "aws_secretsmanager_secret" "snowflake_s3_access_secret" {
  name = "snowflake-s3-access-user-keys"
  tags = {
    CreatedBy = "Terraform"
  }

}

resource "aws_secretsmanager_secret_version" "snowflake_s3_access_secret_version" {
  secret_id     = aws_secretsmanager_secret.snowflake_s3_access_secret.id
  secret_string = jsonencode({
    access_key     = aws_iam_access_key.snowflake_s3_access_key.id,
    access_secret  = aws_iam_access_key.snowflake_s3_access_key.secret
  })
}

###########
# LAMBDA
###########

variable "SENTRY_DSN" {
  description = "Sentry Monitoring DSN"
  default = ""
}


resource "aws_iam_role" "lambda_role" {

  tags = {
    CreatedBy = "Terraform"
  }

  name = "snowpipe-scheduling-${var.ENV_NAME}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_role_policy" {
  name = "snowpipe-scheduling-${var.ENV_NAME}-policy"
  role = aws_iam_role.lambda_role.id

  # tags = {
  #   CreatedBy = "Terraform"
  # }


  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:Get*",
          "secretsmanager:Describe*",
          "secretsmanager:List*"
        ]
        Resource = [
          "${aws_secretsmanager_secret.snowflake_params.arn}",
          "${aws_secretsmanager_secret.snowflake_s3_access_secret.arn}",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:List*",
          "s3:Describe*",
          "s3:Get*",
          "s3:Read*"
        ]
        Resource = [
          "${aws_s3_bucket.data_transfer_bucket.arn}",
          "${aws_s3_bucket.data_transfer_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "snowpipe_scheduling" {
  function_name = "snowpipe-scheduling-function"
  role          = aws_iam_role.lambda_role.arn
  timeout       = 900
  memory_size   = 256
  package_type  = "Image"
  reserved_concurrent_executions = 1
  image_uri = "${aws_ecr_repository.snowpipe_scheduling.repository_url}:latest"

  environment {
    variables = {
      SECRET_NAME_SNOWFLAKE = "${aws_secretsmanager_secret.snowflake_params.name}",
      S3_LAMBDA_SECRET = "${aws_secretsmanager_secret.snowflake_s3_access_secret.name}",
      S3_BUCKET = aws_s3_bucket.data_transfer_bucket.bucket,
      S3_PREFIX = "nexgen/",
      SENTRY_DSN = var.SENTRY_DSN,
    }
  }

  tags = {
    CreatedBy = "Terraform"
  }
  depends_on = [aws_ecr_repository.snowpipe_scheduling]

}

resource "aws_lambda_function_event_invoke_config" "snowpipe_scheduling_invoke" {
  function_name                = aws_lambda_function.snowpipe_scheduling.function_name
  maximum_retry_attempts       = 0
}

resource "aws_cloudwatch_event_rule" "lambda_hourly_rule" {
  name        = "hourly-rule"
  description = "Event rule that triggers every hour to trigger the lambda"

  # schedule_expression = "cron(0 * * * ? *)" # hourly
  schedule_expression = "cron(0 */3 * * ? *)"
  # schedule_expression = "cron(0 * ? * * *)"
  tags = {
    CreatedBy = "Terraform"
  }

}

resource "aws_cloudwatch_event_target" "lambda_hourly_rule_target" {
  rule      = aws_cloudwatch_event_rule.lambda_hourly_rule.name
  target_id = "hourly-rule-target"

  arn = aws_lambda_function.snowpipe_scheduling.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snowpipe_scheduling.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_hourly_rule.arn
}


resource "aws_iam_user" "github_actions_user" {
  name = "github_actions_user"
  tags = {
    CreatedBy = "Terraform"
  }

}

resource "aws_iam_access_key" "github_actions_user_key" {
  user = aws_iam_user.github_actions_user.name
}

resource "aws_iam_user_policy" "github_actions_user_ecr_policy" {
  name = "github_actions_user_ecr_policy"
  user = aws_iam_user.github_actions_user.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:Batch*",
          "ecr:Put*",
          "ecr:Initiate*",
          "ecr:Upload*",
          "ecr:Complete*",
        ]
        Effect   = "Allow"
        Resource = aws_ecr_repository.snowpipe_scheduling.arn
      },
      {
        Action = [
          "ecr:Get*",
          "ecr:List*",
          "ecr:Describe*",
          "lambda:Update*",
        ]
        Effect   = "Allow"
        Resource = "*"
      },


    ]
  })
}


resource "aws_secretsmanager_secret" "github_actions_user_secret" {
  name = "github_actions_user"
  tags = {
    CreatedBy = "Terraform"
  }
}

resource "aws_secretsmanager_secret_version" "github_actions_user_secret_version" {
  secret_id     = aws_secretsmanager_secret.github_actions_user_secret.id
  secret_string = jsonencode({
    aws_access_key_id     = aws_iam_access_key.github_actions_user_key.id
    aws_secret_access_key = aws_iam_access_key.github_actions_user_key.secret
  })
}