# RunBar

macOS 14+ menu bar accessory for GitHub Actions you already watch. Local SwiftPM app. All GitHub access is a `gh` subprocess — RunBar never stores a token.

Human docs: [README.md](README.md), [architecture](docs/architecture.md), [development](docs/development.md), [privacy](docs/privacy.md), [releasing](docs/releasing.md). Do not copy those pages into this file.

## Commands

```bash
make build     # swift build
make test      # swift run RunBarCoreChecks  (this is CI)
make run       # swift run RunBar
make app       # dist/RunBar.app
make install   # ~/Applications/RunBar.app
```

No XCTest / Swift Testing target. Add checks to `Sources/RunBarCoreChecks/main.swift`. Stub `gh` with `FakeGhProcess` in that file.

## Layout

| Path | Owns |
| --- | --- |
| `Sources/RunBarCore` | Models, filters, pins, `GhClient` / `GhProcess`, polling, settings |
| `Sources/RunBar` | SwiftUI: `MenuBarExtra`, Settings, `AppStore` |
| `Sources/RunBarCoreChecks` | Domain + client harness |
| `scripts/` | Bundle, icon, local install |
| `docs/` | GitHub Pages + human docs |
| `design.md` | Marketing site visual rules only |
| `docs/ui.md` | Menu bar panel + Settings visual rules |

Keep GitHub JSON, filtering, grouping, and `ActivitySummary` in RunBarCore. Views stay in RunBar. No new SPM dependencies unless the task needs them.

`GhProcess` must keep looking for Homebrew `gh` at `/opt/homebrew/bin/gh` and `/usr/local/bin/gh` — menu bar apps often have a thin `PATH`. Spawn with argv, not a shell. Bound the wait (30s), drain stdout/stderr concurrently, cap output at 1 MiB, and kill on timeout or cancel.

## Product rules

- Auth stays in `gh`. Never add OAuth, a PAT field, or a token file. Settings are `UserDefaults` (`runbar.settings`) plus `~/.config/runbar/config.json` (not credentials). Write that directory `0700` and the file `0600`.
- Only open run URLs that are `https` on `github.com` / `*.github.com`. Validate `owner/name` against GitHub’s identifier charset before passing them to `gh`.
- Pins use `gh run list -w`, ignore actor/event filters, and sit at the top. `RunFilter.merge` must drop pin IDs from the filtered list.
- Failure tint: a failed run in the last 30 minutes **or** a pin whose latest run failed, even if that run is hours old (`ActivitySummary`).
- Polling: 15s when the panel is open or a run is active, 45s idle, skip while asleep (`PollingPolicy`).
- Accessory app: no Dock icon (`NSApp.setActivationPolicy(.accessory)`).
- No telemetry, analytics, or extra TCC prompts (Screen Recording, Accessibility, Full Disk Access).

## UI and copy

- Panel layout: [`docs/ui.md`](docs/ui.md) (CodexBar grammar: identity / scan / commands). Site: [`design.md`](design.md).
- Run colors live in `RunBarTheme` (success / failure / in-progress). Do not add a brand yellow to chrome.
- Copy is short, specific, present tense. Name the thing (`gh`, Deploy to prod, `make install`). Skip “tiny / delightful / powerful”.
- After panel UI changes, update `docs/assets/screenshot.png` and `docs/assets/screenshot-failure.png`.

## Site

Pages are `docs/index.html` + `docs/site.css`. Follow `design.md`: ink / canvas / studio gray, pills, no gradients, cards, shadows, or a GitHub-dashboard restyle. Markdown docs stay plain.

## Release

Bump `version.env`, add user-facing bullets to `CHANGELOG.md`, keep `AppInfo.fallbackVersion` in sync. After tagging, update `url` / `sha256` in [bryaneaton13/homebrew-tap](https://github.com/bryaneaton13/homebrew-tap) `Formula/runbar.rb` (`./scripts/homebrew-sha.sh`). Do not bottle unsigned builds. Do not attach an unsigned `.app` zip to GitHub Releases — Gatekeeper will block it. Install is `brew install bryaneaton13/tap/runbar` or `make install` until there is Developer ID notarization.

## Do not

- Call `api.github.com` except through `gh`.
- Introduce an Xcode project as the source of truth (SwiftPM + Makefile).
- Commit `.build/`, `dist/`, `.cursor/`, or `tmp/`.
