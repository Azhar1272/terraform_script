import asyncio
import base64
import hashlib
import hmac
import json
import random
import sys
import time
import urllib.parse
from datetime import date, timedelta
import aiohttp
import attr
import boto3
import requests
from asyncio_throttle import Throttler
from requests_oauthlib import OAuth1
import sentry_sdk
from sentry_sdk.integrations.aws_lambda import AwsLambdaIntegration

limit, rate = 2, 1
url = "https://4918734.suitetalk.api.netsuite.com/services/rest/record/v1/"

headers = {"Content-Type": "application/json"}
account_id = "4918734"
consumer_key = "552eae749829796b995b9a3a7d8fee9508c53007c2c69e7b9fb9bccc12fc1308"
consumer_secret = "ec58fd7c1c051e98c21bc5dbde0f1402ecd85e5dbf3ea6664877955aeec1cc83"
token = "70992e488a68fdf1c446a11b1e74cf2e5924667bb8269395bb87de096450d1b5"
token_secret = "6a3b56aaef1c5619f470774b0d1de12e3445762d863468328b4c16ff4677b847"
service = "customerpayment"
url = url + service
kinesisfirehose_name = "netsuite-data-ingestion-customer"
fullload = 0
auth = OAuth1(
    realm=account_id,
    client_key=consumer_key,
    client_secret=consumer_secret,
    resource_owner_key=token,
    resource_owner_secret=token_secret,
    signature_method="HMAC-SHA256"
)
prevday = date.today() + timedelta(days=-1)
yesterday = str(prevday.strftime("%d/%m/%Y"))
today = str(date.today().strftime("%d/%m/%Y"))
print(yesterday,today)

url_not_200 = []
sentry_dsn = "https://b49b07d9a53040ceb0eb5329ba74d8e6@o4504973294305280.ingest.sentry.io/4505509437636608"

if sentry_dsn:
    sentry_sdk.init(
        dsn=sentry_dsn,
        integrations=[
            AwsLambdaIntegration(),
        ],
        traces_sample_rate=1.0,
    )
def generateNonce(length=11):
    """Generate pseudorandom number"""
    return ''.join([str(random.randint(0, 9)) for i in range(length)])
def generateSignature(method, url, consumer_key, nonce, current_time, token, consumer_secret,token_secret, offset):
    signature_method = 'HMAC-SHA256'
    version = '1.0'

    encoded_url = urllib.parse.quote_plus(url)

    if type(offset) == int:
        collected_string = '&'.join(['oauth_consumer_key=' + consumer_key, 'oauth_nonce=' + nonce,
                                     'oauth_signature_method=' + signature_method,
                                     'oauth_timestamp=' + current_time,
                                     'oauth_token=' + token, 'oauth_version=' + version, 'offset=' + str(offset)])
    else:
        collected_string = '&'.join(['oauth_consumer_key=' + consumer_key, 'oauth_nonce=' + nonce,
                                     'oauth_signature_method=' + signature_method,
                                     'oauth_timestamp=' + current_time,
                                     'oauth_token=' + token, 'oauth_version=' + version])

    encoded_string = urllib.parse.quote_plus(collected_string)
    base = '&'.join([method, encoded_url, encoded_string])
    key = '&'.join([consumer_secret, token_secret])
    digest = hmac.new(key=str.encode(key), msg=str.encode(base), digestmod=hashlib.sha256).digest()
    signature = base64.b64encode(digest).decode()
    return urllib.parse.quote_plus(signature)
def get_response(url, params):
    headers = {"Content-Type": "application/json"}
    try:
        response = requests.request("GET", url, auth=auth, headers=headers, params=params)
        response_output = response.text
        if response.status_code!=200:
            url_not_200.append(url)
            dic_response = json.loads(response.text)
            dic_response.update({"url": url})
            response_output = json.dumps(dic_response)
    except:
        url_not_200.append(url)
        dic_response = {"msg": "url failed due connection issue"}
        dic_response.update({"url": url})
        response_output = json.dumps(dic_response)
    return response_output
def put_kinesis_firehose(data):
    firehose = boto3.client('firehose')
    stream_name = kinesisfirehose_name
    # stream_name = 'json_stream'
    # Put the data to the delivery stream
    response = firehose.put_record(
        DeliveryStreamName=stream_name,
        Record={
            'Data': data
        }
    )
def return_url_list():
    url_list = []
    offset = 0
    if fullload == "1":
        params = ""
    else:
        params = {
            'q': f'lastModifiedDate ON_OR_AFTER "' + yesterday + '" AND lastModifiedDate BEFORE "' + today + '"'
        }
    print(params)
    response = json.loads(get_response(url, params))
    print("::::: Response: ",response)
    try:
        total_records = response['totalResults']
    except:
        print("Exceeds request limit, please try again after sometime")
        sys.exit(1)

    print("::::::Total Number of records to fetch: ", total_records)
    while (offset < total_records):
        print("offset: ", offset)
        if fullload == "1":
            param_offset = {
                'offset': offset
            }
        else:
            param_offset = {
                'q': f'lastModifiedDate ON_OR_AFTER "' + yesterday + '" AND lastModifiedDate BEFORE "' + today + '"',
                'offset': offset
            }
        response = get_response(url, params=param_offset)
        print("::::: Response with offset: ", response)
        dict_response = json.loads(response)
        try:
            dict_response['items']
        except:
            print("Exceeds request limit, please try again after sometime")
            sys.exit(1)
        # print(response)

        j = 0
        for i in dict_response['items']:
            id = i['id']
            url_with_id = url + "/" + id
            url_list.append(url_with_id)
            j = j + 1
        offset = offset + 1000
    return url_list
def return_headers_auth(url):
    nonce = generateNonce()
    current_time = str(int(time.time()))
    offset = None
    signature = generateSignature('GET', url, consumer_key, nonce, current_time, token, consumer_secret,
                                  token_secret,
                                  offset)
    headers_auth = {
        'Authorization': f'OAuth realm="{account_id}",'
                         f'oauth_consumer_key="{consumer_key}",'
                         f'oauth_token="{token}",'
                         f'oauth_signature_method="HMAC-SHA256",'
                         f'oauth_timestamp="{str(int(time.time()))}",'
                         f'oauth_nonce="{nonce}",'
                         f'oauth_version="1.0",'
                         f'oauth_signature="{signature}"'
    }
    return headers_auth
def main(urls):
    for url in urls:
        response = get_response(url=url,params="")
        #put_kinesis_firehose(response)
        print(response)

if __name__ == "__main__":
    #urls = return_url_list()
    #urls.clear()
    #urls = ['https://4918734.suitetalk.api.netsuite.com/services/rest/record/v1/subsidiary/998', 'https://4918734.suitetalk.api.netsuite.com/services/rest/record/v1/subsidiary/2', 'https://4918734.suitetalk.api.netsuite.com/services/rest/record/v1/subsidiary/14', 'https://4918734.suitetalk.api.netsuite.com/services/rest/record/v1/subsidiary/997',  'https://4918734.suitetalk.api.netsuite.com/services/rest/record/v1/subsidiary/999']
    urls = ['https://4918734.suitetalk.api.netsuite.com/services/rest/record/v1/subsidiary/a']
    #print(urls)
    try:
        if len(urls) > 0:
            print("Total number of items to process: ", len(urls))
            main(urls)
            i = 0
            while i < 5 and len(url_not_200) > 0:
                time.sleep(5)
                print(len(url_not_200)," url failed Retying attempt:", i+1,)
                retry_urls = url_not_200
                url_not_200 = []
                main(retry_urls)
                i = i +1
                if i == 5:
                    print("Url failed after retrying 5 times:", url_not_200)
                    error_msg = "netsuite url after retrying 5 times:" + str(url_not_200)
                    sentry_sdk.capture_message(error_msg)

        else:
            print("No records to process!")
    except Exception as e:
        error_msg = service + " failed with error:" + e
        sentry_sdk.capture_message(error_msg)