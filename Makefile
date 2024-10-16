export AWS_DEFAULT_REGION=us-east-1
export AWS_ACCESS_KEY_ID ?= test
export AWS_SECRET_ACCESS_KEY ?= test
export LOCAL_RUN ?= true
SHELL := /bin/bash

include .env

build:
		bin/build_lambdas.sh;

awslocal-setup:
		bin/deploy.sh

terraform-setup:
		$(MAKE) build
		cd deployment/terraform; \
		tflocal init; \
		echo "Deploying Terraform configuration 🚀"; \
		tflocal apply  --auto-approve -var="local_run=${LOCAL_RUN}"; \
		echo "Paste the function URLs above to the WebApp 🎉";

terraform-destroy:
		cd deployment/terraform; \
		tflocal destroy --auto-approve;

start:
		LOCALSTACK_AUTH_TOKEN=$(LOCALSTACK_AUTH_TOKEN) localstack start -d

stop:
		@echo
		localstack stop

.PHONY: build awslocal-setup terraform-setup terraform-destroy start stop
