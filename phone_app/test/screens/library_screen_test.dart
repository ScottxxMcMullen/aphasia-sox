import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aphasia_app/models/phrase_entry.dart';
import 'package:aphasia_app/screens/library_screen.dart';
import 'package:aphasia_app/services/api_client.dart';
import 'package:aphasia_app/services/library_store.dart';
import 'package:aphasia_app/services/settings_store.dart';
import 'package:aphasia_app/services/sync_service.dart';

import '../test_helpers.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('library_screen_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<LibraryStore> seed(
    WidgetTester tester,
    Map<String, List<String>> byCategory, {
    Set<String> withoutAudio = const {},
  }) async {
    final store = LibraryStore(tempDir);
    await tester.runAsync(() async {
      var id = 0;
      for (final group in byCategory.entries) {
        for (final text in group.value) {
          id++;
          final entry = PhraseEntry(
            id: '$id',
            category: group.key,
            text: text,
            checksum: 'c$id',
          );
          await store.saveEntry(entry, Uint8List.fromList([id]));
          if (withoutAudio.contains(text)) {
            // Simulates an interrupted sync: the manifest row exists, the
            // audio file does not.
            await store.audioFileFor(entry.id)!.delete();
          }
        }
      }
    });
    return store;
  }

  Future<void> pumpLibrary(
    WidgetTester tester,
    LibraryStore store, {
    ThemeMode themeMode = ThemeMode.system,
    ValueChanged<ThemeMode>? onThemeModeChanged,
    http.Client? client,
  }) async {
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      client: client ?? MockClient((_) async => http.Response('[]', 200)),
    );
    await pumpAndLetInitialLoadSettle(
      tester,
      MaterialApp(
        home: LibraryScreen(
          apiClient: apiClient,
          libraryStore: store,
          syncService: SyncService(apiClient: apiClient, libraryStore: store),
          settingsStore: SettingsStore(),
          themeMode: themeMode,
          onThemeModeChanged: onThemeModeChanged ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('groups phrases under category headers with counts',
      (tester) async {
    final store = await seed(tester, {
      'Emergency': ['Call an ambulance.', 'I need help.', 'Call my family.'],
      'Greetings': ['Hello.'],
    });
    await pumpLibrary(tester, store);

    expect(find.text('EMERGENCY'), findsOneWidget);
    expect(find.text('GREETINGS'), findsOneWidget);
    expect(find.text('Call an ambulance.'), findsOneWidget);
    // Ranked by count like the home screen, so the two never disagree.
    expect(
      tester.getTopLeft(find.text('EMERGENCY')).dy,
      lessThan(tester.getTopLeft(find.text('GREETINGS')).dy),
    );
  });

  testWidgets('the app bar totals come from the manifest', (tester) async {
    final store = await seed(tester, {
      'Emergency': ['Call an ambulance.', 'I need help.'],
      'Greetings': ['Hello.'],
    });
    await pumpLibrary(tester, store);

    expect(find.text('3 phrases · 2 categories'), findsOneWidget);
  });

  group('search', () {
    testWidgets('matches the category name as well as the phrase',
        (tester) async {
      final store = await seed(tester, {
        'Emergency': ['Call an ambulance.', 'I need help.'],
        'Greetings': ['Hello.'],
      });
      await pumpLibrary(tester, store);

      // Typing part of a category name finds the whole category — none of
      // these phrases contain "emerg".
      await tester.enterText(find.byType(TextField).first, 'emerg');
      await tester.pump();

      expect(find.text('Call an ambulance.'), findsOneWidget);
      expect(find.text('I need help.'), findsOneWidget);
      expect(find.text('Hello.'), findsNothing);
    });

    testWidgets('matches phrase text', (tester) async {
      final store = await seed(tester, {
        'Emergency': ['Call an ambulance.', 'I need help.'],
        'Greetings': ['Hello.'],
      });
      await pumpLibrary(tester, store);

      await tester.enterText(find.byType(TextField).first, 'ambul');
      await tester.pump();

      expect(find.text('Call an ambulance.'), findsOneWidget);
      expect(find.text('I need help.'), findsNothing);
    });

    testWidgets('says so when nothing matches', (tester) async {
      final store = await seed(tester, {'Greetings': ['Hello.']});
      await pumpLibrary(tester, store);

      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pump();

      expect(find.text('No phrases match "zzzz".'), findsOneWidget);
      expect(find.text('Hello.'), findsNothing);
    });
  });

  testWidgets('a phrase with no audio is tagged and greyed', (tester) async {
    final store = await seed(
      tester,
      {'Greetings': ['Hello.', 'Goodbye.']},
      withoutAudio: {'Goodbye.'},
    );
    await pumpLibrary(tester, store);

    expect(find.text('no audio'), findsOneWidget);
  });

  testWidgets('deleting removes the row and the manifest entry',
      (tester) async {
    final store = await seed(tester, {'Greetings': ['Hello.']});
    await pumpLibrary(tester, store);

    expect(find.text('Hello.'), findsOneWidget);

    await tapAndWaitFor(tester, find.byIcon(Icons.delete_outline), () async {
      return (await store.manifest()).isEmpty;
    });
    // The store empties first; the row goes when the reloaded manifest
    // future resolves, which is a second read issued after the delete.
    await pumpUntil(tester, () => find.text('Hello.').evaluate().isEmpty);

    expect(find.text('Hello.'), findsNothing);
    expect(find.text('The library is empty. Sync or add a phrase.'),
        findsOneWidget);
  });

  group('appearance', () {
    testWidgets('reports the chosen mode', (tester) async {
      final store = await seed(tester, {'Greetings': ['Hello.']});
      final chosen = <ThemeMode>[];
      await pumpLibrary(tester, store, onThemeModeChanged: chosen.add);

      await tester.tap(find.text('Dark'));
      await tester.pump();
      expect(chosen, [ThemeMode.dark]);

      await tester.tap(find.text('Light'));
      await tester.pump();
      expect(chosen, [ThemeMode.dark, ThemeMode.light]);
    });

    testWidgets('is at the bottom, below the phrases', (tester) async {
      final store = await seed(tester, {'Greetings': ['Hello.']});
      await pumpLibrary(tester, store);

      // Set once and never again — it must not take space above the library
      // it is a footnote to.
      expect(
        tester.getTopLeft(find.text('APPEARANCE')).dy,
        greaterThan(tester.getTopLeft(find.text('Hello.')).dy),
      );
    });
  });

  testWidgets('sync records when it last ran', (tester) async {
    final store = await seed(tester, {'Greetings': ['Hello.']});
    await pumpLibrary(tester, store);

    expect(find.text('Never synced'), findsOneWidget);

    await tapAndWaitFor(tester, find.text('Sync'), () async {
      return await SettingsStore().lastSyncedAt() != null;
    });
    await tester.pump();

    expect(find.text('Synced just now'), findsOneWidget);
    expect(find.text('Never synced'), findsNothing);
  });

  test('relative sync times read as english', () {
    final now = DateTime.now();
    expect(LibraryScreen.relativeSyncFor(null), 'Never synced');
    expect(
      LibraryScreen.relativeSyncFor(now.subtract(const Duration(seconds: 20))),
      'Synced just now',
    );
    expect(
      LibraryScreen.relativeSyncFor(now.subtract(const Duration(minutes: 5))),
      'Synced 5 min ago',
    );
    expect(
      LibraryScreen.relativeSyncFor(now.subtract(const Duration(hours: 1))),
      'Synced 1 hour ago',
    );
    expect(
      LibraryScreen.relativeSyncFor(now.subtract(const Duration(hours: 5))),
      'Synced 5 hours ago',
    );
    expect(
      LibraryScreen.relativeSyncFor(now.subtract(const Duration(days: 1))),
      'Synced 1 day ago',
    );
    expect(
      LibraryScreen.relativeSyncFor(now.subtract(const Duration(days: 3))),
      'Synced 3 days ago',
    );
  });
}
