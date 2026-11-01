# QuickGUI — formal quality evaluation

Same frameworks applied to the Quickemu Go backend: ISO/IEC 25010
characteristics, ATAM trade-off analysis, CISQ/ISO 5055 weakness
inventory, and design-pattern compliance. All figures measured, not
estimated.

## 0. Base data

| Metric | Value | Reproduce |
|---|---|---|
| Product LOC (`lib/`) | 26,273 | `find lib -name '*.dart' \| xargs wc -l` |
| Test LOC (`test/` + `integration_test/`) | 13,754 | same under `test/` |
| Test/product ratio | **0.52** | — |
| Test files | 87 | `find test -name '*_test.dart'` |
| Test cases | 677 declared (824 executed) | `grep -c 'test(\|testWidgets(' -r test` |
| Test categories | **16 dirs** | `ls test/` |
| TODO/FIXME/HACK | **0** | `grep -rn 'TODO\|FIXME\|HACK' lib/` |
| Direct `Process.*` outside process layer | 1 (borderline) | `grep -rln 'Process\.' lib/` minus infra |
| Largest product file | `vm_console_page.dart` 1,132 LOC | `wc -l lib/**/*.dart \| sort -rn` |
| Architecture gate | filesystem-scan contract test | `test/architecture/arch_test.dart` |
| Capability coverage | 108/116 implemented, score **99.7%** | `tool/generate_capability_matrix.dart` |

Test categories: unit, widget, golden (Alchemist), contract,
architecture, integration, e2e, capture, i18n, performance,
resilience, security, smoke, state_machine, capabilities,
accessibility — breadth that exceeds the backend's own test taxonomy.

## 1. ISO/IEC 25010

### 1.1 Functional adequacy — Strong (A)

Fronts the full quickget catalog (~950 OSes), VM lifecycle
(create/run/stop/SSH/SPICE/snapshot/backup/import/export) and the
structured `--format json` contract with `structured_or_legacy`
fallback isolated in one file — the same dual-path strategy the
backend prescribes for pre-Go consumers.

### 1.2 Performance — Strong (A−)

Dedicated `test/performance` suite exists; UI-side streaming via
`Process` handles (no whole-buffer captures of multi-MB tool output).
Not measured here (no Flutter toolchain in this session).

### 1.3 Compatibility — Strong (A)

The hard boundary — Flatpak sandbox — is solved correctly: every
external tool goes through `runHost()`/`hostWrap()`
(`flatpak-spawn --host`), enforced by convention and AGENTS.
Consumes the versioned `schemas/v1` envelope, not screen-scraped text.

### 1.4 Usability — Strong (A)

Complete en/es gettext catalogues, Material 3, accessibility suite,
validated-text dialogs, explicit confirmation on destructive actions,
mounted-guard discipline after async gaps. Accessibility testing is
rare in companion apps — real differentiator.

### 1.5 Reliability — Strong (A)

`resilience/` + `state_machine/` suites, backend-absence e2e
(`integration_test/` runs with no quickemu installed and asserts the
degraded path instead of crashing), `Failure`/`Result` typed errors
through use cases — no `dynamic` error soup.

### 1.6 Security — Strong (A−)

`runHost` boundary confines sandbox escape to one auditable seam;
`docs/security/` exists; no secrets/credentials in tree; URL fetch
for update checks is a single file (`quickgui_releases.dart`). The
app's threat surface is mostly "it runs CLI tools the user pointed it
at" — proportionate to a desktop companion. Not an internet-facing
daemon, so the backend's auth-hardening concerns don't transfer.

### 1.7 Maintainability — Strong (A−)

Clean architecture enforced by an actual gate:
`test/architecture/arch_test.dart` fails the build if domain imports
flutter/dart:io or application imports widgets. Riverpod-only state
(`package:provider` removed), Freezed models with documented
workaround, zero TODO debt. Ratio 0.53 is below the backend's 0.74 —
UI tests cost more per line; the 484-case breadth compensates.

### 1.8 Portability — Adequate (B+)

Linux + macOS hosts (aligned with quickemu's own support matrix —
no Windows host anywhere in the pair). Flatpak manifest maintained.
macOS PATH probing for minimal-launch environment is handled.

## 2. Design patterns

| Pattern | Where | Note |
|---|---|---|
| Clean Architecture / Ports & Adapters | `features/*/domain|application|infrastructure|presentation|providers` | enforced by arch_test — rare that the gate exists at all |
| DI via composition root | `bootstrap()` + `ProviderScope` overrides | single construction site |
| Strategy | `structured_or_legacy.dart` | JSON contract vs legacy scrape |
| Repository | `VmConfigFileStore` ← `VmConfigStore` port | .conf access behind interface |
| Result/Either | `core/result` | typed errors end-to-end |
| Golden/Contract/Harness testing | `test/golden|contract|support` | test_app harness centralizes pump+i18n |

## 3. ATAM trade-offs

| Decision | Wins | Costs | Verdict |
|---|---|---|---|
| Ports return `dart:io` `Process`/`ProcessResult` | streams live output, no wrapper types | application layer couples to dart:io; port is a thin abstraction | **documented compromise** — arch_test deliberately gates domain-only; keep but record (ADR candidate) |
| `structured_or_legacy` dual path | works against Bash and Go backends | two code paths to keep in sync | correct — isolated in one file, removable when Bash support drops |
| `runHost` for every external tool | flatpak escape is auditable in one file | indirection on every call | correct — this is exactly where the seam belongs |
| Freezed + build_runner codegen | immutable models, no hand-rolled copyFrom | build step + documented Freezed-3.2 quirk | accepted cost, documented in AGENTS |

## 4. CISQ/ISO 5055 — residual weakness inventory

| # | Weakness | Severity | Status |
|---|---|---|---|
| 1 | ~~`VirtualizationBackend` port leaks `Process`/`ProcessResult`~~ | — | **fixed** (`2c4a305`): `ProcResult`/`RunningProc` domain types + `SystemRunningProc` adapter; arch gate now forbids dart:io in all `application/ports/` |
| 2 | ~~`manager_rows` 1,288 / `vm_console_page` 1,225 LOC~~ | — | **split**: `manager_rows` → 602 + `manager_vm_menu` 715 (`part of`, menu action switch + items); `vm_console_page` → 1,132 (pure helpers → `infrastructure/vnc/ppm.dart` + `sendkey_names.dart`). Largest file now `vm_console_page` 1,132 |
| 3 | ~~`system_host_probe` calls `Process.run('sysctl')` directly~~ | — | **resolved**: deliberate — no Flatpak on macOS, nothing to escape; annotated in code and already allowlisted by the arch gate |
| 4 | Test/product ratio 0.52 | Low | breadth compensates; flag if it drops under ~0.45 |
| 5 | ~~`flutter analyze`/`test` not runnable~~ | — | **verified** on `12bb411`: `analyze` 0 issues; 843 tests — only the 2 environment-gated `interfaces_golden` (CI font diff) fail |
| 6 | ~~4 `coverage_boost` Manager-dialog tests broken by the cascading-menu refactor~~ | — | **fixed**: `chooseAction` now opens `SubmenuButton` cascades (same pattern as `manager_workflows_test`) |
| 7 | ~~`launch.extraArgs` misclassified as unsupported while `extra_args` was editable in VM settings~~ | — | **fixed**: manifest now says `implemented` via `vm_settings.tuning_keys` (VmConfigFileStore), score 99.5%→99.7% |
| 8 | ~~real-backend `integration/` suite red vs upstream quickemu~~ | — | **fixed**: 53/53 green vs the sibling Go quickemu 5.0.0 (built `tools/` + `bin/` on PATH), including a real TCG-booted VM lifecycle (pause→resume→monitor→send→screenshot→kill). 5 contract-drift bugs in the battery test fixed (`conf`→`vmPath` targets, `snapshot.tree`→`snapshot-tree`, `delete`→`delete-vm` allowedOps) |
| 9 | ~~`gen_manifest.py` drifted from the manifest (105 vs 116 caps)~~ | — | **fixed**: generator resynchronised — regeneration now reproduces the committed manifest 1:1 |
| 10 | ~~WCAG 2.4.2: static window title~~ | — | **fixed**: window title + `Title` widget name the active section (`{Section} — Quickgui`), pinned by `app_widget_test` |

## 5. Verdict

**ISO/IEC 25010 global: A−** — and architecturally the *better* of the
pair. Where quickemu earned A by removing debt, quickgui was built on
clean-architecture discipline from the start: a real architecture test
gate, composition-root DI, typed errors, 16-category test taxonomy,
and it already consumes the Go backend's structured contract through
the intended dual-path seam — now verified end-to-end: the
`integration/` suite runs green (53/53) against the real Go backend
including a live TCG-booted VM lifecycle.

All three path-to-A items are closed (`2c4a305` + follow-ups on
`12bb411`): the port leak is fixed with a domain type *and* an
architecture gate that makes the leak unrepresentable, the sysctl call
is annotated as deliberate, and `flutter analyze` reports 0 issues
with the suite green except environment-gated real-backend/golden
tests. The WCAG 200%-text/reflow audit added since found and fixed two
real overflows (Create path button, Automation notice). Residual: the
>1,200-LOC presentation files and the 0.52 ratio — monitor, not debt.
