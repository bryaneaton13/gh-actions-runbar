# RunBar panel

The menu is a scan surface, not a mini app.

Layout language comes from [CodexBar](https://github.com/steipete/CodexBar): a native macOS menu in three bands — identity, scan, commands — separated by hairlines. Do not copy CodexBar’s product (provider tabs, usage meters, cost). GitHub Actions has no reliable percent-complete, so RunBar never draws a fake progress bar.

Marketing site rules stay in [`design.md`](../design.md). This file is the bar and Settings.

## Thesis

Click the status item. See what is pinned and what is running. Click a row to open that run on GitHub. Everything else is a menu command.

```
┌──────────────────────────────────┐
│  2 running            1 watched  │  identity
│  Updated 8s ago · gh ok          │
├──────────────────────────────────┤
│  Pinned                          │  scan
│  ●  Deploy to prod          1h   │
│     owner/repo · workflow_dispatch│
│                                  │
│  Active                          │
│  ◐  Dev Deploy              3m   │
│  ◐  CodeQL                 12s   │
│                                  │
│  owner/repo                      │
│  ✓  Playwright E2E          2h   │
│  ✓  API Tests               3h   │
├──────────────────────────────────┤
│  Refresh                    ⌘R   │  commands
│  Settings…                  ⌘,   │
│  Quit                       ⌘Q   │
└──────────────────────────────────┘
```

## Borrow / skip (CodexBar)

| CodexBar | RunBar |
| --- | --- |
| Three bands, hairlines, system material | Same |
| Header = name + freshness + trailing plan | Header = running headline + freshness + trailing watch meta |
| Metric blocks with a thin usage bar | Run rows. Status glyph + name + trailing time. No bar |
| Provider switcher tabs | Skip. One list. Repos are section headers, not tabs |
| Footer is real menu items with shortcuts | Same. Refresh, Settings…, Quit |
| 18×18 usage-meter icon | Running count (and failure tint). Not a meter fill |
| Hosted SwiftUI inside `NSMenu` | Keep `MenuBarExtra`. Match the look, not the AppKit menu stack |

## Palette

Chrome is system. Color is only run state.

| Token | Value | Use |
| --- | --- | --- |
| `{colors.success}` | `#3fb950` | Completed run glyph |
| `{colors.failure}` | `#f85149` | Failed glyph, bar tint, pin failure |
| `{colors.in-progress}` | `#d29922` | Running glyph, bar count while jobs are active |
| `{colors.queued}` | `#8b949e` | Queued glyph |
| `{colors.label}` | system `.primary` | Run names, headline |
| `{colors.secondary}` | system `.secondary` | Meta, freshness, section titles |
| `{colors.tertiary}` | system `.tertiary` | Trailing timestamps |
| `{colors.separator}` | system separator | Hairlines between bands and sections |
| `{colors.material}` | `.menu` / window background | Panel fill. Not a custom dark hex |

Do not paint the panel `#1c1c1e`. Do not put `{colors.in-progress}` on header buttons, section capsules, or empty-state CTAs. `RunBarTheme` stays these four semantic colors plus system secondaries.

## Type

SF Pro. Contrast from size and weight, not a second family. Times and the bar count use monospaced digits.

| Role | SwiftUI | Weight | Use |
| --- | --- | --- | --- |
| `{typography.headline}` | `.headline` | semibold | “2 running”, empty-state title |
| `{typography.row}` | `.body` | regular | Workflow name |
| `{typography.meta}` | `.footnote` | regular | Branch · actor · event, freshness |
| `{typography.section}` | `.caption` | semibold | Pinned, Active, `owner/repo` |
| `{typography.time}` | `.footnote.monospacedDigit()` | regular | `3m`, `1h`, `12s` |
| `{typography.bar}` | 12pt rounded, semibold, monospaced digits | — | Status item count |
| `{typography.command}` | `.body` | regular | Refresh, Settings…, Quit |

No `.title3` icon in the header. No tracked-out small caps.

## Layout

- **Width:** 320pt. Current 380pt is a sidebar. CodexBar’s card sits near 310.
- **Horizontal inset:** 16pt on identity and scan. Commands use the menu’s native inset (visually aligned).
- **Vertical rhythm:** 8pt inside the identity band. 4pt between a section title and its first row. 10pt between sections. 0pt between rows in a section (rows are lines, not tiles).
- **Hairline:** 1pt `{colors.separator}` after identity, before commands, and between Pinned / Active / repo groups.
- **Max height:** ~420pt, then scroll the scan band only. Identity and commands stay pinned.
- **Corners:** system menu radius on the popover. **0pt on rows.**

```
identity  8pt pad
────────
scan      8pt pad, scroll
────────
commands  system menu rows
```

## Shape and depth

- Panel: system material. No extra drop shadow, no inner stroke.
- Rows: no fill, no 10pt rounded rect, no `.quaternary` chip.
- Highlight: system menu highlight on hover/press. Do not roll a custom rounded hover.
- Status glyph: 14pt SF Symbol, 18×18 hit box. No pulse ring.
- Commands: look like `NSMenu` items (label, optional shortcut). Not caption links in a toolbar.

## Status item

The bar is the product when the panel is closed.

| State | Glyph | Count | Tint |
| --- | --- | --- | --- |
| Idle, all green | `bolt` (template) | hidden | primary |
| N running | `bolt` | `N` | `{colors.in-progress}` on the count |
| Recent or pinned failure | `bolt.slash` or failure badge | keep N if still running | `{colors.failure}` |
| Refreshing, nothing active | same as idle | hidden | 70% opacity, no spinner in the bar |

One status item. No second extra. Count is the CodexBar meter analog: a three-glyph-wide number, not a progress fill. Accessibility label stays the full `ActivitySummary` sentence.

## Identity band

Left: `{typography.headline}` from `ActivitySummary.headline` (“2 running”, “All clear”, “gh is not signed in”).

Second line: `{typography.meta}` — `Updated {relative}` · `gh ok` | `gh missing` | `gh signed out`. Include the GitHub login only in Settings, not here.

Trailing: watch meta, `{typography.meta}` (“1 repo”, “3 repos”). Not a gear. Not a refresh squircle.

Refresh lives in the command band (`⌘R`). Settings lives there (`⌘,`).

## Scan band

Three group types, in this order, omitted when empty:

1. **Pinned** — pins first, always. Failed pin may use a 1pt `{colors.failure}` leading bar (2pt wide) instead of a stroke around a card.
2. **Active** — in-progress and queued, newest first.
3. **Per repository** — remaining runs, `owner/repo` as `{typography.section}`, truncation `.middle`.

**Row.** One line of `{typography.row}` (workflow name). One line of `{typography.meta}` (repo if needed · branch · actor · event). Trailing `{typography.time}`. Click opens `htmlURL`. Context menu: Open in GitHub, Copy run URL.

**Empty scan.** `{typography.meta}`: “No matching runs.” No tray illustration, no bordered empty card.

**Setup** (`gh` missing / signed out / no repos). Still three bands. Scan band is a short message plus the copyable command (`brew install gh`, `gh auth login`) as monospaced `{typography.meta}`. Primary action is a command-band item (“Add Repository…”) that opens Settings, not a bordered-prominent button in the middle of the panel.

## Command band

| Item | Shortcut |
| --- | --- |
| Refresh | ⌘R |
| Settings… | ⌘, |
| Quit | ⌘Q |

No Website. No GitHub. Those belong on the marketing page and in Settings → About. A command band that looks like a browser toolbar is why the current screenshot reads as a window.

While Refresh is in flight, the row label stays “Refresh” and a small `ProgressView` sits on the trailing edge. Do not swap the identity band for a spinner.

## Settings

Grouped `Form` in a window, not in the popover. Minimum ~540×520. Opened only from Settings….

Sections, in order: Account, Repositories, Filters, Pins, General, About. About holds version, website, and source links.

## Motion

- Relative timestamps tick once per second while the panel is open (`TimelineView`).
- Running glyph is static `{colors.in-progress}`. No `ActivePulseRing`.
- Reduce Motion: no opacity pulse on the status item either.
- Opening the panel must not hitch. Do not rebuild the whole stack on every poll; patch the snapshot in place.

## Copy

Short, specific, present tense. Name `gh`, the workflow, the repo.

| Use | Don’t |
| --- | --- |
| 2 running | Jobs in progress |
| Updated 8s ago | Last synced moments ago |
| gh ok | Connected to GitHub |
| No matching runs | You’re all caught up |
| Add Repository… | Get started |

## Do

- Keep pins at the top and filters off those rows.
- Tint the bar on a pinned failure even when that run is hours old.
- Use system material so the panel sits on the desktop like Control Center, not a floating dark card.
- After panel changes, update `docs/assets/screenshot.png` (in-situ crop: bar + hanging panel) and `docs/assets/screenshot-failure.png` (failure headline, no need for the bar crop).

## Don’t

- Don’t wrap every run in a rounded tile.
- Don’t put Settings, GitHub, Website, and Quit on one caption row.
- Don’t add provider-style tabs, usage bars, or cost rows.
- Don’t restyle Settings as a sidebar unless the form actually needs navigation.
- Don’t introduce a brand yellow outside `{colors.in-progress}` on a running glyph or count.

## Current → target

| Now (`MenuBarPanel`) | Target |
| --- | --- |
| 380pt, `.regularMaterial` | 320pt, menu material |
| Header icon + two squircle buttons | Headline + meta only |
| `RunRow` in 10pt rounded fills | Flat rows, hairlines between groups |
| Capsule section counts | Section title only |
| Pulse ring on active runs | Static glyph |
| Footer link row | Refresh / Settings… / Quit |

Views: `MenuBarPanel.swift`, `RunRow.swift`, `StatusBarLabel.swift`, `Theme.swift`. Tokens in this file win over the current chrome.
