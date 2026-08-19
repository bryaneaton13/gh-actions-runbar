# Architecture

RunBar is a SwiftPM macOS 14+ app with two targets:

```
RunBarApp (SwiftUI)
  MenuBarExtra → MenuBarPanel + StatusBarLabel
  Window → SettingsView
  AppStore (@Observable)
    SettingsStore (UserDefaults + ~/.config/runbar/config.json)
    GhClient → GhProcess (subprocess `gh`)
    PollingPolicy (15s active / 45s idle / pause on sleep)

RunBarCore
  GitHub: GhClient, GhProcess, GhError, JSON DTOs
  Domain: WorkflowRun, Repository, WatchRule, pins, grouping
  ActivitySummary: menu bar icon, counts, failure tint
```

All GitHub access goes through `gh`. The GUI app looks for `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, and `PATH` so a menu bar process that does not inherit your shell still finds Homebrew `gh`.

Pins are fetched separately (`gh run list -w`) and ignore actor/event filters. The menu bar tints on recent failures **and** on a pinned workflow whose latest run failed, even if that run is older than the 30-minute recent window.
