# Serverless image resizer

Make sure you use the same version as the Python Lambdas to make Pillow work (3.9)

## Overview

![Screenshot at 2022-11-23 16-34-12](https://user-images.githubusercontent.com/3996682/203586505-e54ccb3e-5101-4ee8-917d-d6372ee965ef.png)

## Create the infrastructure manually

### Create the buckets

The names are completely configurable via SSM:

```bash
awslocal s3 mb s3://localstack-thumbnails-app-images
awslocal s3 mb s3://localstack-thumbnails-app-resized
```

### Put the bucket names into the parameter store

```bash
awslocal ssm put-parameter --name /localstack-thumbnail-app/buckets/images --value "localstack-thumbnails-app-images"
awslocal ssm put-parameter --name /localstack-thumbnail-app/buckets/resized --value "localstack-thumbnails-app-resized"
```

### Create the DLQ Topic for failed lambda invokes

```bash
awslocal sns create-topic --name failed-resize-topic
```

Subscribe an email address to it (to alert us immediately if an image resize fails!).

```bash
awslocal sns subscribe \
    --topic-arn arn:aws:sns:us-east-1:000000000000:failed-resize-topic \
    --protocol email \
    --notification-endpoint my-email@example.com
```

`awslocal sns list-topics | jq -r '.Topics[] | select(.TopicArn|test("failed-resize-topic")).TopicArn'`


### Create the lambdas

#### S3 pre-signed POST URL generator

```bash
(cd lambdas/presign; rm -f lambda.zip; zip lambda.zip handler.py)
awslocal lambda create-function \
    --function-name presign \
    --runtime python3.9 \
    --timeout 10 \
    --zip-file fileb://lambdas/presign/lambda.zip \
    --handler handler.handler \
    --role arn:aws:iam::000000000000:role/lambda-role
```

Create the function URL:

```bash
awslocal lambda create-function-url-config \
    --function-name presign \
    --auth-type NONE
```

Copy the `FunctionUrl` from the response!

### Resizer Lambda

```bash
(
    cd lambdas/resize
    rm -rf package lambda.zip
    mkdir package
    pip install -r requirements.txt -t package
    zip lambda.zip handler.py
    cd package
    zip -r ../lambda.zip *;
)
awslocal lambda create-function \
    --function-name resize \
    --runtime python3.9 \
    --timeout 10 \
    --zip-file fileb://lambdas/resize/lambda.zip \
    --handler handler.handler \
    --dead-letter-config TargetArn=arn:aws:sns:us-east-1:000000000000:failed-resize-topic \
    --role arn:aws:iam::000000000000:role/lambda-role
```

### Connect the S3 bucket to the resizer lambda

```bash
awslocal s3api put-bucket-notification-configuration \
    --bucket localstack-thumbnails-app-images \
    --notification-configuration "{\"LambdaFunctionConfigurations\": [{\"LambdaFunctionArn\": \"$(awslocal lambda get-function --function-name resize | jq -r .Configuration.FunctionArn)\", \"Events\": [\"s3:ObjectCreated:*\"]}]}"
```

### Create the static s3 webapp

```bash
awslocal s3 mb s3://webapp
awslocal s3 sync --delete ./website s3://webapp
awslocal s3 website s3://webapp --index-document index.html
```

Then visit http://webapp.s3-website.localhost.localstack.cloud:4566


## Develop locally

Create a virtualenv and install all the dependencies there:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
```
