# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
shards install            # required first; ameba is a dev dependency the lint gate needs
make check                # format-check + lint + build + test — the four gates CI enforces
make format               # rewrites files when format-check fails
make lint                 # builds bin/ameba from the pinned checkout on first use (~30s)
make build                # bin/obsctl (debug)
make release              # bin/obsctl (--release)
make run                  # crystal run src/obsctl.cr
```

Reuse a cache dir to speed up repeated builds: `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make check`.

Running specs:

```bash
crystal spec                                     # whole suite (make test)
crystal spec spec/obsctl/cli/main_spec.cr        # one file
crystal spec spec/obsctl/cli/main_spec.cr:120    # one example by line
crystal spec spec/obsctl/tui                     # one directory
crystal spec -e "reconnect"                      # by example name
make contract-rs-compat                          # strict fixture compat against ../obsctl-rs
```

The suite is deterministic and needs no running OBS — it uses an in-tree fake obs-websocket server (`spec/support/fake_obs_server.cr`), real Unix sockets, and real PTYs.

`ameba` is pinned to a master commit because 1.6.4 does not build on Crystal 1.21. CI lints only on the 1.21.0 floor leg; the `latest` leg installs `--production` and just builds + tests.

## Architecture

Three processes, one connection owner:

```
OBS Studio ──WebSocket──> obsctl server (daemon) ──Unix socket JSON──> CLI / TUI
```

The daemon is the sole owner of the OBS WebSocket and the authoritative state holder. Everything else is a thin IPC client. **This boundary is a mechanically enforced contract**, not a convention — `spec/obsctl/architecture_boundary_spec.cr` greps the tree and fails if:

- anything under `src/obsctl/{cli,ipc,domain,tui}/` requires `obs/client`/`obs/connection` or names `OBS::Client`/`OBS::Connection`;
- any file under `src/obsctl/server/` other than `obs_supervisor.cr` constructs an OBS client;
- `IPC::CommandPayload` handling or `@supervisor.with_client` appears anywhere but `server/command_executor.cr`.

Adding an OBS call means going through `CommandExecutor` → `ObsSupervisor#with_client`, never around it.

### Layers

| Path | Role |
| --- | --- |
| `src/obsctl/cli/` | option parsing, thin client commands, completions, `watch` |
| `src/obsctl/domain/` | command registry/parser, aliases, error → exit-code mapping |
| `src/obsctl/ipc/` | newline-delimited JSON Unix-socket protocol, codec, socket path resolution |
| `src/obsctl/server/` | daemon: supervisor, state store, command executor, client registry, log fanout |
| `src/obsctl/obs/` | obs-websocket 5.x client, auth, protocol messages, state snapshots |
| `src/obsctl/tui/` | dashboard: model, input → action, dispatcher, event applier, widgets |
| `src/obsctl/config/` | YAML config, schema validation, atomic writes, dump/diff/explain |
| `src/crytui/` | in-tree immediate-mode TUI library (Ratatui-inspired), independent of obsctl |

`src/obsctl.cr` is a four-line entry point delegating to `CLI::Main.run(ARGV)`.

### Single sources of truth

- **`domain/command_registry.cr`** declares every command once (`CommandSpec`: name, aliases, argument kinds, surface flags, `--json` eligibility, builder proc). The parser, the JSON allowlist, palette completion, `--help`, and generated shell completions all read it, so a command cannot exist on one surface and be missing from another. Add commands here, not in the parser or help text.
- **`domain/errors.cr`** maps every error class to a stable `ExitCode` (0 success, 1 failure, 2 config, 3 connection, 4 OBS request, 5 command parse, 6 IPC). `CLI::Main.run` is only an error boundary — it converts exceptions into the exit code plus either a JSON envelope or a human stderr diagnostic.
- **`config/config_value.cr`** provides the macro that generates getters, YAML mapping, and initializer from one field list. Add a setting with one declaration.

### TUI shape

Unidirectional: `input.cr` maps keys to an `Action`; `dispatcher.cr` applies it (focus moves are a lookup table, commands go over IPC); `event_applier.cr` folds server-pushed `state`/`events`/`logs` into the `Model`; widgets render the model into a CryTUI `Buffer`, which diffs against the previous frame for incremental cell updates. Volume keypresses update the model optimistically and coalesce into one OBS command 120 ms after input stops.

The TUI opens **no** OBS connection — it subscribes to daemon topics.

## Conventions

- **Contracts are frozen.** `docs/protocol.md` (IPC framing, command names, topics) and `docs/commands.md` (CLI grammar, JSON envelopes, exit codes) are public contract. Changing them is a breaking change: update the docs and the fixtures in `spec/fixtures/contracts/` in the same PR.
- **Fixtures require a manifest entry.** Every file under `spec/fixtures/contracts/{cli/human,cli/json,ipc}/` must be listed in `contract_manifest.yml` with `category`, `purpose`, `behavior`, and `contains_dropped_reconnect_diagnostic_logs`. `contract_manifest_audit_spec.cr` fails in both directions — unlisted file on disk, and listed file that no longer exists. The sibling `obsctl-rs` compat check drives entirely off this manifest.
- **Test at the boundary.** `Main.run` takes injectable `stdout`/`stderr`/`tui_runner`; use `spec/support/cli_capture.cr` and assert on captured `IO::Memory` rather than real process output. Use `spec/support/tcp_gate.cr` when a spec needs a port that refuses connections and then becomes reachable — it avoids the TOCTOU race of picking an unused port.
- **Never log secrets.** Route anything that might carry a credential through `Runtime::Logger.redact_secrets` or the equivalent scrubber in `src/obsctl/ipc/response.cr`.
- **Keep `shard.yml` and `src/obsctl/version.cr` in sync** — `spec/obsctl/cli/main_spec.cr` asserts it. Tags are `v<version>`.
- **`.ameba.yml` is the source of truth for lint.** Every disabled rule and exclusion carries a comment explaining why; enabled rules stay at zero offenses. Fix offenses rather than adding exclusions — and if a rule genuinely doesn't fit, change `.ameba.yml` in the same PR with the reason. `Metrics/CyclomaticComplexity` is a deliberate ratchet at 25 (not ameba's default 10); don't raise it.
- **Comments explain *why*.** The codebase consistently documents non-obvious decisions (why a signal trap exists, why a spec pre-declares a nil variable, why a pin exists) rather than restating the code. Match that.

## Spec environment variables

`OBSCTL_CONFIG` (config path override, also a user-facing setting), `OBSCTL_LOCALE` (`en`/`uk`), `OBSCTL_SPEC_MISSING_PASSWORD`, `OBSCTL_TEST_PASSWORD`, `OBSCTL_STRICT_OBSCTL_RS_COMPAT`, `OBSCTL_SKIP_OBSCTL_RS_COMPAT`.
