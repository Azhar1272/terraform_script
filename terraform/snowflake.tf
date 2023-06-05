variable "SNOWFLAKE_ACCOUNT" {
  description = "Snowflake account"
}

variable "SNOWFLAKE_USERNAME" {
  description = "Snowflake username"
}

variable "SNOWFLAKE_PASSWORD" {
  description = "Snowflake password"
  sensitive   = true
}

variable "SNOWFLAKE_ROLE" {
  description = "Snowflake role"
}

# Unused
########
# variable "SNOWFLAKE_REGION" {
#   description = "Snowflake region"
# }

locals {
  database_name = "SNOWFLAKE_NEXGEN_${var.ENV_NAME}"
}

resource "snowflake_database" "this" {
  name = local.database_name
}

resource "snowflake_role" "dbt_user_role" {
  name = "DBT_USER_ROLE_${upper(var.ENV_NAME)}"
}

resource "snowflake_user" "dbt_user" {
  name     = "DBT_USER_${upper(var.ENV_NAME)}"
  password = var.DBT_USER_PASSWORD

  default_role = snowflake_role.dbt_user_role.name
}

resource "snowflake_role_grants" "dbt_user_role_grants" {
  role_name = snowflake_role.dbt_user_role.name
  roles = [
    "PUBLIC",
  ]

  users = [
    snowflake_user.dbt_user.name,
  ]
}

resource "snowflake_database_grant" "dbt_user_role_database_grants" {
  database_name = snowflake_database.this.name
  roles = [
    snowflake_role.dbt_user_role.name,
  ]
}

resource "snowflake_schema" "snowpipe_s3_ingestion" {
  database = snowflake_database.this.name
  name     = "SNOWPIPE_S3_INGESTION"
}

resource "snowflake_schema" "dbt_dev" {
  database = snowflake_database.this.name
  name     = "DBT_DEV"
}

resource "snowflake_schema_grant" "dbt_user_role_schema_usage_grant_raw_schema" {
  database_name = snowflake_database.this.name
  schema_name = snowflake_schema.snowpipe_s3_ingestion.name
  roles = [
    snowflake_role.dbt_user_role.name,
  ]
  for_each = {
    usage  = "USAGE",
    modify = "MODIFY",
  }

  privilege = each.value

}

resource "snowflake_schema_grant" "dbt_user_role_schema_usage_grant_dev_schema" {
  database_name = snowflake_database.this.name
  schema_name = snowflake_schema.dbt_dev.name
  roles = [
    snowflake_role.dbt_user_role.name,
  ]
  for_each = {
    usage  = "USAGE",
    modify = "MODIFY",
    ownership = "OWNERSHIP",
  }

  privilege = each.value
}


resource "snowflake_schema_grant" "dbt_user_role_schema_ownership_grant" {
  database_name = snowflake_database.this.name
  schema_name = snowflake_schema.snowpipe_s3_ingestion.name
  roles = [
    snowflake_role.dbt_user_role.name,
  ]
  privilege    = "OWNERSHIP"
}


variable "DBT_USER_PASSWORD" {
  description = "DBT user password"
  sensitive   = true
}


resource "aws_secretsmanager_secret" "snowflake_params" {
  name = "snowflake-params-lambda"
  description = "Snowflake Connection Parameters"
}

resource "aws_secretsmanager_secret_version" "snowflake_params" {
  secret_id     = aws_secretsmanager_secret.snowflake_params.id
  secret_string = jsonencode({
    snowflake = {
      account_name  = var.SNOWFLAKE_ACCOUNT
      username      = snowflake_user.dbt_user.name
      password      = var.DBT_USER_PASSWORD
      database_name = local.database_name
      schema_name   = snowflake_schema.snowpipe_s3_ingestion.name
      role_name     = snowflake_role.dbt_user_role.name
      warehouse_name = snowflake_warehouse.dbt_wh.name
    }
  })
}

resource "snowflake_warehouse" "dbt_wh" {
  name             = "DBT_WAREHOUSE_${upper(var.ENV_NAME)}"
  warehouse_size   = "X-SMALL"
  auto_suspend     = 60
  auto_resume      = true

  # Grant access to the DBT_USER_ROLE
  depends_on = [
    snowflake_role_grants.dbt_user_role_grants
  ]
}

resource "snowflake_warehouse" "dbt_automated_wh" {
  name             = "DBT_AUTOMATED_WAREHOUSE_${upper(var.ENV_NAME)}"
  warehouse_size   = "X-SMALL"
  auto_suspend     = 60
  auto_resume      = true

  # Grant access
  depends_on = [
    snowflake_role_grants.dbt_user_role_grants
  ]
}

resource "snowflake_warehouse_grant" "dbt_user_role_wh_grants" {
  warehouse_name = snowflake_warehouse.dbt_wh.name
  roles = [
    snowflake_role.dbt_user_role.name
  ]
}

resource "snowflake_warehouse_grant" "dbt_automated_user_role_wh_grants" {
  warehouse_name = snowflake_warehouse.dbt_automated_wh.name
  roles = [
    snowflake_role.dbt_user_role.name
  ]
}



