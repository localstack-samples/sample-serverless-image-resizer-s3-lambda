import os
import time
import typing
import uuid

import boto3
import requests

if typing.TYPE_CHECKING:
    from mypy_boto3_s3 import S3Client
    from mypy_boto3_ssm import SSMClient

s3: "S3Client" = boto3.client(
    "s3", endpoint_url="http://localhost.localstack.cloud:4566"
)
ssm: "SSMClient" = boto3.client(
    "ssm", endpoint_url="http://localhost.localstack.cloud:4566"
)


def test_s3_resize_integration():
    file = "nyan-cat.png"
    key = os.path.basename(file)

    parameter = ssm.get_parameter(Name="/localstack-thumbnail-app/buckets/images")
    source_bucket = parameter["Parameter"]["Value"]

    parameter = ssm.get_parameter(Name="/localstack-thumbnail-app/buckets/resized")
    target_bucket = parameter["Parameter"]["Value"]

    s3.upload_file(file, Bucket=source_bucket, Key=key)

    # try for 15 seconds to wait for the resized image
    for i in range(15):
        try:
            s3.head_object(Bucket=target_bucket, Key=key)
            break
        except:
            pass
        time.sleep(1)

    s3.head_object(Bucket=target_bucket, Key=key)
    s3.download_file(
        Bucket=target_bucket, Key=key, Filename="/tmp/nyan-cat-resized.png"
    )

    assert (
        os.stat("/tmp/nyan-cat-resized.png").st_size < os.stat(key).st_size
    )

    s3.delete_object(Bucket=source_bucket, Key=key)
    s3.delete_object(Bucket=target_bucket, Key=key)


def test_failure_sns_to_ses_integration():
    file = "some-file.txt"
    key = f"{uuid.uuid4()}-{os.path.basename(file)}"

    parameter = ssm.get_parameter(Name="/localstack-thumbnail-app/buckets/images")
    source_bucket = parameter["Parameter"]["Value"]

    s3.upload_file(file, Bucket=source_bucket, Key=key)

    def _check_message():
        response = requests.get("http://localhost:4566/_localstack/ses")
        messages = response.json()['messages']
        assert key in messages[-1]['Body']['text_part']

    # retry to check for the message
    for i in range(9):
        try:
            _check_message()
        except:
            time.sleep(1)
    _check_message()

    # clean up resources
    s3.delete_object(Bucket=source_bucket, Key=key)
