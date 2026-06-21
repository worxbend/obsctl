# Contract Fixture Ownership

This Crystal repository is the current authority for public `obsctl` contract
fixtures. The canonical Crystal fixture root is:

```text
spec/fixtures/contracts/
```

Portable contract fixtures live under these required subdirectories:

```text
spec/fixtures/contracts/
  cli/
    human/
    json/
  ipc/
```

`cli/human/` stores frozen human CLI output, `cli/json/` stores frozen CLI JSON
envelopes, and `ipc/` stores frozen newline-delimited JSON request payloads for
typed IPC commands.

Rust compatibility may use any one of these recognized `obsctl-rs` roots:

```text
spec/fixtures/contracts/
tests/fixtures/contracts/
fixtures/contracts/
```

The selected Rust root must contain matching `cli/human/`, `cli/json/`, and
`ipc/` subdirectories before strict cross-repository comparison is meaningful.
Default single-repository Crystal tests continue to skip Rust compatibility
when the sibling repository or a recognized fixture root is absent. Strict
compatibility remains opt-in until `obsctl-rs` owns a matching fixture root.

## Status Telemetry

The finalized `dropped_reconnect_diagnostic_logs` contract is:

- Current-daemon daemon status fixtures and combined status fixtures include
  `dropped_reconnect_diagnostic_logs` wherever daemon status appears.
- Older-daemon JSON payloads that omit the field are preserved as received;
  Crystal CLI JSON output does not synthesize the missing field.
- Human status output renders missing older-daemon values as unknown (`-`).
- Values are process-local runtime telemetry and reset when the daemon process
  restarts.
- The counter only describes dropped secondary reconnect diagnostic `logs`
  topic fanout from the bounded best-effort path.
- Public JSON values are non-negative signed integers. Internal values above
  `Int64::MAX` are saturated to `Int64::MAX`.
