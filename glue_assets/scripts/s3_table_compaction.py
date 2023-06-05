from common import common

## @params: [JOB_NAME]
raise_on_error = True
args = common.capture_args(['JOB_NAME', 'filesize_mb', 'S3_PREFIX', 'PRIME_BUCKET', 'PRIME_PREFIX'])
sc = common.SparkContext()
glueContext = common.GlueContext(sc)
logger = glueContext.get_logger()
spark = glueContext.spark_session
job = common.Job(glueContext)
job.init(args['JOB_NAME'], args)
    

if args['S3_PREFIX'] == "all":

    prefix_list = common.get_all_prefixes()
    
    for prefix in prefix_list:
        
        table_name = prefix.split("/")[-2]
        args['S3_PREFIX'] = table_name + "/"
        
        if table_name not in ["ETL_CAR_TEST_V4", "ETL_TEST_SHIP_V4", "images"] :
        
            #Declare folder paths to resize
            folder_path = f"s3://{args['PRIME_BUCKET']}/{args['PRIME_PREFIX']}{args['S3_PREFIX']}"
            folder_path_out = f"s3://data-glue-assets/{args['PRIME_PREFIX']}out/{args['S3_PREFIX']}"
            
            #Read data into the dataframe
            df = spark.read.parquet(folder_path) 
            
            total_datasize = common.get_datasize(args['PRIME_BUCKET'], args['PRIME_PREFIX'], args['S3_PREFIX'])
            partition_count = total_datasize//int(args['filesize_mb'])
            
            #Rewrite data as per required size to out folder
            df.repartition(partition_count).write.mode("overwrite").parquet(folder_path_out)
            
            logger.info("Write resized date to :" + folder_path)
            
            #Write resized data to original folder
            df_resized = spark.read.parquet(folder_path_out)
            df_resized.write.mode("overwrite").parquet(folder_path)
            
            #truncate data in temp folder
            df_resized.limit(0).write.mode("overwrite").parquet(folder_path_out)
            
            logger.info("s3_key updated:" + folder_path)    
    
else:    
    #Declare folder paths to resize
    folder_path = f"s3://{args['PRIME_BUCKET']}/{args['PRIME_PREFIX']}{args['S3_PREFIX']}"
    folder_path_out = f"s3://data-glue-assets/{args['PRIME_PREFIX']}out/{args['S3_PREFIX']}"
    
    #Read data into the dataframe
    df = spark.read.parquet(folder_path) 
    
    total_datasize = common.get_datasize(args['PRIME_BUCKET'], args['PRIME_PREFIX'], args['S3_PREFIX'])
    partition_count = total_datasize//int(args['filesize_mb'])
    
    #Rewrite data as per required size to out folder
    df.repartition(partition_count).write.mode("overwrite").parquet(folder_path_out)
    
    logger.info("Write resized date to :" + folder_path)
    
    #Write resized data to original folder
    df_resized = spark.read.parquet(folder_path_out)
    df_resized.write.mode("overwrite").parquet(folder_path)
    
    #truncate data in temp folder
    df_resized.limit(0).write.mode("overwrite").parquet(folder_path_out)
    
    logger.info("s3_key updated:" + folder_path)

job.commit()
