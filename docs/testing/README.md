# Testing strategy

- `test/unit/`: domain + application + infrastructure logic (fake
  backend/process runner — no real quickemu needed).
- `test/widget/`: widget smoke tests with FakeVirtualizationBackend.
- `test/fixtures/backend-responses/`: versioned contract fixtures.
- `integration_test/`: end-to-end (needs a device); covers backend
  absence/incompatibility.
- `dart format --set-exit-if-changed` + `flutter analyze` in CI.
