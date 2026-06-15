# Project Memory

This file is durable context for autonomous agent runs.

## Product Direction

`obsctl-cr` is a Crystal 1.20.2 app for controlling OBS Studio through obs-websocket 5.x. The target architecture is now a local client/server model:

```text
OBS Studio <----obs-websocket----> obsctl server <----local IPC----> obsctl TUI
                                                    <----local IPC----> obsctl CLI
```

The long-lived `obsctl server` owns the OBS WebSocket connection, config, aliases, state cache, reconnect loop, dump-config behavior, and local IPC socket. CLI and TUI are thin clients in normal mode.

## Current Implementation Summary

- Crystal shard builds `bin/obsctl`.
- Existing direct CLI/TUI behavior still talks to OBS through local client wrappers.
- Config loading/writing/validation exists.
- OBS WebSocket client exists with auth, request matching, events channel, scene/audio commands, and snapshot fetch.
- Minimal ANSI TUI exists with session model, event application, and reconnect-on-poll behavior.
- Fake OBS WebSocket server exists for specs.
- `TODO.md` contains the current architecture migration plan.
- `IMPLEMENTATION_CHECK_PLAN.md` contains the strict final review and implementation correctness plan. Autonomous runs must cross-check against it.

## Important Technical Notes

- Crystal cache may need a writable directory:
  `CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache`
- Full specs include local socket/TCP fake-server tests.
- `password_env:` with a blank YAML value means no env password.
- Numeric YAML shortcuts are intentionally loaded as strings.
- Never log plaintext password or generated obs-websocket authentication.

## Latest Pushed Baseline

- Branch: `master`
- Remote: `git@github.com:w0rxbend/obsctl.git`
- Last known pushed commit before autonomous scaffolding: `99cb9c2 Add realtime TUI event handling`

## Next Highest-Value Work

1. Introduce `src/obsctl/ipc/`:
   - socket path resolution
   - newline JSON codec
   - typed request/response/event models
   - Unix client/server primitives
   - specs
2. Introduce `src/obsctl/server/`:
   - state store
   - command executor
   - client registry
   - OBS supervisor skeleton
   - foreground `obsctl server --headless`
3. Convert CLI commands to IPC clients.
4. Convert TUI to IPC subscription client.
5. Add systemd user service support.
