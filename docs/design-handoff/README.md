# Aphasia SOX — design handoff

Five implementation passes taking the app from stock Material to the Aphasia SOX design.
Each pass is a self-contained brief written to be executed by Claude Code working in this repo.

Read this file first, then the pass you are running. Run one pass per branch.

## Fidelity

**High fidelity.** Colors, type sizes, weights, letter-spacing, rule weights and row heights are
final and specified as exact values. Where a brief gives a hex, a px or a Dart snippet, use it
verbatim rather than approximating. Where it gives a rule ("count descending, ties alphabetical"),
implement the rule rather than hard-coding today's output.

## Order and dependencies

| Pass | Brief | Depends on |
| --- | --- | --- |
| 1 · Theme | `THEME-PASS.md` | — |
| 2 · Home layout | `HOME-LAYOUT-PASS.md` | pass 1 (token file) |
| 3 · Say Something | `SAY-SOMETHING-PASS.md` | pass 1 (token file) |
| 4 · Library | `LIBRARY-PASS.md` | pass 1 (token file) |
| 5 · Launcher icon | `ICON-PASS.md` | — |

Pass 1 first. After that, 2, 3, 4 and 5 are independent of each other and can land in any order.

## What each pass changes

1. **Theme** — `lib/theme/sox_tokens.dart` and `lib/theme/sox_theme.dart` (light + dark
   `ThemeData`), bundled Archivo, three lines in `main.dart`. No screen keeps a hard-coded color
   or font afterwards. Exactly one screen line changes: `Colors.red` in `say_something_screen.dart`.
2. **Home layout** — the 2-column category grid becomes count-ranked full-width rows with a
   five-step size ramp; Emergency is pinned above the scroll; the FAB becomes a bottom bar.
3. **Say Something** — the single "Working..." spinner becomes three honest stages, adds
   `ApiClient.ping()`, distinguishes "laptop is off" from a generation failure, and adds a
   spoken state.
4. **Library** — `ManageScreen` becomes `LibraryScreen`: grouped by category with counts,
   searchable, the two inline fields moved into an add dialog that reuses the existing category
   picker. Adds `SettingsStore` and the light/dark/system switch.
5. **Launcher icon** — copy the pre-cut assets in `icon/`, add the adaptive-icon XML, rename the
   launcher label to "Aphasia SOX".

## Rules that hold across every pass

- **Tokens only.** After pass 1, nothing outside `lib/theme/` writes a `Color(0x…)` or a font
  family. If a pass seems to need a new color, stop and say so.
- **Two rule weights.** Structure is drawn with 2px (separates regions) and 1px (separates rows).
  No cards, no elevation shadows, no rounded corners anywhere in the app.
- **One solid accent per screen.** The red is spent on a single element — the primary action or
  Emergency. Everything else competing for it becomes outlined.
- **Never an opacity for disabled text.** Use `SoxTokens.greyOnPaper` / `greyOnDark`; they clear
  4.5:1 on their own ground, and an alpha would not.
- **Size floors.** Speaking screens never put text below 23px, and tap targets are never below
  44px. `LibraryScreen` is the one deliberate exception — it is the caregiver's maintenance
  screen and trades size for overview at 15px rows.
- **Nothing on screen may lie.** No progress indicator that predicts a completion it cannot know,
  no stage that advances on a timer, no placeholder timestamp. This is the reason pass 3 departs
  from its own mock.
- **Scope discipline.** Each brief lists what it does *not* touch. Respect it — the passes were
  cut so each one is reviewable on its own. If a pass appears to require a change outside its
  scope, report it rather than widening the pass.

## Design tokens

| Token | Light | Dark |
| --- | --- | --- |
| ground | `#F3F2F2` | `#201E1D` |
| ink | `#201E1D` | `#F8F4F4` |
| accent | `#EC3013` | `#EC3013` |
| accent pressed | `#AE1800` | `#AE1800` |
| grey (disabled) | `#6B6767` | `#9B9797` |
| major rule | ink @ 40%, 2px | ink @ 40%, 2px |
| minor rule | ink @ 25%, 1px | ink @ 25%, 1px |
| muted text | ink @ 60% | ink @ 60% |

Type: Archivo — ExtraBold 800 for anything that names a thing, Regular 400 for anything that is
speech, SemiBold 600 for captions and metadata. Bundled as an asset, not fetched: the app must
theme correctly on first launch with no network. Corner radius is 0 everywhere.

## Assets

`icon/master/` — three SVG masters (adaptive foreground, legacy square, Play Store).
`icon/android/` — 15 mipmap PNGs at five densities plus the 512px listing image, pre-cut. Copy
these; do not regenerate them from a single PNG with `flutter_launcher_icons`, which would apply
its own safe-zone crop.

`assets/current-icon-concept.png` — the original concept sketch the final mark came from, kept
for provenance only. Not an asset to ship.

## What this design was drawn from

The inputs handed to the design work, kept because they are still the context
the briefs assume:

`DESIGN-BRIEF.md` — who the app is for, the conditions it is used in, and the
open questions. The largest of those is still unanswered: whether the
user's reading is affected, which would change how much of a category's identity can
rest on its name.
`CONTENT.md` — every real category and phrase, generated from the live library.
`source/` — the four screens as they were before any pass landed.

## Implementation status

| Pass | State |
| --- | --- |
| 1 · Theme | Landed. Two mechanical deviations, both recorded in the commit |
| 2 · Home layout | Landed. Real-library order matches the brief exactly |
| 3 · Say Something | Landed. One deviation on the error detail, recorded in the commit |
| 4 · Library | Landed. ManageScreen deleted; add moved into a dialog reusing the picker |
| 5 · Launcher icon | Landed. Label, icon and roundIcon verified in the built APK |

One thing the briefs do not cover, found after they were written and fixed
before pass 2: on `CategoryScreen` a long press opened the move-to-category
picker, and a long press is what a firm tap becomes — Flutter's threshold is
500ms, and when the long press won, the tap was rejected and the phrase did
not play. Pass 2 makes Emergency a large red bar, which would have widened
the road to that collision rather than resolving it.

Moving is now a mode, entered from the category screen's app bar. In speaking
mode a tile does exactly one thing however long it is held, and a test holds
that property: a long press outside move mode still speaks.

## New dependencies

Only two, both in specific passes: nothing in pass 1, 2 or 5; `shared_preferences` in pass 4
(the theme choice and last-sync time must survive a restart). Pass 3 adds no package — `ping()`
uses the existing HTTP client.

## The visual references

The briefs are the source of truth for implementation. The matching before/after pages — one per
pass, plus the full settled design — live in the design project alongside this folder, and are
HTML design references rather than code to port: `Theme Pass`, `Home Layout Pass`,
`Say Something Pass`, `Library Pass`, `Icon Pass`, and `Aphasia SOX` for the whole system. Ask
for them if a brief is ambiguous about how something should look.

## Definition of done

Every brief ends with an on-device checklist. Run it on the real phone, in both themes, at the
system font size the user actually uses — not in a simulator at default settings. A pass is not
finished until its checklist passes.
