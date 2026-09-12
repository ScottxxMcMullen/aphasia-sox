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
  static Color majorRule(Color ink) => ink.withValues(alpha: 0.40);
  static Color minorRule(Color ink) => ink.withValues(alpha: 0.25);
  static Color muted(Color ink) => ink.withValues(alpha: 0.60);

  static const String fontFamily = 'Archivo';
}
