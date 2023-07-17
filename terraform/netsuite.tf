## create s3 bucket
resource "aws_s3_bucket" "netsuite_staging_bucket" {
  bucket = "netsuite-data-staging-${lower(var.ENV_NAME)}"
  tags = {
    CreatedBy = "Terraform"
  }
}

/*
## create script folder under s3 bucket
resource "aws_s3_object" "object" {
  bucket = aws_s3_bucket.netsuite_staging_bucket.id
  key    = "script/"
}
*/


## create secret manager
resource "aws_secretsmanager_secret" "create_secretmanger_netsuite" {
  name = "netsuite/credentials"
}

## create Glue catalog Database
resource "aws_glue_catalog_database" "create_database_netsuite" {
  name = "netsuite"
}

## create Glue job
resource "aws_glue_job" "create_gluejob_netsuite" {
  name         = "netsuite-get-restApi"
  role_arn     = aws_iam_role.create_iam_role_glue_netsuite.arn
  max_capacity = 0.0625
  max_retries = 3
  command {
    script_location = "s3://data-glue-assets-dev/netsuite-get-restApi.py"
    name            = "pythonshell"
    python_version  = "3.9"
  }

  execution_property {
    max_concurrent_runs = 99
  }
  default_arguments = {
    "--region"          = var.AWS_DEFAULT_REGION
    "--secretmanager"   = "netsuite/credentials"
    "--additional-python-modules" = "sentry-sdk, requests_oauthlib"
    "--fullload" = 0
    "--python-modules-installer-option" = "--upgrade"
  }

}

## Create Glue job IAM role
resource "aws_iam_role" "create_iam_role_glue_netsuite" {
  name = "netsuite-glue-role"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "",
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "glue.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
      }]
    }
  )
}

## Attach policies to Glue IAM role: s3, firehose, secret mngr, cloudwatch, glue
resource "aws_iam_role_policy_attachment" "secret_manger_access_to_glue" {
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  role       = aws_iam_role.create_iam_role_glue_netsuite.name
}
resource "aws_iam_role_policy_attachment" "Kinesis_full_access_to_glue" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonKinesisFirehoseFullAccess"
  role       = aws_iam_role.create_iam_role_glue_netsuite.name
}
resource "aws_iam_role_policy_attachment" "s3_full_access_to_glue" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.create_iam_role_glue_netsuite.name
}
resource "aws_iam_role_policy_attachment" "cloudwatch_full_access_to_glue" {
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
  role       = aws_iam_role.create_iam_role_glue_netsuite.name
}
resource "aws_iam_role_policy_attachment" "glue_full_access_to_glue" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  role       = aws_iam_role.create_iam_role_glue_netsuite.name
}

## Create firehose for customer
resource "aws_kinesis_firehose_delivery_stream" "create_firehose_customer_netsuite" {
  name        = "netsuite-data-ingestion-customer"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.create_iam_role_fireshose_netsuite.arn
    bucket_arn          = aws_s3_bucket.netsuite_staging_bucket.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "output/customer/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/customer/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    data_format_conversion_configuration {
      schema_configuration {
        catalog_id    = ""
        database_name = aws_glue_catalog_database.create_database_netsuite.name
        table_name    = aws_glue_catalog_table.create_table_customer_netsuite.name
        region        = var.AWS_DEFAULT_REGION
        version_id    = "LATEST"
        role_arn      = aws_iam_role.create_iam_role_fireshose_netsuite.arn
      }
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {
            # Optional configurations for JSON deserialization
            # For example, "case_insensitive" = "false"
          }
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression                   = "SNAPPY"
            enable_dictionary_compression = true
            # Optional configurations for Parquet serialization
          }
        }
      }
    }
  }
}

## Create firehose for purchaseorder
resource "aws_kinesis_firehose_delivery_stream" "create_firehose_purchaseorder_netsuite" {
  name        = "netsuite-data-ingestion-purchaseorder"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.create_iam_role_fireshose_netsuite.arn
    bucket_arn          = aws_s3_bucket.netsuite_staging_bucket.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "output/purchaseorder/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/purchaseorder/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    data_format_conversion_configuration {
      schema_configuration {
        catalog_id    = ""
        database_name = aws_glue_catalog_database.create_database_netsuite.name
        table_name    = aws_glue_catalog_table.create_table_purchaseorder_netsuite.name
        region        = var.AWS_DEFAULT_REGION
        version_id    = "LATEST"
        role_arn      = aws_iam_role.create_iam_role_fireshose_netsuite.arn
      }
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {
            # Optional configurations for JSON deserialization
            # For example, "case_insensitive" = "false"
          }
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression                   = "SNAPPY"
            enable_dictionary_compression = true
            # Optional configurations for Parquet serialization
          }
        }
      }
    }
  }
}

## create firehose for subsidiary
resource "aws_kinesis_firehose_delivery_stream" "create_firehose_subsidiary_netsuite" {
  name        = "netsuite-data-ingestion-subsidiary"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.create_iam_role_fireshose_netsuite.arn
    bucket_arn          = aws_s3_bucket.netsuite_staging_bucket.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "output/subsidiary/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/subsidiary/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    data_format_conversion_configuration {
      schema_configuration {
        catalog_id    = ""
        database_name = aws_glue_catalog_database.create_database_netsuite.name
        table_name    = aws_glue_catalog_table.create_table_subsidiary_netsuite.name
        region        = var.AWS_DEFAULT_REGION
        version_id    = "LATEST"
        role_arn      = aws_iam_role.create_iam_role_fireshose_netsuite.arn
      }
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {
            # Optional configurations for JSON deserialization
            # For example, "case_insensitive" = "false"
          }
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression                   = "SNAPPY"
            enable_dictionary_compression = true
            # Optional configurations for Parquet serialization
          }
        }
      }
    }
  }
}

## Create firehose for creditmemo
resource "aws_kinesis_firehose_delivery_stream" "create_firehose_creditmemo_netsuite" {
  name        = "netsuite-data-ingestion-creditmemo"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.create_iam_role_fireshose_netsuite.arn
    bucket_arn          = aws_s3_bucket.netsuite_staging_bucket.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "output/creditmemo/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/creditmemo/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    data_format_conversion_configuration {
      schema_configuration {
        catalog_id    = ""
        database_name = aws_glue_catalog_database.create_database_netsuite.name
        table_name    = aws_glue_catalog_table.create_table_creditmemo_netsuite.name
        region        = var.AWS_DEFAULT_REGION
        version_id    = "LATEST"
        role_arn      = aws_iam_role.create_iam_role_fireshose_netsuite.arn
      }
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {
            # Optional configurations for JSON deserialization
            # For example, "case_insensitive" = "false"
          }
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression                   = "SNAPPY"
            enable_dictionary_compression = true
            # Optional configurations for Parquet serialization
          }
        }
      }
    }
  }
}

## Create firehose for customerpayment
resource "aws_kinesis_firehose_delivery_stream" "create_firehose_customerpayment_netsuite" {
  name        = "netsuite-data-ingestion-customerpayment"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.create_iam_role_fireshose_netsuite.arn
    bucket_arn          = aws_s3_bucket.netsuite_staging_bucket.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "output/customerpayment/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/customerpayment/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    data_format_conversion_configuration {
      schema_configuration {
        catalog_id    = ""
        database_name = aws_glue_catalog_database.create_database_netsuite.name
        table_name    = aws_glue_catalog_table.create_table_customerpayment_netsuite.name
        region        = var.AWS_DEFAULT_REGION
        version_id    = "LATEST"
        role_arn      = aws_iam_role.create_iam_role_fireshose_netsuite.arn
      }
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {
            # Optional configurations for JSON deserialization
            # For example, "case_insensitive" = "false"
          }
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression                   = "SNAPPY"
            enable_dictionary_compression = true
            # Optional configurations for Parquet serialization
          }
        }
      }
    }
  }
}

## Create firehose for employee
resource "aws_kinesis_firehose_delivery_stream" "create_firehose_employee_netsuite" {
  name        = "netsuite-data-ingestion-employee"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.create_iam_role_fireshose_netsuite.arn
    bucket_arn          = aws_s3_bucket.netsuite_staging_bucket.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "output/employee/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/employee/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    data_format_conversion_configuration {
      schema_configuration {
        catalog_id    = ""
        database_name = aws_glue_catalog_database.create_database_netsuite.name
        table_name    = aws_glue_catalog_table.create_table_employee_netsuite.name
        region        = var.AWS_DEFAULT_REGION
        version_id    = "LATEST"
        role_arn      = aws_iam_role.create_iam_role_fireshose_netsuite.arn
      }
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {
            # Optional configurations for JSON deserialization
            # For example, "case_insensitive" = "false"
          }
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression                   = "SNAPPY"
            enable_dictionary_compression = true
            # Optional configurations for Parquet serialization
          }
        }
      }
    }
  }
}

## Create firehose for invoice
resource "aws_kinesis_firehose_delivery_stream" "create_firehose_invoice_netsuite" {
  name        = "netsuite-data-ingestion-invoice"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.create_iam_role_fireshose_netsuite.arn
    bucket_arn          = aws_s3_bucket.netsuite_staging_bucket.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "output/invoice/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/invoice/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    data_format_conversion_configuration {
      schema_configuration {
        catalog_id    = ""
        database_name = aws_glue_catalog_database.create_database_netsuite.name
        table_name    = aws_glue_catalog_table.create_table_invoice_netsuite.name
        region        = var.AWS_DEFAULT_REGION
        version_id    = "LATEST"
        role_arn      = aws_iam_role.create_iam_role_fireshose_netsuite.arn
      }
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {
            # Optional configurations for JSON deserialization
            # For example, "case_insensitive" = "false"
          }
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression                   = "SNAPPY"
            enable_dictionary_compression = true
            # Optional configurations for Parquet serialization
          }
        }
      }
    }
  }
}

## Create firehose for journalentry
resource "aws_kinesis_firehose_delivery_stream" "create_firehose_journalentry_netsuite" {
  name        = "netsuite-data-ingestion-journalentry"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.create_iam_role_fireshose_netsuite.arn
    bucket_arn          = aws_s3_bucket.netsuite_staging_bucket.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "output/journalentry/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/journalentry/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    data_format_conversion_configuration {
      schema_configuration {
        catalog_id    = ""
        database_name = aws_glue_catalog_database.create_database_netsuite.name
        table_name    = aws_glue_catalog_table.create_table_journalentry_netsuite.name
        region        = var.AWS_DEFAULT_REGION
        version_id    = "LATEST"
        role_arn      = aws_iam_role.create_iam_role_fireshose_netsuite.arn
      }
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {
            # Optional configurations for JSON deserialization
            # For example, "case_insensitive" = "false"
          }
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression                   = "SNAPPY"
            enable_dictionary_compression = true
            # Optional configurations for Parquet serialization
          }
        }
      }
    }
  }
}

## Create Glue table for customer
resource "aws_glue_catalog_table" "create_table_customer_netsuite" {
  name          = "customer" # Replace with your desired table name
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  description   = "customer table for netsuite"
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  table_type = "EXTERNAL_TABLE"
  parameters = {
    "classification"  = "parquet"
    "compressionType" = "None"
    "typeOfData"      = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.netsuite_staging_bucket.bucket}/output/customer"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "links"
      type = "array<struct<rel:string,href:string>>"
    }
    columns {
      name = "addressbook"
      type = "struct<links:array<struct<rel:string,href:string>>>"
    }
    columns {
      name = "aging"
      type = "double"
    }
    columns {
      name = "aging1"
      type = "double"
    }
    columns {
      name = "aging2"
      type = "double"
    }
    columns {
      name = "aging3"
      type = "double"
    }
    columns {
      name = "aging4"
      type = "double"
    }
    columns {
      name = "alcoholrecipientype"
      type = "struct<id:string,refName:string>"
    }
    columns {
      name = "altphone"
      type = "string"
    }
    columns {
      name = "balance"
      type = "double"
    }
    columns {
      name = "comments"
      type = "string"
    }
    columns {
      name = "companyname"
      type = "string"
    }
    columns {
      name = "contactlist"
      type = "struct<links:array<struct<rel:string,href:string>>>"
    }
    columns {
      name = "creditholdoverride"
      type = "struct<id:string,refName:string>"
    }
    columns {
      name = "creditlimit"
      type = "double"
    }
    columns {
      name = "currency"
      type = "struct<links:array<string>,id:string,refName:string>"
    }
    columns {
      name = "currencylist"
      type = "struct<links:array<struct<rel:string,href:string>>>"
    }
    columns {
      name = "custentity_2663_customer_refund"
      type = "boolean"
    }
    columns {
      name = "custentity_2663_direct_debit"
      type = "boolean"
    }
    columns {
      name = "custentity_credit_controller"
      type = "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
    }
    columns {
      name = "custentity_nexgen_account_code"
      type = "string"
    }
    columns {
      name = "customform"
      type = "struct<id:string,refName:string>"
    }
    columns {
      name = "datecreated"
      type = "string"
    }
    columns {
      name = "defaultaddress"
      type = "string"
    }
    columns {
      name = "depositbalance"
      type = "double"
    }
    columns {
      name = "email"
      type = "string"
    }
    columns {
      name = "emailpreference"
      type = "struct<id:string,refName:string>"
    }
    columns {
      name = "emailtransactions"
      type = "boolean"
    }
    columns {
      name = "entityid"
      type = "string"
    }
    columns {
      name = "entitystatus"
      type = "struct<links:array<string>,id:string,refName:string>"
    }
    columns {
      name = "faxtransactions"
      type = "boolean"
    }
    columns {
      name = "grouppricing"
      type = "struct<links:array<struct<rel:string,href:string>>>"
    }
    columns {
      name = "id"
      type = "string"
    }
    columns {
      name = "isautogeneratedrepresentingentity"
      type = "boolean"
    }
    columns {
      name = "isbudgetapproved"
      type = "boolean"
    }
    columns {
      name = "isinactive"
      type = "boolean"
    }
    columns {
      name = "isperson"
      type = "boolean"
    }
    columns {
      name = "itempricing"
      type = "struct<links:array<struct<rel:string,href:string>>>"
    }
    columns {
      name = "lastmodifieddate"
      type = "string"
    }
    columns {
      name = "overduebalance"
      type = "double"
    }
    columns {
      name = "phone"
      type = "string"
    }
    columns {
      name = "printtransactions"
      type = "boolean"
    }
    columns {
      name = "receivablesaccount"
      type = "struct<links:array<string>,id:string,refName:string>"
    }
    columns {
      name = "salesrep"
      type = "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
    }
    columns {
      name = "salesteam"
      type = "struct<links:array<struct<rel:string,href:string>>>"
    }
    columns {
      name = "shipcomplete"
      type = "boolean"
    }
    columns {
      name = "shippingcarrier"
      type = "struct<id:string,refName:string>"
    }
    columns {
      name = "subsidiary"
      type = "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
    }
    columns {
      name = "syncsalesteams"
      type = "boolean"
    }
    columns {
      name = "terms"
      type = "struct<links:array<string>,id:string,refName:string>"
    }
    columns {
      name = "unbilledorders"
      type = "double"
    }
    columns {
      name = "custentity_credit_controller_2"
      type = "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
    }
    columns {
      name = "daysoverdue"
      type = "int"
    }
    columns {
      name = "fax"
      type = "string"
    }
    columns {
      name = "url"
      type = "string"
    }
    columns {
      name = "type"
      type = "string"
    }
    columns {
      name = "title"
      type = "string"
    }
    columns {
      name = "status"
      type = "int"
    }
    columns {
      name = "o:errordetails"
      type = "array<struct<detail:string,errorCode:string>>"
    }
    columns {
      name = "startdate"
      type = "string"
    }

  }
}

## Create firehose for vendor
resource "aws_kinesis_firehose_delivery_stream" "create_firehose_vendor_netsuite" {
  name        = "netsuite-data-ingestion-vendor"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.create_iam_role_fireshose_netsuite.arn
    bucket_arn          = aws_s3_bucket.netsuite_staging_bucket.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "output/vendor/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/vendor/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    data_format_conversion_configuration {
      schema_configuration {
        catalog_id    = ""
        database_name = aws_glue_catalog_database.create_database_netsuite.name
        table_name    = aws_glue_catalog_table.create_table_vendor_netsuite.name
        region        = var.AWS_DEFAULT_REGION
        version_id    = "LATEST"
        role_arn      = aws_iam_role.create_iam_role_fireshose_netsuite.arn
      }
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {
            # Optional configurations for JSON deserialization
            # For example, "case_insensitive" = "false"
          }
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression                   = "SNAPPY"
            enable_dictionary_compression = true
            # Optional configurations for Parquet serialization
          }
        }
      }
    }
  }
}

## Create firehose for vendorbill
resource "aws_kinesis_firehose_delivery_stream" "create_firehose_vendorbill_netsuite" {
  name        = "netsuite-data-ingestion-vendorbill"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.create_iam_role_fireshose_netsuite.arn
    bucket_arn          = aws_s3_bucket.netsuite_staging_bucket.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "output/vendorbill/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/vendorbill/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    data_format_conversion_configuration {
      schema_configuration {
        catalog_id    = ""
        database_name = aws_glue_catalog_database.create_database_netsuite.name
        table_name    = aws_glue_catalog_table.create_table_vendorbill_netsuite.name
        region        = var.AWS_DEFAULT_REGION
        version_id    = "LATEST"
        role_arn      = aws_iam_role.create_iam_role_fireshose_netsuite.arn
      }
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {
            # Optional configurations for JSON deserialization
            # For example, "case_insensitive" = "false"
          }
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression                   = "SNAPPY"
            enable_dictionary_compression = true
            # Optional configurations for Parquet serialization
          }
        }
      }
    }
  }
}

## Create firehose for vendorsubsidiaryrelationship
resource "aws_kinesis_firehose_delivery_stream" "create_firehose_vendorsubsidiaryrelationship_netsuite" {
  name        = "netsuite-data-ingestion-vendorsubsidiaryrelationship"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.create_iam_role_fireshose_netsuite.arn
    bucket_arn          = aws_s3_bucket.netsuite_staging_bucket.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "output/vendorsubsidiaryrelationship/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "errors/vendorsubsidiaryrelationship/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/"
    data_format_conversion_configuration {
      schema_configuration {
        catalog_id    = ""
        database_name = aws_glue_catalog_database.create_database_netsuite.name
        table_name    = aws_glue_catalog_table.create_table_vendorsubsidiaryrelationship_netsuite.name
        region        = var.AWS_DEFAULT_REGION
        version_id    = "LATEST"
        role_arn      = aws_iam_role.create_iam_role_fireshose_netsuite.arn
      }
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {
            # Optional configurations for JSON deserialization
            # For example, "case_insensitive" = "false"
          }
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression                   = "SNAPPY"
            enable_dictionary_compression = true
            # Optional configurations for Parquet serialization
          }
        }
      }
    }
  }
}

## Create Glue table for purchaseorder
resource "aws_glue_catalog_table" "create_table_purchaseorder_netsuite" {
  name          = "purchaseorder" # Replace with your desired table name
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  description   = "purchaseorder table for netsuite"
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  table_type = "EXTERNAL_TABLE"
  parameters = {
    "classification"  = "parquet"
    "compressionType" = "None"
    "typeOfData"      = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.netsuite_staging_bucket.bucket}/output/purchaseorder"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }


 columns{
    name =  "links"
    type =  "array<struct<rel:string,href:string>>"
  }
 columns{
    name =  "approvalstatus"
    type =  "struct<id:string,refName:string>"
  }
 columns{
    name =  "balance"
    type =  "double"
  }
 columns{
    name =  "billaddress"
    type =  "string"
  }
 columns{
    name =  "billaddresslist"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
 columns{
    name =  "billingaddress"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
 columns{
    name =  "billingaddress_text"
    type =  "string"
  }
 columns{
    name =  "createddate"
    type =  "string"
  }
 columns{
    name =  "currency"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
 columns{
    name =  "custbody1"
    type =  "string"
  }
 columns{
    name =  "custbody2"
    type =  "string"
  }
 columns{
    name =  "custbody5"
    type =  "string"
  }
 columns{
    name =  "custbody_cash_register"
    type =  "boolean"
  }
 columns{
    name =  "custbody_nexus_notc"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
 columns{
    name =  "custbody_nondeductible_processed"
    type =  "boolean"
  }
 columns{
    name =  "custbody_nondeductible_ref_tran"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
 columns{
    name =  "custbody_report_timestamp"
    type =  "string"
  }
 columns{
    name =  "customform"
    type =  "struct<id:string,refName:string>"
  }
 columns{
    name =  "department"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
 columns{
    name =  "duedate"
    type =  "string"
  }
 columns{
    name =  "email"
    type =  "string"
  }
 columns{
    name =  "entity"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
 columns{
    name =  "exchangerate"
    type =  "double"
  }
 columns{
    name =  "expense"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
 columns{
    name =  "id"
    type =  "string"
  }
 columns{
    name =  "item"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
 columns{
    name =  "lastmodifieddate"
    type =  "string"
  }
 columns{
    name =  "location"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
 columns{
    name =  "memo"
    type =  "string"
  }
 columns{
    name =  "orderstatus"
    type =  "struct<id:string,refName:string>"
  }
 columns{
    name =  "prevdate"
    type =  "string"
  }
 columns{
    name =  "shipaddress"
    type =  "string"
  }
 columns{
    name =  "shipdate"
    type =  "string"
  }
 columns{
    name =  "shipisresidential"
    type =  "boolean"
  }
 columns{
    name =  "shipoverride"
    type =  "boolean"
  }
 columns{
    name =  "shippingaddress"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
 columns{
    name =  "shippingaddress_text"
    type =  "string"
  }
 columns{
    name =  "status"
    type =  "struct<id:string,refName:string>"
  }
 columns{
    name =  "subsidiary"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
 columns{
    name =  "subtotal"
    type =  "double"
  }
 columns{
    name =  "suppressusereventsandemails"
    type =  "string"
  }
 columns{
    name =  "tobeemailed"
    type =  "boolean"
  }
 columns{
    name =  "tobefaxed"
    type =  "boolean"
  }
 columns{
    name =  "tobeprinted"
    type =  "boolean"
  }
 columns{
    name =  "total"
    type =  "double"
  }
 columns{
    name =  "trandate"
    type =  "string"
  }
 columns{
    name =  "tranid"
    type =  "string"
  }
 columns{
    name =  "updatedropshiporderqty"
    type =  "string"
  }
 columns{
    name =  "custbody3"
    type =  "string"
  }
 columns{
    name =  "nextapprover"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
 columns{
    name =  "custbody6"
    type =  "string"
  }
 columns{
    name =  "custbody_currentuser_hid"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
 columns{
    name =  "employee"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
 columns{
    name =  "terms"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
 columns{
    name =  "message"
    type =  "string"
  }
    # Add more columns as needed
  }
}

## create Glue table for subsidiary
resource "aws_glue_catalog_table" "create_table_subsidiary_netsuite" {
  name          = "subsidiary" # Replace with your desired table name
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  description   = "subsidiary table for netsuite"
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  table_type = "EXTERNAL_TABLE"
  parameters = {
    "classification"  = "parquet"
    "compressionType" = "None"
    "typeOfData"      = "file"
  }
  
  storage_descriptor {
    location      = "s3://${aws_s3_bucket.netsuite_staging_bucket.bucket}/output/subsidiary"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }
 
 columns{
 name = "links"
 type = "array<struct<rel:string,href:string>>"
 }
 columns{
 name = "country"
 type = "struct<id:string,refName:string>"
 }
 columns{
 name = "currency"
 type = "struct<links:array<string>,id:string,refName:string>"
 }
 columns{
 name = "custrecord_psg_lc_test_mode"
 type = "string"
 }
 columns{
 name = "custrecord_subnav_subsidiary_logo"
 type = "string"
 }
 columns{
 name = "id"
 type = "string"
 }
 columns{
 name = "iselimination"
 type = "boolean"
 }
 columns{
 name = "isinactive"
 type = "boolean"
 }
 columns{
 name = "lastmodifieddate"
 type = "string"
 }
 columns{
 name = "legalname"
 type = "string"
 }
 columns{
 name = "mainaddress"
 type = "struct<links:array<struct<rel:string,href:string>>>"
 }
 columns{
 name = "name"
 type = "string"
 }
 columns{
 name = "parent"
 type = "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
 }
 columns{
 name = "returnaddress"
 type = "struct<links:array<struct<rel:string,href:string>>>"
 }
 columns{
 name = "shippingaddress"
 type = "struct<links:array<struct<rel:string,href:string>>>"
 }
 columns{
 name = "email"
 type = "string"
 }
 columns{
 name = "state"
 type = "string"
 }
 columns{
 name = "url"
 type = "string"
 }
  }
}

## create Glue table for creditmemo
resource "aws_glue_catalog_table" "create_table_creditmemo_netsuite" {
  name          = "creditmemo" # Replace with your desired table name
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  description   = "creditmemo table for netsuite"
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  table_type = "EXTERNAL_TABLE"
  parameters = {
    "classification"  = "parquet"
    "compressionType" = "None"
    "typeOfData"      = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.netsuite_staging_bucket.bucket}/output/creditmemo"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

  columns{
    name =  "links"
    type =  "array<struct<rel:string,href:string>>"
	}
  columns{
    name =  "account"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "amountpaid"
    type =  "double"
  }
  columns{
    name =  "amountremaining"
    type =  "double"
  }
  columns{
    name =  "applied"
    type =  "double"
  }
  columns{
    name =  "billingaddress"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "createddate"
    type =  "string"
  }
  columns{
    name =  "currency"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "custbody_15699_exclude_from_ep_process"
    type =  "boolean"
  }
  columns{
    name =  "custbody_nexus_notc"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "custbody_nondeductible_ref_tran"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "custbody_report_timestamp"
    type =  "string"
  }
  columns{
    name =  "customform"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "entity"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "estgrossprofit"
    type =  "double"
  }
  columns{
    name =  "estgrossprofitpercent"
    type =  "double"
  }
  columns{
    name =  "exchangerate"
    type =  "double"
  }
  columns{
    name =  "id"
    type =  "string"
  }
  columns{
    name =  "item"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "lastmodifieddate"
    type =  "string"
  }
  columns{
    name =  "memo"
    type =  "string"
  }
  columns{
    name =  "postingperiod"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "prevdate"
    type =  "string"
  }
  columns{
    name =  "saleseffectivedate"
    type =  "string"
  }
  columns{
    name =  "salesrep"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "salesteam"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "shipisresidential"
    type =  "boolean"
  }
  columns{
    name =  "shipoverride"
    type =  "boolean"
  }
  columns{
    name =  "shippingaddress"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "status"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "subsidiary"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "subtotal"
    type =  "double"
  }
  columns{
    name =  "tobeemailed"
    type =  "boolean"
  }
  columns{
    name =  "tobefaxed"
    type =  "boolean"
  }
  columns{
    name =  "tobeprinted"
    type =  "boolean"
  }
  columns{
    name =  "total"
    type =  "double"
  }
  columns{
    name =  "totalcostestimate"
    type =  "double"
  }
  columns{
    name =  "trandate"
    type =  "string"
  }
  columns{
    name =  "tranid"
    type =  "string"
  }
  columns{
    name =  "unapplied"
    type =  "double"
  }
  columns{
    name =  "asofdate"
    type =  "string"
  }
  columns{
    name =  "billaddress"
    type =  "string"
  }
  columns{
    name =  "billaddresslist"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "billingaddress_text"
    type =  "string"
  }
  columns{
    name =  "email"
    type =  "string"
  }
  columns{
    name =  "originator"
    type =  "string"
  }
  columns{
    name =  "shipaddress"
    type =  "string"
  }
  columns{
    name =  "shipaddresslist"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "shippingaddress_text"
    type =  "string"
  }
  columns{
    name =  "source"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "department"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "location"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "createdfrom"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "otherrefnum"
    type =  "string"
  }
  columns{
    name =  "type"
    type =  "string"
  }
  columns{
    name =  "title"
    type =  "string"
  }
  columns{
    name =  "o:errordetails"
    type =  "array<struct<detail:string,errorCode:string>>"
  }
   }
}

## create Glue table for customerpayment
resource "aws_glue_catalog_table" "create_table_customerpayment_netsuite" {
  name          = "customerpayment" # Replace with your desired table name
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  description   = "customerpayment table for netsuite"
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  table_type = "EXTERNAL_TABLE"
  parameters = {
    "classification"  = "parquet"
    "compressionType" = "None"
    "typeOfData"      = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.netsuite_staging_bucket.bucket}/output/customerpayment"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

  columns{
    name =  "links"
    type =  "array<struct<rel:string,href:string>>"
  }
  columns{
    name =  "account"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "applied"
    type =  "double"
  }
  columns{
    name =  "apply"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "aracct"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "balance"
    type =  "double"
  }
  columns{
    name =  "cleared"
    type =  "boolean"
  }
  columns{
    name =  "cleareddate"
    type =  "string"
  }
  columns{
    name =  "createddate"
    type =  "string"
  }
  columns{
    name =  "currency"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "custbody_9997_autocash_assertion_field"
    type =  "boolean"
  }
  columns{
    name =  "custbody_9997_is_for_ep_dd"
    type =  "boolean"
  }
  columns{
    name =  "custbody_nondeductible_ref_tran"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "customer"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "customform"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "exchangerate"
    type =  "double"
  }
  columns{
    name =  "id"
    type =  "string"
  }
  columns{
    name =  "lastmodifieddate"
    type =  "string"
  }
  columns{
    name =  "payment"
    type =  "double"
  }
  columns{
    name =  "pending"
    type =  "double"
  }
  columns{
    name =  "postingperiod"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "prevdate"
    type =  "string"
  }
  columns{
    name =  "status"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "subsidiary"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "tobeemailed"
    type =  "boolean"
  }
  columns{
    name =  "total"
    type =  "double"
  }
  columns{
    name =  "trandate"
    type =  "string"
  }
  columns{
    name =  "tranid"
    type =  "string"
  }
  columns{
    name =  "unapplied"
    type =  "double"
  }
  columns{
    name =  "undepfunds"
    type =  "struct<id:boolean,refName:string>"
  }
  columns{
    name =  "memo"
    type =  "string"
  }
  columns{
    name =  "department"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "location"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "type"
    type =  "string"
  }
  columns{
    name =  "title"
    type =  "string"
  }
  columns{
    name =  "o:errordetails"
    type =  "array<struct<detail:string,errorCode:string>>"
  }
   }
}

## create Glue table for employee
resource "aws_glue_catalog_table" "create_table_employee_netsuite" {
  name          = "employee" # Replace with your desired table name
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  description   = "employee table for netsuite"
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  table_type = "EXTERNAL_TABLE"
  parameters = {
    "classification"  = "parquet"
    "compressionType" = "None"
    "typeOfData"      = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.netsuite_staging_bucket.bucket}/output/employee"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

  columns{
    name =  "links"
    type =  "array<struct<rel:string,href:string>>"
  }
  columns{
    name =  "addressbook"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "autoname"
    type =  "boolean"
  }
  columns{
    name =  "btemplate"
    type =  "string"
  }
  columns{
    name =  "corporatecards"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "currency"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "currencylist"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "custentity_2663_eft_file_format"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "custentity_2663_payment_method"
    type =  "boolean"
  }
  columns{
    name =  "custentity_sage_num"
    type =  "int"
  }
  columns{
    name =  "custentity_sage_ref_num"
    type =  "int"
  }
  columns{
    name =  "customform"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "datecreated"
    type =  "string"
  }
  columns{
    name =  "defaultexpensereportcurrency"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "defaultjobresourcerole"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "department"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "effectivedatemode"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "email"
    type =  "string"
  }
  columns{
    name =  "empcenterqty"
    type =  "string"
  }
  columns{
    name =  "empcenterqtymax"
    type =  "string"
  }
  columns{
    name =  "employeetype"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "entityid"
    type =  "string"
  }
  columns{
    name =  "firstname"
    type =  "string"
  }
  columns{
    name =  "fulluserqty"
    type =  "string"
  }
  columns{
    name =  "fulluserqtymax"
    type =  "string"
  }
  columns{
    name =  "gender"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "giveaccess"
    type =  "boolean"
  }
  columns{
    name =  "hiredate"
    type =  "string"
  }
  columns{
    name =  "i9verified"
    type =  "boolean"
  }
  columns{
    name =  "id"
    type =  "string"
  }
  columns{
    name =  "initials"
    type =  "string"
  }
  columns{
    name =  "isempcenterqtyenforced"
    type =  "string"
  }
  columns{
    name =  "isfulluserqtyenforced"
    type =  "string"
  }
  columns{
    name =  "isinactive"
    type =  "boolean"
  }
  columns{
    name =  "isjobmanager"
    type =  "boolean"
  }
  columns{
    name =  "isjobresource"
    type =  "boolean"
  }
  columns{
    name =  "isretailuserqtyenforced"
    type =  "string"
  }
  columns{
    name =  "issalesrep"
    type =  "boolean"
  }
  columns{
    name =  "lastmodifieddate"
    type =  "string"
  }
  columns{
    name =  "lastname"
    type =  "string"
  }
  columns{
    name =  "location"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "middlename"
    type =  "string"
  }
  columns{
    name =  "purchaseorderapprovallimit"
    type =  "double"
  }
  columns{
    name =  "purchaseorderapprover"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "purchaseorderlimit"
    type =  "double"
  }
  columns{
    name =  "rates"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "requirepwdchange"
    type =  "boolean"
  }
  columns{
    name =  "retailuserqty"
    type =  "string"
  }
  columns{
    name =  "retailuserqtymax"
    type =  "string"
  }
  columns{
    name =  "roles"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "salutation"
    type =  "string"
  }
  columns{
    name =  "sendemail"
    type =  "boolean"
  }
  columns{
    name =  "socialsecuritynumber"
    type =  "string"
  }
  columns{
    name =  "subsidiary"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "supervisor"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "targetutilization"
    type =  "double"
  }
  columns{
    name =  "terminationbydeath"
    type =  "boolean"
  }
  columns{
    name =  "wasempcenterhasaccess"
    type =  "string"
  }
  columns{
    name =  "wasfulluserhasaccess"
    type =  "string"
  }
  columns{
    name =  "wasinactive"
    type =  "string"
  }
  columns{
    name =  "wasretailuserhasaccess"
    type =  "string"
  }
  columns{
    name =  "workcalendar"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "custentity_ops_manager"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "title"
    type =  "string"
  }
  columns{
    name =  "custentity_nsgdc_po_approval_delegate"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "type"
    type =  "string"
  }
  columns{
    name =  "status"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "o:errordetails"
    type =  "array<struct<detail:string,errorCode:string>>"
  }
  columns{
    name =  "defaultaddress"
    type =  "string"
  }
  columns{
    name =  "mobilephone"
    type =  "string"
  }
  columns{
    name =  "phone"
    type =  "string"
  }
  columns{
    name =  "salesrole"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "releasedate"
    type =  "string"
  }
   }
}

## create Glue table for invoice
resource "aws_glue_catalog_table" "create_table_invoice_netsuite" {
  name          = "invoice" # Replace with your desired table name
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  description   = "invoice table for netsuite"
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  table_type = "EXTERNAL_TABLE"
  parameters = {
    "classification"  = "parquet"
    "compressionType" = "None"
    "typeOfData"      = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.netsuite_staging_bucket.bucket}/output/invoice"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

  columns{
    name =  "links"
    type =  "array<struct<rel:string,href:string>>"
  }
  columns{
    name =  "account"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "amountpaid"
    type =  "double"
  }
  columns{
    name =  "amountremaining"
    type =  "double"
  }
  columns{
    name =  "amountremainingtotalbox"
    type =  "double"
  }
  columns{
    name =  "asofdate"
    type =  "string"
  }
  columns{
    name =  "billaddress"
    type =  "string"
  }
  columns{
    name =  "billaddresslist"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "billingaddress"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "billingaddress_text"
    type =  "string"
  }
  columns{
    name =  "createddate"
    type =  "string"
  }
  columns{
    name =  "currency"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "custbody_15699_exclude_from_ep_process"
    type =  "boolean"
  }
  columns{
    name =  "custbody_nondeductible_ref_tran"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "custbody_report_timestamp"
    type =  "string"
  }
  columns{
    name =  "customform"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "duedate"
    type =  "string"
  }
  columns{
    name =  "email"
    type =  "string"
  }
  columns{
    name =  "entity"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "estgrossprofit"
    type =  "double"
  }
  columns{
    name =  "estgrossprofitpercent"
    type =  "double"
  }
  columns{
    name =  "exchangerate"
    type =  "double"
  }
  columns{
    name =  "expcost"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "id"
    type =  "string"
  }
  columns{
    name =  "item"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "itemcost"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "lastmodifieddate"
    type =  "string"
  }
  columns{
    name =  "originator"
    type =  "string"
  }
  columns{
    name =  "postingperiod"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "prevdate"
    type =  "string"
  }
  columns{
    name =  "saleseffectivedate"
    type =  "string"
  }
  columns{
    name =  "salesrep"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "salesteam"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "shipaddress"
    type =  "string"
  }
  columns{
    name =  "shipaddresslist"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "shipdate"
    type =  "string"
  }
  columns{
    name =  "shipisresidential"
    type =  "boolean"
  }
  columns{
    name =  "shipoverride"
    type =  "boolean"
  }
  columns{
    name =  "shippingaddress"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "shippingaddress_text"
    type =  "string"
  }
  columns{
    name =  "source"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "status"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "storeorder"
    type =  "string"
  }
  columns{
    name =  "subsidiary"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "subtotal"
    type =  "double"
  }
  columns{
    name =  "terms"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "time"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "tobeemailed"
    type =  "boolean"
  }
  columns{
    name =  "tobefaxed"
    type =  "boolean"
  }
  columns{
    name =  "tobeprinted"
    type =  "boolean"
  }
  columns{
    name =  "total"
    type =  "double"
  }
  columns{
    name =  "totalcostestimate"
    type =  "double"
  }
  columns{
    name =  "trandate"
    type =  "string"
  }
  columns{
    name =  "tranid"
    type =  "string"
  }
  columns{
    name =  "type"
    type =  "string"
  }
  columns{
    name =  "title"
    type =  "string"
  }
  columns{
    name =  "o:errordetails"
    type =  "array<struct<detail:string,errorCode:string>>"
  }
  columns{
    name =  "department"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "location"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "otherrefnum"
    type =  "string"
  }
  columns{
    name =  "memo"
    type =  "string"
  }
  columns{
    name =  "discountamount"
    type =  "double"
  }
  columns{
    name =  "custbody_nexus_notc"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
 }

}

## create Glue table for journalentry
resource "aws_glue_catalog_table" "create_table_journalentry_netsuite" {
  name          = "journalentry" # Replace with your desired table name
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  description   = "journalentry table for netsuite"
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  table_type = "EXTERNAL_TABLE"
  parameters = {
    "classification"  = "parquet"
    "compressionType" = "None"
    "typeOfData"      = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.netsuite_staging_bucket.bucket}/output/journalentry"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }
	
  columns{
    name =  "links"
    type =  "array<struct<rel:string,href:string>>"
  }
  columns{
    name =  "approved"
    type =  "boolean"
  }
  columns{
    name =  "createddate"
    type =  "string"
  }
  columns{
    name =  "currency"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "custbody_adjustment_journal"
    type =  "boolean"
  }
  columns{
    name =  "custbody_cash_register"
    type =  "boolean"
  }
  columns{
    name =  "custbody_nondeductible_ref_tran"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "custbody_report_timestamp"
    type =  "string"
  }
  columns{
    name =  "customform"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "exchangerate"
    type =  "double"
  }
  columns{
    name =  "id"
    type =  "string"
  }
  columns{
    name =  "isreversal"
    type =  "boolean"
  }
  columns{
    name =  "lastmodifieddate"
    type =  "string"
  }
  columns{
    name =  "line"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "postingperiod"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "reversaldefer"
    type =  "boolean"
  }
  columns{
    name =  "subsidiary"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "trandate"
    type =  "string"
  }
  columns{
    name =  "tranid"
    type =  "string"
  }
  columns{
    name =  "void"
    type =  "boolean"
  }
  columns{
    name =  "memo"
    type =  "string"
  }
  columns{
    name =  "accountingbook"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "createdfrom"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "reversaldate"
    type =  "string"
  }
  columns{
    name =  "type"
    type =  "string"
  }
  columns{
    name =  "title"
    type =  "string"
  }
  columns{
    name =  "status"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "o:errordetails"
    type =  "array<struct<detail:string,errorCode:string>>"
  }
 }
}

## create Glue table for vendor
resource "aws_glue_catalog_table" "create_table_vendor_netsuite" {
  name          = "vendor" # Replace with your desired table name
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  description   = "vendor table for netsuite"
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  table_type = "EXTERNAL_TABLE"
  parameters = {
    "classification"  = "parquet"
    "compressionType" = "None"
    "typeOfData"      = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.netsuite_staging_bucket.bucket}/output/vendor"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

  columns{
    name =  "links"
    type =  "array<struct<rel:string,href:string>>"
  }
  columns{
    name =  "addressbook"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "autoname"
    type =  "boolean"
  }
  columns{
    name =  "balance"
    type =  "double"
  }
  columns{
    name =  "balanceprimary"
    type =  "double"
  }
  columns{
    name =  "companyname"
    type =  "string"
  }
  columns{
    name =  "contactlist"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "currency"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "currencylist"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "custentity_11724_pay_bank_fees"
    type =  "boolean"
  }
  columns{
    name =  "custentity_2663_payment_method"
    type =  "boolean"
  }
  columns{
    name =  "customform"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "datecreated"
    type =  "string"
  }
  columns{
    name =  "defaultaddress"
    type =  "string"
  }
  columns{
    name =  "email"
    type =  "string"
  }
  columns{
    name =  "emailpreference"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "emailtransactions"
    type =  "boolean"
  }
  columns{
    name =  "entityid"
    type =  "string"
  }
  columns{
    name =  "faxtransactions"
    type =  "boolean"
  }
  columns{
    name =  "id"
    type =  "string"
  }
  columns{
    name =  "isautogeneratedrepresentingentity"
    type =  "boolean"
  }
  columns{
    name =  "isinactive"
    type =  "boolean"
  }
  columns{
    name =  "isjobresourcevend"
    type =  "boolean"
  }
  columns{
    name =  "isperson"
    type =  "boolean"
  }
  columns{
    name =  "lastmodifieddate"
    type =  "string"
  }
  columns{
    name =  "legalname"
    type =  "string"
  }
  columns{
    name =  "printtransactions"
    type =  "boolean"
  }
  columns{
    name =  "rates"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "subsidiary"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "subsidiaryedition"
    type =  "string"
  }
  columns{
    name =  "unbilledorders"
    type =  "double"
  }
  columns{
    name =  "unbilledordersprimary"
    type =  "double"
  }
  columns{
    name =  "workcalendar"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "custentity_2663_eft_file_format"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "custentity_2663_email_address_notif"
    type =  "string"
  }
  columns{
    name =  "phone"
    type =  "string"
  }
  columns{
    name =  "category"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "terms"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "custentity1"
    type =  "string"
  }
  columns{
    name =  "comments"
    type =  "string"
  }
  columns{
    name =  "altphone"
    type =  "string"
  }
  columns{
    name =  "firstname"
    type =  "string"
  }
  columns{
    name =  "lastname"
    type =  "string"
  }
  columns{
    name =  "salutation"
    type =  "string"
  }
  columns{
    name =  "custentity_9572_vendor_entitybank_format"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "custentity_9572_vendor_entitybank_sub"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "fax"
    type =  "string"
  }
  columns{
    name =  "creditlimit"
    type =  "double"
  }
  columns{
    name =  "expenseaccount"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "url"
    type =  "string"
  }
  columns{
    name =  "type"
    type =  "string"
  }
  columns{
    name =  "title"
    type =  "string"
  }
  columns{
    name =  "status"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "o:errordetails"
    type =  "array<struct<detail:string,errorCode:string>>"
  }
 }
}

## create Glue table for vendorbill
resource "aws_glue_catalog_table" "create_table_vendorbill_netsuite" {
  name          = "vendorbill" # Replace with your desired table name
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  description   = "vendorbill table for netsuite"
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  table_type = "EXTERNAL_TABLE"
  parameters = {
    "classification"  = "parquet"
    "compressionType" = "None"
    "typeOfData"      = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.netsuite_staging_bucket.bucket}/output/vendorbill"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }
	
  columns{
    name =  "links"
    type =  "array<struct<rel:string,href:string>>"
  }
  columns{
    name =  "account"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "approvalstatus"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "balance"
    type =  "double"
  }
  columns{
    name =  "billaddress"
    type =  "string"
  }
  columns{
    name =  "billaddresslist"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "billingaddress"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "billingaddress_text"
    type =  "string"
  }
  columns{
    name =  "createddate"
    type =  "string"
  }
  columns{
    name =  "currency"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "custbody1"
    type =  "string"
  }
  columns{
    name =  "custbody2"
    type =  "string"
  }
  columns{
    name =  "custbody3"
    type =  "string"
  }
  columns{
    name =  "custbody5"
    type =  "string"
  }
  columns{
    name =  "custbody_cash_register"
    type =  "boolean"
  }
  columns{
    name =  "custbody_nexus_notc"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "custbody_nondeductible_processed"
    type =  "boolean"
  }
  columns{
    name =  "custbody_nondeductible_ref_tran"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "custbody_report_timestamp"
    type =  "string"
  }
  columns{
    name =  "customform"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "department"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "documentstatus"
    type =  "string"
  }
  columns{
    name =  "duedate"
    type =  "string"
  }
  columns{
    name =  "entity"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "exchangerate"
    type =  "double"
  }
  columns{
    name =  "expense"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "id"
    type =  "string"
  }
  columns{
    name =  "item"
    type =  "struct<links:array<struct<rel:string,href:string>>>"
  }
  columns{
    name =  "lastmodifieddate"
    type =  "string"
  }
  columns{
    name =  "location"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "memo"
    type =  "string"
  }
  columns{
    name =  "paymenthold"
    type =  "boolean"
  }
  columns{
    name =  "postingperiod"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "prevdate"
    type =  "string"
  }
  columns{
    name =  "received"
    type =  "boolean"
  }
  columns{
    name =  "status"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "subsidiary"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "tobeprinted"
    type =  "boolean"
  }
  columns{
    name =  "total"
    type =  "double"
  }
  columns{
    name =  "trandate"
    type =  "string"
  }
  columns{
    name =  "tranid"
    type =  "string"
  }
  columns{
    name =  "usertotal"
    type =  "double"
  }
  columns{
    name =  "custbody_currentuser_hid"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "terms"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "availablevendorcredit"
    type =  "double"
  }
  columns{
    name =  "type"
    type =  "string"
  }
  columns{
    name =  "title"
    type =  "string"
  }
  columns{
    name =  "o:errordetails"
    type =  "array<struct<detail:string,errorCode:string>>"
  }
 }
}

## create Glue table for vendorsubsidiaryrelationship
resource "aws_glue_catalog_table" "create_table_vendorsubsidiaryrelationship_netsuite" {
  name          = "vendorsubsidiaryrelationship" # Replace with your desired table name
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  description   = "vendorsubsidiaryrelationship table for netsuite"
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  table_type = "EXTERNAL_TABLE"
  parameters = {
    "classification"  = "parquet"
    "compressionType" = "None"
    "typeOfData"      = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.netsuite_staging_bucket.bucket}/output/vendorsubsidiaryrelationship"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      name                  = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }
	
  columns{
    name =  "links"
    type =  "array<struct<rel:string,href:string>>"
  }
  columns{
    name =  "balance"
    type =  "double"
  }
  columns{
    name =  "balancebase"
    type =  "double"
  }
  columns{
    name =  "basecurrency"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "entity"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "id"
    type =  "string"
  }
  columns{
    name =  "isprimarysub"
    type =  "boolean"
  }
  columns{
    name =  "lastmodifieddate"
    type =  "string"
  }
  columns{
    name =  "name"
    type =  "string"
  }
  columns{
    name =  "primarycurrency"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
  columns{
    name =  "subsidiary"
    type =  "struct<links:array<struct<rel:string,href:string>>,id:string,refName:string>"
  }
  columns{
    name =  "unbilledorders"
    type =  "double"
  }
  columns{
    name =  "unbilledordersbase"
    type =  "double"
  }
  columns{
    name =  "type"
    type =  "string"
  }
  columns{
    name =  "title"
    type =  "string"
  }
  columns{
    name =  "status"
    type =  "struct<id:string,refName:string>"
  }
  columns{
    name =  "o:errordetails"
    type =  "array<struct<detail:string,errorCode:string>>"
  }
  columns{
    name =  "creditlimit"
    type =  "double"
  }
  columns{
    name =  "taxitem"
    type =  "struct<links:array<string>,id:string,refName:string>"
  }
 }
}

## Create IAM role for firehose
resource "aws_iam_role" "create_iam_role_fireshose_netsuite" {
  name = "netsuite-firehose-role"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "",
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "firehose.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
      }]
    }
  )
}

## Attach policies to IAM firehose: s3, glue
resource "aws_iam_role_policy_attachment" "s3_full_access_to_firehose" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.create_iam_role_fireshose_netsuite.name
}
resource "aws_iam_role_policy_attachment" "glue_full_access_to_firehose" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  role       = aws_iam_role.create_iam_role_fireshose_netsuite.name
}

## create stepfunction
resource "aws_sfn_state_machine" "create_step_function_netsuite" {
  name     = "netsuite-gluejobs-orchestration"
  role_arn = aws_iam_role.create_iam_role_stepfunction_netsuite.arn

  definition = jsonencode(
                  {
                    "StartAt": "vendorbill",
                    "States": {
                      "vendorbill": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::glue:startJobRun.sync",
                        "Parameters": {
                          "Arguments": {
                            "--kinesisfirehose": "netsuite-data-ingestion-vendorbill",
                            "--service": "vendorbill"
                          },
                          "JobName": "netsuite-get-restApi"
                        },
                        "Next": "vendor"
                      },
                      "vendor": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::glue:startJobRun.sync",
                        "Parameters": {
                          "Arguments": {
                            "--kinesisfirehose": "netsuite-data-ingestion-vendor",
                            "--service": "vendor"
                          },
                          "JobName": "netsuite-get-restApi"
                        },
                        "Next": "creditmemo"
                      },
                      "creditmemo": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::glue:startJobRun.sync",
                        "Parameters": {
                          "Arguments": {
                            "--kinesisfirehose": "netsuite-data-ingestion-creditmemo",
                            "--service": "creditmemo"
                          },
                          "JobName": "netsuite-get-restApi"
                        },
                        "Next": "customer"
                      },
                      "customer": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::glue:startJobRun.sync",
                        "Parameters": {
                          "Arguments": {
                            "--kinesisfirehose": "netsuite-data-ingestion-customer",
                            "--service": "customer"
                          },
                          "JobName": "netsuite-get-restApi"
                        },
                        "Next": "purchaseorder"
                      },
                      "purchaseorder": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::glue:startJobRun.sync",
                        "Parameters": {
                          "Arguments": {
                            "--kinesisfirehose": "netsuite-data-ingestion-purchaseorder",
                            "--service": "purchaseorder"
                          },
                          "JobName": "netsuite-get-restApi"
                        },
                        "Next": "vendorsubsidiaryrelationship"
                      },
                      "vendorsubsidiaryrelationship": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::glue:startJobRun.sync",
                        "Parameters": {
                          "Arguments": {
                            "--kinesisfirehose": "netsuite-data-ingestion-vendorsubsidiaryrelationship",
                            "--service": "vendorsubsidiaryrelationship"
                          },
                          "JobName": "netsuite-get-restApi"
                        },
                        "Next": "subsidiary"
                      },
                      "subsidiary": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::glue:startJobRun.sync",
                        "Parameters": {
                          "Arguments": {
                            "--kinesisfirehose": "netsuite-data-ingestion-subsidiary",
                            "--service": "subsidiary"
                          },
                          "JobName": "netsuite-get-restApi"
                        },
                        "Next": "employee"
                      },
                      "employee": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::glue:startJobRun.sync",
                        "Parameters": {
                          "Arguments": {
                            "--kinesisfirehose": "netsuite-data-ingestion-employee",
                            "--service": "employee"
                          },
                          "JobName": "netsuite-get-restApi"
                        },
                        "Next": "journalentry"
                      },
                      "journalentry": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::glue:startJobRun.sync",
                        "Parameters": {
                          "Arguments": {
                            "--kinesisfirehose": "netsuite-data-ingestion-journalentry",
                            "--service": "journalentry"
                          },
                          "JobName": "netsuite-get-restApi"
                        },
                        "Next": "customerpayment"
                      },
                      "customerpayment": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::glue:startJobRun.sync",
                        "Parameters": {
                          "Arguments": {
                            "--kinesisfirehose": "netsuite-data-ingestion-customerpayment",
                            "--service": "customerpayment"
                          },
                          "JobName": "netsuite-get-restApi"
                        },
                        "Next": "invoice"
                      },
                      "invoice": {
                        "Type": "Task",
                        "Resource": "arn:aws:states:::glue:startJobRun.sync",
                        "Parameters": {
                          "Arguments": {
                            "--kinesisfirehose": "netsuite-data-ingestion-invoice",
                            "--service": "invoice"
                          },
                          "JobName": "netsuite-get-restApi"
                        },
                        "Next": "Wait for firehose to process"
                      },
                      "Wait for firehose to process": {
                        "Type": "Wait",
                        "Next": "Delete prev schema",
                        "Seconds": 120
                      },
                      "Delete prev schema": {
                        "Type": "Task",
                        "Next": "update new schema",
                        "Parameters": {
                          "DatabaseName": "netsuite",
                          "TablesToDelete": [
                            "creditmemo",
                            "customer",
                            "customerpayment",
                            "employee",
                            "invoice",
                            "journalentry",
                            "purchaseorder",
                            "subsidiary",
                            "vendor",
                            "vendorbill",
                            "vendorsubsidiaryrelationship"
                          ]
                        },
                        "Resource": "arn:aws:states:::aws-sdk:glue:batchDeleteTable"
                      },
                      "update new schema": {
                        "Type": "Task",
                        "Parameters": {
                          "Name": "netsuite-create-all-tables"
                        },
                        "Resource": "arn:aws:states:::aws-sdk:glue:startCrawler",
                        "End": true
                      }
                    }
                  }
  )
}

## create IAM role for stepfunction
resource "aws_iam_role" "create_iam_role_stepfunction_netsuite" {
  name = "netsuite-stepfunction-role"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "states.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
    }
  )
}

## Attach policies to IAM stepfunction: glue
resource "aws_iam_role_policy_attachment" "glue_full_access_to_stepfunction" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  role       = aws_iam_role.create_iam_role_stepfunction_netsuite.name
}

## create eventrule to run step function daily
resource "aws_cloudwatch_event_rule" "event_rule" {
  name                = "netsuite-stepfuntion-daily-run" # Replace with your desired rule name
  description         = "Event rule for stepfuntion"
  schedule_expression = "cron(0 2 * * ? *)" # Replace with your desired schedule expression, run daily at 12PM

}

## Attach stepfunction as target to eventrule
resource "aws_cloudwatch_event_target" "stepfunctions_target" {
  rule      = aws_cloudwatch_event_rule.event_rule.name
  target_id = "netsuite-gluejobs-orchestration"
  arn       = aws_sfn_state_machine.create_step_function_netsuite.arn
  role_arn  = aws_iam_role.create_iam_role_event_netsuite.arn
}

## create IAM role for eventrule
resource "aws_iam_role" "create_iam_role_event_netsuite" {
  name = "netsuite-event-role"

  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Effect" : "Allow",
          "Principal" : {
            "Service" : "events.amazonaws.com"
          },
          "Action" : "sts:AssumeRole"
        }
      ]
    }
  )
}

## Attach policies to eventrule: stepfunction
resource "aws_iam_role_policy_attachment" "stepfunction_full_access_to_eventrule" {
  policy_arn = "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess"
  role       = aws_iam_role.create_iam_role_event_netsuite.name
}

## Glue Crawler

resource "aws_glue_crawler" "example" {
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  name          = "netsuite-create-all-tables"
  role          = aws_iam_role.create_iam_role_glue_netsuite.arn

  s3_target {
    path = "s3://${aws_s3_bucket.netsuite_staging_bucket.bucket}/output/"
  }
}