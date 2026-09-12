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
    focusColor: SoxTokens.red.withValues(alpha: 0.12),
    highlightColor: SoxTokens.red.withValues(alpha: 0.10),
    splashColor: SoxTokens.red.withValues(alpha: 0.14),
  );
}
