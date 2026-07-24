# Contributing to obsctl

Thanks for helping out. This document covers the local setup, the gates your
change has to pass, and the conventions the codebase already follows.

## Prerequisites

- Linux
- Crystal **1.20.2 or newer** and Shards
- OBS Studio with **obs-websocket 5.x** for manual testing (the automated specs
  use an in-tree fake OBS server and do not need a running OBS)

## Setup

```bash
shards install
```

Run `shards install` without `--production`: `ameba` is a development
dependency, and its postinstall step is what produces `bin/ameba` for the lint
gate.

## Gates

Every change must pass the same four gates CI enforces. Run them all at once:

```bash
make check
```

That is equivalent to:

| Command | Gate |
| --- | --- |
| `make format-check` | `crystal tool format --check` reports no diffs |
| `make lint` | `ameba` reports zero offenses |
| `make build` | the binary compiles |
| `make test` | `crystal spec` is fully green |

`make format` rewrites files in place if `format-check` fails.

Builds are faster if you reuse a cache directory:

```bash
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make check
```

### Linting

`.ameba.yml` is the source of truth. Every disabled rule and per-path exclusion
in it carries a comment explaining why. The rules that remain enabled are
expected to stay at **zero** offenses — please fix offenses rather than adding
exclusions. If a rule genuinely does not fit the codebase, change `.ameba.yml`
in the same PR and say why in the comment.

`ameba --fix` autocorrects the mechanical rules.

## Layout

| Path | Contents |
| --- | --- |
| `src/obsctl/cli/` | argument parsing and the thin client commands |
| `src/obsctl/server/` | the local daemon, OBS supervisor, and state store |
| `src/obsctl/obs/` | the obs-websocket 5.x client and request definitions |
| `src/obsctl/ipc/` | the Unix-socket protocol between client and daemon |
| `src/obsctl/tui/` | the terminal dashboard |
| `src/obsctl/config/` | config loading, schema validation, and dumping |
| `src/crytui/` | the in-tree immediate-mode TUI library |
| `spec/support/` | the fake OBS server and other spec helpers |
| `spec/fixtures/` | frozen contract fixtures |
| `docs/` | command grammar, config reference, and IPC protocol |

## Conventions

- **Contracts are frozen.** `docs/protocol.md` and `docs/commands.md` describe
  the IPC protocol, CLI grammar, JSON envelopes, and exit codes. Changing any
  of them is a breaking change: update the docs and the fixtures under
  `spec/fixtures/` in the same PR.
- **New commands need specs at the boundary**, not just at the unit level. See
  `spec/obsctl/cli/main_spec.cr` for the pattern — `Main.run` takes injectable
  `stdout`/`stderr`, so assert on captured `IO::Memory` rather than real output.
- **Never log secrets.** `Runtime::Logger.redact_secrets` and the equivalent
  pattern in `src/obsctl/ipc/response.cr` scrub passwords, tokens, and
  obs-websocket authentication strings. Route anything that could carry a
  credential through them.
- **Keep `shard.yml` and `src/obsctl/version.cr` in sync.** A spec asserts they
  match. Release tags are published as `v<version>`.

## Releasing

`shard.yml` and `src/obsctl/version.cr` carry the version currently in
development, so at release time they already hold the version being cut.

1. Confirm both files hold the version you are releasing.
2. Rename the `Unreleased` section of `CHANGELOG.md` to that version with
   today's date, and update the link definitions at the bottom.
3. Tag `v<version>` and push the tag.
4. Bump both files to the next in-development version and open a fresh
   `Unreleased` section.

The release workflow builds static musl binaries for `linux-amd64` and
`linux-arm64`, publishes `SHA256SUMS.txt`, and generates the release notes.

## Reporting security issues

Please do not open a public issue for a vulnerability. See
[SECURITY.md](SECURITY.md).
