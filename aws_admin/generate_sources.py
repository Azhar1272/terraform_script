import boto3
import json
from fastparquet import ParquetFile
import io
import yaml
from collections import OrderedDict

region_name="eu-west-1"

env_name = 'prod'
# AWS S3 connection parameters
bucket_name = f"data-transfer-nexgen-snowpipe-{env_name.lower()}"

s3_folder_path = "nexgen/"


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

s3 = boto3.resource('s3', region_name=region_name)
bucket = s3.Bucket(bucket_name)


parquet_type_map = {
    0: "boolean",
    1: "integer",
    2: "bigint",
    3: "unsupported", # int96 not supported in DBT
    4: "float",
    5: "double precision",
    6: "varchar",
    7: "varchar",
    8: "timestamp",
    9: "smallint",
    10: "smallint",
    11: "unsupported", # list type not supported in DBT
    12: "unsupported", # struct type not directly supported in DBT
    13: "unsupported", # map type not supported in DBT
    14: "numeric",
    15: "varchar",
    16: "unsupported", # time type not supported in DBT
    17: "date",
    18: "unsupported", # interval type not supported in DBT
    19: "json",
    20: "unsupported", # bson type not supported in DBT
    21: "unsupported", # uuid type not directly supported in DBT
    22: "unsupported", # array type not supported in DBT
    23: "unsupported", # ipaddress type not supported in DBT
    24: "bytea",
    25: "unsupported", # duration type not supported in DBT
    26: "bytea",
    27: "varchar",
    28: "unsupported" # geospatial type not supported in DBT
}

tables_schema = dict()
for i, table in enumerate(tables):
    table_name = table.lower()
    pipe_name = f"{table_name}_pipe"

    # Generate DDL statement to create the table schema dynamically
    ddl_columns = []

    path = list(bucket.objects.filter(Prefix=s3_folder_path + table))[0].key
    parquet_file = ParquetFile(
        f"{path}", 
        open_with=lambda p: io.BytesIO(s3_client.get_object(Bucket=bucket_name, Key=p)["Body"].read()),
    )

    schema = {k:parquet_type_map[v.type] for k,v in parquet_file.schema.schema_elements_by_name.items() if k not in ['schema']}
    tables_schema[table_name] = schema


# Create a list of tables and columns
tables_ready = []
for table_name, columns in tables_schema.items():
    table = {'name': table_name, 'columns': []}
    for column_name, data_type in columns.items():
        column = {'name': column_name, 'data_type': data_type, 'nullable': True}
        table['columns'].append(column)
    tables_ready.append(table)

# Create the YAML dictionary
yaml_dict = OrderedDict({
    'version': 2,
    'sources': [
        OrderedDict([
            ('name', 'snowpipe-ingestion-data'),
            ('database', f'SNOWFLAKE_NEXGEN_{env_name.upper()}'),
            ('schema', 'SNOWPIPE_S3_INGESTION'),
            ('freshness', OrderedDict([
                ('warn_after', OrderedDict([('count', 12), ('period', 'hour')])),
                ('error_after', OrderedDict([('count', 24), ('period', 'hour')]))
            ])),
            ('loaded_at_field', 'SNOWPIPE_INSERTION_TIME'),
            ('description', 'Loaded using Snowpipe from S3 DMS from the MySQL Nexgen instance: Nexgen > DMS > S3 > Snowpipe > Snowflake'),
            ('tables', tables_ready)
        ])
    ]
})

yaml_dict = json.loads(json.dumps(yaml_dict))

# Dump the YAML dictionary to a file
with open('sources.yml', 'w') as f:
    yaml.dump(yaml_dict, f, default_flow_style=False, sort_keys=False)
