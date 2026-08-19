# Releasing

No notarized zip and no Homebrew cask. A release is a git tag, a changelog entry, and a bump of the formula in [bryaneaton13/homebrew-tap](https://github.com/bryaneaton13/homebrew-tap).

## Checklist

1. Bump `MARKETING_VERSION` and `BUILD_NUMBER` in `version.env`.
2. Add a `## {version} — {date}` section to `CHANGELOG.md` (user-facing bullets only).
3. Confirm `AppInfo.fallbackVersion` matches `MARKETING_VERSION` if you still use the `swift run` fallback.
4. `make test`
5. `make app` and smoke-open `dist/RunBar.app`
6. Commit, push `main`, tag `v{version}`:

```bash
git tag v0.1.0
git push origin main --tags
```

7. Update `Formula/runbar.rb` in the tap: set `url` to the new tag tarball and `sha256` from `./scripts/homebrew-sha.sh`. Do not add a `bottle` block. Commit and push the tap.

Do not attach an unsigned `.app` zip to GitHub Releases as a download. Gatekeeper will block it. Install is `brew install bryaneaton13/tap/runbar` or `make install` until there is a Developer ID for notarization. `scripts/build-app.sh` ad-hoc signs the local app; do not swallow codesign failures.
