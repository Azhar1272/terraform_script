from utils import utils

## @params: [JOB_NAME, URL, WAREHOUSE, DB, SCHEMA, USERNAME, PASSWORD]
SNOWFLAKE_SOURCE_NAME = "net.snowflake.spark.snowflake"
args = utils.capture_args(['JOB_NAME', 'S3_OUTPUT_PATH', 'TABLE_NAME', 'JDBC_SECRET_NAME', 'PRIME_BUCKET', 'PRIME_PREFIX'])
sc = utils.SparkContext()
glueContext = utils.GlueContext(sc)
logger = glueContext.get_logger()
spark = glueContext.spark_session
job = utils.Job(glueContext)
job.init(args['JOB_NAME'], args)
utils.java_import(spark._jvm, SNOWFLAKE_SOURCE_NAME)
## uj = sc._jvm.net.snowflake.spark.snowflake
spark._jvm.net.snowflake.spark.snowflake.SnowflakeConnectorUtils.enablePushdownSession(spark._jvm.org.apache.spark.sql.SparkSession.builder().getOrCreate())
secret_name_snowflake = args["JDBC_SECRET_NAME"]
    
        
secret_dict = utils.json.loads(
        utils.get_secret(secret_name_snowflake)
        )
    
        
account = secret_dict["snowflake"]["account_name"]
user = secret_dict["snowflake"]["username"]
password = secret_dict["snowflake"]["password"]
database = secret_dict["snowflake"]["database_name"]
schema_name = secret_dict["snowflake"]["schema_name"]
role_name = secret_dict["snowflake"]["role_name"]
warehouse_name = secret_dict["snowflake"]["warehouse_name"]
url = f"https://{account}.snowflakecomputing.com"    


sfOptions = {
"sfURL" : url,
"sfUser" : user,
"sfPassword" : password,
"sfDatabase" : database,
"sfSchema" : schema_name,
"sfWarehouse" : warehouse_name,
"application" : "AWSGlue"
}

table_name = args["TABLE_NAME"] 

if table_name == "all" or args['S3_OUTPUT_PATH'] == "all":
    
    prefix_list = get_all_prefixes()
    
    for prefix in prefix_list:
        
        ## Read from a Snowflake table into a Spark Data Frame
        table_name = prefix.split("/")[-2]
        args['S3_OUTPUT_PATH'] = table_name + "/"
        
        if table_name not in ["ETL_CAR_TEST_V4", "ETL_TEST_SHIP_V4", "images"] :
            snow_df = spark.read.format(SNOWFLAKE_SOURCE_NAME).options(**sfOptions).option("dbtable", table_name).load()
            logger.info(f"Read data from snowflake table {table_name} with count {snow_df.count()}")
            
            ## Create empty dataframe to truncate snowflake table
            snow_df_empty = snow_df.limit(0)
            
            ## Write the empty Data Frame contents back to Snowflake 
            snow_df_empty.write.format(SNOWFLAKE_SOURCE_NAME).options(**sfOptions).option("dbtable", table_name).mode("overwrite").save()
            logger.info("Truncate data from snowflake table")
            
            ## Move to terraform
            folder_path = f"s3://{args['PRIME_BUCKET']}/{args['PRIME_PREFIX']}{args['S3_OUTPUT_PATH']}"
            
            ## Write new s3 data to snoflake table
            df_new = spark.read.parquet(folder_path) 
            df_new.write.format(SNOWFLAKE_SOURCE_NAME).options(**sfOptions).option("dbtable", table_name).mode("overwrite").save()
            logger.info(f"Loaded new data to snowflake table {table_name} with count {df_new.count()}")

else:
    
    ## Read from a Snowflake table into a Spark Data Frame
    snow_df = spark.read.format(SNOWFLAKE_SOURCE_NAME).options(**sfOptions).option("dbtable", table_name).load()
    logger.info(f"Read data from snowflake table {table_name} with count {snow_df.count()}")
    
    ## Create empty dataframe to truncate snowflake table
    snow_df_empty = snow_df.limit(0)
    
    ## Write the empty Data Frame contents back to Snowflake 
    snow_df_empty.write.format(SNOWFLAKE_SOURCE_NAME).options(**sfOptions).option("dbtable", table_name).mode("overwrite").save()
    logger.info("Truncate data from snowflake table")
    
    ## Move to terraform
    folder_path = f"s3://{args['PRIME_BUCKET']}/{args['PRIME_PREFIX']}{args['S3_OUTPUT_PATH']}"
    
    ## Write new s3 data to snoflake table
    df_new = spark.read.parquet(folder_path) 
    df_new.write.format(SNOWFLAKE_SOURCE_NAME).options(**sfOptions).option("dbtable", table_name).mode("overwrite").save()
    logger.info(f"Loaded new data to snowflake table {table_name} with count {df_new.count()}")


job.commit()
