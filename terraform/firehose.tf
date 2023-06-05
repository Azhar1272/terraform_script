resource "aws_kinesis_firehose_delivery_stream" "create_firehose_customer_netsuite" {
  name        = "netsuite-data-ingestion-customer"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.create_iam_role_fireshose_netsuite.arn
    bucket_arn          = aws_s3_bucket.create_bucket_netsuite.arn
    buffering_size      = 64
    buffering_interval  = 60
    prefix              = "customer/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/customer/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/!{firehose:error-output-type}/"
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
resource "aws_iam_role_policy_attachment" "s3_full_access_to_firehose" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.create_iam_role_fireshose_netsuite.name
}

resource "aws_iam_role_policy_attachment" "glue_full_access_to_firehose" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
  role       = aws_iam_role.create_iam_role_fireshose_netsuite.name
}