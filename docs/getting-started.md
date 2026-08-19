# Getting started

RunBar is a macOS 14+ menu bar app. It talks to GitHub through the [GitHub CLI](https://cli.github.com/) (`gh`) you already have signed in.

![RunBar panel with a pinned deploy, two running jobs, and recent Actions](assets/screenshot.png)

## 1. Install `gh` and sign in

```bash
brew install gh
gh auth login
```

The default `gh` scopes are enough to list repositories and workflow runs you can already see on GitHub.

## 2. Install RunBar

Homebrew compiles RunBar on your Mac (no notarized download):

```bash
brew install bryaneaton13/tap/runbar
runbar
```

Run `runbar` once. That opens the app and links `~/Applications/RunBar.app` so Spotlight, Raycast, and launch at login (`SMAppService`) see it.

From a clone, `make install` copies `RunBar.app` into `~/Applications` directly.

## 3. Add repositories

Open the menu bar panel → **Settings** (or the gear). Then:

- Type `owner/name` and click **Add**, or
- **Browse GitHub repos** to pick personal, organization, and collaborator repos.

Until at least one repository or pin is added, the panel shows an empty state with a button into Settings.

## 4. Optional: filters and pins

- **Only my runs** uses `gh run list -u` so you see commits, PRs, and dispatches you triggered.
- Event toggles cover `push`, `pull_request`, `workflow_dispatch`, and `merge_group`.
- **Pin a workflow** (for example Deploy to prod) to keep it at the top. Pins ignore event filters.
- **Show everyone's runs** (under Pinned workflows, on by default) skips `-u` on those pins so you still see the job when someone else triggers it. Turn it off if you only want your own pin runs.

Click a run to open it on GitHub. RunBar only follows `https` links on `github.com`.
