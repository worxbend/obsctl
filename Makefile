CRYSTAL ?= crystal

.PHONY: build test format lint bootstrap-obsctl-rs-contract-fixtures contract-rs-compat run release

build:
	$(CRYSTAL) build src/obsctl.cr -o bin/obsctl

test:
	$(CRYSTAL) spec

format:
	$(CRYSTAL) tool format

lint:
	@if [ -x bin/ameba ]; then bin/ameba; else echo "ameba not installed; run shards install"; fi

bootstrap-obsctl-rs-contract-fixtures:
	scripts/bootstrap_obsctl_rs_contract_fixtures ../obsctl-rs

contract-rs-compat:
	OBSCTL_STRICT_OBSCTL_RS_COMPAT=1 $(CRYSTAL) spec spec/obsctl/contracts

run:
	$(CRYSTAL) run src/obsctl.cr

release:
	$(CRYSTAL) build --release src/obsctl.cr -o bin/obsctl
