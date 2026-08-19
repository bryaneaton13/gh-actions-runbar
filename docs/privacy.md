# Privacy

RunBar is a local menu bar app. It does not have its own GitHub account, OAuth app, or telemetry.

## What RunBar uses

- The **GitHub CLI** (`gh`) already installed and signed in on your Mac.
- `gh` subprocesses such as `gh auth status`, `gh api user`, `gh run list`, `gh workflow list`, and repo search. Each call has a 30-second timeout, a 1 MiB output cap, and is killed if it hangs.
- Settings in `UserDefaults` and a mirror file at `~/.config/runbar/config.json` (repository list, filters, pins, launch-at-login). That file is not a credential store. RunBar writes the directory as `0700` and the file as `0600`.

## What RunBar does not do

- It does **not** store a GitHub token, password, or PAT. Auth stays in `gh`.
- It does **not** crawl your disk. It only reads its own config file and talks to `gh`.
- It does **not** send usage analytics.
- It does **not** request Screen Recording, Accessibility, Full Disk Access, or Keychain items of its own.
- It does **not** open run links unless they are `https` URLs on `github.com` (or a `*.github.com` host).

`gh` itself may use the Keychain for its tokens. That is GitHub CLI behavior, not RunBar.

## Permissions

RunBar is a menu bar accessory (`LSUIElement`). Launch at login uses `SMAppService` and only applies when the app lives under Applications. `make install` copies the bundle to `~/Applications`. The Homebrew formula installs into the Cellar; `runbar` (and the app, once launched from that keg) links `~/Applications/RunBar.app`.
