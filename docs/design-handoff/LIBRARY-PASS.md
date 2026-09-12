# Library pass — instructions for Claude Code

**Prerequisite:** the theme pass is merged. Independent of passes 2 and 3.

**Goal:** replace `ManageScreen` with the `LibraryScreen` from design `1i` — grouped by category
with counts, searchable, with the two inline text fields moved into an "Add a phrase" dialog —
and add the light / dark / system theme switch.

**Why:** the current screen is a flat `ListView` of all 76 phrases in manifest order, with no
grouping, no search and no way to tell which category a run of rows belongs to without reading
each subtitle. It is also the only screen with permanently-visible text inputs, which pushes the
list into the bottom third of the display. Grouping and a search field make it a screen a
caregiver can actually maintain a library from.

**This is the caregiver's screen, not the speaker's.** Density is deliberately higher here than
anywhere else in the app: 15px phrase rows, 12px category headers. Do not apply the speaking
screens' type sizes.

**Files touched:** new `lib/screens/library_screen.dart` (replacing
`lib/screens/manage_screen.dart`), `lib/main.dart`, new `lib/services/settings_store.dart`.

**One new package:** `shared_preferences` — the theme choice and the last-sync time both have to
survive a restart. Nothing else is added.

---

## 1. `SettingsStore`

Two persisted values, one file. Keep it this narrow — it is not a general preferences layer.

```dart
import 'package:shared_preferences/shared_preferences.dart';

/// The two things the app remembers between launches.
class SettingsStore {
  static const _themeKey = 'theme_mode';
  static const _syncedKey = 'last_synced_at';

  Future<ThemeMode> themeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return switch (prefs.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }

  Future<DateTime?> lastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getInt(_syncedKey);
    return raw == null ? null : DateTime.fromMillisecondsSinceEpoch(raw);
  }

  Future<void> markSynced() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_syncedKey, DateTime.now().millisecondsSinceEpoch);
  }
}
```

Call `markSynced()` in `_sync()`'s success path, next to the existing `_statusMessage` set.

## 2. `themeMode` in `main.dart`

The app widget becomes stateful so the switch can change the mode live. Read the stored value in
`initState` and default to `ThemeMode.system` until it arrives — the first frame must not wait on
disk.

```dart
ThemeMode _themeMode = ThemeMode.system;

@override
void initState() {
  super.initState();
  widget.settingsStore.themeMode().then((mode) {
    if (mounted) setState(() => _themeMode = mode);
  });
}

// in build:
themeMode: _themeMode,
```

Pass `onThemeModeChanged` down to `LibraryScreen`; it calls `setState` here and
`SettingsStore.setThemeMode` to persist. Do not use a state-management package for one value.

## 3. Grouping and search

```dart
final _searchController = TextEditingController();
String _query = '';

/// Category name -> its phrases, ordered by count descending then
/// alphabetically, matching the home screen's ranking so the two screens
/// never disagree about which category is "first".
Map<String, List<PhraseEntry>> _grouped(List<PhraseEntry> entries) {
  final q = _query.trim().toLowerCase();
  final filtered = q.isEmpty
      ? entries
      : entries.where((e) =>
          e.text.toLowerCase().contains(q) ||
          e.category.toLowerCase().contains(q)).toList();

  final Map<String, List<PhraseEntry>> groups = {};
  for (final entry in filtered) {
    groups.putIfAbsent(entry.category, () => []).add(entry);
  }

  final keys = groups.keys.toList()
    ..sort((a, b) {
      final byCount = groups[b]!.length.compareTo(groups[a]!.length);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  return {for (final k in keys) k: groups[k]!};
}
```

Searching matches phrase text **and** category name, so typing "emerg" finds the whole category.
Wire `_searchController` to `setState(() => _query = value)` via `onChanged` — no debounce needed
for 76 local rows. Dispose it, along with the other controllers.

When the filter returns nothing, show a single line in place of the list: "No phrases match
'{query}'." at `bodyMedium`, muted, padded 24px. No illustration, no button.

## 4. The header block

Under the app bar, above the list, in a 2px-ruled block:

- A search field, `hintText: 'Search phrases'`, no label. Prefix a 20px search icon.
- A row: `ElevatedButton('Add a phrase')`, `OutlinedButton('Sync')`, then right-aligned
  two-line sync meta at 12px muted: relative last-sync time, and the last sync's result.

The meta strings, both from real values — `SettingsStore.lastSyncedAt()` and the count `_sync()`
already returns:

```dart
String _relative(DateTime? at) {
  if (at == null) return 'Never synced';
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'Synced just now';
  if (d.inMinutes < 60) return 'Synced ${d.inMinutes} min ago';
  if (d.inHours < 24) return 'Synced ${d.inHours} hour${d.inHours == 1 ? '' : 's'} ago';
  return 'Synced ${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
}
```

Only `Add a phrase` is the filled red button. `Sync` is outlined — one solid accent per screen.

The app bar's right side carries the totals at 12px muted: `'76 phrases · 11 categories'`, built
from the manifest, not hard-coded.

## 5. Category headers and phrase rows

```dart
// Category header: a tinted band, sticky is not required.
Container(
  color: dark ? SoxTokens.darkInk.withOpacity(0.06) : const Color(0xFFEAE9E9),
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  child: Row(children: [
    Text(category.toUpperCase(), style: TextStyle(
      fontFamily: SoxTokens.fontFamily, fontWeight: FontWeight.w800,
      fontSize: 12, letterSpacing: 1.2, color: ink)),
    const Spacer(),
    Text('${phrases.length}', style: Theme.of(context).textTheme.bodySmall),
  ]),
)
```

The band takes a 2px top rule (except the first) and a 1px bottom rule. Phrase rows below it:
text at `bodyMedium` (15px), a 1px bottom rule, and a 44px delete `IconButton` — the existing
`_delete(entry.id)`, unchanged.

A phrase with no audio gets a small outlined red tag reading `no audio` between the text and the
delete button, and its text drops to the grey token. `PhraseEntry` already exposes what
`category_screen.dart:146` tests for — use the same check, don't invent a second one.

Build the whole thing as one `ListView` of flattened children (headers and rows interleaved)
rather than nested scrollables.

## 6. Add a phrase, as a dialog

Delete the two inline `TextField`s. `Add a phrase` opens a dialog: a single autofocused text
field for the phrase, then — on submit — the **existing** `showCategoryPicker` from
`category_picker.dart` to choose the category. Do not write a second category input; the picker
already canonicalises case ("church" vs "Church") and offers "New category...".

On confirm, run the current `_addPhrase()` body unchanged (`addPhrase` → `getPhraseAudio` →
`saveEntry` → `_reload`), with the text and category coming from the dialog rather than the
controllers. Keep every error path and the status message exactly as they are.

## 7. The theme switch

At the bottom of the list, after the last category, in a block separated by a 2px rule:

- An 11px letterspaced caption: `APPEARANCE`.
- Three square segmented options — `Light`, `Dark`, `System` — 48px tall, 2px ink border,
  the selected one filled ink with paper text. Not a Material `SegmentedButton`; square corners
  and the ink fill are the point. Selecting one calls `onThemeModeChanged` immediately.

Placement at the bottom is deliberate: it is set once and never again, and it must not take space
above the library it is a footnote to.

## 8. Route and naming

Rename the class and file (`ManageScreen` → `LibraryScreen`, `manage_screen.dart` →
`library_screen.dart`), update the settings-icon route in `home_screen.dart`, and change the app
bar title to `Library`. Delete `manage_screen.dart`. Leave `LibraryStore`, `SyncService` and
`ApiClient` untouched — only the screen changes.

---

## Definition of done — check on device, both themes

1. Phrases are grouped under category headers with correct counts, in the same order the home
   screen ranks them.
2. Typing "emerg" shows the whole Emergency group; typing "water" shows the single phrase under
   its category header; typing nonsense shows the no-match line and nothing else.
3. The app bar total matches the real manifest (76 phrases · 11 categories today).
4. Sync updates the relative time to "Synced just now"; kill and relaunch — it reads "Synced N
   min ago", not "Never synced".
5. Add a phrase: the dialog takes the text, the existing picker takes the category, "church"
   lands in an existing "Church" rather than creating a duplicate, and the row appears in the
   right group.
6. Delete still removes a row immediately and survives a reload.
7. A phrase with no audio shows the `no audio` tag and grey text.
8. The appearance switch changes the theme instantly; relaunch and the choice holds. With
   System selected, flipping the OS setting flips the app.
9. `Add a phrase` is the only filled red button on the screen.
10. Light and dark, and at the system's largest font scale.
