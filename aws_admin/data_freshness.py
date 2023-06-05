import snowflake.connector
import snowflake.connector
import boto3
import os
import json


bucket_name = os.environ.get('S3_BUCKET', "data-transfer-nexgen-snowpipe-dev")
s3_folder_path = os.environ.get('S3_PREFIX', "nexgen/")

env_name = os.environ.get('ENV_NAME', 'dev')
secret_name_snowflake = os.environ.get('SECRET_NAME_SNOWFLAKE', "snowflake-params-lambda")
s3_lambda_secret = os.environ.get('S3_LAMBDA_SECRET', "snowflake-s3-access-user-keys")

region_name= os.environ.get('AWS_REGION', "eu-west-1")

secret_dict = json.loads(
        boto3.client("secretsmanager", region_name=region_name,).get_secret_value(SecretId=secret_name_snowflake)[
            "SecretString"
        ]
    )
account = secret_dict["snowflake"]["account_name"]
user = secret_dict["snowflake"]["username"]
password = secret_dict["snowflake"]["password"]
database = secret_dict["snowflake"]["database_name"]
schema_name = secret_dict["snowflake"]["schema_name"]
role_name = secret_dict["snowflake"]["role_name"]
warehouse_name = secret_dict["snowflake"]["warehouse_name"]
modified_column = 'SNOWPIPE_INSERTION_TIME'
modified_data_type = 'TIMESTAMP_NTZ'  # Modify the data type as desired


conn = snowflake.connector.connect(
    user=user,
    password=password,
    account=account,
    warehouse=warehouse_name,
    database=database,
    schema=schema_name
)


# Execute SQL statements
try:
    cursor = conn.cursor()
    cursor.execute("SHOW TABLES")
    tables = [row[1] for row in cursor.fetchall()]

# Iterate over the tables
    #filtered_tables = [table for table in tables if table == 'ACCOUNTS']
    for table in tables:
        cursor = conn.cursor()

        # Get column information from the existing table
        get_columns_query = f'''DESCRIBE TABLE {table}'''
        cursor.execute(get_columns_query)

        # Fetch column information

       
        columns = cursor.fetchall()

        if modified_column not in [column[0] for column in columns]:
            print(f"Table - {table} does not have {modified_column} . No changes will be applied.")
        else:
            is_modified = False
            for column in columns:
                column_name = column[0]
                data_type = column[1]
                if column_name.lower() == modified_column.lower() and data_type.upper() in ['TIMESTAMP_NTZ', 'TIMESTAMP_NTZ(9)']:
                    is_modified = True
                    break

            # Generate column definitions for the new table
            if is_modified:
                print(f"Table - {table} with {modified_column} already has the {modified_data_type} data type.")
            else:
                column_definitions = []
                for column in columns:
                    column_name = column[0]
                    data_type = column[1]
                    if column_name == modified_column:
                        data_type = modified_data_type
                    
                    if column_name.isupper():
                        column_name = column_name.upper()
                    else:
                        column_name = f'"{column_name}"'

                    column_definitions.append(f'{column_name} {data_type}')

                # Create a new table with modified column data type
                new_table = f'{table}_NEW'
                create_table_query = f'''
                CREATE TABLE {new_table} (
                    {', '.join(column_definitions)}
                ) AS SELECT * FROM {table}
                '''
                cursor.execute(create_table_query)

                # Drop the existing table
                drop_table_query = f'''
                DROP TABLE {table}
                '''
                cursor.execute(drop_table_query)

                # Rename the new table to the existing table name
                rename_table_query = f'''
                ALTER TABLE {new_table} RENAME TO {table}
                '''
                cursor.execute(rename_table_query)

                # Commit the changes
                conn.commit()

                print(f"Updated {modified_column} to {modified_data_type} in Table - {table}")

except snowflake.connector.Error as e:
    print("Error: {}".format(e))

finally:
    # Close the connection
    conn.close()