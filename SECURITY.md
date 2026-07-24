# Security Policy

## Supported versions

Only the latest released version receives security fixes. Please upgrade before
reporting an issue against an older tag.

## Reporting a vulnerability

**Do not open a public issue.** Use GitHub's private vulnerability reporting:

1. Go to the [Security tab](https://github.com/worxbend/obsctl/security/advisories)
2. Choose **Report a vulnerability**

Please include the obsctl version (`obsctl --version`), your OS, the OBS Studio
and obs-websocket versions, and the steps to reproduce. If you have a patch,
attach it to the advisory rather than opening a pull request, so the fix and the
disclosure land together.

Expect an initial response within seven days.

## Security model

obsctl brokers credentials for the obs-websocket control plane. Understanding
what it does and does not protect helps when judging whether a finding is a
vulnerability.

### Credentials

- The obs-websocket password is read from the environment variable named by
  `connection.password_env` (default `OBS_WEBSOCKET_PASSWORD`), or from
  `connection.password` in the config file.
- Storing the password in plaintext under `connection.password` is supported but
  discouraged; `obsctl validate-config` emits a warning when it is set. Prefer
  `connection.password_env`.
- The password is never sent to OBS directly. It is combined with the
  server-supplied salt and challenge into a SHA-256 authentication string, as
  the obs-websocket 5.x protocol specifies.
- Log output and IPC error payloads are scrubbed for values keyed by
  `password`, `authentication`/`auth string`, `token`, and `secret`.

### The local daemon

- The daemon listens on a Unix domain socket, by default at
  `$XDG_RUNTIME_DIR/obsctl/obsctl.sock`, falling back to
  `/tmp/obsctl-<uid>/obsctl.sock`.
- The socket is created with mode `0600`, so only the user running the daemon
  can connect.
- The IPC protocol has **no authentication of its own** — socket permissions are
  the entire access control boundary. Anything that can open the socket can
  drive OBS: switch scenes, toggle audio, and start or stop streaming and
  recording. Do not relax the socket permissions or expose the socket path to
  other users.
- The daemon does not listen on any TCP port. It only makes an outbound
  connection to the obs-websocket endpoint in your config.

### Out of scope

- Anything requiring an attacker who already has local access as the user
  running obsctl. That user can read the config and drive OBS directly.
- Vulnerabilities in OBS Studio or obs-websocket. Report those to their
  respective projects.
- Configurations that deliberately weaken the defaults, such as setting
  `connection.password` in a world-readable config file.
