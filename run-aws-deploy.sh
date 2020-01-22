#!/usr/bin/env bash
#
#  One script to rule them all, 
#  one script to find them, 
#  One script to bring them all 
#  and in the darkness bind them.
#
set -ex
#AWS_SECRET_KEY_ID=${AWS_SECRET_ACCESS_KEY:?'Must provide access key id'}
#AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:?'Must provide secret access key id'}
export AWS_DEFAULT_REGION='us-east-2'
export AWS_DEFAULT_OUTPUT='json'
export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:?'Must provide account id'}
export ECR_REGISTRY_ADDRESS=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
export GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
export DOCKER_IMAGE_NAME='employees-api'
export DOCKER_DATA_IMAGE='data-wrapper'
export DOCKER_IMAGE_TAG=${GIT_BRANCH}

export SERVICE_HOST='0.0.0.0'
export SERVICE_PORT='8080'
export DB_FILE='chinook.db'
export FLASK_ENV='production'
export FLASK_APP='server.py'
export API_PREFIX='/api'

export AWS_PROFILE='default'
export APP_NAME=${DOCKER_IMAGE_NAME}
export EB_ENVIRONMENT_NAME=${APP_NAME}-${GIT_BRANCH}
#export EFS_TOKEN='EBFileSystem'
export BACKEND_INSTANCE_TYPE='t2.micro'
export TEST_PAGE_BUCKET="rcbop-test-service-${GIT_BRANCH}"

CWD=$(pwd)

cleanup(){
    #echo 'Cleaning up credentials'
    #aws configure set aws_access_key_id '' --profile "$AWS_PROFILE"
    #aws configure set aws_secret_access_key '' --profile "$AWS_PROFILE"
    cd "$CWD"
    echo 'cleaning up work dir'
    rm -vf elasticbeanstalk/deploy/.ebextensions/eb-efs-config.yaml
    rm -vf elasticbeanstalk/deploy/*
    rm -rf elasticbeanstalk/deploy/.elasticbeanstalk*
    rm -rf elasticbeanstalk/deploy/.gitignore
    rm -rf cloudfront/cloudfront.json
}

trap cleanup EXIT

#echo 'configure aws cli'
#aws configure set region "$AWS_DEFAULT_REGION" --profile "$AWS_PROFILE"
#aws configure set output 'json' --profile "$AWS_PROFILE"

#set +x
#aws configure set aws_access_key_id "$AWS_SECRET_KEY_ID" --profile "$AWS_PROFILE"
#aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile "$AWS_PROFILE"
#set -x

######### FRONTEND
S3_BUCKETS=$(aws s3api list-buckets --profile $AWS_PROFILE)
if [[ "${S3_BUCKETS}" != *${TEST_PAGE_BUCKET}* ]]; then
    echo 'Creating static page s3 bucket'
    aws s3 mb s3://${TEST_PAGE_BUCKET} --region ${AWS_DEFAULT_REGION} --profile "${AWS_PROFILE}"
    echo 'ok'
fi

echo 'Copying data'
aws s3 cp test_service/testeget.html s3://${TEST_PAGE_BUCKET}/index.html --acl public-read --profile "${AWS_PROFILE}"
echo 'ok'

echo 'Enabling web configuration for s3 bucket'
aws s3 website s3://${TEST_PAGE_BUCKET} --index-document index.html --profile "${AWS_PROFILE}"
echo 'ok'

######### BACKEND
REPO_LIST=$(aws ecr describe-repositories --profile ${AWS_PROFILE})

if [[ "${REPO_LIST}" != *${DOCKER_IMAGE_NAME}* ]]; then
    echo 'Creating ECR repos'
    aws ecr create-repository --repository-name "${DOCKER_IMAGE_NAME}" --profile "${AWS_PROFILE}"
    echo 'ok'
fi

echo 'Building docker images'
docker-compose build

echo 'Authenticating to ECR'
$(aws ecr get-login --no-include-email --profile ${AWS_PROFILE})

echo 'Tagging new docker image'
docker tag ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG} ${ECR_REGISTRY_ADDRESS}/${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}
echo 'Pushing new docker image to ECR'
docker push ${ECR_REGISTRY_ADDRESS}/${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}
echo 'ok'

CWD=$(pwd)

APP_LIST=$(aws elasticbeanstalk describe-applications --profile ${AWS_PROFILE})

#EFS_CHECK=$(aws efs describe-file-systems --region ${AWS_DEFAULT_REGION} | jq '.FileSystems[].CreationToken')
#
#if [[ "${EFS_CHECK}" != *${EFS_TOKEN}* ]]; then
#    aws efs create-file-system --creation-token ${EFS_TOKEN} --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
#if
#
#EFS_ID=$(aws efs describe-file-systems --region ${AWS_DEFAULT_REGION} | jq ".FileSystems[] | select(.CreationToken == '${EFS_TOKEN}' | .FileSystemId")
#export AWS_EFS_ID=$EFS_ID
#eval "echo \"$(<eb-efs-config.yaml.tmpl)\"" 2> /dev/null > elasticbeanstalk/.ebextensions/eb-efs-config.yaml

echo 'Grant ECR read/pull rights to eb ec2 role'
aws iam attach-role-policy --role-name "aws-elasticbeanstalk-ec2-role" --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
echo 'ok'

if [[ "$APP_LIST" != *${EB_ENVIRONMENT_NAME}* ]]; then
    echo 'Creting ElasticBeanstalk Application'
    aws elasticbeanstalk create-application --application-name ${EB_ENVIRONMENT_NAME} --profile ${AWS_PROFILE}
    echo 'ok'
fi

echo 'starting elastic beanstalk setup'
cd elasticbeanstalk
echo 'Rendering dockerun eb template'
eval "echo \"$(<Dockerrun.aws.single.json.tmpl)\"" 2> /dev/null > deploy/Dockerrun.aws.json

echo 'Rendering ebextensions envvars options.config'
eval "echo \"$(<options.config.tmpl)\"" 2> /dev/null > deploy/.ebextensions/options.config

# single container setup
cd deploy
echo 'init elasticbeanstalk cli'
eb init ${EB_ENVIRONMENT_NAME} --region ${AWS_DEFAULT_REGION} -p "docker" --profile ${AWS_PROFILE}
ENV_CHECK=$(eb list --profile ${AWS_PROFILE} | grep $EB_ENVIRONMENT_NAME || echo 'NOT_CREATED')

if [[ "$ENV_CHECK" == 'NOT_CREATED' ]]; then
    echo "Creating beanstalk environment :: ${EB_ENVIRONMENT_NAME}"
    eb create ${EB_ENVIRONMENT_NAME} -i ${BACKEND_INSTANCE_TYPE} --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
else
    echo "Deploying on beanstalk environment :: ${EB_ENVIRONMENT_NAME}"
    eb use ${EB_ENVIRONMENT_NAME} --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
    eb deploy ${EB_ENVIRONMENT_NAME} -l "$(date "+%Y%m%d-%H%M%S")-$(uuidgen)" --staged --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
fi

sh "eb status --verbose"
cd $CWD

## CLOUDFRONT (CDN and reverse proxy)
export S3_ORIGIN_ID="S3-${TEST_PAGE_BUCKET}"
export S3_DOMAIN_NAME="${S3_ORIGIN_ID}.s3-website-${AWS_DEFAULT_REGION}.amazonaws.com"
export ELB_ORIGIN_ID="ELB-${EB_ENVIRONMENT_NAME}"
export CDN_COMMENT=${EB_ENVIRONMENT_NAME}
ELB_DOMAIN_NAME=$(aws elasticbeanstalk describe-environments --environment-names ${EB_ENVIRONMENT_NAME} --query "Environments[?Status=='Ready'].EndpointURL"))
export ELB_DOMAIN_NAME

cd cloudfront
echo 'Rendering cloudfront configurations'
eval "echo \"$(<cloudfront.config.skeleton.json)\"" 2> /dev/null > cloudfront.json

AWS_CF_LIST=$(aws cloudfront list-distributions --profile "${AWS_PROFILE}")
if [[ "$CDN_COMMENT" != *${AWS_CF_LIST}* ]]; then
    aws cloudfront create-distribution --default-root-object index.html --distribution-config cloudfront.json
    AWS_CF_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='${EB_ENVIRONMENT_NAME}'].Id" | jq '.[]')
    aws cloudfront wait distribution-deployed --id ${AWS_CF_ID}
else
    AWS_CF_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='${EB_ENVIRONMENT_NAME}'].Id" | jq '.[]')
    aws cloudfront create-invalidation --distribution-id ${AWS_CF_ID} --paths '*''
fi