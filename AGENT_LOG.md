# Agent Log

Append-only progress log for autonomous iterations.

## 2026-06-15

- Added autonomous runner scaffolding:
  - `AGENT.md`
  - `MEMORY.md`
  - `seed_plan.md`
  - `scripts/agent-loop.sh`
- Goal: enable bounded Codex CLI iterations over `TODO.md` and the daemon/client-server migration plan.
2026-06-15T18:02:36Z 
2026-06-15T18:02:36Z autonomous loop started budget=5h worktree=/home/worxbend/Worxpace/obsctl full_auto=0 push=0
2026-06-15T18:02:36Z iteration 1 started
2026-06-15T18:02:36Z iteration 1 codex failed status=2
2026-06-15T18:05:48Z 
2026-06-15T18:05:48Z autonomous md loop started iterations=25 budget=5h push=1
2026-06-15T18:05:48Z iteration 1 started
2026-06-15T18:05:48Z iteration 1 codex failed
2026-06-15T18:06:37Z 
2026-06-15T18:06:37Z autonomous md loop started iterations=25 budget=5h push=1
2026-06-15T18:06:37Z iteration 1 started

## 2026-06-15 IPC primitives

- Added `src/obsctl/ipc/` with typed request/response/event models, newline JSON codec, socket path resolution, Unix client/session wrappers, and Unix server binding with stale socket cleanup.
- Added IPC specs for codec validation, socket path resolution, stale socket cleanup, and Unix socket round trip.
- Updated protocol docs and `TODO.md`; next planned slice is `server/` foreground/headless runtime.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T18:11:16Z iteration 1 validation started
2026-06-15T18:11:23Z iteration 1 committed
2026-06-15T18:11:25Z iteration 1 pushed
2026-06-15T18:11:25Z iteration 2 started

## 2026-06-15 Server runtime scaffold

- Added `src/obsctl/server/` with foreground/headless server options, state store, OBS supervisor fiber, command executor, and Unix socket IPC session handling.
- Wired `obsctl server` and `obsctl server --headless` into the CLI while leaving existing direct CLI commands unchanged for the next proxy-conversion slice.
- Adjusted CLI option parsing so command-specific flags such as `server --headless` are preserved for command handlers.
- Added server specs covering IPC availability when OBS is unavailable and scene changes through the server-owned OBS client.
- Fixed Unix server accept-loop re-raise now that the blocking listen path is compiled by server runtime.
- Updated `TODO.md` and command docs; next planned slice is CLI command proxying through local IPC.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T18:17:10Z iteration 2 validation started
2026-06-15T18:17:17Z iteration 2 committed
2026-06-15T18:17:19Z iteration 2 pushed
2026-06-15T18:17:19Z iteration 3 started

## 2026-06-15 CLI IPC proxying

- Added `CLI::ClientCommands` to send non-interactive OBS-control commands over local Unix socket IPC instead of creating an OBS WebSocket client.
- Added `server-status`, `vol` alias support, remote IPC error mapping, and missing-server startup/service guidance with exit code `3`.
- Updated CLI integration specs so scene/audio commands run through an `obsctl server` instance backed by the fake OBS server.
- Updated `README.md`, `docs/commands.md`, and `TODO.md`; next planned slice is server client registry and broadcast fanout for subscriptions.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T18:22:02Z iteration 3 validation started
2026-06-15T18:22:10Z iteration 3 committed
2026-06-15T18:22:12Z iteration 3 pushed
2026-06-15T18:22:12Z iteration 4 started

## 2026-06-15 Server subscription broadcasts

- Added a persistent server-side client registry for subscribed IPC sessions with topic validation and dead-session cleanup.
- Wired state-store updates to broadcast `state` events to subscribers after supervisor refreshes and command-triggered snapshot changes.
- Serialized IPC session writes so command responses and pushed events cannot interleave on a socket.
- Added server coverage proving a subscribed IPC client receives a pushed state snapshot after a server-owned scene change.
- Updated protocol docs and `TODO.md`; next planned slice is converting the TUI to subscribe over local IPC.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T18:26:57Z iteration 4 validation started
2026-06-15T18:27:06Z iteration 4 committed
2026-06-15T18:27:08Z iteration 4 pushed
2026-06-15T18:27:08Z iteration 5 started

## 2026-06-15 TUI IPC client

- Added an IPC-backed TUI session client that subscribes to server state, parses pushed snapshots, and forwards scene/audio/dump/reload commands to the server.
- Changed normal TUI startup to use the IPC client by default; the direct OBS session adapter remains available for embedded-style use/tests.
- Routed `obsctl tui` to the same TUI startup path as bare `obsctl`.
- Added TUI IPC subscription/command-forwarding coverage and updated existing session specs for the client boundary.
- Updated `README.md`, `docs/commands.md`, and `TODO.md`; next planned slice is systemd user service command support.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T18:33:02Z iteration 5 validation started
2026-06-15T18:33:11Z iteration 5 committed
2026-06-15T18:33:13Z iteration 5 pushed
2026-06-15T18:33:13Z iteration 6 started

## 2026-06-15 Systemd user service commands

- Added `src/obsctl/service/` with systemd user service unit rendering, installer/uninstaller behavior, and `systemctl --user` command execution.
- Wired `obsctl service install|uninstall|status|start|stop|restart` into the CLI outside the OBS IPC proxy path.
- Added service specs covering unit generation, install/uninstall daemon reloads, action dispatch, invalid actions, and systemctl failure mapping.
- Updated `README.md`, `docs/commands.md`, and `TODO.md`; next planned slice is explicit OBS event subscription options during Identify in server mode.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T18:37:13Z iteration 6 validation started
2026-06-15T18:37:21Z iteration 6 committed
2026-06-15T18:37:24Z iteration 6 pushed
2026-06-15T18:37:24Z iteration 7 started

## 2026-06-15 OBS Identify event subscriptions

- Added protocol constants for obs-websocket event subscription masks and wired server-owned OBS clients to Identify with an explicit General + Scenes + Inputs subscription mask.
- Extended the fake OBS server to record Identify payloads without blocking the handshake.
- Added OBS client and server specs proving explicit `eventSubscriptions` are sent, plus protocol coverage for the server default mask.
- Updated `docs/protocol.md` and `TODO.md`; next planned slice is dump-config CLI integration coverage through the server.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T18:40:24Z iteration 7 validation started
2026-06-15T18:40:32Z iteration 7 committed
2026-06-15T18:40:35Z iteration 7 pushed
2026-06-15T18:40:35Z iteration 8 started

## 2026-06-15 Dump-config CLI integration coverage

- Added CLI integration coverage proving `obsctl dump-config` is sent through the local server IPC path while the server owns the fake OBS WebSocket connection.
- Verified dump-config preserves existing aliases, discovers missing OBS scenes/audio inputs, writes the config, and creates a backup.
- Updated `TODO.md`; next planned slice is pending request/WebSocket close error handling.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T18:43:18Z iteration 8 validation started
2026-06-15T18:43:28Z iteration 8 committed
2026-06-15T18:43:30Z iteration 8 pushed
2026-06-15T18:43:30Z iteration 9 started

## 2026-06-15 OBS pending request shutdown

- Hardened `OBS::Client` WebSocket shutdown handling so close callbacks and reader-fiber errors mark the client unidentified and fail in-flight pending requests promptly.
- Buffered per-request response channels so late responses cannot block the reader after caller timeouts.
- Added fake OBS server hooks for delayed request responses and request notifications, keeping notifications nonblocking so tests do not alter server behavior.
- Added OBS client integration coverage proving an in-flight request fails with `ConnectionFailed` when the WebSocket closes instead of waiting for the request timeout.
- Updated `TODO.md`; next planned slice is detecting established OBS WebSocket disconnects in the server supervisor and reconnecting statefully.
- Validation passed after fixing a fake-server notification backpressure regression found by the first full spec run:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T18:47:44Z iteration 9 validation started
2026-06-15T18:47:53Z iteration 9 committed
2026-06-15T18:47:56Z iteration 9 pushed
2026-06-15T18:47:56Z iteration 10 started

## 2026-06-15 Server OBS disconnect detection

- Added OBS client connection-state reporting and changed the server supervisor to monitor established WebSocket sessions after the initial snapshot.
- Server state now transitions to disconnected when OBS closes after a successful connection, clears the stale client, keeps IPC available, and retries when reconnect is enabled.
- Hardened the fake OBS server so tests can close accepted WebSocket sessions deterministically.
- Added server coverage proving IPC status remains available after an established OBS disconnect and scene commands return `OBS_UNAVAILABLE`.
- Updated `TODO.md`; next planned slice is raw-mode keyboard handling and a real command palette.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T18:50:31Z iteration 10 validation started
2026-06-15T18:50:41Z iteration 10 committed
2026-06-15T18:50:43Z iteration 10 pushed
2026-06-15T18:50:43Z iteration 11 started

## 2026-06-15 TUI raw command palette input

- Added a testable TUI input controller with command palette open/edit/backspace/submit/cancel behavior and dashboard shortcuts for quit, reload-config, and dump-config.
- Changed the ANSI TUI app loop to read raw character input when attached to a TTY while preserving non-TTY character input.
- Added command palette input specs and updated README, command docs, and `TODO.md`; next planned slice is evaluating termisu/proper widgets or event/log topic fanout.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T18:54:00Z iteration 11 validation started
2026-06-15T18:54:10Z iteration 11 committed
2026-06-15T18:54:13Z iteration 11 pushed
2026-06-15T18:54:13Z iteration 12 started

## 2026-06-15 Server event/log topic fanout

- Added server-side `events` and `logs` IPC topic broadcasts for OBS events, supervisor connection state, and command failures.
- Changed subscription acknowledgement behavior so the initial snapshot is pushed only to clients subscribed to `state`.
- Taught the IPC-backed TUI session client to parse pushed OBS event topic payloads into existing TUI event objects.
- Added fake OBS event emission helpers and specs covering event fanout, state refresh after OBS events, command failure log fanout, and TUI IPC event parsing.
- Updated `README.md`, `docs/protocol.md`, and `TODO.md`; next planned slice is request correlation hardening for long-lived IPC clients or termisu evaluation.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T19:00:20Z iteration 12 validation started
2026-06-15T19:00:31Z iteration 12 committed
2026-06-15T19:00:34Z iteration 12 pushed
2026-06-15T19:00:34Z iteration 13 started

## 2026-06-15 TUI IPC request correlation

- Hardened the IPC-backed TUI session client with per-request pending response channels so overlapping long-lived commands are matched by response ID.
- Kept pushed IPC events on the existing event queue while command responses are dispatched directly to their waiting request.
- Added TUI IPC coverage proving two concurrent commands complete when the fake server replies out of order.
- Updated `TODO.md`; next planned slice is termisu/proper widget evaluation or documentation polish.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T19:03:10Z iteration 13 validation started
2026-06-15T19:03:21Z iteration 13 committed
2026-06-15T19:03:23Z iteration 13 pushed
2026-06-15T19:03:23Z iteration 14 started

## 2026-06-15 Config server/reconnect schema

- Added top-level `server` and `reconnect` config sections, including compatibility for legacy `connection.reconnect` and canonical top-level writes.
- Wired configured `server.socket_path` into `obsctl server`, thin CLI IPC clients, and normal TUI IPC sessions.
- Fixed boolean config parsing so explicit `false` values are preserved, and added validation for server path and reconnect policy values.
- Added specs for config migration, reconnect precedence, custom socket CLI behavior, and boolean parsing; updated config docs and `TODO.md`.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T19:10:23Z iteration 14 validation started
2026-06-15T19:10:34Z iteration 14 committed
2026-06-15T19:10:36Z iteration 14 pushed
2026-06-15T19:10:36Z iteration 15 started

## 2026-06-15 Server maintenance IPC commands

- Added missing server-side IPC maintenance commands for config validation, explicit OBS reconnect requests, and guarded server shutdown.
- Wired `/obs-status`, `/validate-config`, `/reconnect`, and `/shutdown-server` through the shared command parser and thin client command mapper while keeping `obsctl validate-config` as a local config-file check.
- Added server specs for IPC config validation, default shutdown rejection, and enabled shutdown lifecycle behavior, plus parser coverage for the new maintenance commands.
- Updated README, command docs, protocol docs, and `TODO.md`; next planned slice remains termisu/proper widget evaluation or public API documentation polish.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T19:18:06Z iteration 15 validation started
2026-06-15T19:18:18Z iteration 15 committed
2026-06-15T19:18:20Z iteration 15 pushed
2026-06-15T19:18:20Z iteration 16 started

## 2026-06-15 TUI panelized ANSI renderer

- Evaluated `termisu`: available as a Crystal shard, but upstream documents it as pre-1.0 and not battle-tested, so this slice avoided adding a new runtime dependency.
- Replaced the monolithic ANSI renderer body with connection, scenes, grouped scene map, audio, recent logs, and command palette widget renderers.
- Taught the IPC-backed TUI session client and session model to collect server `logs` topic messages for dashboard display.
- Added TUI renderer, IPC log-topic, and session log-model specs; updated README, command docs, and `TODO.md`.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T19:24:19Z iteration 16 validation started
2026-06-15T19:24:31Z iteration 16 committed
2026-06-15T19:24:33Z iteration 16 pushed
2026-06-15T19:24:33Z iteration 17 started

## 2026-06-15 Plaintext password validation warning

- Added config-schema warnings for plaintext `connection.password` values without exposing the configured secret.
- Changed `obsctl validate-config` to print the plaintext-password warning while keeping config loading side-effect free.
- Added schema and CLI specs for safe warning behavior, and updated README/config/command docs plus `TODO.md`.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T19:28:56Z iteration 17 validation started
2026-06-15T19:29:08Z iteration 17 committed
2026-06-15T19:29:10Z iteration 17 pushed
2026-06-15T19:29:10Z iteration 18 started

## 2026-06-15 Server log-level wiring

- Added typed runtime log-level parsing and filtering for `--log-level debug|info|warn|error`.
- Wired CLI server startup to create a runtime logger and persist server lifecycle, supervisor, and command-failure log events with redaction.
- Added runtime logger specs, CLI invalid-level coverage, and server log persistence coverage.
- Updated README, command docs, and `TODO.md`; next planned slice remains termisu/public documentation polish.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T19:32:19Z iteration 18 validation started
2026-06-15T19:32:41Z iteration 18 committed
2026-06-15T19:33:01Z iteration 18 validation started
2026-06-15T19:33:12Z iteration 18 committed
2026-06-15T19:33:16Z iteration 18 pushed
2026-06-15T19:33:16Z iteration 19 started

## 2026-06-15 Server status payload polish

- Expanded server-side `get_server_status` IPC responses with uptime, socket path, subscribed client count, OBS connection state, reconnecting state, and last error.
- Updated thin CLI `server-status` formatting to print the expanded daemon status fields.
- Added server IPC coverage for the daemon status contract and documented the output in README/commands docs.
- Updated `TODO.md` to reflect the completed status payload polish.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T19:35:52Z iteration 19 validation started
2026-06-15T19:36:04Z iteration 19 committed
2026-06-15T19:36:06Z iteration 19 pushed
2026-06-15T19:36:06Z iteration 20 started

## 2026-06-15 Dump-config conflict reporting

- Hardened `ConfigDump.merge` so dump writes preserve top-level `server` and `reconnect` daemon settings.
- Added pre-write dump conflict reporting for duplicate scene/audio aliases or shortcuts and alias/shortcut collisions with discovered OBS object names.
- Added config-level and CLI-through-server coverage proving conflicting dumps return a config error without writing the config or creating a backup.
- Updated README, config docs, command docs, and `TODO.md`; Milestone 5 now has no remaining tracked dump-config items.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T19:40:40Z iteration 20 validation started
2026-06-15T19:40:52Z iteration 20 committed
2026-06-15T19:40:54Z iteration 20 pushed
2026-06-15T19:40:54Z iteration 21 started

## 2026-06-15 TUI viewport-bounded renderer

- Added viewport-aware ANSI TUI rendering with width/height bounds, terminal `COLUMNS`/`LINES` sizing, fixed panel budgets, and line truncation for long scene/audio/log content.
- Added renderer coverage proving output stays within the requested viewport.
- Updated README, command docs, and `TODO.md`; next planned slice remains termisu/incremental renderer evaluation or public documentation polish.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T19:44:18Z iteration 21 validation started
2026-06-15T19:44:30Z iteration 21 committed
2026-06-15T19:44:32Z iteration 21 pushed
2026-06-15T19:44:32Z iteration 22 started

## 2026-06-15 TUI incremental ANSI renderer

- Added a frame-building path to the ANSI TUI renderer and an incremental renderer that emits row-level diffs after the initial full paint.
- Switched the interactive TUI app loop to use incremental rendering while preserving the existing full-render API for tests and snapshots.
- Added renderer specs covering first-paint behavior, changed-row updates, and unchanged-frame no-op output.
- Updated README, command docs, and `TODO.md`; next planned slice is public documentation comments/lint polish or CLI service smoke coverage.
- Validation passed:
  - `make format`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test`
  - `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build`
  - `make lint` (Ameba not installed; Makefile skip path)
2026-06-15T19:47:36Z iteration 22 validation started
