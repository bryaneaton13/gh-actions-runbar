# Changelog

All notable changes to RunBar are documented here.

## 0.4.0 — 2026-08-20

### Fixes

- Pinned workflows show one latest run each. **Show everyone's runs** still skips `-u` so a teammate's Deploy to prod stays on that row.

## 0.3.0 — 2026-08-19

### Features

- Settings → About checks GitHub Releases through `gh` and says when a newer version is out.
- Homebrew installs copy `brew upgrade bryaneaton13/tap/runbar`. Other installs open GitHub Releases. The panel shows **Update available** only when a newer tag is known.

## 0.2.0 — 2026-08-19

### Features

- Settings toggle **Show everyone's runs** on pinned workflows (on by default). Pins still ignore event filters; when this is on, `gh run list -w` skips `-u` so you see Deploy to prod (and other pins) when someone else triggers them.
- Pinned workflows can show several recent runs, not only the latest, and the row names the GitHub user who triggered each run.

## 0.1.0 — 2026-08-19

### Highlights

- First public release of the macOS menu bar app for GitHub Actions.
- Watch selected repositories, filter to your runs, and pin workflows such as Deploy to prod.
- Uses your existing GitHub CLI session. RunBar does not store a GitHub token.
- `gh` calls time out after 30 seconds. Config is written owner-only (`0600`). Run links must be GitHub `https` URLs.

### Features

- Menu bar icon with a live running count and a failure accent, including pinned workflow failures that would otherwise age out of the recent window.
- Adaptive polling: 15s while the panel is open or a run is active, 45s when idle, paused while the Mac is asleep.
- Settings for repositories (personal, org, and collaborator), event filters, pins, and launch at login.
- Config mirrored to `~/.config/runbar/config.json`.
- Homebrew formula: `brew install bryaneaton13/tap/runbar` compiles on your Mac.
