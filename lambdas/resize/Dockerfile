FROM python:3

RUN apt update
RUN apt-get install zip

RUN mkdir package

COPY . .

RUN pip install -r requirements.txt --target package

CMD ["zip", "-r", "lambda.zip", "package"]
