CRYSTAL ?= crystal

.PHONY: build test format lint contract-rs-compat run release

build:
	$(CRYSTAL) build src/obsctl.cr -o bin/obsctl

test:
	$(CRYSTAL) spec

format:
	$(CRYSTAL) tool format

lint:
	@if [ -x bin/ameba ]; then bin/ameba; else echo "ameba not installed; run shards install"; fi

contract-rs-compat:
	@if [ -d ../obsctl-rs ]; then \
		$(CRYSTAL) spec spec/obsctl/contracts; \
	else \
		echo "obsctl-rs sibling not found; skipping fixture compatibility"; \
	fi

run:
	$(CRYSTAL) run src/obsctl.cr

release:
	$(CRYSTAL) build --release src/obsctl.cr -o bin/obsctl
