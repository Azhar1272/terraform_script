import boto3
import time

def create_or_update_policy(policy_name, policy_document):
    try:
        policy = iam.create_policy(
            PolicyName=policy_name,
            PolicyDocument=policy_document
        )
        print(f"Policy {policy_name} created.")
    except iam.exceptions.EntityAlreadyExistsException:
        print(f"Policy {policy_name} already exists.")
        policy = iam.get_policy(PolicyArn=f"arn:aws:iam::{iam.get_user()['User']['Arn'].split(':')[4]}:policy/{policy_name}")

        # Check if the policy has the maximum number of versions
        versions = iam.list_policy_versions(PolicyArn=policy['Policy']['Arn'])['Versions']
        if len(versions) >= 5:
            # Delete the oldest non-default version
            oldest_non_default_version = min((v for v in versions if not v['IsDefaultVersion']), key=lambda v: v['CreateDate'])
            iam.delete_policy_version(PolicyArn=policy['Policy']['Arn'], VersionId=oldest_non_default_version['VersionId'])

        # Create a new policy version and set it as the default
        iam.create_policy_version(
            PolicyArn=policy['Policy']['Arn'],
            PolicyDocument=policy_document,
            SetAsDefault=True
        )
        print(f"Policy {policy_name} updated.")
    return policy

def attach_role_policy(role_name, policy_arn):
    # Check if the policy is already attached to the role
    attached_policies = iam.list_attached_role_policies(RoleName=role_name)['AttachedPolicies']
    if any(policy['PolicyArn'] == policy_arn for policy in attached_policies):
        print(f"Policy {policy_arn} already attached to role {role_name}.")
    else:
        # Attach the policy to the role
        iam.attach_role_policy(RoleName=role_name, PolicyArn=policy_arn)
        print(f"Policy {policy_arn} attached to role {role_name}.")


# AWS clients
iam = boto3.client('iam')

# User creation
user_name = 'tf_cloud_assume_user'

try:
    iam.get_user(UserName=user_name)
    print(f"User {user_name} already exists.")
except iam.exceptions.NoSuchEntityException:
    iam.create_user(UserName=user_name)
    print(f"User {user_name} created.")

# Policy names and documents
policy_name_1 = "policy-StsAssumeRole-terraform"
policy_document_1 = '''{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Resource": "*"
        }
    ]
}'''

policy_name_2 = "TerraformCloudCustomPolicy"
policy_document_2 = '''{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "iam:*"
            ],
            "Resource": [
                "arn:aws:iam::*:role/*",
                "arn:aws:iam::*:user/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:Create*",
                "s3:Create*",
                "s3:Get*",
                "s3:List*",
                "s3:Put*",
                "rds:Describe*",
                "ec2:Describe*",
                "ec2:Revoke*",
                "secretsmanager:Create*",
                "secretsmanager:Get*",
                "secretsmanager:List*",
                "secretsmanager:Put*",
                "secretsmanager:Describe*",
                "secretsmanager:Tag*",
                "rds:List*",
                "rds:Describe*",
                "rds:Get*",
                "dms:Describe*",
                "dms:Create*",
                "dms:Delete*",
                "dms:Modify*",
                "dms:List*",
                "dms:Start*",
                "ec2:DescribeSubnets",
                "ec2:DescribeVpcAttribute",
                "ec2:ModifyVpcAttribute",
                "ec2:Authorize*",
                "ec2:Create*",
                "ec2:Delete*",
                "ec2:Describe*",
                "ec2:Modify*",
                "iam:Create*",
                "ecr:*",
                "iam:Get*",
                "iam:List*",
                "iam:Put*",
                "lambda:*",
                "cloudwatch:*",
                "cloudformation:*",
                "apigateway:*",
                "logs:*",
                "events:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dms:Describe*",
                "dms:Create*",
                "dms:Delete*",
                "dms:Modify*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::data-transfer-nextgen-snowflake",
                "arn:aws:s3:::data-transfer-nextgen-snowflake/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:Delete*",
                "s3:Delete*",
                "rds:Delete*",
                "secretsmanager:Delete*",
                "dms:Delete*",
                "iam:Delete*",
                "ecr:Delete*",
                "lambda:Delete*",
                "cloudwatch:Delete*",
                "cloudformation:Delete*",
                "apigateway:Delete*",
                "logs:Delete*",
                "events:Delete*"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/CreatedBy": "Terraform"
                }
            }
        }
    ]
}
'''

# Create or update policies
policy_1 = create_or_update_policy(policy_name_1, policy_document_1)
policy_2 = create_or_update_policy(policy_name_2, policy_document_2)

# Attach policies to user
iam.attach_user_policy(UserName=user_name, PolicyArn=policy_1['Policy']['Arn'])
print(f"Policy {policy_name_1} attached to user {user_name}.")
# iam.attach_user_policy(UserName=user_name, PolicyArn=policy_2['Policy']['Arn'])
# print(f"Policy {policy_name_2} attached to user {user_name}.")


# Create the role with a temporary AssumeRole policy
temp_assume_role_policy_document = '''{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "sts.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}'''

role_name = "iam_role_terraform_v1"
try:
    role = iam.create_role(
        RoleName=role_name,
        AssumeRolePolicyDocument=temp_assume_role_policy_document,
    )
    print(f"Role {role_name} created.")
except iam.exceptions.EntityAlreadyExistsException:
    print(f"Role {role_name} already exists.")
    role = iam.get_role(RoleName=role_name)

# Get the ARN of the newly created role
role_arn = role["Role"]["Arn"]

# Use the ARN of the tf_cloud_assume_user
tf_cloud_assume_user_arn = iam.get_user(UserName=user_name)['User']['Arn']

assume_role_policy_document = f'''{{
    "Version": "2012-10-17",
    "Statement": [
        {{
            "Effect": "Allow",
            "Principal": {{
                "Service": "sts.amazonaws.com",
                "AWS": [
                    "{tf_cloud_assume_user_arn}",
                    "{role_arn}"
                ]
            }},
            "Action": "sts:AssumeRole"
        }}
    ]
}}'''
# policy_3 = create_or_update_policy(assume_policy_name, assume_role_policy_document)



# Update the AssumeRole policy with the correct ARN


for policy_arn in [policy_2['Policy']['Arn'], policy_1['Policy']['Arn']]:
    attach_role_policy(role_name=role_name, policy_arn=policy_arn)
    # iam.attach_role_policy(
    #     RoleName=role_name,
    #     PolicyArn=policy_arn
    # )

# Update the role with the new AssumeRole policy
print('sleeping for 20 secs...')
time.sleep(20)

iam.update_assume_role_policy(
    RoleName=role_name,
    PolicyDocument=assume_role_policy_document
)
print(f"AssumeRole policy for {role_name} updated.")
# Update the role with the new AssumeRole policy
# iam.update_assume_role_policy(
#     RoleName=role_name,
#     PolicyDocument=policy_document_2
# )
# print(f"AssumeRole policy for {role_name} updated.")

response = iam.create_access_key(
    UserName=user_name
)

access_key_id = response['AccessKey']['AccessKeyId']
secret_access_key = response['AccessKey']['SecretAccessKey']
print('###########################################################################')
print(f"#### Credentials to import into TF cloud for impersonating {user_name}")
print('###########################################################################')

print(f'Access key ID: {access_key_id}')
print(f'Secret access key: {secret_access_key}')
