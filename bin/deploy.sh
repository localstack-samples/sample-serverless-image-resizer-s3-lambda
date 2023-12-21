#!/bin/bash

export AWS_DEFAULT_REGION=us-east-1

awslocal s3 mb s3://localstack-thumbnails-app-images
awslocal s3 mb s3://localstack-thumbnails-app-resized

awslocal ssm put-parameter --name /localstack-thumbnail-app/buckets/images --type "String" --value "localstack-thumbnails-app-images"
awslocal ssm put-parameter --name /localstack-thumbnail-app/buckets/resized --type "String" --value "localstack-thumbnails-app-resized"

awslocal sns create-topic --name failed-resize-topic
awslocal sns subscribe \
    --topic-arn arn:aws:sns:us-east-1:000000000000:failed-resize-topic \
    --protocol email \
    --notification-endpoint my-email@example.com

(cd lambdas/presign; rm -f lambda.zip; zip lambda.zip handler.py)
awslocal lambda create-function \
    --function-name presign \
    --runtime python3.9 \
    --timeout 10 \
    --zip-file fileb://lambdas/presign/lambda.zip \
    --handler handler.handler \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --environment Variables="{STAGE=local}"

awslocal lambda wait function-active-v2 --function-name presign

awslocal lambda create-function-url-config \
    --function-name presign \
    --auth-type NONE

(cd lambdas/list; rm -f lambda.zip; zip lambda.zip handler.py)
awslocal lambda create-function \
    --function-name list \
    --runtime python3.9 \
    --timeout 10 \
    --zip-file fileb://lambdas/list/lambda.zip \
    --handler handler.handler \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --environment Variables="{STAGE=local}"

awslocal lambda wait function-active-v2 --function-name list

awslocal lambda create-function-url-config \
    --function-name list \
    --auth-type NONE

os=$(uname -s)
if [ "$os" == "Darwin" ]; then
    (
        cd lambdas/resize
        rm -rf libs lambda.zip
        docker run --platform linux/x86_64 -v "$PWD":/var/task "public.ecr.aws/sam/build-python3.9" /bin/sh -c "pip install -r requirements.txt -t libs; exit"
        cd libs && zip -r ../lambda.zip . && cd ..
        zip lambda.zip handler.py
        rm -rf libs
    )
else
    (
        cd lambdas/resize
        rm -rf package lambda.zip
        mkdir package
        pip install -r requirements.txt -t package
        zip lambda.zip handler.py
        cd package
        zip -r ../lambda.zip *;
    )
fi

awslocal lambda create-function \
    --function-name resize \
    --runtime python3.9 \
    --timeout 10 \
    --zip-file fileb://lambdas/resize/lambda.zip \
    --handler handler.handler \
    --dead-letter-config TargetArn=arn:aws:sns:us-east-1:000000000000:failed-resize-topic \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --environment Variables="{STAGE=local}"

awslocal lambda wait function-active-v2 --function-name resize
awslocal lambda put-function-event-invoke-config --function-name resize --maximum-event-age-in-seconds 3600 --maximum-retry-attempts 0

awslocal s3api put-bucket-notification-configuration \
    --bucket localstack-thumbnails-app-images \
    --notification-configuration "{\"LambdaFunctionConfigurations\": [{\"LambdaFunctionArn\": \"$(awslocal lambda get-function --function-name resize | jq -r .Configuration.FunctionArn)\", \"Events\": [\"s3:ObjectCreated:*\"]}]}"

awslocal s3 mb s3://webapp
awslocal s3 sync --delete ./website s3://webapp
awslocal s3 website s3://webapp --index-document index.html

echo
echo "Fetching function URL for 'presign' Lambda..."
awslocal lambda list-function-url-configs --function-name presign | jq -r '.FunctionUrlConfigs[0].FunctionUrl'
echo "Fetching function URL for 'list' Lambda..."
awslocal lambda list-function-url-configs --function-name list | jq -r '.FunctionUrlConfigs[0].FunctionUrl'

echo "Now open the Web app under https://webapp.s3-website.localhost.localstack.cloud and paste the function URLs above (make sure to use https:// as protocol)"
