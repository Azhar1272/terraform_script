import json

import boto3

# Create IAM client
iam = boto3.client('iam')
sts = boto3.client('sts')

# Retrieve the account ID
response = sts.get_caller_identity()
print(response)
account_id = response['Account']
print(account_id)
# Create a policy
policy = {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:DescribeSecret",
                "secretsmanager:GetResourcePolicy",
                "secretsmanager:GetSecretValue"
            ],
            "Resource": [
                f"arn:aws:secretsmanager:*:secret:sftp_integration_files_user_secret*"
            ]

        }

    ]
}

'''
# Define other ARN components
bucket_name = 'my-bucket'
object_key = 'my-object'

# Construct the ARN using the retrieved account ID
my_arn = f'arn:aws:s3:::{bucket_name}/{object_key}'
'''


print(policy)


response = iam.create_policy(
  PolicyName='test-terraform-user-access-policy',
  PolicyDocument=json.dumps(policy)
)



print(response)