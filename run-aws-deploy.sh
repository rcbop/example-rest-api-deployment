#!/usr/bin/env bash
#
#  One script to rule them all, 
#  one script to find them, 
#  One script to bring them all 
#  and in the darkness bind them.
#
set -x
set -e
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

source ./setup-backend-envvars.sh

export AWS_PROFILE='default'
export APP_NAME=${DOCKER_IMAGE_NAME}
export EB_ENVIRONMENT_NAME=${APP_NAME}-${GIT_BRANCH}
export BACKEND_INSTANCE_TYPE='t2.micro'
export FRONTEND_BUCKET="rcbop-test-service-${GIT_BRANCH}"

CWD=$(pwd)

sep(){
    echo -e "\033[32;1m########################\033[0m"
}
separator(){
    echo -e "\033[32;1;5m >>>> $1 \033[0m"
}

cleanup(){
    #echo 'Cleaning up credentials'
    #aws configure set aws_access_key_id '' --profile "$AWS_PROFILE"
    #aws configure set aws_secret_access_key '' --profile "$AWS_PROFILE"
    cd "$CWD"
    echo 'Cleaning rendered templates'
    rm -vf aws/*.json
    rm -vf aws/elasticbeanstalk/deploy/.ebextensions/eb-efs-config.yaml
    rm -vf aws/elasticbeanstalk/deploy/*
    rm -rf aws/elasticbeanstalk/deploy/.*
    rm -rf aws/elasticbeanstalk/deploy/.gitignore
    rm -rf aws/cloudfront/*.json
    rm -rf aws/route53/*.json
}

trap cleanup EXIT

#echo 'configure aws cli'
#aws configure set region "$AWS_DEFAULT_REGION" --profile "$AWS_PROFILE"
#aws configure set output 'json' --profile "$AWS_PROFILE"

#set +x
#aws configure set aws_access_key_id "$AWS_SECRET_KEY_ID" --profile "$AWS_PROFILE"
#aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY" --profile "$AWS_PROFILE"
#set -x

sep
separator "##### AWS DEPLOYMENT SCRIPT #####"
sep
echo
echo
separator "Building docker images"
docker-compose build

######### RESOURCE GROUP
sep
separator "Creating resource group"

cd aws

export GROUP_TAG_KEY='resource-group'
export GROUP_TAG_VALUE=${EB_ENVIRONMENT_NAME}

RES_GROUPS=$(aws resource-groups list-groups --profile ${AWS_PROFILE})
if [[ $RES_GROUPS != *$EB_ENVIRONMENT_NAME* ]]; then
    aws resource-groups create-group --name ${EB_ENVIRONMENT_NAME} \
        --tags "Key=resource-group,Value=${GROUP_TAG_VALUE}" \
        --resource-query '{"Type":"TAG_FILTERS_1_0","Query":"{\"ResourceTypeFilters\":[\"AWS::AllSupported\"],\"TagFilters\":[{\"Key\":\"resource-group\",\"Values\":[\"employees-api-master\"]}]}"}' \
        --profile ${AWS_PROFILE}
fi

######### FRONTEND
sep
separator "S3 frontend deployment"
echo
S3_BUCKETS=$(aws s3api list-buckets --profile $AWS_PROFILE)
if [[ "${S3_BUCKETS}" != *${FRONTEND_BUCKET}* ]]; then
    echo 'Creating static page s3 bucket'
    aws s3 mb s3://${FRONTEND_BUCKET} --region ${AWS_DEFAULT_REGION} --profile "${AWS_PROFILE}"
    aws s3api put-bucket-tagging --bucket ${FRONTEND_BUCKET} --tagging "TagSet=[{Key=${GROUP_TAG_KEY},Value=${GROUP_TAG_VALUE}}]" --profile "${AWS_PROFILE}"
    echo 'ok'
fi

echo 'Copying data'
aws s3 cp ../test_service/testeget.html s3://${FRONTEND_BUCKET}/index.html --acl public-read --profile "${AWS_PROFILE}"
echo 'ok'

echo 'Enabling web configuration for s3 bucket'
aws s3 website s3://${FRONTEND_BUCKET} --index-document index.html --profile "${AWS_PROFILE}"
echo 'ok'
echo

######### BACKEND
sep
separator "Elastic Beanstalk backend deployment"
echo
REPO_LIST=$(aws ecr describe-repositories --profile ${AWS_PROFILE})

if [[ "${REPO_LIST}" != *${DOCKER_IMAGE_NAME}* ]]; then
    echo 'Creating ECR repos'
    aws ecr create-repository --repository-name "${DOCKER_IMAGE_NAME}" --profile "${AWS_PROFILE}"
    aws ecr tag-resource --resource-arn arn:aws:ecr:${AWS_DEFAULT_REGION}:${AWS_ACCOUNT_ID}:repository/${DOCKER_IMAGE_NAME} \
        --tags "Key=${GROUP_TAG_KEY},Value=${GROUP_TAG_VALUE}" --profile "${AWS_PROFILE}"
    echo 'ok'
fi

separator "Authenticating to ECR"
echo
$(aws ecr get-login --no-include-email --profile ${AWS_PROFILE})

echo 'Tagging new docker image'
docker tag ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG} ${ECR_REGISTRY_ADDRESS}/${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}
echo 'Pushing new docker image to ECR'
docker push ${ECR_REGISTRY_ADDRESS}/${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG}
echo 'ok'

CWD=$(pwd)

sep
separator "Grant ECR read/pull rights to eb ec2 role"
echo
aws iam attach-role-policy --role-name "aws-elasticbeanstalk-ec2-role" --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
echo 'ok'

APP_LIST=$(aws elasticbeanstalk describe-applications --profile ${AWS_PROFILE})
if [[ "$APP_LIST" != *${EB_ENVIRONMENT_NAME}* ]]; then
    echo 'Creting ElasticBeanstalk Application'
    aws elasticbeanstalk create-application --application-name ${EB_ENVIRONMENT_NAME} --profile ${AWS_PROFILE}
    aws elasticbeanstalk update-tags-for-resource \
        --resource-arn "arn:aws:elasticbeanstalk:${AWS_DEFAULT_REGION}:${AWS_ACCOUNT_ID}:application/${EB_ENVIRONMENT_NAME}" \
        --tags-to-add "Key=${GROUP_TAG_KEY},Value=${GROUP_TAG_VALUE}" \
        --profile "${AWS_PROFILE}"
    echo 'ok'
fi

sep
separator "Starting elastic beanstalk setup"
echo
cd elasticbeanstalk
mkdir -p deploy/.ebextensions
echo 'Rendering dockerun eb template'
eval "echo \"$(<Dockerrun.aws.single.json.tmpl)\"" 2> /dev/null > deploy/Dockerrun.aws.json

echo 'Rendering ebextensions envvars options.config'
eval "echo \"$(<options.config.tmpl)\"" 2> /dev/null > deploy/.ebextensions/options.config

cd deploy
echo 'Initialize elasticbeanstalk cli'
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

cd $CWD

######### CLOUDFRONT (CDN and reverse proxy)
sep
separator "Cloudfront deployment" 
export S3_ORIGIN_ID="S3-${FRONTEND_BUCKET}"
export S3_BUCKET_DOMAIN="${FRONTEND_BUCKET}.s3.amazonaws.com"
export ELB_ORIGIN_ID="ELB-${EB_ENVIRONMENT_NAME}"
export CDN_COMMENT=${EB_ENVIRONMENT_NAME}
export CALLER_REF=$(date "+%Y%m%d-%H%M%S")
export DEFAULT_ROOT_OBJ='index.html'
export CNAME_ALIAS='example-rest-api-deployment.rogerpeixoto.net'
export ACM_CERTIFICATE_ID='daa792a7-9fe4-4d55-b095-ca56a282c4b0'
export CERTIFICATE_ARN="arn:aws:acm:us-east-1:${AWS_ACCOUNT_ID}:certificate/${ACM_CERTIFICATE_ID}"
export ELB_DOMAIN_NAME=$(aws elasticbeanstalk describe-environments --environment-names ${EB_ENVIRONMENT_NAME} --query "Environments[?Status=='Ready'].EndpointURL" | jq '.[]' -r)
export HOSTED_ZONE_NAME='rogerpeixoto.net'

cd cloudfront
echo 'Rendering cloudfront configurations'
eval "echo \"$(<cloudfront.config.skeleton.json.tmpl)\"" 2> /dev/null > cloudfront.json

cat cloudfront.json | jq

AWS_CF_LIST=$(aws cloudfront list-distributions --profile "${AWS_PROFILE}")
if [[ -z ${AWS_CF_LIST} ]]; then
    aws cloudfront create-distribution --distribution-config file://cloudfront.json
    AWS_CF_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='${EB_ENVIRONMENT_NAME}'].Id" | jq '.[]' -r)
    aws cloudfront tag-resource --resource "arn:aws:cloudfront::${AWS_ACCOUNT_ID}:distribution/${AWS_CF_ID}" --tags "Key=${GROUP_TAG_KEY},Value=${GROUP_TAG_VALUE}"
    aws cloudfront wait distribution-deployed --id ${AWS_CF_ID}
# else
#     AWS_CF_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?Comment=='${EB_ENVIRONMENT_NAME}'].Id" | jq '.[]' -r)
#     aws cloudfront create-invalidation --distribution-id ${AWS_CF_ID} --paths '/index.html'
#     aws cloudfront wait invalidation-complete --id ${AWS_CF_ID}
fi

cd $CWD

######### ROUTE 53 DNS SERVICE
cd route53

sep
separator "Route53 dns creation\033[0m" 

HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Config.Comment=='${EB_ENVIRONMENT_NAME}'].Id" | jq '.[]' -r | xargs basename)
if [ -z $HOSTED_ZONE_ID ]; then
    aws route53 create-hosted-zone --name ${HOSTED_ZONE_NAME} --caller-reference $(date "+%Y%m%d-%H%M%S") --hosted-zone-config Comment="${EB_ENVIRONMENT_NAME}"
fi
export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Config.Comment=='${EB_ENVIRONMENT_NAME}'].Id" | jq '.[]' -r | xargs basename)
aws route53 change-tags-for-resource --resource-type 'hostedzone' --resource-id $HOSTED_ZONE_ID --add-tags "Key=${GROUP_TAG_KEY},Value=${GROUP_TAG_VALUE}"

export AWS_CF_DOMAIN_NAME=$(aws cloudfront list-distributions --query "DistributionList.Items[?Id=='${AWS_CF_ID}'].DomainName" | jq '.[]' -r)

eval "echo \"$(<record-set.config.json.tmpl)\"" 2> /dev/null > record-set.json
cat record-set.json | jq
aws route53 change-resource-record-sets --hosted-zone-id ${HOSTED_ZONE_ID} --change-batch file://record-set.json