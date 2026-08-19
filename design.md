# RunBar site

Marketing page only (GitHub Pages + README chrome). The menu bar panel is [`docs/ui.md`](docs/ui.md).

The screenshot is the product. Chrome stays out of the way.

The GitHub Pages site and README should read like a printed catalog page for a Mac utility: one large lockup, one photograph of the panel, install commands, then a few short facts. No gradients, no card shadows, no accent color used for mood. Color in the screenshot (running yellow, success green, fail red) is enough.

## Palette

Almost everything is ink, canvas, and studio gray.

| Token | Hex | Use |
| --- | --- | --- |
| `{colors.ink}` | `#111111` | Headlines, body, primary pill, footer |
| `{colors.canvas}` | `#ffffff` | Page background |
| `{colors.studio}` | `#f5f5f5` | Stage behind the screenshot, secondary pill, code block |
| `{colors.hairline}` | `#cacacb` | 1px rules between sections |
| `{colors.mute}` | `#707072` | Supporting copy, captions, footer links |
| `{colors.on-primary}` | `#ffffff` | Text on the black pill |

Semantic color stays in the app screenshot. Do not add a yellow/amber brand stripe to the marketing page.

## Type

One family. Contrast comes from size, not from mixing display fonts.

- **UI:** `-apple-system`, `"Helvetica Neue"`, Helvetica, Arial, sans-serif
- **Code:** `ui-monospace`, `"SF Mono"`, Menlo, monospace

| Role | Size | Weight | Line height | Notes |
| --- | --- | --- | --- | --- |
| `{typography.display}` | `clamp(48px, 8vw, 80px)` | 500 | 0.9 | Hero lockup, sentence case (not all caps) |
| `{typography.heading}` | 24px | 500 | 1.2 | Section titles |
| `{typography.body}` | 16px | 400 | 1.5 | Lede and feature copy |
| `{typography.button}` | 16px | 500 | 1 | Pill labels |
| `{typography.caption}` | 13px | 400 | 1.4 | Meta line, footer, code header |
| `{typography.code}` | 13px | 400 | 1.6 | Install snippet |

Letter-spacing stays at 0. Do not uppercase the whole page or track out small labels.

## Layout

- **Base unit:** 8px
- **Section gap:** 48px desktop, 32px tablet, 24px mobile
- **Content width:** 1120px, 24px side gutters (40px on small screens)
- **Hero:** two columns. Copy left, screenshot on `{colors.studio}` right. Collapse to one column under 860px, copy first.
- **Whitespace** separates sections. It is not padding inside cards. Sections meet at a hairline, not a colored block.

## Shape and depth

- Pills: `{rounded.pill}` 9999px on primary, secondary, and the copy control
- Everything else: `{rounded.none}` 0px (page, screenshot stage, code block, footer)
- No drop shadows. No inset glows. Depth is the dark panel photo sitting on studio gray.

## Components

**Primary pill.** Background `{colors.ink}`, text `{colors.on-primary}`, height 48px, padding 16px 32px. One per fold. Pressed: opacity 0.55.

**Secondary pill.** Background `{colors.studio}`, text `{colors.ink}`, same size. Used for "Source on GitHub" next to install.

**Install block.** `{colors.studio}` fill, no radius, no border. Caption row on top with a text-only Copy control. Preformatted commands in `{typography.code}` `{colors.ink}`.

**Screenshot stage.** `{colors.studio}` field, 48px padding, image centered at its native portrait crop (`docs/assets/screenshot.png`, 391×524). Do not draw a fake menu bar around it.

**Feature row.** Three columns of plain text on canvas. Title `{typography.heading}`, body `{colors.mute}`. No cards, no numbered markers, no `job / id` eyebrows.

**Footer.** Hairline above. Caption text. Links in `{colors.mute}`, underline on hover.

**Focus.** 2px `{colors.ink}` outline, 3px offset, on every control.

## Copy

Write like the README: short, specific, present tense. Name the thing (`gh`, Deploy to prod, `make install`). Do not sell the category.

Avoid: yellow tracked eyebrows, simulated macOS chrome, "tiny" / "delightful" / "powerful", decorative monospace labels on feature blocks, three stacked metaphors for the same idea.

Hero lockup: "GitHub Actions, in your menu bar."

## Do

- Put the real panel screenshot in the hero and the README. Update `docs/assets/screenshot.png` when the UI changes.
- Keep one black pill in the first screen.
- Use studio gray as the photograph backdrop, the same way a product shot sits on a seamless.
- Match this page on GitHub Pages (`docs/index.html`, `docs/site.css`). Markdown docs stay plain.

## Don't

- Don't restyle the page as a dark GitHub dashboard. The app is already dark; the site is the studio around it.
- Don't add gradients, glass, or a running-yellow brand color.
- Don't wrap features in bordered cards.
- Don't invent a second display typeface.
- Don't put a fake menu bar, window traffic lights, or an illustrated SVG stand-in of the panel on the site.

## Breakpoints

| Width | Layout |
| --- | --- |
| 1120px+ | Two-column hero, three feature columns, two-column privacy row |
| 860px | Single column, 32px section gap, screenshot under the install block |
| 600px | Display type ~48px, pills still 48px tall, code block scrolls horizontally |
