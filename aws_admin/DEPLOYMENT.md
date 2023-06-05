# Steps for Deploying NexGen-ELT-Snowflake-Data

This guide provides detailed instructions on how to deploy the NexGen-ELT-Snowflake-Data project. These instructions assume that you have a GitHub account and an AWS account.

## Prerequisites

Before starting, make sure you have the following:

- A GitHub account
- An AWS account
- `awscli` installed on your local machine
- `boto3` installed on your local machine

## Deployment Steps

1. Clone the GitHub repo by running the following command in your terminal:

    ```
    git clone https://github.com/Lucion-Environmental/NexGen-ELT-Snowflake-Data -b main
    ```

2. Activate the admin `awscli` profile with the following command:

    ```
    aws configure --profile <nameofyour_aws_profile> --region eu-west-1
    ```

    This will allow you to use an admin user that has the right to provision IAM on the account.

3. Navigate to the project root directory in your terminal and run the following commands:

    ```
    export AWS_PROFILE='<nameofyour_aws_profile>'
    pip install boto3
    python admin/create_tf_user_assume.py
    ```

    This will create a new user named `tf_cloud_assume_user`.

4. Go to the AWS console, log in to your account, and navigate to IAM. Create a key pair for the user that was generated in the previous step (`tf_cloud_assume_user`) and record the key pair.

5. Go to Terraform Cloud at `https://app.terraform.io/app`. Log in and go to the workspace for the environment you want to deploy to. Update the workspace variables with the key pair you created in the previous step.

6. Add the AWS credentials to the GitHub variables and re-run the pipeline from GitHub Actions:

    - Go to the GitHub repo at `https://github.com/Lucion-Environmental/NexGen-ELT-Snowflake-Data` and navigate to Settings > Security > Secrets and Variables > Actions.
    - Update the respective AWS secrets with their new value.
    - Trigger the `release` pipeline by going to Actions and clicking the "Run workflow" button.

That's it! Your project should now be successfully deployed.
