import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aphasia_app/models/phrase_entry.dart';
import 'package:aphasia_app/screens/home_screen.dart';
import 'package:aphasia_app/services/audio_playback_service.dart';
import 'package:aphasia_app/services/library_store.dart';

import '../test_helpers.dart';

class FakeAudioPlaybackService implements AudioPlaybackService {
  final List<String> playedPaths = [];

  @override
  Future<void> playFile(File file) async {
    playedPaths.add(file.path);
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('home_screen_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('shows one tile per distinct category', (tester) async {
    final store = LibraryStore(tempDir);
    await tester.runAsync(() async {
      await store.saveEntry(
        const PhraseEntry(id: '1', category: 'Greetings', text: 'Hello.', checksum: 'a'),
        Uint8List.fromList([1]),
      );
      await store.saveEntry(
        const PhraseEntry(id: '2', category: 'Needs', text: 'Help.', checksum: 'b'),
        Uint8List.fromList([2]),
      );
    });

    await pumpAndLetInitialLoadSettle(
      tester,
      MaterialApp(
        home: HomeScreen(
          libraryStore: store,
          audioPlaybackService: FakeAudioPlaybackService(),
        ),
      ),
    );

    expect(find.text('Greetings'), findsOneWidget);
    expect(find.text('Needs'), findsOneWidget);
  });

  group('ranking', () {
    /// Seeds [counts] phrases per category so the ranking and the size ramp
    /// have something real to sort.
    Future<LibraryStore> seed(
      WidgetTester tester,
      Directory dir,
      Map<String, int> counts,
    ) async {
      final store = LibraryStore(dir);
      await tester.runAsync(() async {
        var id = 0;
        for (final entry in counts.entries) {
          for (var i = 0; i < entry.value; i++) {
            id++;
            await store.saveEntry(
              PhraseEntry(
                id: '$id',
                category: entry.key,
                text: 'Phrase $id',
                checksum: 'c$id',
              ),
              Uint8List.fromList([id]),
            );
          }
        }
      });
      return store;
    }

    Future<void> pumpHome(WidgetTester tester, LibraryStore store) =>
        pumpAndLetInitialLoadSettle(
          tester,
          MaterialApp(
            home: Scaffold(
              body: HomeScreen(
                libraryStore: store,
                audioPlaybackService: FakeAudioPlaybackService(),
              ),
            ),
          ),
        );

    double rowY(WidgetTester tester, String category) =>
        tester.getTopLeft(find.byKey(ValueKey('category-$category'))).dy;

    test('the size ramp is five steps, floored at 25', () {
      expect(rowMetrics(12).fontSize, 36);
      expect(rowMetrics(9).fontSize, 36);
      expect(rowMetrics(8).fontSize, 32);
      expect(rowMetrics(7).fontSize, 29);
      expect(rowMetrics(6).fontSize, 27);
      expect(rowMetrics(5).fontSize, 25);
      expect(rowMetrics(1).fontSize, 25);
      // Below 25 a name stops being a target you can hit at arm's length on
      // a moving bus, so the ramp floors rather than continuing down.
      for (final count in [1, 5, 6, 7, 8, 9, 40]) {
        expect(rowMetrics(count).fontSize, greaterThanOrEqualTo(25));
        expect(rowMetrics(count).minHeight, greaterThanOrEqualTo(76));
      }
    });

    testWidgets('rows rank by count descending, ties alphabetical', (tester) async {
      final store = await seed(tester, tempDir, {
        'Medical': 4,
        'Answers': 9,
        'Greetings': 8,
        'Feelings': 8,
        'Needs': 7,
      });
      await pumpHome(tester, store);

      // Feelings and Greetings are tied at 8 — alphabetical inside the tie,
      // so the order is stable when the library reloads.
      expect(rowY(tester, 'Answers'), lessThan(rowY(tester, 'Feelings')));
      expect(rowY(tester, 'Feelings'), lessThan(rowY(tester, 'Greetings')));
      expect(rowY(tester, 'Greetings'), lessThan(rowY(tester, 'Needs')));
      expect(rowY(tester, 'Needs'), lessThan(rowY(tester, 'Medical')));
    });

    testWidgets('Emergency is pinned above the list, not ranked in it',
        (tester) async {
      final store = await seed(tester, tempDir, {
        'Emergency': 7,
        'Answers': 9,
        'Medical': 4,
      });
      await pumpHome(tester, store);

      // Once, as the bar — the ranked list must not carry it as well.
      expect(find.text('EMERGENCY'), findsOneWidget);
      expect(find.byKey(const ValueKey('category-Emergency')), findsNothing);

      // Above Answers, which outranks it 9 to 7 — being pinned beats count.
      final double barY = tester.getTopLeft(find.text('EMERGENCY')).dy;
      expect(barY, lessThan(rowY(tester, 'Answers')));
    });

    testWidgets('no Emergency category means no bar', (tester) async {
      final store = await seed(tester, tempDir, {'Answers': 9, 'Medical': 4});
      await pumpHome(tester, store);

      expect(find.text('EMERGENCY'), findsNothing);
      expect(find.byKey(const ValueKey('category-Answers')), findsOneWidget);
    });

    testWidgets('each row shows its phrase count', (tester) async {
      final store = await seed(tester, tempDir, {'Answers': 9, 'Medical': 4});
      await pumpHome(tester, store);

      expect(find.text('9'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
    });
  });

  testWidgets('shows a message when the library is empty', (tester) async {
    final store = LibraryStore(tempDir);

    await pumpAndLetInitialLoadSettle(
      tester,
      MaterialApp(
        home: HomeScreen(
          libraryStore: store,
          audioPlaybackService: FakeAudioPlaybackService(),
        ),
      ),
    );

    expect(find.text('No phrases yet.'), findsOneWidget);
  });
}
