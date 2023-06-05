resource "aws_glue_job" "create_gluejob_customer_netsuite" {
  name         = "netsuite-get-customer"
  role_arn     = aws_iam_role.create_iam_role_glue_netsuite.arn
  max_capacity = 0.0625
  command {
    script_location = "s3://${aws_s3_bucket.create_bucket_netsuite.bucket}/script/customer.py"
    name            = "pythonshell"
    python_version  = "3.9"
  }

  default_arguments = {
    "--kinesisfirehose" = "netsuite-data-ingestion-customer"
    "--region"          = var.AWS_DEFAULT_REGION
    "--service"         = "customer/1018"
    "--secretmanager"   = "netsuite/secrets"
  }

}

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

resource "aws_glue_trigger" "netsuite-glue-trigger" {
  name     = "netsuite-trigger"
  schedule = "cron(0 * * * ? *)"
  type     = "SCHEDULED"

  actions {
    job_name = aws_glue_job.create_gluejob_customer_netsuite.name
  }
}