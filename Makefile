CRYSTAL ?= crystal

.PHONY: build test format format-check lint check bootstrap-obsctl-rs-contract-fixtures contract-rs-compat run release

# Every gate CI enforces, in the order a contributor should hit them.
check: format-check lint build test

build:
	mkdir -p bin
	$(CRYSTAL) build src/obsctl.cr -o bin/obsctl

test:
	$(CRYSTAL) spec

format:
	$(CRYSTAL) tool format

format-check:
	$(CRYSTAL) tool format --check

lint:
	@if [ ! -x bin/ameba ]; then \
		echo "ameba not found at bin/ameba; run 'shards install' first" >&2; \
		exit 1; \
	fi
	bin/ameba

bootstrap-obsctl-rs-contract-fixtures:
	scripts/bootstrap_obsctl_rs_contract_fixtures ../obsctl-rs

contract-rs-compat:
	OBSCTL_STRICT_OBSCTL_RS_COMPAT=1 $(CRYSTAL) spec spec/obsctl/contracts

run:
	$(CRYSTAL) run src/obsctl.cr

release:
	mkdir -p bin
	$(CRYSTAL) build --release src/obsctl.cr -o bin/obsctl
