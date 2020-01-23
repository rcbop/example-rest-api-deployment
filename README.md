# Employees RestAPI

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

## AWS deployment

### Run setup

Run setup script, input your AWS credentials (AWS_SECRET_KEY_ID, AWS_SECRET_ACCESS_KEY) and default region

```bash
./setup-aws-tools.sh
```

### Run deployment script

```bash
export AWS_ACCOUNT_ID=<YOUR_ACCOUNT_ID>
# start with bash -x to debug issues
./run-aws-deploy.sh
```