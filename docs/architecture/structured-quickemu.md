# Structured Quickemu contract

How quickgui executes VM commands and what it guarantees.

## Executor

`StructuredQuickemu` (`lib/infrastructure/quickemu/structured_quickemu.dart`)
runs every command as `quickemu <args> --format json` with arguments passed
as a list (no string concatenation), separate stdout/stderr capture and:

- **Timeouts by category** — explicit call timeout → instance default →
  category default (short: status/list/pause/resume/monitor/send-keys;
  medium: doctor/screenshot/delete-plan/snapshots/shutdown; long: clone,
  resize, export/import, backups). Timeout → `BACKEND_TIMEOUT`.
- **Output limit** — stdout/stderr bounded at 4 MB; over the limit the
  process is drained and the command fails with
  `BACKEND_OUTPUT_TOO_LARGE` (never silently truncated).
- **Cancellation** — `cancelSignal` + `onStarted` let callers attach the
  spawned process; cancellation kills gracefully (SIGTERM, escalating to
  SIGKILL after ~3 s) and surfaces `AppFailure(kind: cancelled, code:
  CANCELLED)` — Activity records it as *cancelled*, not failed.

## Envelope validation

The v1 envelope is decoded and checked in `resolve()`:

- `schemaVersion`, `command`, `success`, `data`, `warnings`, `errors`,
  `meta` (`requestId`, `operationId`) are required/typed.
- **Coherence**: `success:true` + non-zero exit code, or
  `success:false` + exit 0 → `INCOHERENT_RESPONSE`.
- `command` mismatch → `COMMAND_MISMATCH`.
- Backend-reported failure → `COMMAND_FAILED` with the envelope's
  error list.
- Missing/malformed envelope → the four envelope-absence codes
  (`EMPTY_RESPONSE`, `MALFORMED_JSON`, `UNEXPECTED_SHAPE`,
  `MISSING_SCHEMA_VERSION`) that `isBackendEnvelopeMissing` recognises.

## Legacy fallback policy

`runVmActionOrLegacy` is the single call-site policy:

- Envelope-absence → `LegacyTelemetry.record(command, code)` + legacy
  `runAction` call.
- **Any other defect propagates as `AppFailure`** — an incoherent or
  broken modern response never degrades silently.
- `LegacyPolicy` (`lib/core/telemetry/legacy_policy.dart`) pins the
  supported window: minimum structured Quickemu version, commands that
  may fall back, and contract-only commands (`capabilities`,
  `list-vms`, `status`) that never do.
- Diagnostics shows fallback count, affected commands and last use;
  `AppLog.event` records `legacy=true` on fallback executions.

## Typed failures → Activity

`AppFailure` carries `kind`, `code`, `message` and `retryable`.
`ActivityController.run` maps it to `OperationState.failed` /
`cancelled` and persists `failureCode`/`retryable` in history, plus a
safe `RetrySpec` (logical command, normalised args, `regeneratesPlan`,
`requiresConfirmation`, `idempotent`). Retry re-dispatches through
`runVmActionOrLegacy` — destructive operations regenerate the delete
plan and re-ask for confirmation.

## IDs and observability

`AppLog.event` writes structured records (`requestId`, `operationId`,
`vm`, `command`, `durationMs`, `exitCode`, `legacy`, `failureCode`)
into `LogStore` — a bounded local ring (200) exported by the
diagnostics report together with `LegacyTelemetry` entries.
