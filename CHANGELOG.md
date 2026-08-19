# Changelog

All notable changes to RunBar are documented here.

## 0.1.0 — 2026-08-19

### Highlights

- First public release of the macOS menu bar app for GitHub Actions.
- Watch selected repositories, filter to your runs, and pin workflows such as Deploy to prod.
- Uses your existing GitHub CLI session. RunBar does not store a GitHub token.

### Features

- Menu bar icon with a live running count and a failure accent, including pinned workflow failures that would otherwise age out of the recent window.
- Adaptive polling: 15s while the panel is open or a run is active, 45s when idle, paused while the Mac is asleep.
- Settings for repositories (personal, org, and collaborator), event filters, pins, and launch at login.
- Config mirrored to `~/.config/runbar/config.json`.
