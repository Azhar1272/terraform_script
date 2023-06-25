import sys
from requests_oauthlib import OAuth1
import hashlib
import hmac
import json
import requests
import base64
import time
import random
import urllib.parse
import boto3
import aiohttp
import asyncio
from datetime import date, timedelta, datetime
from asyncio_throttle import Throttler
from botocore.exceptions import ClientError

########### glue code ################
'''
from awsglue.utils import getResolvedOptions


args = getResolvedOptions(sys.argv, ['kinesisfirehose','secretmanager','region','service','fullload'])

kinesisfirehose_name = str(args['kinesisfirehose'])
secretmanager_name = str(args['secretmanager'])
region_name = str(args['region'])
service = str(args['service'])
fullload = args['fullload']

def getSecrets(secretmanager,region):

    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region
    )

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secretmanager
        )
    except ClientError as e:
        # For a list of exceptions thrown, see
        # https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
        raise e

    # Decrypts secret using the associated KMS key.
    secret = json.loads(get_secret_value_response['SecretString'])
    return secret

secrets = getSecrets(secretmanager_name,region_name)
account_id = secrets["accountid"]
consumer_key = secrets["consumer_key"]
consumer_secret = secrets["consumer_secret"]
token = secrets["token"]
token_secret = secrets["token_secret"]
url = secrets["url"] + service

headers = {"Content-Type": "application/json"}
auth = OAuth1(
    realm=account_id,
    client_key = consumer_key,
    client_secret = consumer_secret,
    resource_owner_key = token,
    resource_owner_secret = token_secret,
    signature_method="HMAC-SHA256"
    )
'''
########### glue code ################


###### Python code ##########
headers = {"Content-Type": "application/json"}
account_id = "4918734"
consumer_key = "552eae749829796b995b9a3a7d8fee9508c53007c2c69e7b9fb9bccc12fc1308"
consumer_secret = "ec58fd7c1c051e98c21bc5dbde0f1402ecd85e5dbf3ea6664877955aeec1cc83"
token = "70992e488a68fdf1c446a11b1e74cf2e5924667bb8269395bb87de096450d1b5"
token_secret = "6a3b56aaef1c5619f470774b0d1de12e3445762d863468328b4c16ff4677b847"
url = "https://4918734.suitetalk.api.netsuite.com/services/rest/record/v1/customer"
kinesisfirehose_name = "netsuite-data-ingestion-customer"
fullload = 0
auth = OAuth1(
    realm=account_id,
    client_key = consumer_key,
    client_secret = consumer_secret,
    resource_owner_key = token,
    resource_owner_secret = token_secret,
    signature_method="HMAC-SHA256"
    )
#### Comment for glue code#######

prevday = date.today() + timedelta(days=-2)
current_date = str(prevday.strftime("%d/%m/%Y"))
def generateNonce(length=11):
    """Generate pseudorandom number"""
    return ''.join([str(random.randint(0, 9)) for i in range(length)])


def generateSignature(method, url, consumer_key, nonce, current_time, token, consumer_secret,
                      token_secret,offset):
    signature_method = 'HMAC-SHA256'
    version = '1.0'

    encoded_url = urllib.parse.quote_plus(url)

    if type(offset) == int:
        collected_string = '&'.join(['oauth_consumer_key=' + consumer_key, 'oauth_nonce=' + nonce,
                                     'oauth_signature_method=' + signature_method, 'oauth_timestamp=' + current_time,
                                     'oauth_token=' + token, 'oauth_version=' + version, 'offset=' + str(offset)])
    else:
        collected_string = '&'.join(['oauth_consumer_key=' + consumer_key, 'oauth_nonce=' + nonce,
                                     'oauth_signature_method=' + signature_method, 'oauth_timestamp=' + current_time,
                                     'oauth_token=' + token, 'oauth_version=' + version])

    encoded_string = urllib.parse.quote_plus(collected_string)
    base = '&'.join([method, encoded_url, encoded_string])
    key = '&'.join([consumer_secret, token_secret])
    digest = hmac.new(key=str.encode(key), msg=str.encode(base), digestmod=hashlib.sha256).digest()
    signature = base64.b64encode(digest).decode()
    return urllib.parse.quote_plus(signature)

def get_response(url,params):
    headers = {"Content-Type": "application/json"}
    response = requests.request("GET", url, auth=auth, headers=headers,params=params)
    #print(json.loads(response.text))
    return json.loads(response.text)

def put_kinesis_firehose(data):
    firehose = boto3.client('firehose')
    stream_name =  kinesisfirehose_name
    #stream_name = 'json_stream'
    # Put the data to the delivery stream
    response = firehose.put_record(
        DeliveryStreamName=stream_name,
        Record={
            'Data': data
        }
    )

    '''
    # Check the response for any errors
    if response['ResponseMetadata']['HTTPStatusCode'] == 200:
        print('Data sent to the delivery stream successfully.')
    else:
        print('Failed to send data to the delivery stream.')
    '''
def return_url_list():
    url_list = []
    offset = 0
    if fullload == "1":
        params = ""
    else:
        params = {
            'q': f'lastModifiedDate AFTER "' + current_date + '"'
        }
    response = get_response(url, params)
    #print("::::: Response: ",response)
    total_records = response['totalResults']
    print("::::::Total Number of records to fetch: " ,total_records)
    while (offset < total_records):
        print("offset: ",offset)
        if fullload == "1":
            param_offset = {
                'offset': offset
            }
        else:
            param_offset = {
                'q': f'lastModifiedDate AFTER "' + current_date + '"',
                'offset': offset
            }
        response = json.dumps(get_response(url,params=param_offset))
        #print(response)
        dict_response = json.loads(response)
        dict_response['items']
        j = 0
        for i in dict_response['items']:
            id = i['id']
            url_with_id = url + "/" + id
            url_list.append(url_with_id)
            j = j + 1
        offset = offset + 1000
    return url_list

async def fetch(session,account_id, consumer_key, consumer_secret, token, token_secret, url,throttler):
    #await asyncio.sleep(10)
    nonce = generateNonce()
    current_time = str(int(time.time()))
    offset = None
    signature = generateSignature('GET', url, consumer_key, nonce, current_time, token, consumer_secret,
                                  token_secret,
                                  offset)

    headers = {
        'Authorization': f'OAuth realm="{account_id}",'
                         f'oauth_consumer_key="{consumer_key}",'
                         f'oauth_token="{token}",'
                         f'oauth_signature_method="HMAC-SHA256",'
                         f'oauth_timestamp="{str(int(time.time()))}",'
                         f'oauth_nonce="{nonce}",'
                         f'oauth_version="1.0",'
                         f'oauth_signature="{signature}"'
    }

    await asyncio.sleep(random.random() * 2)
    async with session.request("GET", url , headers=headers) as response:
        print(await response.text())
            #loop.create_task(put_kinesis_firehose(await response.text()))
            #put_kinesis_firehose(await response.text())

async def main(loop,urlx):
    throttler = Throttler(rate_limit=100,period=5)

    async with aiohttp.ClientSession() as session:
        for url in urlx:
            tasks = [
                loop.create_task(fetch(session,account_id, consumer_key, consumer_secret, token, token_secret, url,throttler))
            ]
        await asyncio.wait(tasks)


urlx = return_url_list()
if len(urlx) > 0:
    print("Total number of items to process: ", len(urlx))
    loop = asyncio.get_event_loop()
    try:
        loop.run_until_complete(main(loop,urlx))
    except asyncio.CancelledError:
        print('\nCancelled')
    finally:
        loop.close()
else:
    print("No records to process!")
