SHELL := /bin/bash

.PHONY: deploy-media deploy-audiobooks deploy-media-full deploy-management deploy-networking deploy-automation deploy-all down-all ansible-sync ansible-deps vault-edit generate-creds extract-keys

deploy-media:
	@echo "Starting docker-media-stack (movies & TV)..."
	cd docker-media-stack && COMPOSE_PROFILES=media docker compose up -d

deploy-audiobooks:
	@echo "Starting docker-media-stack (audiobooks)..."
	cd docker-media-stack && COMPOSE_PROFILES=audiobooks docker compose up -d

deploy-media-full:
	@echo "Starting docker-media-stack (all media)..."
	cd docker-media-stack && COMPOSE_PROFILES=media,audiobooks docker compose up -d

deploy-management:
	@echo "Starting docker-management-stack..."
	cd docker-management-stack && docker compose up -d

deploy-networking:
	@echo "Starting docker-networking-stack..."
	cd docker-networking-stack && docker compose up -d

deploy-automation:
	@echo "Starting docker-automation-stack..."
	cd docker-automation-stack && docker compose up -d

deploy-all: deploy-management deploy-networking deploy-media-full deploy-automation

down-all:
	@echo "Stopping docker-automation-stack..."
	cd docker-automation-stack && docker compose down
	@echo "Stopping docker-media-stack..."
	cd docker-media-stack && COMPOSE_PROFILES=media,audiobooks,recommendarr docker compose down
	@echo "Stopping docker-networking-stack..."
	cd docker-networking-stack && docker compose down
	@echo "Stopping docker-management-stack..."
	cd docker-management-stack && docker compose down
	@echo "All stacks stopped."

ansible-deps:
	ansible-galaxy collection install -r ansible/requirements.yml --upgrade
	pip3 install --user uptime-kuma-api

ansible-sync:
	ansible-playbook -i ansible/inventory/hosts.yml ansible/site.yml --ask-vault-pass

vault-edit:
	ansible-vault edit ansible/group_vars/all/vault.yml

generate-creds:
	@./scripts/generate-credentials.sh $(STACK)

extract-keys:
	@./scripts/extract-api-keys.sh
