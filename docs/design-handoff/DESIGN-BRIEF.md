# Aphasia SOX — design brief

Hand this folder to Claude Design (or any designer). It is self-contained:
the brief below, the real screen source in `source/`, the real phrase
content in `CONTENT.md`, and the current icon concept in `assets/`.

---

## What the app is

An assistive-communication app built for a family member with aphasia.
Aphasia is a word-finding disorder: the person understands everything said
to them and knows what they mean, but the words don't always come out. The
app speaks for them **in their own cloned voice** when they don't.

It is used **in public, during an episode** — ordering at a restaurant, at
a pharmacy counter, asking a stranger for help. That setting drives most of
the design decisions below.

Two ways to speak:

1. **Saved phrases** — tap a category, tap a phrase, it plays. Audio files
   live on the phone, so this works with no signal, no wifi, nothing.
2. **Say Something** — type anything, a home server generates it in their
   voice and plays it. Needs a network connection to a laptop at home.

The core loop is **two taps from home screen to speech.** Protecting that
is the single most important thing about this design.

---

## Who is using it, and under what conditions

Established, from the app's own phrase library:

- The user needs to explain their condition to strangers — the library has
  phrases like "I have aphasia. It affects my speech, not my hearing."
  and "Please slow down." / "One question at a time, please."

Open questions worth asking before designing — do not assume:

- Which hand the phone is operated with, and whether there is weakness on
  one side. Aphasia frequently arrives alongside one-sided weakness, which
  would make one-handed reachability a real constraint.
- Whether reading is affected. Aphasia can impair reading as well as
  speech. If it does, **text labels alone are not enough** and category
  identity has to carry in color, shape, or icon. This materially changes
  the design and is the highest-value question to get answered.
- Vision, and whether the phone's system font scaling is in use.

Conditions: outdoors and in restaurants, so glare and low light both.
Under time pressure, with a stranger waiting — which is exactly when
fine motor control and word-finding are worst.

---

## What exists today

**There is essentially no design system.** The entire visual
specification in the codebase is one line:

```dart
ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal)
```

Everything else — type, spacing, elevation, component shape — is stock
Material 3 default. Nothing has been designed. That is not a constraint
to work within; it is the gap to fill. There are no brand assets, no
custom fonts, no tokens file, no logo.

The one deliberate visual decision so far is the launcher icon concept in
`assets/current-icon-concept.png`: a cream sock on a deep teal tile
(`#0B423F`) with coral cuff stripes (`#E8734A`). The teal was chosen to
tie to that `Colors.teal` seed. Treat it as a starting point, not a
constraint — including the palette.

### Screens

All four are in `source/` as real Flutter source. Read that rather than
trusting this summary — it is the ground truth, and exact values (spacing,
grid counts, tile structure) are in it.

| Screen | What's on it |
|---|---|
| **Home** (`home_screen.dart` + `AppShell` in `main.dart`) | AppBar with the app name and a settings icon; a 2-column grid of category tiles (plain `Card` + centered `headlineSmall` text); an extended FAB, "Say Something", with a mic icon |
| **Category** (`category_screen.dart`) | AppBar with the category name; 2-column grid of phrase tiles, each a `Card` with centered text. Tap plays. Long-press opens a "move to another category" picker. A phrase whose audio file is missing renders greyed and non-tappable |
| **Say Something** (`say_something_screen.dart`) | A text field, a "Speak" button that becomes a spinner + "Working..." during generation (cold voice-engine loads take up to ~90s), an error line, and a "Save to library" button that appears after a successful play |
| **Manage** (`manage_screen.dart`) | Caregiver screen. Category + phrase text fields, "Add phrase", "Sync library", a status line, and a flat `ListView` of every phrase with a delete icon |

Shared: `widgets/category_picker.dart` — the category chooser dialog,
used by both save and move flows, plus an inline "New category..." prompt.

### Known rough edges, worth designing away

- **Home has no empty state worth the name** — it renders the bare string
  "No phrases yet."
- **Manage is an undesigned admin list.** 76 phrases in one flat
  `ListView`, no grouping, no search. It is the caregiver's screen, so it
  can look different from the speaking screens — but it should not look
  unfinished.
- **Nothing distinguishes categories from each other** except their name.
  Eleven identical teal-ish cards.
- **"Emergency" sits in the same grid as "Small Talk"**, with the same
  weight, in alphabetical position. That is a real safety-relevant
  hierarchy problem.
- **Long-press to move a phrase is invisible.** No affordance hints it
  exists.

---

## What to design

In rough priority:

1. **Home / category / phrase tiles.** The two-tap core loop. Make
   categories distinguishable at a glance and make phrase tiles readable
   at arm's length in bad light. Tap targets should be generous — well
   past the 44px floor; these are the whole product.
2. **Emergency, given its own treatment.** Reachable faster than two taps
   if that can be done without making it easy to fire by accident.
3. **The launcher icon.** Square, ends up at 5 Android densities down to
   48×48px, so it must survive that. No wordmark in the icon.
4. **Say Something**, including the long-wait state — a cold voice-engine
   load can take the better part of a minute and currently shows a
   spinner and the word "Working...".
5. **Manage**, as a caregiver surface — grouping and finding among 76+
   phrases.

Name: **Aphasia SOX**. "SOX" reads as "socks" — a family inside joke about
reaching for a word and a different one arriving, which is what aphasia
does. The tone should carry that: warm and a bit funny, not clinical.
This is not a medical device; it is someone's own voice.

One caution on tone: the library includes blunt and profane phrases the
owner deliberately added. It is the user's own voice, not a care product's voice.
Design accordingly — dignity, not softness.

---

## Constraints a design has to survive

- **Flutter / Material 3.** Whatever is designed has to be buildable in
  Flutter widgets. Custom painting is possible but costs real effort.
- **Offline is the default.** Every saved phrase works with the phone in
  airplane mode. Nothing in the design may imply a connection is needed
  for the core loop.
- **Content is user-generated and grows.** Categories are created freely
  by the user from a text field, so a design that hand-assigns an icon or
  color per category needs a rule for categories that don't exist yet.
- **Category names are arbitrary length**, single line today, and can be
  anything they type.
- **Phrase text length varies a lot** — from "Yes." to "Aphasia means my
  brain has trouble finding words. I understand you, I just can't always
  speak easily." Both live in the same grid today.
