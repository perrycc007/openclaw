# OpenClaw local development helpers
# Usage: make start | make stop | make restart | make qr | make status | make logs

SHELL := /bin/bash

GATEWAY_TOKEN := a69543a8abb5c136bec202bc8b7ed305031eda96649a5bd1ce2094adc0d8deb4
GATEWAY_PORT  := 18789

export COREPACK_ENABLE_STRICT := 0
export OPENCLAW_INGEST_ONLY   := 1
export OPENCLAW_GATEWAY_TOKEN := $(GATEWAY_TOKEN)

# --- Helpers ---

define find_pid
$$(netstat -ano 2>/dev/null | grep ':$(GATEWAY_PORT)' | grep LISTENING | awk '{print $$NF}' | head -1)
endef

define kill_pid
if command -v taskkill >/dev/null 2>&1; then \
	taskkill //F //PID $$PID >/dev/null 2>&1 && echo "Killed PID $$PID"; \
else \
	kill -9 $$PID 2>/dev/null && echo "Killed PID $$PID"; \
fi
endef

# --- Gateway lifecycle ---

.PHONY: start stop restart status logs qr login logout clean-creds test-msg help

start: ## Start the gateway in the background
	@echo "Building OpenClaw..."
	@pnpm build
	@echo "Starting OpenClaw gateway on port $(GATEWAY_PORT)..."
	@nohup pnpm openclaw gateway run --port $(GATEWAY_PORT) --force > /tmp/openclaw-gateway.log 2>&1 &
	@sleep 5
	@"$(MAKE)" --no-print-directory status

stop: ## Stop the running gateway
	@echo "Stopping OpenClaw gateway..."
	@pnpm openclaw gateway stop 2>/dev/null \
		|| (echo "Service not found, killing by port..."; \
		    PID=$(find_pid); \
		    if [ -n "$$PID" ]; then $(kill_pid) \
		    else echo "No gateway process found."; fi)

restart: stop start ## Restart the gateway

status: ## Show gateway status
	@echo "--- Gateway process ---"
	@PID=$(find_pid); \
	if [ -n "$$PID" ]; then \
		echo "Gateway running (PID $$PID) on port $(GATEWAY_PORT)"; \
		echo "Control UI: http://localhost:$(GATEWAY_PORT)"; \
	else \
		echo "Gateway is NOT running."; \
	fi

logs: ## Tail the gateway log
	@tail -f /tmp/openclaw-gateway.log

# --- Testing ---

test-msg: ## Send a test message to +85296374978 via WhatsApp
	@pnpm openclaw message send --channel whatsapp --target +85296374978 --message "Hello from OpenClaw"

# --- WhatsApp ---

qr: ## Show WhatsApp QR code in terminal for linking
	@echo "Generating WhatsApp QR code..."
	@pnpm openclaw channels login --channel whatsapp

login: qr ## Alias for qr

logout: ## Log out of WhatsApp and clear session
	@pnpm openclaw channels logout --channel whatsapp

clean-creds: ## Remove all WhatsApp credentials from disk
	@echo "Removing WhatsApp credentials..."
	@rm -rf ~/.openclaw/credentials/whatsapp/default/*
	@echo "Done. Run 'make qr' to re-link."

# --- Help ---

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
