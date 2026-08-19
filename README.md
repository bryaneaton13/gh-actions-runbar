# RunBar

A native macOS menu bar app for GitHub Actions. Watch the repos you care about, filter to your commits / PRs / manual runs, and pin workflows like Deploy to prod so they always sit at the top of the panel.

Requires macOS 14+ and a signed-in [GitHub CLI](https://cli.github.com/) (`gh`).

## Features

- Menu bar icon with a live running count, and a failure accent after a recent watched failure
- Pinned workflows that ignore actor/event filters
- Filters: only my runs, plus `push`, `pull_request`, `workflow_dispatch`, and `merge_group`
- Click a run to open it on GitHub
- Adaptive polling: 15s while the panel is open or a run is active, 45s when idle
- Settings for repositories (including org/collaborator repos), filters, pins, and launch at login

## Prerequisites

```bash
brew install gh
gh auth login
```

## Build and run

```bash
swift build
swift run RunBar
swift run RunBarCoreChecks
```

Install a local app bundle:

```bash
make app
make install
open ~/Applications/RunBar.app
```

Config is stored in `UserDefaults` and also written to `~/.config/runbar/config.json`.
