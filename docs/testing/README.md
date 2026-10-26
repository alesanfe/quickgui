# Testing strategy

- `test/unit/`: domain + application + infrastructure logic (fake
  backend/process runner — no real quickemu needed).
- `test/widget/`: widget smoke tests with FakeVirtualizationBackend.
- `test/fixtures/backend-responses/`: versioned contract fixtures.
- `integration_test/`: end-to-end (needs a device); covers backend
  absence/incompatibility.
- `dart format --set-exit-if-changed` + `flutter analyze` in CI.

## Contract parity against a real quickemu

`test/contract/structured_quickemu_test.dart` asserts QuickGUI's parser
against the sibling quickemu repo's `schemas/v1/` documents (envelope +
per-command `data` payloads for `vm.delete-plan`, `vm.snapshot.list`,
`vm.status`, `vm.plan`).

To verify an installed quickemu by hand:

```sh
quickemu --capabilities --format json    # envelope + capability flags
quickemu --vm x.conf --op-list           # async-operation registry
quickemu --vm x.conf --delete-plan       # prints planId for --delete-vm
quickemu --host-info                     # host inventory envelope
```

The app normalizes namespaced command names (`vm.status` ≡ `status`)
and past-tense lifecycle names (`vm.started`, `vm.trashed`) via
`StructuredQuickemu._commandMatches`.
