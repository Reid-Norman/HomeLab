SHELL := /bin/bash

.PHONY: deploy-media deploy-management deploy-networking deploy-automation deploy-all ansible-sync vault-edit generate-creds

deploy-media:
	@echo "Starting docker-media-stack..."
	cd docker-media-stack && COMPOSE_PROFILES=vpn docker compose up -d

deploy-management:
	@echo "Starting docker-management-stack..."
	cd docker-management-stack && docker compose up -d

deploy-networking:
	@echo "Starting docker-networking-stack..."
	cd docker-networking-stack && docker compose up -d

deploy-automation:
	@echo "Starting docker-automation-stack..."
	cd docker-automation-stack && docker compose up -d

deploy-all: deploy-management deploy-networking deploy-media deploy-automation

ansible-sync:
	ansible-playbook -i ansible/inventory/hosts.yml ansible/site.yml --ask-vault-pass

vault-edit:
	ansible-vault edit ansible/group_vars/all/vault.yml

generate-creds:
	@./scripts/generate-credentials.sh $(STACK)
