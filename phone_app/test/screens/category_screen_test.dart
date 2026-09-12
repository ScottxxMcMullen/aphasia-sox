import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aphasia_app/models/phrase_entry.dart';
import 'package:aphasia_app/screens/category_screen.dart';
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
    tempDir = await Directory.systemTemp.createTemp('category_screen_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('tapping a phrase tile plays its audio file', (tester) async {
    final store = LibraryStore(tempDir);
    await tester.runAsync(() => store.saveEntry(
          const PhraseEntry(id: '1', category: 'Greetings', text: 'Hello.', checksum: 'a'),
          Uint8List.fromList([1, 2, 3]),
        ));
    final fakePlayback = FakeAudioPlaybackService();

    await pumpAndLetInitialLoadSettle(
      tester,
      MaterialApp(
        home: CategoryScreen(
          category: 'Greetings',
          libraryStore: store,
          audioPlaybackService: fakePlayback,
        ),
      ),
    );

    expect(find.text('Hello.'), findsOneWidget);

    await tester.tap(find.text('Hello.'));
    await tester.pumpAndSettle();

    expect(fakePlayback.playedPaths, hasLength(1));
    expect(fakePlayback.playedPaths.first, contains('1.wav'));
  });

  testWidgets('only shows phrases from the selected category', (tester) async {
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
        home: CategoryScreen(
          category: 'Greetings',
          libraryStore: store,
          audioPlaybackService: FakeAudioPlaybackService(),
        ),
      ),
    );

    expect(find.text('Hello.'), findsOneWidget);
    expect(find.text('Help.'), findsNothing);
  });

  testWidgets('a phrase with no local audio file is greyed out and not tappable', (tester) async {
    // Write a manifest entry directly, without ever writing its audio
    // file, to simulate an interrupted sync (per the spec's error
    // handling: such a tile must be greyed/hidden, not silently no-op).
    final store = LibraryStore(tempDir);
    final fakePlayback = FakeAudioPlaybackService();
    await tester.runAsync(() async {
      final manifestFile = File('${tempDir.path}/manifest.json');
      await manifestFile.writeAsString(jsonEncode([
        {'id': 'missing', 'category': 'Greetings', 'text': 'Ghost phrase', 'checksum': 'z'},
      ]));
    });

    await pumpAndLetInitialLoadSettle(
      tester,
      MaterialApp(
        home: CategoryScreen(
          category: 'Greetings',
          libraryStore: store,
          audioPlaybackService: fakePlayback,
        ),
      ),
    );

    expect(find.text('Ghost phrase'), findsOneWidget);

    await tester.tap(find.text('Ghost phrase'));
    await tester.pumpAndSettle();

    expect(fakePlayback.playedPaths, isEmpty);
  });

  group('moving a phrase', () {
    Future<void> pumpCategoryScreen(
      WidgetTester tester,
      LibraryStore store, {
      required String category,
    }) async {
      await pumpAndLetInitialLoadSettle(
        tester,
        MaterialApp(
          home: CategoryScreen(
            category: category,
            libraryStore: store,
            audioPlaybackService: FakeAudioPlaybackService(),
          ),
        ),
      );
    }

    // Pushes CategoryScreen onto a route stack rather than making it `home`,
    // so tests can tell whether emptying a category popped back.
    Future<void> pushCategoryScreen(
      WidgetTester tester,
      LibraryStore store, {
      required String category,
    }) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await pumpAndLetInitialLoadSettle(
        tester,
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Center(child: Text('behind'))),
        ),
      );
      await tester.runAsync(() async {
        navigatorKey.currentState!.push(MaterialPageRoute(
          builder: (_) => CategoryScreen(
            category: category,
            libraryStore: store,
            audioPlaybackService: FakeAudioPlaybackService(),
          ),
        ));
        // Build the pushed route so its `initState` starts the manifest read
        // here, inside the real zone. Without this pump the first build (and
        // so the dart:io read) happens back in the FakeAsync zone, where it
        // never resolves and the FutureBuilder's spinner animates forever —
        // which is what `pumpAndSettle` then waits on until it times out.
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    Future<LibraryStore> seedStore(WidgetTester tester, Directory dir) async {
      final store = LibraryStore(dir);
      await tester.runAsync(() async {
        await store.saveEntry(
          const PhraseEntry(id: '1', category: 'Greetings', text: 'Hello.', checksum: 'a'),
          Uint8List.fromList([1]),
        );
        await store.saveEntry(
          const PhraseEntry(id: '2', category: 'Greetings', text: 'Goodbye.', checksum: 'b'),
          Uint8List.fromList([2]),
        );
        await store.saveEntry(
          const PhraseEntry(id: '3', category: 'Needs', text: 'Help.', checksum: 'c'),
          Uint8List.fromList([3]),
        );
      });
      return store;
    }

    Future<String> categoryOf(LibraryStore store, String id) async {
      return (await store.manifest()).firstWhere((e) => e.id == id).category;
    }

    // Reading the manifest is real dart:io, so an assertion that reads it
    // must go through `runAsync` too. A bare `await store.manifest()` in a
    // test body looks harmless and hangs the whole run: the read is issued
    // in the FakeAsync zone, where it never completes and nothing times it
    // out.
    Future<String> readCategory(
      WidgetTester tester,
      LibraryStore store,
      String id,
    ) async {
      late String category;
      await tester.runAsync(() async {
        category = await categoryOf(store, id);
      });
      return category;
    }

    /// Enters move mode from the app bar. A plain `setState`, so a real tap
    /// works here — nothing in this step touches the disk.
    Future<void> enterMoveMode(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.drive_file_move_outline));
      await tester.pumpAndSettle();
    }

    // Calls the tile's own `onTap` instead of tapping it, because the two
    // halves of this interaction need opposite test zones and a Future's zone
    // is fixed where it starts: the dialog needs frames pumped, while `_move`
    // ends in real dart:io (`moveEntry`), which only resolves under
    // `runAsync`. Starting the chain from the callback inside `runAsync`
    // keeps the whole thing in the real zone.
    //
    // That the tile is actually wired to this callback is covered separately,
    // by 'a real tap in move mode opens the picker'.
    Future<void> openMovePicker(WidgetTester tester, String phrase) async {
      await enterMoveMode(tester);
      final tile = tester.widget<InkWell>(
        find.ancestor(of: find.text(phrase), matching: find.byType(InkWell)).first,
      );
      await tester.runAsync(() async {
        tile.onTap!();
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
    }

    testWidgets('a real tap in move mode opens the picker', (tester) async {
      final store = await seedStore(tester, tempDir);
      await pumpCategoryScreen(tester, store, category: 'Greetings');

      // A real gesture here, so the tile's wiring is under test rather than
      // the callback being invoked directly.
      await enterMoveMode(tester);
      await tester.tap(find.text('Hello.'));
      await tester.pumpAndSettle();

      expect(find.text('Move to which category?'), findsOneWidget);
      expect(find.text('Needs'), findsOneWidget);
      // The category being viewed is not offered — moving a phrase to where
      // it already is would do nothing.
      expect(
        find.descendant(of: find.byType(SimpleDialog), matching: find.text('Greetings')),
        findsNothing,
      );
    });

    // The reason this mode exists. Moving used to be a long press on the tile
    // that speaks, so holding a beat past Flutter's 500ms threshold rejected
    // the tap and opened a filing dialog instead of saying anything — on
    // Emergency as much as anywhere else.
    testWidgets('a long press outside move mode speaks and files nothing',
        (tester) async {
      final store = await seedStore(tester, tempDir);
      final fakePlayback = FakeAudioPlaybackService();
      await pumpAndLetInitialLoadSettle(
        tester,
        MaterialApp(
          home: CategoryScreen(
            category: 'Greetings',
            libraryStore: store,
            audioPlaybackService: fakePlayback,
          ),
        ),
      );

      await tester.longPress(find.text('Hello.'));
      await tester.pumpAndSettle();

      // The property that matters: with no long-press recognizer in the
      // arena, the tap wins on pointer-up however long the press was held,
      // so a firm press still speaks.
      expect(fakePlayback.playedPaths, hasLength(1));
      expect(find.text('Move to which category?'), findsNothing);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(await readCategory(tester, store, '1'), 'Greetings');
      expect(find.text('Hello.'), findsOneWidget);
    });

    testWidgets('a tile in move mode files instead of speaking', (tester) async {
      final store = await seedStore(tester, tempDir);
      final fakePlayback = FakeAudioPlaybackService();
      await pumpAndLetInitialLoadSettle(
        tester,
        MaterialApp(
          home: CategoryScreen(
            category: 'Greetings',
            libraryStore: store,
            audioPlaybackService: fakePlayback,
          ),
        ),
      );

      await enterMoveMode(tester);
      await tester.tap(find.text('Hello.'));
      await tester.pumpAndSettle();

      expect(find.text('Move to which category?'), findsOneWidget);
      // The whole point of the mode being explicit: while it is on, a tile
      // never speaks.
      expect(fakePlayback.playedPaths, isEmpty);
    });

    testWidgets('leaving move mode restores speaking', (tester) async {
      final store = await seedStore(tester, tempDir);
      final fakePlayback = FakeAudioPlaybackService();
      await pumpAndLetInitialLoadSettle(
        tester,
        MaterialApp(
          home: CategoryScreen(
            category: 'Greetings',
            libraryStore: store,
            audioPlaybackService: fakePlayback,
          ),
        ),
      );

      await enterMoveMode(tester);
      expect(find.text('Move a phrase'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Move a phrase'), findsNothing);
      await tester.tap(find.text('Hello.'));
      await tester.pumpAndSettle();
      expect(fakePlayback.playedPaths, hasLength(1));
    });

    testWidgets('a completed move leaves move mode', (tester) async {
      final store = await seedStore(tester, tempDir);
      await pumpCategoryScreen(tester, store, category: 'Greetings');

      await openMovePicker(tester, 'Hello.');
      await tapAndWaitFor(tester, find.text('Needs'), () async {
        return await categoryOf(store, '1') == 'Needs';
      });
      await tester.pump();

      // One move per visit — leaving the mode on would put the screen one
      // stray tap away from moving a second phrase.
      expect(find.text('Move a phrase'), findsNothing);
      expect(find.byIcon(Icons.drive_file_move_outline), findsOneWidget);
    });

    testWidgets('choosing a category moves the phrase and says so', (tester) async {
      final store = await seedStore(tester, tempDir);
      await pumpCategoryScreen(tester, store, category: 'Greetings');

      await openMovePicker(tester, 'Hello.');
      await tapAndWaitFor(tester, find.text('Needs'), () async {
        return await categoryOf(store, '1') == 'Needs';
      });

      expect(await readCategory(tester, store, '1'), 'Needs');

      // The poll above returns as soon as the write lands, which can be
      // before `_move` gets to its `setState`; `readCategory`'s runAsync
      // gives that the real time it needs, and this pump draws the result.
      await tester.pump();
      expect(find.text('Moved "Hello." to Needs.'), findsOneWidget);
      // Still on Greetings, which keeps its remaining phrase.
      expect(find.text('Goodbye.'), findsOneWidget);
      expect(find.text('Hello.'), findsNothing);
    });

    testWidgets('the audio file survives a move', (tester) async {
      final store = await seedStore(tester, tempDir);
      await pumpCategoryScreen(tester, store, category: 'Greetings');

      await openMovePicker(tester, 'Hello.');
      await tapAndWaitFor(tester, find.text('Needs'), () async {
        return await categoryOf(store, '1') == 'Needs';
      });

      await tester.runAsync(() async {
        expect(await store.audioFileFor('1')!.readAsBytes(), [1]);
      });
    });

    testWidgets('moving the last phrase out pops back to the grid', (tester) async {
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
      await pushCategoryScreen(tester, store, category: 'Greetings');

      await openMovePicker(tester, 'Hello.');
      await tapAndWaitFor(tester, find.text('Needs'), () async {
        return await categoryOf(store, '1') == 'Needs';
      });
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('behind'), findsOneWidget);
    });

    testWidgets('moving into a new category names it', (tester) async {
      final store = await seedStore(tester, tempDir);
      await pumpCategoryScreen(tester, store, category: 'Greetings');

      await openMovePicker(tester, 'Hello.');
      await tapAndLetRealIoSettle(tester, find.text('New category...'));
      await tester.enterText(find.byType(TextField), 'Church');
      await tapAndWaitFor(tester, find.text('Save'), () async {
        return await categoryOf(store, '1') == 'Church';
      });

      expect(await readCategory(tester, store, '1'), 'Church');
    });

    testWidgets('dismissing the picker leaves the phrase where it was', (tester) async {
      final store = await seedStore(tester, tempDir);
      await pumpCategoryScreen(tester, store, category: 'Greetings');

      await openMovePicker(tester, 'Hello.');
      // Tapping the barrier outside the dialog is how a mis-triggered
      // long-press gets backed out of.
      await tester.runAsync(() async {
        await tester.tapAt(const Offset(5, 5));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(await readCategory(tester, store, '1'), 'Greetings');
      expect(find.text('Hello.'), findsOneWidget);
    });
  });
}
