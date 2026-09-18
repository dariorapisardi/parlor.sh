# Brand: the mark

The logo, specified against the tokens in `docs/style.css.inc`. No webfont, no build step, no
new colour. Two SVG files and three small diffs, all applied in `docs/`.

## The one idea

Brackets are the walls of the room. The two dots are who is inside. The second dot takes
`--accent`, the same colour a handle takes in a transcript, so the mark and the log agree about
who is speaking. Nobody stands between the two dots.

## Geometry

A 32-unit canvas. Every number is an integer or a half, so the mark sits on whole pixels at
16, 32, 64 and 128.

| | |
|---|---|
| canvas | 32 x 32 |
| wall stroke | 2, butt ends, no round caps |
| wall height | 21 outer (y 5.5 to 26.5); path height 19 |
| wall return | 3 inward, top and bottom |
| dots | r 3, centres (11.5, 16) and (20.5, 16) |
| gap between dots | 3 |
| optical margin | 4.5 left and right, 5.5 top and bottom |

Clear space around the mark is one dot diameter: 6 units at 32, 4 at 16.

## Sizes

- **24px and up:** the full mark, walls and dots (`mark.svg`).
- **Below 24px:** the walls fall under a pixel. Use the dot tile instead (`favicon.svg`):
  16-unit canvas, `rx 3`, dots r 2 at x 5 and 11. The dots carry the meaning, so the favicon
  keeps them and drops the room.

## Colour: unchanged

| token | light | dark | role in the mark |
|---|---|---|---|
| `--fg` | `#1d1c1a` | `#e9e6df` | walls, first dot, wordmark |
| `--accent` | `#8a3b12` | `#e0925f` | second dot, and nothing else |
| `--bg` | `#fbfaf7` | `#161513` | the dots when the tile is filled |
| `--dim`, `--line`, `--box` | | | never in the mark |

On the site the mark takes `currentColor` and `var(--accent)`, so the theme switch already
handles it. The favicon's colours are fixed: it sits on browser chrome, not on the page.

## Type: unchanged

The wordmark is the `h1` as it is: lowercase *parlor*, the `ui-monospace` stack, 1.35rem, bold,
normal tracking. A service whose whole argument is that nothing needs installing should not make
a browser fetch a typeface to render the word "parlor". It will look slightly different on macOS,
Windows and Linux; on a site that renders its own documentation in the reader's mono, that is
consistent rather than sloppy.

The lockup is the mark, then *parlor.sh* with the `.sh` suffix in `--dim`. The site's `h1` uses
the same lockup.

## Don't

- Colour both dots the same. The pair only means two parties because they differ.
- Outline the dots, round the wall ends, or add a third dot.
- Draw the walls below 24px. Use the dot tile.
- Put the mark on `--accent`, on a photograph, or in a circle.
- Set the wordmark in a display or proportional face, or in caps.
- Animate the dots on the page. The blink belongs to a terminal, not to a logo.
