import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aphasia_app/models/phrase_entry.dart';
import 'package:aphasia_app/screens/say_something_screen.dart';
import 'package:aphasia_app/services/api_client.dart';
import 'package:aphasia_app/services/audio_playback_service.dart';
import 'package:aphasia_app/services/library_store.dart';

class FakeAudioPlaybackService implements AudioPlaybackService {
  final List<String> playedPaths = [];

  @override
  Future<void> playFile(File file) async {
    playedPaths.add(file.path);
  }
}

// `SaySomethingScreen`'s onPressed handlers do real dart:io file writes
// (a temp preview file in `_speak`, and `LibraryStore.saveEntry`'s audio +
// manifest writes in `_saveToLibrary`). Real dart:io I/O awaited inside a
// fire-and-forget Future (an `onPressed: VoidCallback` is never awaited by
// the framework, so the async handler it kicks off is exactly that) never
// resolves under Flutter test binding's FakeAsync zone. `tester.runAsync()`
// steps outside that zone; the tap that starts the handler and a short
// trailing real delay must be inside the SAME runAsync call so the
// detached Future is actually serviced.
//
// Deliberately `pump()`, not `pumpAndSettle()`, afterwards: a success path
// here shows a SnackBar, whose auto-dismiss timer gets created while still
// inside runAsync's real zone. `pumpAndSettle()` would then wait for that
// timer to fire before returning, but once runAsync has returned control
// to the FakeAsync zone, nothing services a real-zone timer any more, so
// the wait never ends. A single `pump()` is enough to flush the setState
// this test cares about without waiting on unrelated animations.
// See https://api.flutter.dev/flutter/flutter_test/WidgetTester/runAsync.html.
Future<void> _tapAndLetRealIoSettle(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
}

// Like `_tapAndLetRealIoSettle`, but for a tap whose fire-and-forget chain
// hops through several real awaits (here: two more network round trips
// plus a manifest + audio file write in `LibraryStore.saveEntry`). A fixed
// delay is a race under load — running the full suite (multiple test
// files' real file I/O contending for the disk) can make that chain take
// longer than a short fixed sleep, and if the test body (and then
// `tearDown`, which deletes the shared temp dir) moves on before the
// write actually lands, `saveEntry`'s rename fails with a `PathAccessException`
// after the test has already reported its result. Polling for the actual
// expected outcome inside the same runAsync call avoids guessing a delay.
// `expectedId` is the specific phrase id we're waiting for (e.g. 'p9').
Future<List<PhraseEntry>> _tapAndWaitForManifest(
  WidgetTester tester,
  Finder finder,
  LibraryStore store,
  String expectedId,
) async {
  var manifest = <PhraseEntry>[];
  await tester.runAsync(() async {
    await tester.tap(finder);
    for (var i = 0; i < 100; i++) {
      manifest = await store.manifest();
      if (manifest.any((entry) => entry.id == expectedId)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pump();
  return manifest;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('say_something_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('typing text and tapping Speak plays the returned audio', (tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/health') {
        return http.Response('{"status":"ok"}', 200);
      }
      expect(request.url.path, '/generate');
      return http.Response.bytes([1, 2, 3], 200);
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final store = LibraryStore(tempDir);
    final playback = FakeAudioPlaybackService();

    await tester.pumpWidget(MaterialApp(
      home: SaySomethingScreen(
        apiClient: apiClient,
        libraryStore: store,
        audioPlaybackService: playback,
        categories: const ['Greetings'],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Hello there.');
    await _tapAndLetRealIoSettle(tester, find.text('SPEAK IT'));

    expect(playback.playedPaths, hasLength(1));
  });

  testWidgets('shows an error message when the server is unreachable', (tester) async {
    final mockClient = MockClient((request) async => throw Exception('connection refused'));
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final store = LibraryStore(tempDir);
    final playback = FakeAudioPlaybackService();

    await tester.pumpWidget(MaterialApp(
      home: SaySomethingScreen(
        apiClient: apiClient,
        libraryStore: store,
        audioPlaybackService: playback,
        categories: const ['Greetings'],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Hello there.');
    await tester.tap(find.text('SPEAK IT'));
    await tester.pumpAndSettle();

    // A failed ping is a different problem from a failed generation, and the
    // panel says which: this one is fixed by going and waking a machine.
    expect(find.text('COULD NOT REACH THE LAPTOP'), findsOneWidget);
    expect(find.text('SOMETHING WENT WRONG'), findsNothing);
    expect(
      find.textContaining('The laptop at home may be asleep'),
      findsOneWidget,
    );
    // The point of the panel: a failure costs a new sentence, not the voice.
    expect(
      find.textContaining('Saved phrases still work'),
      findsOneWidget,
    );
    expect(playback.playedPaths, isEmpty);
  });

  testWidgets('a generation failure is not reported as an unreachable laptop',
      (tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/health') {
        return http.Response('{"status":"ok"}', 200);
      }
      return http.Response('voicebox is wedged', 502);
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

    await tester.pumpWidget(MaterialApp(
      home: SaySomethingScreen(
        apiClient: apiClient,
        libraryStore: LibraryStore(tempDir),
        audioPlaybackService: FakeAudioPlaybackService(),
        categories: const ['Greetings'],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Hello there.');
    await tester.tap(find.text('SPEAK IT'));
    await tester.pumpAndSettle();

    expect(find.text('SOMETHING WENT WRONG'), findsOneWidget);
    expect(find.text('COULD NOT REACH THE LAPTOP'), findsNothing);
  });

  testWidgets('the wait shows real stages and never a predicted finish',
      (tester) async {
    final generation = Completer<http.Response>();
    final mockClient = MockClient((request) async {
      if (request.url.path == '/health') {
        return http.Response('{"status":"ok"}', 200);
      }
      return generation.future;
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

    await tester.pumpWidget(MaterialApp(
      home: SaySomethingScreen(
        apiClient: apiClient,
        libraryStore: LibraryStore(tempDir),
        audioPlaybackService: FakeAudioPlaybackService(),
        categories: const ['Greetings'],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Hello there.');
    // The chain has to start in the real zone: it ends in a real temp-file
    // write, and a Future's zone is fixed where it starts. The ping resolves
    // inside this call, leaving the request parked on the generation.
    await tester.runAsync(() async {
      await tester.tap(find.text('SPEAK IT'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();

    expect(find.text('Reached the laptop at home'), findsOneWidget);
    expect(find.text('Building your voice'), findsOneWidget);
    expect(find.text('Speaking'), findsOneWidget);
    expect(
      find.textContaining('takes about a minute'),
      findsOneWidget,
    );

    // Indeterminate on purpose. A bar with a `value` would be predicting a
    // completion the app cannot know — a cold engine load has no schedule.
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);

    // Finish inside runAsync: the completion path writes a real temp file,
    // and `pumpAndSettle` would never return anyway — an indeterminate bar
    // animates forever and the ticker is a repeating Timer. Both are the
    // design working as intended, so the test ends the request instead of
    // waiting for the screen to go quiet.
    await tester.runAsync(() async {
      generation.complete(http.Response.bytes([1, 2, 3], 200));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.text('SPOKEN IN YOUR VOICE'), findsOneWidget);
    expect(find.text('SAY SOMETHING ELSE'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('SAY SOMETHING ELSE clears the field and the spoken state',
      (tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path == '/health') {
        return http.Response('{"status":"ok"}', 200);
      }
      return http.Response.bytes([1, 2, 3], 200);
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);

    await tester.pumpWidget(MaterialApp(
      home: SaySomethingScreen(
        apiClient: apiClient,
        libraryStore: LibraryStore(tempDir),
        audioPlaybackService: FakeAudioPlaybackService(),
        categories: const ['Greetings'],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Hello there.');
    await _tapAndLetRealIoSettle(tester, find.text('SPEAK IT'));
    expect(find.text('SPOKEN IN YOUR VOICE'), findsOneWidget);

    await tester.tap(find.text('SAY SOMETHING ELSE'));
    await tester.pump();

    expect(find.text('SPOKEN IN YOUR VOICE'), findsNothing);
    expect(find.text('SPEAK IT'), findsOneWidget);
    // Cleared, rather than re-sending the same sentence on the next tap.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('saving after a successful speak downloads and stores the phrase', (tester) async {
    final requestedPaths = <String>[];
    final mockClient = MockClient((request) async {
      requestedPaths.add(request.url.path);
      if (request.url.path == '/health') {
        return http.Response('{"status":"ok"}', 200);
      }
      if (request.url.path == '/generate') {
        return http.Response.bytes([1, 2, 3], 200);
      }
      if (request.url.path == '/library/phrases') {
        return http.Response(
          jsonEncode({
            'id': 'p9',
            'category': 'Greetings',
            'text': 'Hello there.',
            'checksum': 'z',
          }),
          200,
        );
      }
      if (request.url.path == '/library/audio/p9') {
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw Exception('unexpected request: ${request.url}');
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final store = LibraryStore(tempDir);
    final playback = FakeAudioPlaybackService();

    await tester.pumpWidget(MaterialApp(
      home: SaySomethingScreen(
        apiClient: apiClient,
        libraryStore: store,
        audioPlaybackService: playback,
        categories: const ['Greetings'],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Hello there.');
    await _tapAndLetRealIoSettle(tester, find.text('SPEAK IT'));

    // Tapping "Save to library" kicks off `_showSaveDialog()` as an
    // unawaited (fire-and-forget) Future; tapping "Greetings" resumes its
    // suspended `await showDialog(...)` and, from there, runs
    // `_saveToLibrary`'s real network + file I/O.
    await _tapAndLetRealIoSettle(tester, find.text('Save to library'));
    final manifest = await _tapAndWaitForManifest(tester, find.text('Greetings'), store, 'p9');

    expect(requestedPaths, ['/health', '/generate', '/library/phrases', '/library/audio/p9']);
    expect(manifest.map((e) => e.id), ['p9']);
  });

  testWidgets('creating a new category from the save dialog saves into it', (tester) async {
    String? sentCategory;
    final mockClient = MockClient((request) async {
      if (request.url.path == '/health') {
        return http.Response('{"status":"ok"}', 200);
      }
      if (request.url.path == '/generate') {
        return http.Response.bytes([1, 2, 3], 200);
      }
      if (request.url.path == '/library/phrases') {
        sentCategory = (jsonDecode(request.body) as Map<String, dynamic>)['category'] as String;
        return http.Response(
          jsonEncode({
            'id': 'p10',
            'category': sentCategory,
            'text': 'See you at church.',
            'checksum': 'c',
          }),
          200,
        );
      }
      if (request.url.path == '/library/audio/p10') {
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw Exception('unexpected request: ${request.url}');
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final store = LibraryStore(tempDir);

    await tester.pumpWidget(MaterialApp(
      home: SaySomethingScreen(
        apiClient: apiClient,
        libraryStore: store,
        audioPlaybackService: FakeAudioPlaybackService(),
        categories: const ['Greetings'],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'See you at church.');
    await _tapAndLetRealIoSettle(tester, find.text('SPEAK IT'));

    await _tapAndLetRealIoSettle(tester, find.text('Save to library'));
    await _tapAndLetRealIoSettle(tester, find.text('New category...'));

    // The name prompt is a second dialog with its own field.
    await tester.enterText(find.byType(TextField).last, 'Church');
    final manifest =
        await _tapAndWaitForManifest(tester, find.text('Save'), store, 'p10');

    expect(sentCategory, 'Church');
    expect(manifest.single.category, 'Church');
  });

  testWidgets('a new category matching an existing one is reused, not duplicated', (tester) async {
    String? sentCategory;
    final mockClient = MockClient((request) async {
      if (request.url.path == '/health') {
        return http.Response('{"status":"ok"}', 200);
      }
      if (request.url.path == '/generate') {
        return http.Response.bytes([1, 2, 3], 200);
      }
      if (request.url.path == '/library/phrases') {
        sentCategory = (jsonDecode(request.body) as Map<String, dynamic>)['category'] as String;
        return http.Response(
          jsonEncode({
            'id': 'p11',
            'category': sentCategory,
            'text': 'Hello there.',
            'checksum': 'd',
          }),
          200,
        );
      }
      if (request.url.path == '/library/audio/p11') {
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw Exception('unexpected request: ${request.url}');
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final store = LibraryStore(tempDir);

    await tester.pumpWidget(MaterialApp(
      home: SaySomethingScreen(
        apiClient: apiClient,
        libraryStore: store,
        audioPlaybackService: FakeAudioPlaybackService(),
        categories: const ['Greetings'],
      ),
    ));

    await tester.enterText(find.byType(TextField), 'Hello there.');
    await _tapAndLetRealIoSettle(tester, find.text('SPEAK IT'));

    await _tapAndLetRealIoSettle(tester, find.text('Save to library'));
    await _tapAndLetRealIoSettle(tester, find.text('New category...'));

    // Differs from the existing "Greetings" only by case and padding.
    await tester.enterText(find.byType(TextField).last, '  greetings ');
    await _tapAndWaitForManifest(tester, find.text('Save'), store, 'p11');

    expect(sentCategory, 'Greetings');
  });
}

