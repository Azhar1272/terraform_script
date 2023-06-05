# Local development

### 1 - Set up 
* your AWS CLI – https://aws.amazon.com/getting-started/guides/setup-environment/module-three/
*  *Docker* in your local machine to be able to build the image – https://docs.docker.com/desktop/install/windows-install/
* Install and set up the serverless framework to be able to deploy the lambda, the framework should use the same AWS authentication method/credentials as the rest – https://www.serverless.com/framework/docs/providers/fn/guide/installation
In your machine to be able to build the image

2 - Run `sh docker_build.sh` to build the image locally + upload to ECR – in the current state we can't get serverless to build the image

3 - Run `sls deploy` to redeploy the Lambda