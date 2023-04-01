# Serverless image resizer

[![LocalStack Pods Launchpad](https://localstack.cloud/gh/launch-pod-badge.svg)](https://app.localstack.cloud/launchpad?url=https://github.com/thrau/serverless-image-resizer/releases/download/v0.1.0/serverless-image-resizer-cloudpod-v0.1.0.zip)


A serverless application that demos several AWS functionalities on LocalStack:
* S3
* S3 bucket notifications to trigger a Lambda
* S3 pre-signed POST
* S3 website
* SSM
* Lambda
* Lambda function URLs
* Lambda SNS on failure destination
* SNS to SES Subscriptions
* SES LocalStack testing endpoint

Moreover, the repo includes a GitHub actions workflow to demonstrate how to run end-to-end tests of your AWS apps using LocalStack in CI.

Here's the app in action:


https://user-images.githubusercontent.com/3996682/229314248-86122e9e-0150-4292-b889-401e6fb8f398.mp4


## Overview

![Screenshot at 2023-04-02 01-32-56](https://user-images.githubusercontent.com/3996682/229322761-92f52eec-5bfb-412a-a3cb-8af4ee1fed24.png)

## Prerequisites

### Dev environment

Make sure you use the same version as the Python Lambdas to make Pillow work.
If you use pyenv, then first install and activate Python 3.9:
```bash
pyenv install 3.9.16
pyenv global 3.9.16
```

```console
% python --version
Python 3.9.16
```

Create a virtualenv and install all the development dependencies there:

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
```

### LocalStack

Start LocalStack Pro with the appropriate CORS configuration for the S3 Website:

```bash
LOCALSTACK_API_KEY=... localstack start
```

## Create the infrastructure manually

You can create the AWS infrastructure on LocalStack by running `bin/deploy.sh`.
Here are instructions to deploy it manually step-by-step.

### Create the buckets

The names are completely configurable via SSM:

```bash
awslocal s3 mb s3://localstack-thumbnails-app-images
awslocal s3 mb s3://localstack-thumbnails-app-resized
```

### Put the bucket names into the parameter store

```bash
awslocal ssm put-parameter --name /localstack-thumbnail-app/buckets/images --type "String" --value "localstack-thumbnails-app-images"
awslocal ssm put-parameter --name /localstack-thumbnail-app/buckets/resized --type "String" --value "localstack-thumbnails-app-resized"
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

### Create the lambdas

#### S3 pre-signed POST URL generator

This Lambda is responsible for generating pre-signed POST URLs to upload files to an S3 bucket.

```bash
(cd lambdas/presign; rm -f lambda.zip; zip lambda.zip handler.py)
awslocal lambda create-function \
    --function-name presign \
    --runtime python3.9 \
    --timeout 10 \
    --zip-file fileb://lambdas/presign/lambda.zip \
    --handler handler.handler \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --environment Variables="{STAGE=local}"
```

Create the function URL:

```bash
awslocal lambda create-function-url-config \
    --function-name presign \
    --auth-type NONE
```

Copy the `FunctionUrl` from the response, you will need it later to make the app work.

### Image lister lambda

The `list` Lambda is very similar:

```bash
(cd lambdas/list; rm -f lambda.zip; zip lambda.zip handler.py)
awslocal lambda create-function \
    --function-name list \
    --handler handler.handler \
    --zip-file fileb://lambdas/list/lambda.zip \
    --runtime python3.9 \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --environment Variables="{STAGE=local}"
```

Create the function URL:

```bash
awslocal lambda create-function-url-config \
    --function-name list \
    --auth-type NONE
```

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
    --role arn:aws:iam::000000000000:role/lambda-role \
    --environment Variables="{STAGE=local}"
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

## Using the app

Once deployed, visit http://webapp.s3-website.localhost.localstack.cloud:4566

Paste the Function URL of the presign Lambda you created earlier into the form field.
```bash
awslocal lambda list-function-url-configs --function-name presign
awslocal lambda list-function-url-configs --function-name list
```

After uploading a file, you can download the resized file from the `localstack-thumbnails-app-resized` bucket.

### Testing failures

If the `resize` Lambda fails, an SNS message is sent to a topic that an SES subscription listens to.
An email is then sent with the raw failure message.
In a real scenario you'd probably have another lambda sitting here, but it's just for demo purposes.
Since there's no real email server involved, you can use the [SES developer endpoint](https://docs.localstack.cloud/user-guide/aws/ses/) to list messages that were sent via SES:

curl -s http://localhost.localstack.cloud:4566/_aws/ses

An alternative is to use a service like MailHog or smtp4dev, and start LocalStack using `SMTP_HOST=host.docker.internal:1025` pointing to the mock SMTP server.

## Run integration tests

Once all resource are created on LocalStack, you can run the automated integration tests.

```bash
pytest tests/
```

## GitHub Action

The demo LocalStack in CI, `.github/workflows/integration-test.yml` contains a GitHub Action that starts up LocalStack,
deploys the infrastructure to it, and then runs the integration tests.
