import boto3

def user_exists(iam, user_name):
    try:
        iam.get_user(UserName=user_name)
        return True
    except iam.exceptions.NoSuchEntityException:
        return False

def policy_exists(iam, policy_name):
    policies = iam.list_policies(Scope='Local')['Policies']
    for policy in policies:
        if policy['PolicyName'] == policy_name:
            return policy['Arn']
    return None

iam = boto3.client('iam')
user_name = "terraform-cloud"

if not user_exists(iam, user_name):
    iam.create_user(UserName=user_name)
    print(f"Created IAM user: {user_name}")
else:
    print(f"IAM user {user_name} already exists")

policy_name = "TerraformCloudCustomPolicy"
policy_document = '''
{
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
                "s3:Describe*",
                "s3:Put*",
                "rds:Describe*",
                "ec2:Describe*",
                "ec2:Revoke*",
                "secretsmanager:Create*",
                "secretsmanager:Get*",
                "secretsmanager:*",
                "secretsmanager:Put*",
                "secretsmanager:Describe*",
                "rds:ListTagsForResource",
                "dms:*",
                "ec2:Describe*",
                "ec2:DescribeSubnets",
                "ec2:DescribeVpcAttribute",
                "ec2:ModifyVpcAttribute",
                "ec2:Authorize*",
                "ec2:*",
                "iam:Create*",
                "ecr:*",
                "iam:Get*",
                "iam:List*",
                "iam:Describe*",
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
                "dms:*"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:*"
            ],
            "Resource": [
                "arn:aws:s3:::data-transfer-nexgen-snowflake",
                "arn:aws:s3:::data-transfer-nexgen-snowflake/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "*"
            ],
            "Resource": "*",
            "Condition": {
                "StringEquals": {
                    "aws:ResourceTag/CreatedBy": "Terraform"
                }
            }
        }

    ]
}'''

policy_arn = policy_exists(iam, policy_name)
if policy_arn is None:
    response = iam.create_policy(
        PolicyName=policy_name,
        PolicyDocument=policy_document
    )
    policy_arn = response['Policy']['Arn']
    print(f"Created custom policy: {policy_name}")
else:
    print(f"Policy {policy_name} already exists")
    response = iam.list_policy_versions(PolicyArn=policy_arn)
    policy_versions = response['Versions']
    if len(policy_versions) >= 5:
        oldest_version = sorted(policy_versions, key=lambda x: x['CreateDate'])[0]
        iam.delete_policy_version(PolicyArn=policy_arn, VersionId=oldest_version['VersionId'])
    iam.create_policy_version(PolicyArn=policy_arn, PolicyDocument=policy_document, SetAsDefault=True)
    print(f"Updated custom policy: {policy_name}")

attached_policies = iam.list_attached_user_policies(UserName=user_name)['AttachedPolicies']
if not any(p['PolicyArn'] == policy_arn for p in attached_policies):
    iam.attach_user_policy(
        UserName=user_name,
        PolicyArn=policy_arn
    )
    print(f"Attached policy '{policy_name}' to user '{user_name}'")
else:
    print(f"Policy '{policy_name}' is already attached to user '{user_name}'")
