# Lambda testing scenerios 

**1. New table creation and new snowpipe creation**

| Scenario                                         | Status                                          | Details                                         |
|--------------------------------------------------|-------------------------------------------------|-------------------------------------------------|                                                              
| Create new table in source |  ✅ | No change , lambda or snowpipe gets triggered only when new file is added to s3|
| Add records to the table |  ✅    | New file is added to S3 by DMS . When lambda is executed, new table and snowpipe is created in uppercase |
| Add new records |  ✅    | Snowpipe automatically adds the data to snowflake table with Op as 'I' |
| Delete records |  ✅    | Snowpipe automatically adds the data to snowflake table with Op as 'D' |
| Update records |  ✅    | Snowpipe automatically adds the data to snowflake table with Op as 'U' |

**2. New columns added to the source schema**

| Scenario                                         | Status                                          | Details                                         |
|--------------------------------------------------|-------------------------------------------------|-------------------------------------------------|                                                              
| Added new columns to source schema               |  ✅                                             |No change , lambda or snowpipe gets triggered only when new file is added                                                 |
| Added new records to source schema               | ✅                                              | After lambda execution , new columns are added and new records are added to the snowflake table                                              |
| Delete records                                  | ✅                                              | Snowpipe refresh works with creating Op value as D and adding deleted records                                                |
| Update records                                  | ✅                                              | Snowpipe refresh works with creating Op value as U and adding updated records                                                |


**3.Dropped columns from the source schema**

| Scenario                                         | Status                                          | Details                                         |
|--------------------------------------------------|-------------------------------------------------|-------------------------------------------------|                                                              
|Dropped existing columns in source schema         |   ✅                                            |    No change , lamda or snowpipe gets triggred when file is added to s3                                         |
|Added new records to the source table             |   ✅                                            |     The snowpipe refresh happens with marking the dropped columns as null in the snowflake table                                            |
|                                                  |   ✅                                            |       
| Delete records                                  | ✅                                              |         snowpipe refresh works with creating Op value as D and dropped columns as null                                          |
| Update records                                  | ✅                                              |              snowpipe refresh works with creating Op as U and dropped column as null                                         |                                    |

**4.Add the Dropped columns back to source schema**

| Scenario                                         | Status                                          | Details                                         |
|--------------------------------------------------|-------------------------------------------------|-------------------------------------------------|                                                              
|Add dropped columns back in source schema         |   ✅                                            |    No change , lamda or snowpipe gets triggred when file is added to s3                                         |
|Added new records to the source table             |   ✅                                            |   Snowpipe refresh works fine with copying the data                                           |
|                                                  |   ✅                                            |       
| Delete records                                  | ✅                                              |         snowpipe refresh works with creating Op value as D and dropped columns as null                                          |
| Update records                                  | ✅                                              |              snowpipe refresh works with creating Op as U and dropped column as null                                         |                                    |

**5.Delete the snowpipe or case sensitive change - To test the negative scenerio**

| Scenario                                         | Status                                          | Details                                         |
|--------------------------------------------------|-------------------------------------------------|-------------------------------------------------|                                                              
| Delete the snowpipe when columns are deleted from source schem             |  🔴                   |When the snowpipe is deleted , the new snowpipe create or replace tries to get executed and errors out since the column count is not matching with the table|
| Create a snowpipe with lowercase to test the negative test case | 🔴 | It fails because the number of columns does not match with table and snowpipe create or replace statement |

**6.Delete the table or case sensitive change - To test the negative scenerio**
| Scenario                                         | Status                                          | Details                                         |
|--------------------------------------------------|-------------------------------------------------|-------------------------------------------------|     
| Delete the table                                 | ✅                                              | When lambda is executed,  new table is created |
| Delete the table |🟡| Need to test the snowpipe statement with this |