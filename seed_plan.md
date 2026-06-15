# seed_plan.md

Build `obsctl-cr` into a production-quality local OBS control daemon with thin CLI and TUI clients.

## Objective

Implement the architecture tracked in `TODO.md` and checked by `IMPLEMENTATION_CHECK_PLAN.md`:

```text
OBS Studio <----obs-websocket----> obsctl server <----local IPC----> obsctl TUI
                                                    <----local IPC----> obsctl CLI
```

`TODO.md` is the canonical progress tracker. Autonomous runs must use it to choose the next task and must update it after each successful implementation slice.

`IMPLEMENTATION_CHECK_PLAN.md` is the correctness and final-review contract. Autonomous runs must use it to prevent architectural drift.

## MVP Target

The shippable MVP should support:

- `obsctl server --headless`
- Unix socket IPC at `$XDG_RUNTIME_DIR/obsctl/obsctl.sock` or `/tmp/obsctl-$UID/obsctl.sock`
- CLI commands sent through the server:
  - `obsctl status`
  - `obsctl scene <target>`
  - `obsctl mute <target>`
  - `obsctl unmute <target>`
  - `obsctl toggle-mute <target>`
  - `obsctl vol <target> <0-100>`
  - `obsctl dump-config`
  - `obsctl reload-config`
- TUI client subscribing to server state instead of connecting directly to OBS.
- OBS supervisor that keeps server alive while OBS is unavailable and reconnects forever.
- Systemd user service installation commands.

## Constraints

- Crystal 1.20.2.
- Unix domain sockets for local IPC, not TCP.
- Newline-delimited JSON IPC.
- No password/auth leakage.
- Tests for protocol codecs, command execution, server lifecycle, and CLI client behavior.
- Keep repo buildable after each iteration.

## Validation Contract

Run:

```sh
make format
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make test
CRYSTAL_CACHE_DIR=/tmp/obsctl-crystal-cache make build
make lint
```

`make lint` currently prints a skip message unless Ameba is installed.
