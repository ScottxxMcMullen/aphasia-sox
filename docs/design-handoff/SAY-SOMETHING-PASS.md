# Say Something pass — instructions for Claude Code

**Prerequisite:** the theme pass is merged (`lib/theme/` exists). The home layout pass is
independent of this one — they can land in either order.

**Goal:** replace the single "Working..." button state with the staged wait from design `1d`, and
give a finished phrase an explicit spoken state. Layout otherwise stays as it is.

**Why:** a cold Voicebox engine load takes the better part of a minute — the code comment in
`say_something_screen.dart` already says so. One spinner for 60 seconds reads as a hang, and the
person using it has no way to tell a slow generation from a dead server. The stages say which
part is slow, and say it truthfully.

**Files touched:** `lib/screens/say_something_screen.dart`, plus one new method on `ApiClient`.

---

## 1. Honesty rule for this screen

Every stage indicator must reflect something the app actually knows. No timed fakes: do not
advance a stage on a `Future.delayed`, and do not show a progress bar that fills toward a
guessed completion. The mock in `1d` draws an 8-second sweep — that was a placeholder for the
frame, and it is deliberately **not** in this spec. What ships instead is a count-up of real
elapsed seconds and an indeterminate bar.

The three stages, and what each one is allowed to mean:

| Stage | Complete when | Shows |
| --- | --- | --- |
| Reached the laptop at home | `ApiClient.ping()` returned | Round-trip time, e.g. "2s" |
| Building your voice | `generateSpeech()` returned bytes | Elapsed, counting up: "0:18" |
| Speaking | Playback started | Nothing |

## 2. `ApiClient.ping()`

Stage one needs a real signal that the server answered. Add the smallest possible call —
a HEAD or GET against the health route the server already exposes (check `api_client.dart` for
the base URL and the existing route constants; if there is no health route, use the cheapest
existing GET rather than inventing an endpoint).

```dart
/// Cheap round-trip check so the UI can tell "the laptop is asleep" apart
/// from "the model is loading". Short timeout: this is not the real work.
Future<Duration> ping() async {
  final stopwatch = Stopwatch()..start();
  final response = await _client
      .get(_uri('/health'))
      .timeout(const Duration(seconds: 5));
  if (response.statusCode >= 400) {
    throw ApiException('server returned ${response.statusCode}');
  }
  return stopwatch.elapsed;
}
```

A failed ping is the most useful error this screen can produce: it means the machine is off or
off the network, which is the common case and is not the same message as a generation failure.

## 3. Stage state in `_SaySomethingScreenState`

Replace the single `_isBusy` bool with a stage enum plus an elapsed ticker. Keep `_isBusy` as a
derived getter so the existing `onPressed: _isBusy ? null : …` guards keep working unchanged.

```dart
enum _Stage { idle, reaching, generating, speaking, spoken }

_Stage _stage = _Stage.idle;
Duration? _reachedIn;      // stage 1 result, shown as "2s"
Duration _elapsed = Duration.zero;
Timer? _ticker;

bool get _isBusy => _stage == _Stage.reaching ||
                    _stage == _Stage.generating ||
                    _stage == _Stage.speaking;

void _startTicker() {
  _ticker?.cancel();
  _elapsed = Duration.zero;
  _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted) setState(() => _elapsed += const Duration(seconds: 1));
  });
}

@override
void dispose() {
  _ticker?.cancel();
  _textController.dispose();   // currently missing — add it while you are here
  super.dispose();
}
```

`_textController` is never disposed in the current file. Fix that in this pass.

## 4. `_speak()`, restaged

Same three operations in the same order, with the stage set before each and the error paths
unchanged apart from which stage they return to.

```dart
Future<void> _speak() async {
  final text = _textController.text.trim();
  if (text.isEmpty) return;

  setState(() {
    _stage = _Stage.reaching;
    _errorMessage = null;
    _reachedIn = null;
  });

  try {
    _reachedIn = await widget.apiClient.ping();
    if (!mounted) return;
    setState(() => _stage = _Stage.generating);
    _startTicker();

    final audio = await widget.apiClient.generateSpeech(text);
    final tempFile = File('${Directory.systemTemp.path}/say_something_preview.wav');
    await tempFile.writeAsBytes(audio);
    _ticker?.cancel();
    if (!mounted) return;
    setState(() => _stage = _Stage.speaking);

    await widget.audioPlaybackService.playFile(tempFile);
    if (!mounted) return;
    setState(() {
      _lastAudio = audio;
      _lastText = text;
      _stage = _Stage.spoken;
    });
  } on ApiException catch (e) {
    if (!mounted) return;
    setState(() {
      _errorMessage = _stage == _Stage.reaching
          ? 'Could not reach the laptop: ${e.message}'
          : 'Could not reach the server: ${e.message}';
      _stage = _Stage.idle;
    });
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _errorMessage = 'Something went wrong. Please try again.';
      _stage = _Stage.idle;
    });
  } finally {
    _ticker?.cancel();
  }
}
```

The two `ApiException` messages differ on purpose. "Could not reach the laptop" is actionable —
go wake the machine. "Could not reach the server" during generation means something else.

## 5. The stage panel

Shown only while `_isBusy`. A 2px-framed box above the Speak button: one row per stage, a 14px
square marker, the label, and the meta value flush right. Done stages are ink, the active stage
is red, stages not yet reached are the muted ink.

```dart
class _StageRow extends StatelessWidget {
  const _StageRow({required this.label, required this.meta, required this.state});

  final String label;
  final String meta;
  final _RowState state;   // done | active | pending

  @override
  Widget build(BuildContext context) {
    final Color ink = Theme.of(context).colorScheme.onSurface;
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color fg = switch (state) {
      _RowState.done => ink,
      _RowState.active => Theme.of(context).colorScheme.error,
      // The real grey token, not an opacity: a pending stage still has to be
      // readable. `withOpacity` would replace muted()'s alpha, not multiply it,
      // and land at 2.75:1. The token clears 4.5:1 on both grounds.
      _RowState.pending => dark ? SoxTokens.greyOnDark : SoxTokens.greyOnPaper,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: state == _RowState.pending ? Colors.transparent : fg,
              border: Border.all(color: fg, width: 2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: SoxTokens.fontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 17,
                color: fg,
              ),
            ),
          ),
          Text(meta, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
```

Under the three rows: an indeterminate `LinearProgressIndicator()` (no `value` — it is not a
prediction), then the reassurance line at 13px muted:

> The first sentence after a quiet spell takes about a minute. Saved phrases still work while
> you wait.

That sentence is the most important copy on the screen. It is the difference between waiting and
assuming the app is broken. Keep it verbatim.

Format the elapsed meta as `m:ss` (`0:18`), and the ping result as whole seconds (`2s`).

## 6. The error panel

`_errorMessage` currently renders as one bare line of red text. Replace that with a framed
panel — a 2px red border, no fill — holding three parts, in this order:

1. **Heading**, 13px ExtraBold, uppercase, `letterSpacing: 1.3`, in `colorScheme.error`. Derived
   from which stage failed, so it is the same distinction as the message in §4:
   `COULD NOT REACH THE LAPTOP` when the ping failed, `SOMETHING WENT WRONG` otherwise.
2. **Detail**, `bodyMedium` at 15px full-strength ink — the exception text, e.g.
   "Connection refused. The laptop at home may be asleep or off the network."
3. **Reassurance**, `bodySmall`, verbatim:

   > Saved phrases still work — everything in your library plays from this phone.

That third line is the point of the panel. A failure here costs the speaker a new sentence, not
their voice, and the screen should say so.

```dart
enum _Failure { unreachable, generation }

// Track alongside _errorMessage in the catch blocks in §4:
//   _failure = _stage == _Stage.reaching ? _Failure.unreachable : _Failure.generation;
_Failure? _failure;
```

Panel placement: it takes the stage panel's slot — the two are never on screen together
(`_errorMessage != null` implies `_stage == _Stage.idle`). It sits above the bottom Speak bar,
which stays enabled so the person can retry without navigating away. Keep the existing
`if (_errorMessage != null)` guard; only the widget inside it changes.

Split the message so the detail reads as a sentence rather than a prefix plus a colon: keep
`_errorMessage` as the detail text only ("Connection refused. The laptop at home may be asleep
or off the network.") and let the heading carry "Could not reach the laptop". Drop the
`'Could not reach the laptop: '` / `'Could not reach the server: '` prefixes from §4 once the
heading exists — they would otherwise appear twice.

## 7. The spoken state

When `_stage == _Stage.spoken`, above the button:

- A solid red bar, paper text, 20px ExtraBold: `SPOKEN IN YOUR VOICE`.
- Below it the existing "Save to library" action, restyled as an **outlined** button (2px rule,
  transparent fill, ink text) so the red stays spent on one thing per screen. Use
  `OutlinedButton` with `side: BorderSide(color: SoxTokens.majorRule(ink), width: 2)` and square
  corners; it calls `_showSaveDialog()` exactly as now.

The bottom button's label changes with the stage:

```dart
String get _speakLabel => switch (_stage) {
  _Stage.spoken => 'SAY SOMETHING ELSE',
  _ => 'SPEAK IT',
};
```

`SAY SOMETHING ELSE` clears the field and returns to idle (`_textController.clear()`,
`_stage = _Stage.idle`, `_lastAudio = null`) rather than re-sending the same text.

## 8. The field

The field is a `TextField` with a hint today. Make it multi-line and large, matching `1d`:
`maxLines: null`, `minLines: 3`, `style` from `titleLarge`, hint "Type it here", with the label
"WHAT YOU WANT TO SAY" above it as an 11px letterspaced caption rather than an input label. The
underline comes from `inputDecorationTheme`; no fill, no box.

---

## Definition of done — check on device

1. With the laptop **off**: tapping Speak fails at stage one within ~5s and shows the error
   panel headed "COULD NOT REACH THE LAPTOP", with the offline reassurance line — not a bare
   line of red text, and not "Something went wrong".
2. With the laptop on but the model cold: stage one completes with a real round-trip figure,
   stage two counts up in real seconds past 0:30, and the bar is indeterminate — it never
   appears to fill toward a finish.
3. Stage three appears when audio actually starts, and the panel is replaced by the red
   SPOKEN IN YOUR VOICE bar when playback ends.
4. Save to library still opens the category picker and still saves; the snackbar is unchanged.
5. SAY SOMETHING ELSE clears the field and the spoken state; the Speak button says SPEAK IT
   again.
6. No stage ever advances without the corresponding call returning — pull the network mid-
   generation and confirm the app errors rather than proceeding to "Speaking".
7. The reassurance sentence is visible on a small phone without scrolling while the panel is up.
8. The pending "Speaking" row is readable — it uses the grey token, not an opacity. Check it
   against the ground in both themes.
9. Light and dark, and at the system's largest font scale.
