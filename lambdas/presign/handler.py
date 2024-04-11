import json
import os
import typing

import boto3
from botocore.exceptions import ClientError

if typing.TYPE_CHECKING:
    from mypy_boto3_s3 import S3Client
    from mypy_boto3_ssm import SSMClient

# used to make sure that S3 generates pre-signed URLs that have the localstack URL in them
endpoint_url = None
if os.getenv("STAGE") == "local":
    endpoint_url = "https://localhost.localstack.cloud:4566"

s3: "S3Client" = boto3.client("s3", endpoint_url=endpoint_url)
ssm: "SSMClient" = boto3.client("ssm", endpoint_url=endpoint_url)


def get_bucket_name() -> str:
    parameter = ssm.get_parameter(Name="/localstack-thumbnail-app/buckets/images")
    return parameter["Parameter"]["Value"]


def handler(event, context):
    bucket = get_bucket_name()

    key = event["rawPath"].lstrip("/")
    if not key:
        raise ValueError("no key given")

    # make sure the bucket exists
    try: 
        s3.head_bucket(Bucket=bucket)
    except Exception:
        s3.create_bucket(Bucket=bucket)

    # make sure the object does not exist
    try:
        s3.head_object(Bucket=bucket, Key=key)
        return {"statusCode": 409, "body": f"{bucket}/{key} already exists"}
    except ClientError as e:
        if e.response["ResponseMetadata"]["HTTPStatusCode"] != 404:
            raise

    # generate the pre-signed POST url
    url = s3.generate_presigned_post(Bucket=bucket, Key=key)

    # return it!
    return {"statusCode": 200, "body": json.dumps(url)}


if __name__ == "__main__":
    print(handler(None, None))
