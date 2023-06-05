import snowflake.connector
import boto3
import json
from fastparquet import ParquetFile
import io
import logging
import sys
import os
from typing import List, Tuple
import time
from collections import OrderedDict
import sentry_sdk
from sentry_sdk.integrations.aws_lambda import AwsLambdaIntegration
from datetime import datetime, timedelta
import pytz

# logger = logging.getLogger()
# logger.setLevel(logging.INFO)


# Configure Sentry Monitoring
sentry_dsn = os.environ.get('SENTRY_DSN', None)
if sentry_dsn:
    sentry_sdk.init(
        dsn=sentry_dsn,
        integrations=[
            AwsLambdaIntegration(),
        ],

        # Set traces_sample_rate to 1.0 to capture 100%
        # of transactions for performance monitoring.
        # We recommend adjusting this value in production,
        traces_sample_rate=1.0,
    )


if sentry_dsn:
    print('logs sent to Sentry, log in at sentry.io to see the traces')


def handler(event=None, context=None):



    secret_name_snowflake = os.environ.get('SECRET_NAME_SNOWFLAKE', "snowflake-params-lambda")
    s3_lambda_secret = os.environ.get('S3_LAMBDA_SECRET', "snowflake-s3-access-user-keys")

    # AWS S3 connection parameters
    bucket_name = os.environ.get('S3_BUCKET', "data-transfer-nexgen-snowpipe-dev")
    s3_folder_path = os.environ.get('S3_PREFIX', "nexgen/")

    region_name="eu-west-1"

    secret_dict = json.loads(
        boto3.client("secretsmanager", region_name=region_name,).get_secret_value(SecretId=secret_name_snowflake)[
            "SecretString"
        ]
    )

    snowflake_s3_access_user_creds = json.loads(
        boto3.client("secretsmanager", region_name=region_name,).get_secret_value(SecretId=s3_lambda_secret)[
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

    snowflake_s3_access_key = snowflake_s3_access_user_creds['access_key']
    snowflake_s3_access_secret = snowflake_s3_access_user_creds['access_secret']


    # Create a Snowflake connection
    conn = snowflake.connector.connect(
        account=account, user=user, password=password, database=database, schema=schema_name, role=role_name, warehouse=warehouse_name,
    )

    def execute_query(q: str) -> List[Tuple]:
        try:
            cursor = conn.cursor()
            cursor.execute(q)
            results = cursor.fetchall()
            return results

        except Exception as e:
            raise Exception(f"problem with query: {q} -> {e}")

    # Create a Snowflake external stage pointing to the S3 bucket
    stage_name = "nexgen_stage"

    execute_query(
        f"""CREATE STAGE IF NOT EXISTS {database}.{schema_name}.{stage_name} 
        URL='s3://{bucket_name}/{s3_folder_path}' 
        CREDENTIALS = (
        AWS_KEY_ID = '{snowflake_s3_access_key}'
        AWS_SECRET_KEY = '{snowflake_s3_access_secret}'
        );
        """
    )

    s3_client = boto3.client("s3", region_name=region_name,)
    # List the directories in the S3 bucket
    tables = list(
        set(
            [
                d["Prefix"].split("/")[-2]
                for d in s3_client
                .list_objects(Bucket=bucket_name, Prefix=s3_folder_path, Delimiter="/")
                .get("CommonPrefixes")
            ]
        )
    )
	
    # Hardcode a list of tables that we want to ignore
    excluded_tables = [
        'remote_vendors',
        'remote_purchase_codes',
        'remote_users'
        'remote_purchase_lines'
        'images',
        'files',
        'tracking_events',
        'print_history',
        'devices',
        'fulltext',
        'projected_sales',
        'calendar_events',
        'export_history',
        'db_backups',
        'dashboard_tracking',
    ]
	
    tables = [c for c in tables if c.lower() not in [l.lower() for l in excluded_tables]]


    s3 = boto3.resource('s3', region_name=region_name)
    bucket = s3.Bucket(bucket_name)


    parquet_type_map = {
        idx: "STRING" for idx in range(32)
    }

    all_pipes = execute_query(f"""SELECT PIPE_NAME FROM {database}.INFORMATION_SCHEMA.PIPES WHERE PIPE_SCHEMA = '{schema_name}'""")
    all_pipes = [d[0].upper() for d in all_pipes]


    # Create a Snowpipe for each directory in the S3 bucket
    try:
        succeeded = []
        failed = []

        for i, table in enumerate(tables):
            try:
                table_name = table.upper()

                pipe_name = f"{table_name}_PIPE".upper()

                pipe_created = (pipe_name in all_pipes)
                table_schema_updated = False

                # Generate DDL statement to create the table schema dynamically
                ddl_columns = []

                # Get the most recent
                objects = bucket.objects.filter(Prefix=s3_folder_path + table + '/').all()

                sorted_objects = sorted(objects, key=lambda obj: obj.last_modified, reverse=True)

                path = sorted_objects[0].key


                parquet_file = ParquetFile(
                    f"{path}", 
                    open_with=lambda p: io.BytesIO(s3_client.get_object(Bucket=bucket_name, Key=p)["Body"].read()),
                )

                schema = OrderedDict((k,parquet_type_map[v.type]) for k,v in parquet_file.schema.schema_elements_by_name.items() if k.lower() not in ['schema'])
                
                # Add a OP column even if it doesn't exist in the initial schema (initial load parquet file), as the first column
                if 'Op'.lower() not in [k.lower() for k in schema.keys()]:
                    new_d = OrderedDict([('Op', 'STRING')])
                    new_d.update(schema)
                    schema = new_d

                # for field in parquet_file.get()["Body"].get_internal_value()["schema"]["fields"]:
                #     ddl_columns.append(f"{field['name']} {field['type'].upper()}")
                
                count_ddl = f"""select COLUMN_NAME from {database}.INFORMATION_SCHEMA.COLUMNS WHERE table_name = '{table_name}' and table_schema = '{schema_name}'"""

                snowflake_column_list_raw = execute_query(count_ddl)
                snowflake_column_list = [item[0] for item in snowflake_column_list_raw]

                table_already_created = len(snowflake_column_list) > 0 
                
                table_schema_updated = False

                extra_manual_columns = {'SNOWPIPE_INSERTION_TIME': 'TIMESTAMP_NTZ'}


                if table_already_created:
                    
                    if len(snowflake_column_list) != (len(schema) + len(extra_manual_columns)):
                    # We need to add some columns

                        new_column_list = list(sorted(set(schema) - set(snowflake_column_list)))

                        table_schema_updated = len(new_column_list) > 0

                        for new_column in new_column_list:
                            
                            # Add the new column to the back of the schema
                            schema[new_column] = 'STRING'

                            alter_query = f"""ALTER TABLE "{database}"."{schema_name}"."{table_name}" ADD COLUMN "{new_column}" STRING ;"""
                            execute_query(alter_query)
                            print(f'New column `{new_column}` added to {database}.{schema_name}.{table_name}')

                if not table_already_created:
                    ddl = f"""CREATE TABLE IF NOT EXISTS "{database}"."{schema_name}"."{table_name}" (
                            {','.join([f'"{k}" {v}' for k, v in extra_manual_columns.items()])}{', ' if len(extra_manual_columns) > 0 else ''}
                             {', '.join([f'"{k}" {v}' for k, v in schema.items()])}
                            )"""

                    # Execute the DDL statement to create the table
                    execute_query(ddl)

                    utc = pytz.UTC
                    
                    # Create datetime object for 7 days ago in UTC timezone
                    seven_days_ago = utc.localize(datetime.now() - timedelta(days=7))

                    # Filter objects by last modified time
                    historic_files = [obj for obj in sorted_objects if obj.last_modified < seven_days_ago]
         
                    # Load the historic files which are older than 7 days 
                    for historic_file in historic_files:
                        execute_query(
                        f"""
                        COPY INTO "{database}"."{schema_name}"."{table_name}"
                        FROM (
                        SELECT TO_TIMESTAMP(METADATA$START_SCAN_TIME)::TIMESTAMP_NTZ AS snowpipe_insertion_time, {', '.join([f'$1:{k}::{v}' for k,v in schema.items()])}
                        FROM @{database}.{schema_name}.{stage_name}/{table}/{os.path.basename(historic_file.key)} 
                        ) 
                        FILE_FORMAT = (TYPE = PARQUET)
                        """
                        )
                        print(f'Loaded historic file `{os.path.basename(historic_file.key)}` to {database}.{schema_name}.{table_name}')


                # Create the Snowpipe pipe for the directory

                if table_schema_updated or not pipe_created:

                    if table_schema_updated:
                        # Following the steps in
                        # https://docs.snowflake.com/en/user-guide/data-load-snowpipe-manage#modifying-the-copy-statement-in-a-pipe-definition

                        execute_query(f'ALTER PIPE "{database}"."{schema_name}"."{pipe_name.upper()}" SET PIPE_EXECUTION_PAUSED=true')

                        # TODO: Implement a limit of retries, fail if the limit has been reached
                        retry_delay = 2
                        while True:
                            r = execute_query(f"SELECT SYSTEM$PIPE_STATUS( '{database}.{schema_name}.{pipe_name}' )")
                            r = json.loads(r[0][0])
                            if r['executionState'] == 'PAUSED' and int(r['pendingFileCount']) == 0:
                                break
                            else:
                                retry_delay = retry_delay * 1.3
                                if r['executionState'] != 'PAUSED':
                                    execute_query(f'ALTER PIPE "{database}"."{schema_name}"."{pipe_name.upper()}" SET PIPE_EXECUTION_PAUSED=true')

                                # TODO: Add a condition for pendingFileCount

                                # Force the stop
                                time.sleep(retry_delay)



                    execute_query(
                        f"""CREATE OR REPLACE PIPE "{database}"."{schema_name}"."{pipe_name.upper()}"
                        AUTO_INGEST = TRUE
                        AS
                        COPY INTO "{database}"."{schema_name}"."{table_name}"
                        FROM (
                        SELECT TO_TIMESTAMP(METADATA$START_SCAN_TIME)::TIMESTAMP_NTZ AS snowpipe_insertion_time, {', '.join([f'$1:{k}::{v}' for k,v in schema.items()])}
                        FROM @{database}.{schema_name}.{stage_name}/{table}/ 
                        ) 
                        FILE_FORMAT = (TYPE = PARQUET)
                        """
                    )

                    execute_query(f'ALTER PIPE "{database}"."{schema_name}"."{pipe_name.upper()}" REFRESH')

                # Temporarily stopped refresh and paused all pipes until we can make this work without loading all rows all the time.
                # Worth reviewing: https://docs.snowflake.com/en/user-guide/data-load-snowpipe-auto-s3

                if table_schema_updated or not pipe_created:
                    execute_query(f'ALTER PIPE "{database}"."{schema_name}"."{pipe_name.upper()}" SET PIPE_EXECUTION_PAUSED=false')
                
                succeeded.append(table_name)
                print(f'Done creating assets for {table_name} -> {i+1}/{len(tables)}')
            
            except Exception as e:
                failed.append((table, str(e)))

        # Close the Snowflake connection
        if len(failed) == 0:
            response = {
                'statusCode': 200,
                'body': json.dumps(f"The function succeeded and updated {len(tables)} tables")
            }
        else:
            error = json.dumps(f"The function managed to update {len(succeeded)}, \n but failed for {len(failed)} tables: {failed}")

            if sentry_dsn:
                sentry_sdk.capture_message(error, "fatal")

            response = {
                'statusCode': 500,
                'body': json.dumps(f"The function managed to update {len(succeeded)} tables: {succeeded}, \n but failed for {len(failed)} tables: {failed}")
            }


    except Exception as e:

        if sentry_dsn:
            sentry_sdk.capture_exception(e)

        print('Error ' + str(e))
        error_message = str(e)
        response = {
            "statusCode": 500,
            "body": json.dumps({"error": error_message})
        }
    finally:
        conn.close()
        if not str(response['statusCode']).startswith('2'):
            print(response)
            sys.exit(1)

        return response