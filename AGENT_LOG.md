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
