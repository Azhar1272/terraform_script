resource "aws_s3_bucket" "create_bucket_netsuite" {
  bucket = "get-netsuite-data"

}

resource "aws_s3_object" "object" {
  bucket = aws_s3_bucket.create_bucket_netsuite.id
  key    = "script/"
}
resource "aws_secretsmanager_secret" "create_secretmanger_netsuite" {
  name = "netsuite/secrets"
}

resource "aws_glue_catalog_database" "create_database_netsuite" {
  name = "netsuite" # Replace with your desired database name
}

resource "aws_glue_catalog_table" "create_table_customer_netsuite" {
  name          = "customer" # Replace with your desired table name
  database_name = aws_glue_catalog_database.create_database_netsuite.name
  description   = "customer table for netsuite"

  table_type = "EXTERNAL_TABLE"
  parameters = {
    "classification"  = "parquet"
    "compressionType" = "None"
    "typeOfData"      = "file"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.create_bucket_netsuite.bucket}/customer"
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
    # Add more columns as needed
  }
}

