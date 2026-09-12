import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aphasia_app/theme/sox_theme.dart';
import 'package:aphasia_app/theme/sox_tokens.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// WCAG 2.1 contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final double la = _luminance(a);
  final double lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  group('themes build', () {
    test('light and dark both construct with the SOX scheme', () {
      for (final theme in [soxLight(), soxDark()]) {
        expect(theme.useMaterial3, isTrue);
        expect(theme.colorScheme.primary, SoxTokens.red);
        expect(theme.textTheme.bodyLarge!.fontFamily, SoxTokens.fontFamily);
      }
      expect(soxLight().brightness, Brightness.light);
      expect(soxDark().brightness, Brightness.dark);
      expect(soxLight().scaffoldBackgroundColor, SoxTokens.paper);
      expect(soxDark().scaffoldBackgroundColor, SoxTokens.darkGround);
    });
  });

  group('contrast', () {
    // The disabled/missing-audio/pending grey is the one token three later
    // passes lean on, specifically because it is a real color rather than an
    // alpha — an alpha over these grounds lands near 2.75:1. If either of
    // these drops below 4.5:1 the token has been "tidied" into something that
    // no longer does its job.
    test('the grey tokens clear 4.5:1 on their own grounds', () {
      expect(_contrast(SoxTokens.greyOnPaper, SoxTokens.paper),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(SoxTokens.greyOnDark, SoxTokens.darkGround),
          greaterThanOrEqualTo(4.5));
    });

    test('body text is far clear of the floor in both themes', () {
      expect(_contrast(SoxTokens.ink, SoxTokens.paper), greaterThan(7));
      expect(_contrast(SoxTokens.darkInk, SoxTokens.darkGround), greaterThan(7));
    });

    // Red is the accent, and it is only ever spent on large bold type or on a
    // solid block. It does not clear 4.5:1 against paper, so it must never
    // become the color of ordinary running text — see redPressed, which does.
    test('redPressed is the one that clears 4.5:1 on paper', () {
      expect(_contrast(SoxTokens.redPressed, SoxTokens.paper),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(SoxTokens.red, SoxTokens.paper), lessThan(4.5));
    });
  });

  group('shape', () {
    test('nothing the theme styles has a rounded corner', () {
      for (final theme in [soxLight(), soxDark()]) {
        final shapes = <ShapeBorder?>[
          theme.cardTheme.shape,
          theme.dialogTheme.shape,
          theme.floatingActionButtonTheme.shape,
          theme.snackBarTheme.shape,
        ];
        for (final shape in shapes) {
          expect(shape, isA<RoundedRectangleBorder>());
          expect((shape! as RoundedRectangleBorder).borderRadius,
              BorderRadius.zero);
        }
      }
    });

    test('no component carries an elevation shadow', () {
      for (final theme in [soxLight(), soxDark()]) {
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.cardTheme.elevation, 0);
        expect(theme.dialogTheme.elevation, 0);
        expect(theme.floatingActionButtonTheme.elevation, 0);
        expect(theme.snackBarTheme.elevation, 0);
      }
    });
  });
}
