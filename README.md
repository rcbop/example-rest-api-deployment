# Employees Restapi

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
./local-deploy.sh
```

or just

```bash
docker-compose up --build
```

## AWS Deployment Quick start

```bash
aws configure
#... input credentials and default region
ACCOUNT_ID=<YOUR_ACCOUNT_ID> bash ./aws-deploy.sh
```