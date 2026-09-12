# Home layout pass — instructions for Claude Code

**Prerequisite:** the theme pass (`THEME-PASS.md`) is merged. Colors, Archivo and the rule
weights already come from `lib/theme/`. This pass adds no new colors and no new fonts.

**Goal:** replace the 2-column category grid with the ranked ledger from design `1a` — full-width
rows, type size carrying the rank, Emergency pinned above the list, Say Something pinned below.
When this lands, Home matches the `1a` frame in `Aphasia SOX.dc.html`.

**Why it changes:** with 11 categories the alphabetical grid puts Emergency second by accident
and gives it exactly the same weight as Small Talk. Rank is the whole point of the screen — the
category you need in a crisis should be the largest thing on it and reachable without a scroll.

**Files touched:** `lib/screens/home_screen.dart`, and the `Scaffold` that hosts it (the FAB
moves into a bottom bar). Nothing else. Category, Say Something, Manage and the picker keep
their current layouts — those are later passes.

---

## 1. Rank instead of sort

`home_screen.dart` currently builds the category list as a sorted set:

```dart
final categories = <String>{
  for (final entry in snapshot.data!) entry.category,
}.toList()
  ..sort();
```

Replace it with a count per category, ranked by count descending and alphabetically within a
tie, with Emergency pulled out of the list entirely:

```dart
const String kEmergency = 'Emergency';

final Map<String, int> counts = <String, int>{};
for (final entry in snapshot.data!) {
  counts.update(entry.category, (n) => n + 1, ifAbsent: () => 1);
}

final bool hasEmergency = counts.containsKey(kEmergency);
final List<MapEntry<String, int>> ranked = counts.entries
    .where((e) => e.key != kEmergency)
    .toList()
  ..sort((a, b) {
    final int byCount = b.value.compareTo(a.value);
    return byCount != 0 ? byCount : a.key.compareTo(b.key);
  });
```

Ties are alphabetical so the order is stable across syncs — Feelings, Greetings, How to Talk to
Me and Ordering Food all sit at 8 today, and they must not shuffle when the library reloads.

## 2. The size ramp

Type size and row height both come from the phrase count. Five steps, no interpolation — a
continuous scale would produce sizes that differ by a point and read as a mistake rather than a
rank.

```dart
/// Row metrics by phrase count. Five steps: the ramp is a rank, not a measurement.
({double fontSize, double minHeight}) _rowMetrics(int count) {
  if (count >= 9) return (fontSize: 36, minHeight: 104);
  if (count == 8) return (fontSize: 32, minHeight: 96);
  if (count == 7) return (fontSize: 29, minHeight: 88);
  if (count == 6) return (fontSize: 27, minHeight: 82);
  return (fontSize: 25, minHeight: 76);
}
```

25px is the floor — below that a category name stops being a target you can hit at arm's length
on a moving bus. If a future category ever exceeds 12 phrases the top step still caps at 36.

## 3. The row

A full-width row, name flush left, count flush right, 2px rule underneath. No card, no tile, no
border box — the rules do the separating.

```dart
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.count,
    required this.onTap,
  });

  final String category;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = _rowMetrics(count);
    final Color ink = Theme.of(context).colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: metrics.minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: SoxTokens.majorRule(ink), width: SoxTokens.ruleMajor),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                category,
                style: TextStyle(
                  fontFamily: SoxTokens.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: metrics.fontSize,
                  height: 1.02,
                  letterSpacing: -0.02 * metrics.fontSize,
                  color: ink,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$count',
              style: TextStyle(
                fontFamily: SoxTokens.fontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: SoxTokens.muted(ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

The count is information for whoever maintains the library, not for the speaker — keep it at
14px muted. It must never compete with the name.

## 4. Emergency, pinned

Emergency is not a row. It is a solid red bar directly under the app bar, above the scroll, 80px
minimum, always on screen. Tapping it opens `CategoryScreen(category: 'Emergency')` — the same
navigation the row used, so nothing downstream changes.

```dart
class _EmergencyBar extends StatelessWidget {
  const _EmergencyBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color paper = Theme.of(context).colorScheme.onPrimary;
    return Material(
      color: SoxTokens.red,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 80),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Text(
                'EMERGENCY',
                style: TextStyle(
                  fontFamily: SoxTokens.fontFamily,
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                  height: 1,
                  letterSpacing: -0.32,
                  color: paper,
                ),
              ),
              const Spacer(),
              Icon(Icons.arrow_forward, size: 26, color: paper),
            ],
          ),
        ),
      ),
    );
  }
}
```

Render it only when `hasEmergency` is true. If the library ever syncs without an Emergency
category the bar disappears rather than opening an empty screen.

## 5. Assembling the screen

`GridView.count` becomes a `Column` of two pinned pieces around a scrolling `ListView`:

```dart
return Column(
  children: [
    if (hasEmergency)
      _EmergencyBar(
        onTap: () => _openCategory(context, kEmergency),
      ),
    Expanded(
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: ranked.length,
        itemBuilder: (context, i) => _CategoryRow(
          category: ranked[i].key,
          count: ranked[i].value,
          onTap: () => _openCategory(context, ranked[i].key),
        ),
      ),
    ),
  ],
);
```

Pull the existing push-and-reload out of the tile into one method so both the bar and the rows
use it — the `_reload()` after the pop must survive, or an edit made in Manage won't show up:

```dart
Future<void> _openCategory(BuildContext context, String category) async {
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => CategoryScreen(
        category: category,
        libraryStore: widget.libraryStore,
        audioPlaybackService: widget.audioPlaybackService,
      ),
    ),
  );
  _reload();
}
```

`ListView.builder` rather than `ListView` with children: the row list is short today but the
library grows, and the pinned bar means the scroll view no longer sizes itself.

## 6. Say Something moves from FAB to bottom bar

In the `Scaffold` that hosts `HomeScreen`, remove `floatingActionButton` and set
`bottomNavigationBar` instead. Same `onPressed`, same destination — only the shape changes.

```dart
bottomNavigationBar: Container(
  decoration: BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    border: Border(
      top: BorderSide(
        color: SoxTokens.majorRule(Theme.of(context).colorScheme.onSurface),
        width: SoxTokens.ruleMajor,
      ),
    ),
  ),
  padding: const EdgeInsets.all(12),
  child: SizedBox(
    height: 76,
    child: ElevatedButton.icon(
      onPressed: _openSaySomething,   // unchanged
      icon: const Icon(Icons.mic_none, size: 26),
      label: const Text('SAY SOMETHING'),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(76),
        textStyle: const TextStyle(
          fontFamily: SoxTokens.fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 22,
          letterSpacing: 0.22,
        ),
      ),
    ),
  ),
),
```

The 2px top rule on the bar's container — in the snippet above — makes the region read as pinned
rather than a button floating over the list. A FAB overlaps the last row and hides part of it;
a bar does not, which matters when the last row is a category rather than dead space.

## 7. Keep the app bar as it is

Title, settings action and the 2px bottom rule already come from `appBarTheme`. Renaming
"Aphasia App" to the SOX wordmark is the launcher-icon pass, not this one.

---

## Definition of done — check on device, both themes

1. Emergency is a red bar under the app bar, on screen without scrolling, and does not appear
   twice (it must be gone from the ranked list).
2. Category order is Answers, Feelings, Greetings, How to Talk to Me, Ordering Food, Needs,
   Getting Around, Out & About, Small Talk, Medical — count descending, alphabetical inside ties.
3. Answers renders at 36px and Medical at 25px; no row is smaller than 25px or shorter than 76px.
4. Reload the library twice — the order does not change.
5. Say Something is a full-width red bar at the bottom with a rule above it, and the last
   category row is fully visible above it, not overlapped.
6. Tap Emergency and tap a row: both land on the same `CategoryScreen` they did before, and
   returning still refreshes the list.
7. A long category name ("How to Talk to Me") stays on one line at its ranked size; if it wraps,
   report it rather than dropping the size below 25px.
8. Both light and dark, and at the system's largest font scale.
