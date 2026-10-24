# Architecture overview

```
lib/
  main.dart                     bootstrap + OS catalogue loading
  src/
    app.dart                    MaterialApp, theme, locale
    globals.dart                shared helpers + `backend` singleton
    infrastructure/
      process/                  ProcessRunner abstraction
      virtualization/           VirtualizationBackend + QuickemuBackend
    mixins/                     app_version, preferences_mixin
    model/                      presentation models (OperatingSystem, Version, Option, VmInfo)
    pages/                      manager, downloader, *_selection
    widgets/                    home_page/, left_menu, etc.
test/
  fakes/                        FakeVirtualizationBackend
  *_test.dart                   unit/widget tests
```

Layering rule: presentation widgets → `backend` (interface) →
infrastructure → external processes. Presentation code must not spawn
quickemu/quickget directly (except during the ongoing migration —
grep for `runHost\('quick` to find remaining call sites).
