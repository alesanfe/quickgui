# State management

quickgui uses `setState` + `ChangeNotifier` (AppSettings) — no external
state package. Long-running operations (downloads) stream via
`VirtualizationBackend.downloadImage` and update local widget state;
VM state refreshes on a 5s timer in the Manager.
