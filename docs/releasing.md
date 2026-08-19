# Releasing

No notarized zip, no Sparkle, and no Homebrew cask. A release is a version bump, a changelog entry, a git tag, and a bump of the formula in [bryaneaton13/homebrew-tap](https://github.com/bryaneaton13/homebrew-tap).

CI creates the tag. You still choose the version. Do not attach an unsigned `.app` zip; Gatekeeper will block it. The in-app notice follows the GitHub tag; Homebrew users still need the tap `url` / `sha256` bump before `brew upgrade` installs that tag.

## Versioning

`MARKETING_VERSION` in `version.env` is `MAJOR.MINOR.PATCH`. RunBar is still `0.x`.

| Bump | When |
| --- | --- |
| **Patch** (`0.1.0` → `0.1.1`) | Fixes, copy, docs that do not change Settings or panel behavior |
| **Minor** (`0.1.0` → `0.2.0`) | User-facing features, new settings, pin/filter behavior |
| **Major** | Breaking install or data changes. Do not jump to `1.0.0` just to ship a feature |

Always increment `BUILD_NUMBER` when `MARKETING_VERSION` changes. Keep `AppInfo.fallbackVersion` in sync.

Do not use semantic-release or conventional-commit auto-bumps. This repo does not follow conventional commits, and a docs-only merge should not mint a Homebrew tag.

## Checklist

1. Bump `MARKETING_VERSION` and `BUILD_NUMBER` in `version.env`.
2. Add a `## {version} — {date}` section to `CHANGELOG.md` (user-facing bullets only).
3. Confirm `AppInfo.fallbackVersion` matches `MARKETING_VERSION` if you still use the `swift run` fallback.
4. `make test`
5. `make app` and smoke-open `dist/RunBar.app`
6. Commit and push `main`. After `RunBarCoreChecks` is green, the `Tag release` job in `.github/workflows/ci.yml` creates `v{version}` and a notes-only GitHub Release (changelog section, no assets). The job no-ops if that tag already exists. It does **not** bump `version.env` for you.

   To tag locally instead (or to retry if CI already passed):

   ```bash
   ./scripts/release-notes.sh > /tmp/runbar-notes.md
   gh release create "v$(grep MARKETING_VERSION version.env | cut -d= -f2)" \
     --title "RunBar $(grep MARKETING_VERSION version.env | cut -d= -f2)" \
     --notes-file /tmp/runbar-notes.md
   ```

7. After the tag exists on GitHub, update `Formula/runbar.rb` in the tap: set `url` to the new tag tarball and `sha256` from `./scripts/homebrew-sha.sh`. Do not add a `bottle` block. Commit and push the tap. Tagging does not update the tap — that is a separate repo, and the tarball hash only exists after the tag is pushed.

Install is `brew install bryaneaton13/tap/runbar` or `make install` until there is a Developer ID for notarization. `scripts/build-app.sh` ad-hoc signs the local app; do not swallow codesign failures.
