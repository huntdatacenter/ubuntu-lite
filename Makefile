# Use one shell for all commands in a target recipe
.ONESHELL:
.EXPORT_ALL_VARIABLES:
# Set default goal
.DEFAULT_GOAL := help
# Use bash shell in Make instead of sh
SHELL := /bin/bash
# Charm variables
CHARM_NAME := ubuntu-lite.charm
CHARMHUB_NAME := huntdatacenter-ubuntu-lite
CHARM_STORE_URL := cs:~huntdatacenter/ubuntu-lite
CHARM_HOMEPAGE := https://github.com/huntdatacenter/ubuntu-lite/
CHARM_BUGS_URL := https://github.com/huntdatacenter/ubuntu-lite/issues
CHARM_BUILD_DIR ?= /tmp/charm-builds
# Jujuna variables - can be overrided by env
TIMEOUT ?= 600
ERROR_TIMEOUT ?= 60

# Multipass variables
UBUNTU_VERSION = jammy
MOUNT_TARGET = /home/ubuntu/vagrant
DIR_NAME = "$(shell basename $(shell pwd))"
VM_NAME = juju-dev--$(DIR_NAME)

name:  ## Print name of the VM
	echo "$(VM_NAME)"

list:  ## List existing VMs
	multipass list

launch:
	multipass launch $(UBUNTU_VERSION) -v --timeout 3600 --name $(VM_NAME) --memory 4G --cpus 4 --disk 20G --cloud-init juju.yaml \
	&& multipass exec $(VM_NAME) -- cloud-init status

mount:
	echo "Assure allowed in System settings > Privacy > Full disk access for multipassd"
	multipass mount --type 'classic' --uid-map $(shell id -u):1000 --gid-map $(shell id -g):1000 $(PWD) $(VM_NAME):$(MOUNT_TARGET)

umount:
	multipass umount $(VM_NAME):$(MOUNT_TARGET)

bootstrap:
	$(eval ARCH := $(shell multipass exec $(VM_NAME) -- dpkg --print-architecture))
	multipass exec $(VM_NAME) -- juju bootstrap localhost lxd --bootstrap-constraints arch=$(ARCH) \
	&& multipass exec $(VM_NAME) -- juju add-model default

ssh:  ## Connect into the VM
	multipass exec -d $(MOUNT_TARGET) $(VM_NAME) -- bash --login

up: launch mount bootstrap ssh  ## Start a VM

down:  ## Stop the VM
	multipass delete -v $(VM_NAME)

destroy:  ## Destroy the VM
	multipass delete -v --purge $(VM_NAME)


lint: ## Run linter
	tox -e lint

clean:  ## Remove artifacts
	charmcraft clean --verbose
	rm -vf $(CHARM_BUILD) $(CHARM_NAME)

$(CHARM_BUILD):
	charmcraft pack --verbose

$(CHARM_NAME): $(CHARM_BUILD)
	mv -v $(CHARM_BUILD) $(CHARM_NAME)

build: $(CHARM_NAME)  ## Build charm

clean-build: clean $(CHARM_NAME)  ## Build charm from scratch

deploy: ## Deploy charm
	juju deploy ./$(CHARM_NAME)

login:
	bash -c "test -s ~/.charmcraft-auth || charmcraft login --export ~/.charmcraft-auth"

release: login  ## Release charm
	@echo "# -- Releasing charm: https://charmhub.io/$(CHARMHUB_NAME)"
	$(eval CHARMCRAFT_AUTH := $(shell cat ~/.charmcraft-auth))
	charmcraft upload --name $(CHARMHUB_NAME) --release latest/stable $(CHARM_NAME)

upgrade: ## Upgrade charm
	juju upgrade-charm $(CHARM_NAME) --path ./$(CHARM_NAME)

force-upgrade: ## Force upgrade charm
	juju upgrade-charm $(CHARM_NAME) --path ./$(CHARM_NAME) --force-units


deploy-focal-bundle: ## Deploy Focal test bundle
	juju deploy ./tests/bundles/focal.yaml

deploy-jammy-bundle: ## Deploy Jammy test bundle
	juju deploy ./tests/bundles/jammy.yaml

deploy-noble-bundle: ## Deploy Noble test bundle
	juju deploy ./tests/bundles/noble.yaml


test-focal-bundle: ## Test Focal test bundle
	tox -e test-focal

test-jammy-bundle: ## Test Jammy test bundle
	tox -e test-jammy

test-noble-bundle: ## Test Noble test bundle
	tox -e test-noble


# Internal targets
clean-repo:
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo '!!! Hard resetting repo and removing untracked files !!!'; \
		git reset --hard; \
		git clean -fdx; \
	fi


# Display target comments in 'make help'
help: ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {sub("\\\\n",sprintf("\n%22c"," "), $$2);printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
