# Architecture

RunBar is a SwiftPM macOS 14+ app with two targets:

```
RunBarApp (SwiftUI)
  MenuBarExtra → MenuBarPanel + StatusBarLabel
  Window → SettingsView
  Window → WorkflowDispatchView
  AppStore (@Observable)
    SettingsStore (UserDefaults + ~/.config/runbar/config.json)
    GhClient → GhProcess (subprocess `gh`)
    PollingPolicy (15s active / 45s idle / pause on sleep)
    UpdateCheckPolicy (24h `gh release view` of this repo)

RunBarCore
  GitHub: GhClient, GhProcess, GhError, JSON DTOs
  Domain: WorkflowRun, Repository, WatchRule, pins, grouping, AppVersion, TypicalDuration
  ActivitySummary: menu bar icon, counts, failure tint
  InstallOrigin: Homebrew Cellar vs other
```

All GitHub access goes through `gh`. The GUI app looks for `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, and `PATH` so a menu bar process that does not inherit your shell still finds Homebrew `gh`. `GhProcess` runs `gh` with argv (not a shell), drains stdout/stderr together, caps output at 1 MiB, and kills the process after 30 seconds or if the refresh is cancelled.

Repository owner/name values are limited to GitHub’s identifier charset so they cannot be parsed as extra CLI flags. Run URLs from `gh` must be `https` on `github.com` before the panel will open them.

Update checks use `gh release view --repo bryaneaton13/gh-actions-runbar --json tagName,url`. Homebrew formula installs (`/Cellar/runbar/` or `/opt/runbar/`) copy `brew upgrade bryaneaton13/tap/runbar` instead of replacing the app. Last check time is `UserDefaults` (`runbar.update`), not `config.json`. Failures stay in Settings; they do not become panel errors. There is no Sparkle updater.

Pins are fetched separately (`gh run list -w`) and ignore event filters. Each pin shows its latest run. **Show everyone's runs** (default on) skips `-u` so that run can belong to someone else. `gh run list` has no actor field, so pin rows read `actor.login` from `gh api repos/<owner>/<name>/actions/runs`. The menu bar tints on recent failures **and** on a pinned workflow whose latest run failed, even if that run is older than the 30-minute recent window.

Typical duration is text only. For each in-progress workflow, RunBar runs `gh run list -w --status completed --limit 10` (no `-u`) and takes the median of success, failure, and timed-out durations. Running rows render `3m · typically 4m`. No usable history means elapsed time only. Cancelled and skipped runs do not count. There is no progress bar.

Row actions stay in the context menu. `gh run rerun` / `gh run rerun --failed` / `gh run cancel` take a numeric run id and `-R owner/name`. Cancel confirms with `NSAlert` first. **Run workflow** opens a small window, reads `gh workflow view --yaml --ref`, parses `on.workflow_dispatch.inputs`, and starts the job with `gh workflow run --ref` plus `-f key=value` for each input. Git refs, workflow names, input keys, and run ids are validated before they reach `gh`. Missing `workflow` scope is a copyable `gh auth refresh -s workflow` hint.
