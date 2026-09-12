import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aphasia_app/widgets/category_picker.dart';

/// Pumps a bare screen with one button that opens the picker, and records
/// whatever the picker returns.
Future<List<String?>> _pumpPicker(
  WidgetTester tester, {
  required List<String> categories,
  String? exclude,
}) async {
  final results = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              results.add(await showCategoryPicker(
                context: context,
                categories: categories,
                title: 'Move to which category?',
                exclude: exclude,
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  group('canonicaliseCategory', () {
    test('returns an existing category when the typed name differs only by case', () {
      expect(canonicaliseCategory('church', ['Greetings', 'Church']), 'Church');
    });

    test('trims surrounding whitespace before matching', () {
      expect(canonicaliseCategory('  Church  ', ['Church']), 'Church');
    });

    test('returns the trimmed name when nothing matches', () {
      expect(canonicaliseCategory('  Church ', ['Greetings']), 'Church');
    });

    test('returns an empty string for a blank name', () {
      expect(canonicaliseCategory('   ', ['Greetings']), '');
    });
  });

  group('showCategoryPicker', () {
    testWidgets('returns the category the user taps', (tester) async {
      final results = await _pumpPicker(tester, categories: ['Greetings', 'Needs']);

      await tester.tap(find.text('Needs'));
      await tester.pumpAndSettle();

      expect(results, ['Needs']);
    });

    testWidgets('omits the excluded category', (tester) async {
      await _pumpPicker(
        tester,
        categories: ['Greetings', 'Needs'],
        exclude: 'Greetings',
      );

      expect(find.text('Greetings'), findsNothing);
      expect(find.text('Needs'), findsOneWidget);
    });

    testWidgets('returns null when the user dismisses the list', (tester) async {
      final results = await _pumpPicker(tester, categories: ['Greetings']);

      // Tapping the barrier outside the dialog is how a mis-tap gets undone.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(results, [null]);
    });

    testWidgets('New category... prompts for a name and returns it', (tester) async {
      final results = await _pumpPicker(tester, categories: ['Greetings']);

      await tester.tap(find.text('New category...'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Church');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(results, ['Church']);
    });

    testWidgets('a new name matching an existing category folds into it', (tester) async {
      final results = await _pumpPicker(tester, categories: ['Church', 'Greetings']);

      await tester.tap(find.text('New category...'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'church');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(results, ['Church']);
    });

    testWidgets('a blank new name returns null rather than an empty category', (tester) async {
      final results = await _pumpPicker(tester, categories: ['Greetings']);

      await tester.tap(find.text('New category...'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(results, [null]);
    });

    testWidgets('cancelling the name prompt returns null', (tester) async {
      final results = await _pumpPicker(tester, categories: ['Greetings']);

      await tester.tap(find.text('New category...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(results, [null]);
    });
  });
}
