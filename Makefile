export AWS_ACCESS_KEY_ID ?= test
export AWS_SECRET_ACCESS_KEY ?= test
export LOCAL_RUN ?= true
SHELL := /bin/bash

include .env

usage:				## Show this help 
		@grep -F -h "##" $(MAKEFILE_LIST) | grep -F -v grep -F | sed -e 's/\\$$//' -e 's/##//'

install:			## Install dependencies
		@pip install -r requirements-dev.txt

build: 				## Build lambdas in the lambdas folder
		bin/build_lambdas.sh; 

awslocal-setup: 		## Deploy the application locally using `awslocal`, a wrapper for the AWS CLI
		$(MAKE) build
		deployment/awslocal/deploy.sh

terraform-setup:		## Deploy the application locally using `tflocal`, a wrapper for Terraform CLI
		$(MAKE) build
		cd deployment/terraform; \
		tflocal init; \
		echo "Deploying Terraform configuration 🚀"; \
		tflocal apply  --auto-approve -var="local_run=${LOCAL_RUN}"; \
		echo "Paste the function URLs above to the WebApp 🎉";

terraform-destroy:		## Destroy all resources created locally using terraform scripts
		cd deployment/terraform; \
		tflocal destroy --auto-approve;

start:				## Start the LocalStack Pro container in the detached mode
		@LOCALSTACK_AUTH_TOKEN=$(LOCALSTACK_AUTH_TOKEN) localstack start -d

stop:				## Stop the LocalStack Pro container
		localstack stop

.PHONY: usage install build awslocal-setup terraform-setup terraform-destroy start stop
