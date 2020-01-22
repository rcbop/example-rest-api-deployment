#!/usr/bin/env bash
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
export CONTAINER_PORT='8080'
export AWS_PROFILE='default'
export APP_NAME=${DOCKER_IMAGE_NAME}
export ENVIRONMENT_NAME=${APP_NAME}-${GIT_BRANCH}
export EFS_TOKEN='EBFileSystem'
export BACKEND_INSTANCE_TYPE='t2.micro'
export TEST_PAGE_BUCKET="rcbop-test-service-${GIT_BRANCH}"

CWD=$(pwd)

cleanup(){
    #echo 'Cleaning up credentials'
    #aws configure set aws_access_key_id '' --profile "$AWS_PROFILE"
    #aws configure set aws_secret_access_key '' --profile "$AWS_PROFILE"
    cd "$CWD"
    rm -f elasticbeanstalk/.ebextensions/eb-efs-config.yaml
    rm -f elasticbeanstalk/deploy/*
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

if [[ "$APP_LIST" != *${ENVIRONMENT_NAME}* ]]; then
    echo 'Creting ElasticBeanstalk Application'
    aws elasticbeanstalk create-application --application-name ${ENVIRONMENT_NAME} --profile ${AWS_PROFILE}
    echo 'ok'
fi

cd elasticbeanstalk
echo 'Rendering dockerun eb template'
eval "echo \"$(<Dockerrun.aws.single.tmpl)\"" 2> /dev/null > workdir/Dockerrun.aws.json

# single container setup
cd workdir
echo 'init elasticbeanstalk cli'
eb init ${ENVIRONMENT_NAME} --region ${AWS_DEFAULT_REGION} -p "docker" --profile ${AWS_PROFILE}
ENV_CHECK=$(eb list --profile ${AWS_PROFILE} | grep $ENVIRONMENT_NAME || echo 'NOT_CREATED')

if [[ "$ENV_CHECK" == 'NOT_CREATED' ]]; then
    echo "Creating beanstalk environment :: ${ENVIRONMENT_NAME}"
    eb create ${ENVIRONMENT_NAME} -i ${BACKEND_INSTANCE_TYPE} --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
else
    echo "Deploying on beanstalk environment :: ${ENVIRONMENT_NAME}"
    eb use ${ENVIRONMENT_NAME} --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
    eb deploy ${ENVIRONMENT_NAME} -l $(date "+%Y%m%d-%H%M%S")-$(uuidgen) --staged --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
fi

sh "eb status --verbose"

## CLOUDFRONT (CDN and reverse proxy)
#AWS_CF_LIST=$(aws cloudfront list-distributions --profile "${AWS_PROFILE}")
#aws cloudfront wait distribution-deployed --id $AWS_CF_ID 
