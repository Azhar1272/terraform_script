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
import attr
from attr.validators import instance_of

@attr.s
class Fetch:

    limit = attr.ib()
    rate = attr.ib(default=5, converter=int)

    async def fetch(self, url, limit):

        async with self.limit:
            async with aiohttp.ClientSession() as session:
                async with session.request("GET", url) as response:
                    await response.text()
                    print(response.status)
                    await asyncio.sleep(self.rate)

async def main(urls,rate,limit):
    limit = asyncio.Semaphore(limit)
    f = Fetch(rate=rate, limit=limit)
    tasks = []
    for url in urls:
        tasks.append(f.fetch(url=url, limit=limit))
    results = await asyncio.gather(*tasks)
urls = []
for n in range(1000):
    url = f'http://httpbin.org/anything/{n}'
    urls.append(url)

print(urls)
limit = 100
rate = 5
if len(urls) > 0:
    print("Total number of items to process: ", len(urls))
    asyncio.run(main(urls,rate=rate,limit=limit))
else:
    print("No records to process!")