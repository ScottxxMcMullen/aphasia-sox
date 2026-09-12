# Theme pass — instructions for Claude Code

**Goal:** replace `ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal)` with the Aphasia SOX
theme (light + dark), and change nothing else. Every screen keeps its current widgets, layout,
navigation and copy. When this pass is done the app looks like the "after" frames in
`Theme Pass.dc.html`: paper ground, ink text, square hairline-bordered tiles, one red accent.

**Out of scope for this PR** — do not do these, they are later passes:

- No layout changes. The 2-column `GridView.count` at 16px stays 2-column at 16px.
- No pinned Emergency bar, no category ordering or sizing, no search, no Library screen.
- No new widgets (`SoxTile`, `SoxAppBar` etc.) and no changes to `home_screen.dart`,
  `category_screen.dart`, `manage_screen.dart`, `category_picker.dart`.
- No launcher icon, no app rename, no `flutter_tts` / sync / `LibraryStore` changes.
- The only screen file that changes is `say_something_screen.dart`, one line — see step 5.

---

## 1. Fonts — bundle Archivo as an asset

The app must theme correctly on first launch with no network (it already renders before the
first sync), so vendor the font rather than fetching it. Do **not** add `google_fonts`.

Download the static TTFs from Google Fonts (Archivo, Regular 400 / SemiBold 600 / ExtraBold 800)
into `assets/fonts/`:

```
assets/fonts/Archivo-Regular.ttf
assets/fonts/Archivo-SemiBold.ttf
assets/fonts/Archivo-ExtraBold.ttf
```

`pubspec.yaml`:

```yaml
flutter:
  uses-material-design: true
  fonts:
    - family: Archivo
      fonts:
        - asset: assets/fonts/Archivo-Regular.ttf
          weight: 400
        - asset: assets/fonts/Archivo-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/Archivo-ExtraBold.ttf
          weight: 800
```

## 2. New file — `lib/theme/sox_tokens.dart`

Every value the design uses, and nothing else. Nothing outside `lib/theme/` should ever write a
`Color(0x…)` again.

```dart
import 'package:flutter/material.dart';

/// The Aphasia SOX design tokens. Two grounds, one accent, two rule weights.
class SoxTokens {
  SoxTokens._();

  /// Grounds and ink. Dark mode is a second theme, not an inversion:
  /// the ground drops to the ink value and the ink lifts to near-paper.
  static const Color paper = Color(0xFFF3F2F2);
  static const Color ink = Color(0xFF201E1D);
  static const Color darkGround = Color(0xFF201E1D);
  static const Color darkInk = Color(0xFFF8F4F4);

  /// The one accent, identical in both themes — Emergency must read the
  /// same in a dark restaurant as in a car park at noon.
  static const Color red = Color(0xFFEC3013);
  static const Color redPressed = Color(0xFFAE1800);

  /// Disabled / missing-audio text. Not an opacity: a real grey that clears
  /// 4.5:1 on its own ground (light 4.9:1, dark 5.6:1). Three passes depend on
  /// this token for disabled, missing-audio and pending text — do not lighten it.
  static const Color greyOnPaper = Color(0xFF6B6767);
  static const Color greyOnDark = Color(0xFF9B9797);

  /// Rules. Structure is drawn with two weights and nothing else —
  /// major separates regions, minor separates rows.
  static const double ruleMajor = 2;
  static const double ruleMinor = 1;
  static Color majorRule(Color ink) => ink.withOpacity(0.40);
  static Color minorRule(Color ink) => ink.withOpacity(0.25);
  static Color muted(Color ink) => ink.withOpacity(0.60);

  static const String fontFamily = 'Archivo';
}
```

## 3. New file — `lib/theme/sox_theme.dart`

One builder, parameterised by brightness. Type scale: Archivo ExtraBold (800) for anything
that names a thing, Archivo Regular (400) for anything that is speech. Sizes are up on stock
Material because the reader is slower and further away — this is still theme-only, the grid
does not move.

```dart
import 'package:flutter/material.dart';

import 'sox_tokens.dart';

ThemeData soxLight() => _sox(Brightness.light);
ThemeData soxDark() => _sox(Brightness.dark);

ThemeData _sox(Brightness brightness) {
  final bool dark = brightness == Brightness.dark;
  final Color ground = dark ? SoxTokens.darkGround : SoxTokens.paper;
  final Color ink = dark ? SoxTokens.darkInk : SoxTokens.ink;
  final Color grey = dark ? SoxTokens.greyOnDark : SoxTokens.greyOnPaper;
  final Color major = SoxTokens.majorRule(ink);
  final Color minor = SoxTokens.minorRule(ink);

  final ColorScheme scheme = ColorScheme(
    brightness: brightness,
    primary: SoxTokens.red,
    onPrimary: dark ? SoxTokens.darkInk : SoxTokens.paper,
    secondary: ink,
    onSecondary: ground,
    surface: ground,
    onSurface: ink,
    error: dark ? SoxTokens.red : SoxTokens.redPressed,
    onError: dark ? SoxTokens.darkInk : SoxTokens.paper,
  );

  TextStyle heading(double size, {double spacing = -0.4}) => TextStyle(
        fontFamily: SoxTokens.fontFamily,
        fontWeight: FontWeight.w800,
        fontSize: size,
        height: 1.1,
        letterSpacing: spacing,
        color: ink,
      );
  TextStyle body(double size, {Color? color, FontWeight weight = FontWeight.w400}) => TextStyle(
        fontFamily: SoxTokens.fontFamily,
        fontWeight: weight,
        fontSize: size,
        height: 1.35,
        color: color ?? ink,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: ground,
    canvasColor: ground,
    fontFamily: SoxTokens.fontFamily,
    disabledColor: grey,
    dividerColor: minor,
    splashFactory: InkRipple.splashFactory,

    // Category tile labels come through headlineSmall (home_screen.dart:97);
    // phrase tiles and the Say Something field come through bodyLarge.
    textTheme: TextTheme(
      displaySmall: heading(34),
      headlineMedium: heading(30),
      headlineSmall: heading(26),
      titleLarge: heading(22, spacing: -0.2),
      titleMedium: body(17, weight: FontWeight.w600),
      bodyLarge: body(17),
      bodyMedium: body(15.5),
      bodySmall: body(13, color: SoxTokens.muted(ink)),
      labelLarge: TextStyle(
        fontFamily: SoxTokens.fontFamily,
        fontWeight: FontWeight.w800,
        fontSize: 15,
        letterSpacing: 0.2,
        color: ink,
      ),
    ),

    appBarTheme: AppBarTheme(
      backgroundColor: ground,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: heading(22, spacing: -0.2),
      iconTheme: IconThemeData(color: ink, size: 26),
      // The rule under the bar, drawn by the theme so no screen needs a bottom:.
      shape: Border(bottom: BorderSide(color: major, width: SoxTokens.ruleMajor)),
    ),

    // Tiles are line drawings: transparent, square, hairline-framed, no shadow.
    cardTheme: CardThemeData(
      color: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: major, width: SoxTokens.ruleMajor),
        borderRadius: BorderRadius.zero,
      ),
    ),

    // The FAB is the one solid object on the board.
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: SoxTokens.red,
      foregroundColor: dark ? SoxTokens.darkInk : SoxTokens.paper,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      extendedTextStyle: TextStyle(
        fontFamily: SoxTokens.fontFamily,
        fontWeight: FontWeight.w800,
        fontSize: 17,
        letterSpacing: 0.2,
        color: dark ? SoxTokens.darkInk : SoxTokens.paper,
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: SoxTokens.red,
        foregroundColor: dark ? SoxTokens.darkInk : SoxTokens.paper,
        disabledBackgroundColor: grey,
        disabledForegroundColor: ground,
        elevation: 0,
        minimumSize: const Size.fromHeight(56),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        textStyle: const TextStyle(
          fontFamily: SoxTokens.fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: 17,
          letterSpacing: 0.2,
        ),
      ).copyWith(
        overlayColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.pressed)
              ? SoxTokens.redPressed
              : null,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: dark ? SoxTokens.red : SoxTokens.redPressed,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        minimumSize: const Size(48, 48),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: ink,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        minimumSize: const Size(48, 48),
      ),
    ),

    // Fields are a line, not a filled pill.
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      labelStyle: body(16, color: SoxTokens.muted(ink)),
      floatingLabelStyle: TextStyle(
        fontFamily: SoxTokens.fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 13,
        letterSpacing: 0.4,
        color: dark ? SoxTokens.red : SoxTokens.redPressed,
      ),
      hintStyle: body(17, color: SoxTokens.muted(ink)),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: major, width: SoxTokens.ruleMajor),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: SoxTokens.red, width: SoxTokens.ruleMajor),
      ),
      errorStyle: body(14, color: dark ? SoxTokens.red : SoxTokens.redPressed),
    ),

    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      titleTextStyle: body(17),
      subtitleTextStyle: TextStyle(
        fontFamily: SoxTokens.fontFamily,
        fontWeight: FontWeight.w600,
        fontSize: 12,
        letterSpacing: 0.6,
        color: SoxTokens.muted(ink),
      ),
      iconColor: ink,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      minVerticalPadding: 10,
    ),

    dividerTheme: DividerThemeData(
      color: minor,
      thickness: SoxTokens.ruleMinor,
      space: 1,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: ground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: ink, width: SoxTokens.ruleMajor),
        borderRadius: BorderRadius.zero,
      ),
      titleTextStyle: heading(24),
      contentTextStyle: body(17),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      contentTextStyle: body(16, color: ground),
      actionTextColor: SoxTokens.red,
      behavior: SnackBarBehavior.fixed,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: SoxTokens.red,
      linearMinHeight: 4,
    ),

    // Keyboard focus is the accent, never the default blue.
    focusColor: SoxTokens.red.withOpacity(0.12),
    highlightColor: SoxTokens.red.withOpacity(0.10),
    splashColor: SoxTokens.red.withOpacity(0.14),
  );
}
```

## 4. `lib/main.dart` — three lines

```diff
 import 'package:flutter/material.dart';
+import 'theme/sox_theme.dart';
@@
     return MaterialApp(
       title: 'Aphasia App',
-      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
+      theme: soxLight(),
+      darkTheme: soxDark(),
+      themeMode: ThemeMode.system,
```

`ThemeMode.system` for now — the in-app light/dark/system switch belongs to the Library screen
pass, which does not exist yet.

## 5. The one hard-coded color in the app

`say_something_screen.dart:159` paints its error with `const TextStyle(color: Colors.red)`.
`Colors.red` is not the SOX red and never picks up dark mode. Change only this expression:

```diff
-                Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
+                Text(
+                  _errorMessage!,
+                  style: TextStyle(color: Theme.of(context).colorScheme.error),
+                ),
```

A repo-wide grep confirms this is the only one: the only other style references are
`Theme.of(context).textTheme.headlineSmall` (home_screen.dart:97) and
`Theme.of(context).disabledColor` (category_screen.dart:146), both of which now resolve to
SOX values with no edit.

---

## Definition of done — check on device, both themes

Run the app on the real phone at the system font size the user actually uses, once in light and once in
dark (`adb shell "cmd uimode night yes"` / `no`), and confirm:

1. Home — paper ground, no teal anywhere, category names in Archivo ExtraBold, tiles are
   square transparent boxes with a 2px rule, no drop shadow.
2. Home — the "Say Something" FAB is a square red block with paper text, no shadow.
3. Category (Emergency) — phrase text is Archivo Regular ~17px and wraps without clipping;
   the long "Aphasia means my brain…" tile still fits its box.
4. Category — a phrase with missing audio reads grey and stays untappable.
5. Long-press a phrase, move it — the picker dialog and the confirmation snackbar are both
   square, ink-on-paper (paper-on-ink in dark), no rounded Material shapes left.
6. Say Something — the field is an underline, focus turns the underline red, and a forced
   server error prints in the SOX red, not `Colors.red`.
7. Manage — "Add phrase" and "Sync library" are square red buttons, list rows are separated
   by a 1px rule, delete icons are ink.
8. Nothing anywhere still uses a rounded corner, a Material elevation shadow, or Roboto.
9. Kill and relaunch with the network off: Archivo still renders (the font is bundled, not fetched).

If a screen needs a layout change to satisfy one of these, stop and note it instead — layout
belongs to the next pass.
