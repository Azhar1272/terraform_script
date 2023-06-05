import boto3

iam = boto3.client('iam')
user_name = "terraform-cloud"
policy_name = "TerraformCloudCustomPolicy"

def detach_user_policy(iam, user_name, policy_arn):
    try:
        iam.detach_user_policy(UserName=user_name, PolicyArn=policy_arn)
        print(f"Detached policy '{policy_name}' from user '{user_name}'.")
    except iam.exceptions.NoSuchEntityException:
        print(f"Policy '{policy_name}' is not attached to user '{user_name}'.")

def delete_policy(iam, policy_arn):
    try:
        versions = iam.list_policy_versions(PolicyArn=policy_arn)['Versions']
        for version in versions:
            if not version['IsDefaultVersion']:
                iam.delete_policy_version(PolicyArn=policy_arn, VersionId=version['VersionId'])
        iam.delete_policy(PolicyArn=policy_arn)
        print(f"Deleted policy '{policy_name}'.")
    except iam.exceptions.NoSuchEntityException:
        print(f"Policy '{policy_name}' does not exist.")

def delete_user(iam, user_name):
    try:
        iam.delete_user(UserName=user_name)
        print(f"Deleted user '{user_name}'.")
    except iam.exceptions.NoSuchEntityException:
        print(f"User '{user_name}' does not exist.")
    except iam.exceptions.DeleteConflictException:
        print(f"User '{user_name}' cannot be deleted due to existing resources attached.")

def policy_exists(iam, policy_name):
    policies = iam.list_policies(Scope='Local')['Policies']
    for policy in policies:
        if policy['PolicyName'] == policy_name:
            return policy['Arn']
    return None

policy_arn = policy_exists(iam, policy_name)

if policy_arn:
    detach_user_policy(iam, user_name, policy_arn)
    delete_policy(iam, policy_arn)
else:
    print(f"Policy '{policy_name}' does not exist.")

delete_user(iam, user_name)
