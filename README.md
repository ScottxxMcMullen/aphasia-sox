# Aphasia SOX

**An Android app that speaks for someone with aphasia — in their own voice.**

Aphasia is a word-finding disorder. The person understands everything said to
them and knows exactly what they mean; the words just don't always come out.
Aphasia SOX gives them a phone they can tap instead, and what comes out of it
sounds like *them*, not a synthesized stranger.

I built it for a family member, for the moments it matters most: ordering at a
restaurant, standing at a pharmacy counter, explaining to someone new what
aphasia is while they wait.

The name is a family joke. "SOX" reads as "socks" — which is roughly what it
feels like to reach for one word and have a different one arrive.

---

## How it works

```
 ┌──────────────── phone ────────────────┐        ┌────── laptop at home ──────┐
 │                                        │        │                            │
 │  Saved phrases ── audio on the device  │        │  FastAPI server            │
 │  (works in airplane mode)              │        │    └─ local voice-cloning  │
 │                                        │        │       TTS engine           │
 │  Say Something ────────────────────────┼─ Tailscale ─▶  generates new speech │
 │  Sync ◀────────────────────────────────┼───────────┼── phrase library        │
 └────────────────────────────────────────┘        └────────────────────────────┘
```

**Saved phrases are the core, and they never touch the network.** Every phrase
is an audio file on the phone. Tap a category, tap a phrase, it plays — no
signal, no server, nothing. That was the first design constraint and the one
everything else is measured against: the thing a person depends on in public
cannot depend on a laptop being awake.

**New sentences are the extra.** Typing something new sends it to a small
server at home that wraps a locally-run voice-cloning model. The server is
reachable only over a private Tailscale network — it binds to the tailnet
address, never `0.0.0.0`, and nothing is exposed to the internet.

This repository is the phone app. The home server is not included.

---

## Decisions worth a look

### The progress bar that refuses to lie

A cold load of the voice model takes the better part of a minute. One spinner
for sixty seconds reads as a crash, and the person has no way to tell a slow
generation from a dead server.

So Say Something shows three stages — reaching the laptop, building the voice,
speaking — and **each one advances only when the corresponding call actually
returns**. Nothing moves on a timer. The progress bar is indeterminate on
purpose: the app cannot know when a cold load will finish, so it does not draw
something that implies it does. A test asserts the bar has no `value`.

A new `ping()` makes the failure useful. If the laptop is off, the app says so
within five seconds — *could not reach the laptop* — instead of hanging for
ninety, and tells the person their saved phrases still work.

### A safety bug on the emergency path

Moving a phrase between categories was originally a long press on the tile.
That put speaking and filing 500 milliseconds apart — Flutter's long-press
threshold — and when the long press won, **the tap was rejected and nothing
was spoken**. Pressing firmly is exactly what people do under stress.

It surfaced while reviewing a redesign that made Emergency a large pinned red
bar: the design would have widened the road to the problem without touching it.
Moving is now an explicit mode entered from the app bar, and outside that mode
there is no long-press recognizer in the gesture arena at all. The regression
test states the property directly: a long press outside move mode *still
speaks*.

### A design system, implemented and then measured

The visual design came as five implementation briefs from a design pass —
tokens, a bundled typeface, a ranked home screen, the staged wait, a grouped
library. They're in [`docs/design-handoff/`](docs/design-handoff/), with the
deviations each one made recorded against it.

Implementing them meant checking them. The brief claimed its disabled-text grey
cleared 4.5:1 contrast; it clears 5.00:1 and 5.75:1, and a test now holds that
floor. Measuring everything else found two pairings the brief missed, both just
under WCAG AA — documented rather than quietly adjusted, since the design's own
rule is to report a color problem instead of inventing a new color.

Categories on the home screen are ranked by phrase count on a five-step type
ramp, with Emergency pinned above the scroll regardless of rank. Against the
real library the resulting order matches the brief's prediction exactly.

### Tests that hang instead of failing

This app does real file I/O from widget callbacks, and Flutter's widget tests
run inside a fake async zone. A Future's zone is fixed where it starts — so a
test that kicks off real disk work in the wrong zone doesn't fail. **It hangs
forever, with no timeout.**

That pattern turned up in several distinct shapes: a tap that starts a chain
whose continuation writes a file; a dialog opened in one zone and dismissed in
another; a bare `await store.manifest()` in an assertion; a tap fired while a
route is still sliding in, landing off-screen and missing silently. Each fix is
commented at the site where it applies, and the shared shapes live in
[`test/test_helpers.dart`](phone_app/test/test_helpers.dart). The comments look
like over-explanation until you have waited on a test that will never return.

99 tests.

---

## Running it

```bash
cd phone_app
flutter test
```

To build a release APK, copy `dart_defines.example.json` to
`dart_defines.json`, set `SERVER_URL` to your server's address, and run:

```powershell
./build-release.ps1
```

The server address is supplied at build time rather than kept in source. The
script refuses to build without it: a plain `flutter build apk` succeeds but
produces an app whose live speech quietly points at `localhost`, which is not a
mistake to ship to someone who depends on it.

Without a server, the app still installs and every saved phrase still plays.

---

## Built with

Flutter · Dart · Material 3 with a custom token system · Archivo (SIL OFL) ·
`audioplayers` · `shared_preferences` · FastAPI and a local voice-cloning TTS
engine on the server side · Tailscale

Built with [Claude Code](https://claude.com/claude-code), with the visual
design produced in Claude Design.

## License

Code is MIT — see [`LICENSE`](LICENSE). The bundled Archivo typeface is under
the SIL Open Font License, included alongside it in
[`phone_app/assets/fonts/`](phone_app/assets/fonts/).
