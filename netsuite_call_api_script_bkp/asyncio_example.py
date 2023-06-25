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
from datetime import datetime
from asyncio_throttle import Throttler
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

print("Start::::::::::::", datetime.now())
account_id = "4918734"
consumer_key = "552eae749829796b995b9a3a7d8fee9508c53007c2c69e7b9fb9bccc12fc1308"
consumer_secret = "ec58fd7c1c051e98c21bc5dbde0f1402ecd85e5dbf3ea6664877955aeec1cc83"
token = "70992e488a68fdf1c446a11b1e74cf2e5924667bb8269395bb87de096450d1b5"
token_secret = "6a3b56aaef1c5619f470774b0d1de12e3445762d863468328b4c16ff4677b847"
url = "https://4918734.suitetalk.api.netsuite.com/services/rest/record/v1/customer"
offset = 0
all_records = getRestApi(account_id=account_id, consumer_key=consumer_key, consumer_secret=consumer_secret, token=token,
               token_secret=token_secret, url=url, offset=offset, fullresult=True)
#print(all_records)
total_records = (all_records['totalResults'])
#print(total_records)
url_list = []
while (offset < total_records):

    response = json.dumps(getRestApi(account_id=account_id, consumer_key=consumer_key, consumer_secret=consumer_secret, token=token,
               token_secret=token_secret, url=url, offset=offset, fullresult=True))
    dict_response = json.loads(response)
    dict_response['items']
    #print(offset)
    j = 0
    for i in dict_response['items']:

        id = i['id']
        url_with_id = url + "/" + id
        url_list.append(url_with_id)
        j = j+1
    offset = offset + 1000

async def fetch(session,account_id, consumer_key, consumer_secret, token, token_secret, url):
    #await asyncio.sleep(10)
    nonce = generateNonce()
    current_time = str(int(time.time()))
    offset = None
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
    throttler = Throttler(rate_limit=100,period=60)
    while True:
        await asyncio.sleep(random.random() * 2)
        async with throttler:
            #print(url)
            async with session.request("GET", url , headers=headers) as response:
                print(await response.status)
                #return await response.text()

async def fetch_all(urls, loop):
    async with aiohttp.ClientSession(loop=loop) as session:
        #await asyncio.sleep(3)
        results = await asyncio.gather(*[fetch(session,account_id, consumer_key, consumer_secret, token, token_secret, url) for url in urls], return_exceptions=True)
        #await asyncio.sleep(3)
        return results

if __name__ == '__main__':
    loop = asyncio.get_event_loop()
    urls = url_list
    htmls = loop.run_until_complete(fetch_all(urls, loop))
    print(htmls)