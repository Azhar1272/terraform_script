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
import attr
from awsglue.utils import getResolvedOptions
from botocore.exceptions import ClientError

args = getResolvedOptions(sys.argv, ['kinesisfirehose','secretmanager','region','service','fullload'])

kinesisfirehose_name = str(args['kinesisfirehose'])
secretmanager_name = str(args['secretmanager'])
region_name = str(args['region'])
service = str(args['service'])
fullload = args['fullload']
prevday = date.today() + timedelta(days=-2)
current_date = str(prevday.strftime("%d/%m/%Y"))
limit, rate = 10, 5
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

@attr.s
class Fetch:
    limit = attr.ib()
    rate = attr.ib(default=5, converter=int)

    async def fetch(self, url, limit, headers_auth):
        async with self.limit:
            async with aiohttp.ClientSession() as session:
                async with session.request("GET", url, headers=headers_auth) as response:
                    put_kinesis_firehose(await response.text())
                    print(url, response.status)
                    await asyncio.sleep(self.rate)


def generateNonce(length=11):
    """Generate pseudorandom number"""
    return ''.join([str(random.randint(0, 9)) for i in range(length)])


def generateSignature(method, url, consumer_key, nonce, current_time, token, consumer_secret,
                      token_secret, offset):
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
    response = requests.request("GET", url, auth=auth, headers=headers, params=params)
    # print(json.loads(response.text))
    return json.loads(response.text)

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
            'q': f'lastModifiedDate AFTER "' + current_date + '"'
        }
    response = get_response(url, params)
    # print("::::: Response: ",response)
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
                'q': f'lastModifiedDate AFTER "' + current_date + '"',
                'offset': offset
            }
        response = json.dumps(get_response(url, params=param_offset))
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


async def main(urls, rate, limit):
    # limit = asyncio.Semaphore(limit)
    limit = Throttler(rate_limit=limit, period=rate)
    f = Fetch(rate=rate, limit=limit)
    tasks = []
    for url in urls:
        headers_auth = return_headers_auth(url)
        tasks.append(f.fetch(url=url, limit=limit, headers_auth=headers_auth))
    results = await asyncio.gather(*tasks)


'''
for n in range(1000):
    url = f'http://httpbin.org/anything/{n}'
    urls.append(url)
'''
# print(urls)
if __name__ == "__main__":
    print("Calling service:", service)
    urls = return_url_list()
    if len(urls) > 0:
        print("Total number of items to process: ", len(urls))
        asyncio.run(main(urls, rate=rate, limit=limit))
    else:
        print("No records to process!")
