-include .env

.PHONY: all test deploy-test deploy help

# Foundry commands
FORGE ?= forge

# Default to not broadcasting
BROADCAST ?= false

# Split flags into basic and broadcast-specific
BASIC_FLAGS = --rpc-url ${TENDERLY_URL}

# Conditional broadcast flags
ifeq ($(BROADCAST),true)
    BROADCAST_FLAGS = --slow \
                     --broadcast \
                     --verify \
                     --verifier-url ${TENDERLY_VERIFIER_URL} \
                     --etherscan-api-key ${TENDERLY_ACCESS_TOKEN}
else
    BROADCAST_FLAGS =
endif

help:
	@echo "Available commands:"
	@echo "  make deploy-test                     - Deploy test environment (dry run)"
	@echo "  make deploy-test BROADCAST=true      - Deploy test environment (broadcast)"
	@echo "  make deploy SCRIPT=path/to/script.sol  - Deploy custom script (dry run)"
	@echo "  make deploy SCRIPT=path/to/script.sol BROADCAST=true  - Deploy custom script (broadcast)"

# Deploy test environment
deploy-test:
	${FORGE} script script/deploy/test_env/TestEnvironmentSetup.s.sol ${BASIC_FLAGS} ${BROADCAST_FLAGS}

# Generic deploy command
deploy:
	@if [ -z "$(SCRIPT)" ]; then \
		echo "Error: SCRIPT parameter is required. Usage: make deploy SCRIPT=path/to/script.sol"; \
		exit 1; \
	fi
	${FORGE} script ${SCRIPT} ${BASIC_FLAGS} ${BROADCAST_FLAGS} 