#!/usr/bin/env bash
set -ex
AWS_REGION='us-east-2'
#AWS_SECRET_KEY_ID=${AWS_SECRET_ACCESS_KEY:?'Must provide access key id'}
#AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY:?'Must provide secret access key id'}
ACCOUNT_ID=${ACCOUNT_ID:?'Must provide account id'}

ECR_REGISTRY_ADDRESS=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

DOCKER_IMAGE_NAME='employees-api'
DOCKER_DATA_IMAGE='data-wrapper'
DOCKER_IMAGE_TAG=${GIT_BRANCH}

AWS_PROFILE='default'
APP_NAME=${DOCKER_IMAGE_NAME}
ENVIRONMENT_NAME=${APP_NAME}-${GIT_BRANCH}

EFS_TOKEN='EBFileSystem'
BACKEND_INSTANCE_TYPE='t2.micro'

TEST_PAGE_BUCKET="rcbop-test-service-${GIT_BRANCH}"

CWD=$(pwd)

cleanup(){
    #echo 'Cleaning up credentials'
    #aws configure set aws_access_key_id '' --profile "$AWS_PROFILE"
    #aws configure set aws_secret_access_key '' --profile "$AWS_PROFILE"
    cd "$CWD"
    rm -f elasticbeanstalk/.ebextensions/eb-efs-config.yaml
}

trap cleanup EXIT
#
#echo 'configure aws cli'
#aws configure set region "$AWS_REGION" --profile "$AWS_PROFILE"
#aws configure set output 'json' --profile "$AWS_PROFILE"
#
#set +x
#aws configure set aws_access_key_id "$AWS_SECRET_KEY_ID" --profile "$AWS_PROFILE"
#aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile "$AWS_PROFILE"

######### FRONTEND
S3_BUCKETS=$(aws s3api list-buckets --profile $AWS_PROFILE)
if [[ "${S3_BUCKETS}" != *${TEST_PAGE_BUCKET}* ]]; then
    echo 'Creating static page s3 bucket'
    aws s3 mb s3://${TEST_PAGE_BUCKET} --region ${AWS_REGION} --profile "${AWS_PROFILE}"
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
    aws ecr create-repository --repository-name "${DOCKER_DATA_IMAGE}" --profile "${AWS_PROFILE}"
    echo 'ok'
fi

echo 'Building docker image'
DOCKER_IMAGE_NAME=$DOCKER_IMAGE_NAME DOCKER_IMAGE_TAG=$DOCKER_IMAGE_TAG docker-compose build employees_api

DOCKER_DATA_IMAGE=$DOCKER_DATA_IMAGE DOCKER_IMAGE_TAG=$DOCKER_IMAGE_TAG docker-compose build data_wrapper

echo 'Authenticating to ECR'
$(aws ecr get-login --no-include-email --profile ${AWS_PROFILE})

echo 'Pushing new docker image'
docker tag ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG} ${ECR_REGISTRY_ADDRESS}/${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}
docker push ${ECR_REGISTRY_ADDRESS}/${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}

echo 'Pushing data wrapper'
docker tag ${DOCKER_DATA_IMAGE}:${DOCKER_IMAGE_TAG} ${ECR_REGISTRY_ADDRESS}/${DOCKER_DATA_IMAGE}:${DOCKER_IMAGE_TAG}
docker push "${ECR_REGISTRY_ADDRESS}/${DOCKER_DATA_IMAGE}:${DOCKER_IMAGE_TAG}"

CWD=$(pwd)

APP_LIST=$(aws elasticbeanstalk describe-applications --profile ${AWS_PROFILE})

#EFS_CHECK=$(aws efs describe-file-systems --region ${AWS_REGION} | jq '.FileSystems[].CreationToken')
#
#if [[ "${EFS_CHECK}" != *${EFS_TOKEN}* ]]; then
#    aws efs create-file-system --creation-token ${EFS_TOKEN} --region ${AWS_REGION} --profile ${AWS_PROFILE}
#if
#
#EFS_ID=$(aws efs describe-file-systems --region ${AWS_REGION} | jq ".FileSystems[] | select(.CreationToken == '${EFS_TOKEN}' | .FileSystemId")
#export AWS_EFS_ID=$EFS_ID
#eval "echo \"$(<eb-efs-config.yaml.tmpl)\"" 2> /dev/null > elasticbeanstalk/.ebextensions/eb-efs-config.yaml

if [[ "$APP_LIST" != *${ENVIRONMENT_NAME}* ]]; then
    echo 'Creting ElasticBeanstalk Application'
    aws elasticbeanstalk create-application --application-name ${ENVIRONMENT_NAME} --profile ${AWS_PROFILE}
    echo 'ok'
fi

cd elasticbeanstalk
echo 'init elasticbeanstalk cli'
eb init ${ENVIRONMENT_NAME} --region ${AWS_REGION} -p "docker" --profile ${AWS_PROFILE}

ENV_CHECK=$(eb list --profile ${AWS_PROFILE} | grep $ENVIRONMENT_NAME || echo 'NOT_CREATED')

if [[ "$ENV_CHECK" == 'NOT_CREATED' ]]; then
    echo "Creating beanstalk environment :: ${ENVIRONMENT_NAME}"
    eb create ${ENVIRONMENT_NAME} -i ${BACKEND_INSTANCE_TYPE} --region ${AWS_REGION} --profile ${AWS_PROFILE}
else
    echo "Deploying on beanstalk environment :: ${ENVIRONMENT_NAME}"
    eb use ${ENVIRONMENT_NAME} --region ${AWS_REGION} --profile ${AWS_PROFILE}
    eb deploy ${ENVIRONMENT_NAME} --staged --region ${AWS_REGION} --profile ${AWS_PROFILE}
fi

sh "eb status --verbose"