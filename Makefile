CRYSTAL ?= crystal

# `crystal tool format` skips a top-level lib/ but not a nested one, and
# building crytui/ on its own leaves a crytui/lib/ full of vendored code that
# is not ours to reformat. Naming the trees explicitly keeps the formatter on
# first-party code wherever dependencies happen to be installed.
FORMAT_PATHS = src spec scripts crytui/src crytui/spec

.PHONY: build test format format-check lint check bootstrap-obsctl-rs-contract-fixtures contract-rs-compat run release site-themes

# Every gate CI enforces, in the order a contributor should hit them.
check: format-check lint build test

build:
	mkdir -p bin
	$(CRYSTAL) build src/obsctl.cr -o bin/obsctl

# CryTUI is its own shard under crytui/, so its specs live outside spec/ and a
# bare `crystal spec` would miss them. They are two invocations rather than one
# because CryTUI would otherwise be compiled into the same program twice, under
# two names: obsctl reaches it as the installed shard (lib/crytui, a symlink),
# while its own specs reach it by relative path. Crystal treats those as two
# different files and refuses to reopen the enums. Separate runs also keep the
# library's specs honest — they compile without obsctl present at all.
test:
	$(CRYSTAL) spec
	$(CRYSTAL) spec crytui/spec

format:
	$(CRYSTAL) tool format $(FORMAT_PATHS)

format-check:
	$(CRYSTAL) tool format --check $(FORMAT_PATHS)

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

# Re-exports the microsite's theme palettes from the real theme table. Run
# after changing a theme; the Pages workflow fails if the committed palettes no
# longer match.
site-themes:
	$(CRYSTAL) run scripts/render_site_themes.cr
