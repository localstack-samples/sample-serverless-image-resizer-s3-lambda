# adapted from https://docs.aws.amazon.com/lambda/latest/dg/with-s3-tutorial.html
import os
import typing
import uuid
from urllib.parse import unquote_plus

import boto3
from PIL import Image

if typing.TYPE_CHECKING:
    from mypy_boto3_s3 import S3Client
    from mypy_boto3_ssm import SSMClient

MAX_DIMENSIONS = 400, 400
"""The max width and height to scale the image to."""

endpoint_url = None
if os.getenv("STAGE") == "local":
    endpoint_url = "https://localhost.localstack.cloud:4566"

s3: "S3Client" = boto3.client("s3", endpoint_url=endpoint_url)
ssm: "SSMClient" = boto3.client("ssm", endpoint_url=endpoint_url)


def get_bucket_name() -> str:
    parameter = ssm.get_parameter(Name="/localstack-thumbnail-app/buckets/resized")
    return parameter["Parameter"]["Value"]


def resize_image(image_path, resized_path):
    with Image.open(image_path) as image:
        # Calculate the thumbnail size
        width, height = image.size
        max_width, max_height = MAX_DIMENSIONS
        if width > max_width or height > max_height:
            ratio = max(width / max_width, height / max_height)
            width = int(width / ratio)
            height = int(height / ratio)
        size = width, height
        # Generate the resized image
        image.thumbnail(size)
        image.save(resized_path)


def download_and_resize(bucket, key) -> str:
    tmpkey = key.replace("/", "")
    download_path = f"/tmp/{uuid.uuid4()}{tmpkey}"
    upload_path = f"/tmp/resized-{tmpkey}"
    s3.download_file(bucket, key, download_path)
    resize_image(download_path, upload_path)
    return upload_path


def handler(event, context):
    target_bucket = get_bucket_name()

    for record in event["Records"]:
        source_bucket = record["s3"]["bucket"]["name"]
        key = unquote_plus(record["s3"]["object"]["key"])
        print(source_bucket, key)

        resized_path = download_and_resize(source_bucket, key)
        s3.upload_file(resized_path, target_bucket, key)
