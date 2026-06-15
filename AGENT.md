# Autonomous Agent Rules

You are an autonomous implementation agent working on `obsctl-cr`, a Crystal CLI/TUI and local daemon for controlling OBS Studio through obs-websocket 5.x.

## Goal

Implement the project described by `seed_plan.md`, `TODO.md`, `MEMORY.md`, and `IMPLEMENTATION_CHECK_PLAN.md`.

## Operating Loop

Each iteration must:

1. Inspect the repository state.
2. Read `TODO.md`, `IMPLEMENTATION_CHECK_PLAN.md`, `MEMORY.md`, and the latest `AGENT_LOG.md` entries.
3. Treat `TODO.md` as the canonical project progress tracker.
4. Derive the next task from the current `TODO.md` status, especially `Major Architecture Update`, `Milestone Tracking`, and `Planned Next`.
5. Cross-check the task against `IMPLEMENTATION_CHECK_PLAN.md` before coding.
6. Update `TODO.md` after implementation so completed work, remaining gaps, and planned next steps stay accurate.
7. Choose the next highest-value task that can be completed as a small vertical slice.
8. Implement the task.
9. Run validation:
   - `make format`
   - `make test`
   - `make build`
   - `make lint` when dependencies are available
10. Fix regressions.
11. Update docs when user-visible behavior changes.
12. Append a concise entry to `AGENT_LOG.md`.
13. Commit a logically separated checkpoint if validation passes.

## Priorities

Current architecture priority:

1. Convert the app into a local client/server architecture.
2. Add `ipc/` protocol, codec, Unix socket path resolution, Unix server, and Unix client.
3. Add `server/` foreground/headless runtime with authoritative state store, command executor, OBS supervisor, and client registry.
4. Convert normal CLI commands to local IPC clients.
5. Convert TUI to subscribe to server state/events over IPC.
6. Add `systemd --user` service install/control commands.

## Rules

- Never ask for clarification unless blocked by missing credentials, unavailable tools, or a safety issue.
- Prefer small vertical slices over broad rewrites.
- Keep code production-grade and idiomatic Crystal.
- Preserve user work. Do not revert unrelated changes.
- Do not fake passing tests.
- Do not commit failing validation unless the commit is explicitly a diagnostic checkpoint and the failure is documented.
- Do not print or log OBS passwords or generated authentication strings.
- Do not introduce network-facing control APIs for local IPC; use Unix domain sockets by default.
- Do not let CLI/TUI clients create OBS WebSocket connections in normal mode after server IPC exists.
- Treat IPC requests as external input and validate them.
- Keep `TODO.md` current every iteration. Move completed items out of “Remaining” and adjust “Planned Next”.
- Keep implementation aligned with `IMPLEMENTATION_CHECK_PLAN.md`; if code diverges, update the plan only when the architecture decision changes intentionally.
- Stop if secrets, destructive operations, or paid external actions are required.

## Definition Of Done

- App builds.
- Critical path has tests.
- `TODO.md` accurately reflects what changed.
- README/docs explain new user-visible behavior.
- `AGENT_LOG.md` records the iteration.
- A checkpoint commit exists for successful work.

## Commit Style

- Commit message format: short imperative summary, for example `Add IPC request codec`.
- One logical change per commit.
- Do not include generated compiler caches or local binaries unless explicitly required.
