CRYSTAL ?= crystal

.PHONY: build test format format-check lint check bootstrap-obsctl-rs-contract-fixtures contract-rs-compat run release site-frames readme-shots

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

# ameba no longer ships a postinstall that produces bin/ameba, so build it here
# from the pinned checkout. The binary is rebuilt only when the source changes.
bin/ameba: lib/ameba/src/cli.cr
	@if [ ! -d lib/ameba ]; then \
		echo "lib/ameba is missing; run 'shards install' first" >&2; \
		exit 1; \
	fi
	mkdir -p bin
	$(CRYSTAL) build lib/ameba/src/cli.cr -o bin/ameba

lint: bin/ameba
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

# Redraws the microsite's terminal frames from the real widget code. Run after
# changing a widget or a theme; the Pages workflow fails if the committed
# frames no longer match.
site-frames:
	$(CRYSTAL) run scripts/render_site_frames.cr

# Redraws the README screenshots from the same widget code. They are committed
# under docs/assets, so run this after changing a widget or a theme.
readme-shots:
	$(CRYSTAL) run scripts/render_readme_shots.cr
