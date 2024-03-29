import hashlib
import hmac
import json
import requests
import base64
import time
import random
import urllib.parse
import boto3
from botocore.exceptions import ClientError
import sys
from awsglue.utils import getResolvedOptions

args = getResolvedOptions(sys.argv, ['kinesisfirehose','secretmanager','region','service'])

kinesisfirehose_name = str(args['kinesisfirehose'])
secretmanager_name = str(args['secretmanager'])
region_name = str(args['region'])
service = str(args['service'])


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



def getRestApi(account_id, consumer_key, consumer_secret, token, token_secret, url,offset,fullresult):
    nonce = generateNonce()
    current_time = str(int(time.time()))
    signature = generateSignature('GET', url, consumer_key, nonce, current_time, token, consumer_secret, token_secret,offset)

    payload = ""

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
    #print(headers)
    if (fullresult == True ):
        response = requests.request("GET", url + '?offset=' + str(offset), data=payload, headers=headers)
    else:
        response = requests.request("GET", url , data=payload, headers=headers)
    #print(url)
    return json.loads(response.text)


def put_kinesis_firehose(data):
    firehose = boto3.client('firehose')
    stream_name = 'netsuite-data-ingestion-purchaseorder'
    # stream_name = 'json_stream'
    # Put the data to the delivery stream
    response = firehose.put_record(
        DeliveryStreamName=stream_name,
        Record={
            'Data': data
        }
    )

    # Check the response for any errors
    if response['ResponseMetadata']['HTTPStatusCode'] == 200:
        print('Data sent to the delivery stream successfully.')
    else:
        print('Failed to send data to the delivery stream.')


account_id = "4918734"
consumer_key = "552eae749829796b995b9a3a7d8fee9508c53007c2c69e7b9fb9bccc12fc1308"
consumer_secret = "ec58fd7c1c051e98c21bc5dbde0f1402ecd85e5dbf3ea6664877955aeec1cc83"
token = "70992e488a68fdf1c446a11b1e74cf2e5924667bb8269395bb87de096450d1b5"
token_secret = "6a3b56aaef1c5619f470774b0d1de12e3445762d863468328b4c16ff4677b847"
url = "https://4918734.suitetalk.api.netsuite.com/services/rest/record/v1/purchaseorder"
offset = 0
all_records = getRestApi(account_id=account_id, consumer_key=consumer_key, consumer_secret=consumer_secret, token=token,
               token_secret=token_secret, url=url, offset=offset, fullresult=True)
total_records = (all_records['totalResults'])

while (offset < total_records):

    response = json.dumps(getRestApi(account_id=account_id, consumer_key=consumer_key, consumer_secret=consumer_secret, token=token,token_secret=token_secret, url=url, offset=offset, fullresult=True))

    dict_response = json.loads(response)
    dict_response['items']
    print(offset)
    for i in dict_response['items']:
        id = i['id']
        record = json.dumps(
            getRestApi(account_id=account_id, consumer_key=consumer_key, consumer_secret=consumer_secret, token=token,
                       token_secret=token_secret, url=url + '/' + id, offset=None, fullresult=False))
        #print("id: ",id)
        print(record)
    offset = offset+1000