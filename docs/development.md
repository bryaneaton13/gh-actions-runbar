# Development

Requires macOS 14+ and Swift 6 (Xcode or Command Line Tools).

```bash
make build
make run
make test
make app       # dist/RunBar.app
make install   # ~/Applications/RunBar.app
make icon      # regenerate Resources/AppIcon.icns
```

`make test` runs `RunBarCoreChecks`, an executable harness in `Sources/RunBarCoreChecks`. There is no XCTest target.

## Layout

- `Sources/RunBar` — SwiftUI menu bar + settings
- `Sources/RunBarCore` — models, `gh` client, polling policy, settings store
- `scripts/build-app.sh` — release binary, Info.plist, ad-hoc sign
- `version.env` — `MARKETING_VERSION` and `BUILD_NUMBER` used by the bundle

Config while developing: `UserDefaults` key `runbar.settings` and `~/.config/runbar/config.json` (directory `0700`, file `0600`).

GitHub Pages lives in `docs/` (`index.html`, `site.css`). Visual rules for that page are in [`design.md`](../design.md). The menu bar panel is [`ui.md`](ui.md). The panel screenshot is `docs/assets/screenshot.png`.
