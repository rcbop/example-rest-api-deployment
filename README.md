# Employees RestAPI

Available in http://example-rest-api-deployment.rogerpeixoto.net/

or

d2nk8979z63bee.cloudfront.net

## Requirements

* docker
* docker-compose
* python3
* python3-pip
* git
* jq
* bash

## Local Deployment

```bash
./run-local-deploy.sh
```

## AWS Deployment Quick start

```bash
aws configure
#... input credentials and default region
AWS_ACCOUNT_ID=<YOUR_ACCOUNT_ID> bash ./run-aws-deploy.sh
```