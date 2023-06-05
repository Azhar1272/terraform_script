import boto3

# AWS clients
iam = boto3.client('iam')

# User deletion
user_name = 'tf_cloud_assume_user'
try:
    # Detach policies first
    attached_policies = iam.list_attached_user_policies(UserName=user_name)['AttachedPolicies']
    for policy in attached_policies:
        iam.detach_user_policy(UserName=user_name, PolicyArn=policy['PolicyArn'])
    # Delete access keys before deleting the user
    access_keys = iam.list_access_keys(UserName=user_name)['AccessKeyMetadata']
    for access_key in access_keys:
        iam.delete_access_key(UserName=user_name, AccessKeyId=access_key['AccessKeyId'])
    iam.delete_user(UserName=user_name)
    print(f"User {user_name} deleted.")
except iam.exceptions.NoSuchEntityException:
    print(f"User {user_name} no longer exists.")

# Policy deletion
policy_name_1 = "policy-StsAssumeRole-terraform"
policy_name_2 = "TerraformCloudCustomPolicy"
for policy_name in [policy_name_1, policy_name_2]:
    try:
        policy = iam.get_policy(PolicyArn=f"arn:aws:iam::{iam.get_user()['User']['Arn'].split(':')[4]}:policy/{policy_name}")
        # Detach policy from all entities
        policy_attachments = iam.list_entities_for_policy(PolicyArn=policy['Policy']['Arn'])
        for attachment in policy_attachments['PolicyUsers']:
            iam.detach_user_policy(UserName=attachment['UserName'], PolicyArn=policy['Policy']['Arn'])
        for attachment in policy_attachments['PolicyRoles']:
            iam.detach_role_policy(RoleName=attachment['RoleName'], PolicyArn=policy['Policy']['Arn'])
        policy_versions = iam.list_policy_versions(PolicyArn=policy['Policy']['Arn'])['Versions']
        for version in policy_versions:
            if not version['IsDefaultVersion']:
                iam.delete_policy_version(PolicyArn=policy['Policy']['Arn'], VersionId=version['VersionId'])
        iam.delete_policy(PolicyArn=policy['Policy']['Arn'])
        print(f"Policy {policy_name} deleted.")
    except iam.exceptions.NoSuchEntityException:
        print(f"Policy {policy_name} no longer exists.")

# Role deletion
role_name = "iam_role_terraform_v1"
try:
    # Detach policies first
    attached_policies = iam.list_attached_role_policies(RoleName=role_name)['AttachedPolicies']
    for policy in attached_policies:
        iam.detach_role_policy(RoleName=role_name, PolicyArn=policy['PolicyArn'])
    iam.delete_role(RoleName=role_name)
    print(f"Role {role_name} deleted.")
except iam.exceptions.NoSuchEntityException:
    print(f"Role {role_name} no longer exists.")
