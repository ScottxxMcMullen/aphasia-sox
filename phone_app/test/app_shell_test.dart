import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aphasia_app/main.dart';
import 'package:aphasia_app/models/phrase_entry.dart';
import 'package:aphasia_app/services/api_client.dart';
import 'package:aphasia_app/services/audio_playback_service.dart';
import 'package:aphasia_app/services/library_store.dart';
import 'package:aphasia_app/services/settings_store.dart';
import 'package:aphasia_app/services/sync_service.dart';

import 'test_helpers.dart';

class FakeAudioPlaybackService implements AudioPlaybackService {
  @override
  Future<void> playFile(File file) async {}
}

// A tap on the settings icon or the "Say Something" FAB triggers a handler
// that itself does real dart:io before (settings: inside the pushed
// `ManageScreen`'s `initState`; Say Something: directly, awaited in
// `onPressed` before the `Navigator.push`) navigating -- another instance of
// the same real-I/O-vs-FakeAsync class of bug documented in
// `manage_screen_test.dart`. The triggering `tester.tap()` call must run
// inside the same `runAsync()` call as a trailing real delay so the
// underlying real Future actually completes and its continuation (including
// the `Navigator.push` and any `setState`) runs for real, rather than being
// stuck in the FakeAsync zone forever. `tester.pump()` (never
// `pumpAndSettle()`) is used afterwards: the destination screen
// (`ManageScreen`) shows an indefinite, endlessly-repeating
// `CircularProgressIndicator` while its own `initState` manifest fetch is
// in flight, and `pumpAndSettle()` loops forever waiting for that animation
// to stop.
Future<void> _tapAndLetNavigationSettle(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  // Bounded pumps (not pumpAndSettle) to flush the route transition
  // animation and the final frame.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

// `AppShell.initState` kicks off an un-awaited `syncIfLibraryEmpty(...)`
// check (see finding #3 in main.dart) that always -- even when it's a no-op
// because the library already has entries -- does a real dart:io
// `manifest()` read (plus a network round trip via `SyncService.sync()`
// when the library starts empty), then, once that resolves, bumps
// `_libraryRevision` via `setState`. That setState re-keys `HomeScreen`,
// firing a SECOND real dart:io `manifest()` read in the freshly built
// instance's own `initState`.
//
// The shared `pumpAndLetInitialLoadSettle` (see `test_helpers.dart`) isn't
// enough here on its own: a `Future`'s `.then()` callback always runs bound
// to whichever zone was current when `.then()` was registered (here, the
// real zone active during `runAsync`'s `pumpWidget` call in that helper) --
// so the sync-check's `setState` genuinely does land for real within that
// helper's 100ms real delay. But `setState` only marks the widget dirty; the
// *rebuild* (and the fresh `HomeScreen`'s new `initState` real IO it
// triggers) is only kicked off by the NEXT `pump()`, which in that shared
// helper is its trailing one, called OUTSIDE `runAsync`. A build triggered
// from a pump() call made outside `runAsync` runs in the FakeAsync test
// zone, so that second read never resolves (matching every other
// documented instance of this hazard in this codebase) and leaves an open
// file handle that races the test's `tearDown` deleting the shared temp
// directory (`PathAccessException`).
//
// This replaces `pumpAndLetInitialLoadSettle` for AppShell-hosted widgets:
// every pump that could trigger a fresh `initState`'s real IO stays inside
// ONE `runAsync` scope, with a real delay after each, so the whole
// two-level chain resolves for real before control ever returns to the
// FakeAsync zone.
Future<void> _pumpAppShellAndLetBackgroundSyncSettle(WidgetTester tester, Widget widget) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(widget);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // Still inside runAsync: if the sync-check's setState already landed,
    // this rebuild (and any fresh initState it triggers) stays in the real
    // zone instead of the FakeAsync one.
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });
  await tester.pump();
}

// Unlike `_tapAndLetNavigationSettle`, this waits for real dart:io triggered
// by the tap to actually resolve and be reflected on screen, rather than
// just flushing a route-push animation after a fixed delay. `tester.tap()`
// alone does not pump a frame, so e.g. a pushed `ManageScreen` isn't
// actually constructed -- and its `initState` (which kicks off a real
// dart:io `manifest()` read) doesn't fire -- until the FIRST `pump()` after
// the tap. If that first pump happens outside `runAsync` (back in the
// FakeAsync zone, as `_tapAndLetNavigationSettle`'s delay-then-exit-runAsync
// shape does), the real read that `initState` kicks off can never resolve
// for the rest of the test, and the screen's data-dependent content stays
// stuck on `CircularProgressIndicator` forever -- silently, since asserting
// only e.g. an AppBar title (built synchronously, unconditionally) doesn't
// notice. Keeping the tap AND the first pump (and then polling for
// `contentFinder`, which should depend on the resolved real I/O -- e.g. a
// pre-seeded phrase's text, or a category tile that only exists once a
// freshly-saved manifest entry has been read back) inside the same
// `runAsync` call lets that real read actually complete for real before we
// check for it. Used both for a settings-icon tap into `ManageScreen` and
// for popping back to a freshly-rekeyed `HomeScreen` (see finding #2's
// `_libraryRevision` mechanism in `main.dart`), which does the exact same
// kind of real dart:io read in its own `initState`.
Future<void> _tapAndWaitForContent(
  WidgetTester tester,
  Finder finder,
  Finder contentFinder,
) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await tester.pump();
    for (var i = 0; i < 100; i++) {
      if (contentFinder.evaluate().isNotEmpty) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  });
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

// Like `_tapAndWaitForManageLoaded`, but for a tap whose onPressed handler
// (`_addPhrase`) is itself a fire-and-forget Future doing real dart:io plus
// mocked network calls. Copied from `manage_screen_test.dart` rather than
// shared: per the review, this tap-specific helper has genuinely different
// semantics (it polls the *store*, not the widget tree) from the other
// tap-specific helpers in this file and is deliberately kept local to
// whichever file needs it. See `manage_screen_test.dart` for the full
// explanation of why this polls `store.manifest()` for a SPECIFIC predicate
// rather than a fixed delay or a "did it change" check.
Future<List<PhraseEntry>> _tapAndWaitForManifestState(
  WidgetTester tester,
  Finder finder,
  LibraryStore store,
  bool Function(List<PhraseEntry> manifest) predicate,
) async {
  var manifest = <PhraseEntry>[];
  await tester.runAsync(() async {
    await tester.tap(finder);
    for (var i = 0; i < 100; i++) {
      manifest = await store.manifest();
      if (predicate(manifest)) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  });
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  return manifest;
}

void main() {
  // AphasiaApp reads the stored theme on start, and SettingsStore goes
  // through SharedPreferences, which has no platform channel under test.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('app_shell_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('tapping the settings icon opens the Library', (tester) async {
    final store = LibraryStore(tempDir);
    await tester.runAsync(() => store.saveEntry(
          const PhraseEntry(id: '1', category: 'Greetings', text: 'Hello.', checksum: 'a'),
          Uint8List.fromList([1]),
        ));
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      client: MockClient((_) async => http.Response('[]', 200)),
    );
    final syncService = SyncService(apiClient: apiClient, libraryStore: store);

    await _pumpAppShellAndLetBackgroundSyncSettle(
      tester,
      AphasiaApp(
        apiClient: apiClient,
        libraryStore: store,
        syncService: syncService,
        audioPlaybackService: FakeAudioPlaybackService(),
        settingsStore: SettingsStore(),
      ),
    );

    await _tapAndWaitForContent(
      tester,
      find.byIcon(Icons.settings),
      find.text('Hello.'),
    );

    expect(find.text('Library'), findsOneWidget);
    // Proves LibraryScreen's own initState manifest() read actually
    // resolved and rendered -- not just that the AppBar title (built
    // synchronously, unconditionally) is present.
    expect(find.text('Hello.'), findsOneWidget);
  });

  testWidgets('tapping Say Something opens the entry screen', (tester) async {
    final store = LibraryStore(tempDir);
    await tester.runAsync(() async {
      await store.saveEntry(
        const PhraseEntry(id: '1', category: 'Greetings', text: 'Hello.', checksum: 'a'),
        Uint8List.fromList([1]),
      );
    });
    final apiClient = ApiClient(
      baseUrl: 'http://test',
      client: MockClient((_) async => http.Response('[]', 200)),
    );
    final syncService = SyncService(apiClient: apiClient, libraryStore: store);

    await _pumpAppShellAndLetBackgroundSyncSettle(
      tester,
      AphasiaApp(
        apiClient: apiClient,
        libraryStore: store,
        syncService: syncService,
        audioPlaybackService: FakeAudioPlaybackService(),
        settingsStore: SettingsStore(),
      ),
    );

    await _tapAndLetNavigationSettle(tester, find.text('SAY SOMETHING'));

    expect(find.text('Say Something'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('deleting in the Library refreshes what Home shows', (tester) async {
    final mockClient = MockClient((request) async {
      throw Exception('unexpected request: ${request.url}');
    });
    final apiClient = ApiClient(baseUrl: 'http://test', client: mockClient);
    final store = LibraryStore(tempDir);
    final syncService = SyncService(apiClient: apiClient, libraryStore: store);

    await tester.runAsync(() async {
      await store.saveEntry(
        const PhraseEntry(id: 'p1', category: 'Needs', text: 'Help.', checksum: 'x'),
        Uint8List.fromList([1, 2, 3]),
      );
    });

    await _pumpAppShellAndLetBackgroundSyncSettle(
      tester,
      AphasiaApp(
        apiClient: apiClient,
        libraryStore: store,
        syncService: syncService,
        audioPlaybackService: FakeAudioPlaybackService(),
        settingsStore: SettingsStore(),
      ),
    );

    expect(find.byKey(const ValueKey('category-Needs')), findsOneWidget);

    await _tapAndWaitForContent(
      tester,
      find.byIcon(Icons.settings),
      find.text('Help.'),
    );
    // `_tapAndWaitForContent` returns as soon as the content is in the tree,
    // which happens while the pushed route is still sliding in from the
    // right — tapping then lands off the viewport and silently misses. Let
    // the transition finish first.
    await tester.pump(const Duration(milliseconds: 400));

    // Emptying the category deletes it, since categories are only labels on
    // phrases. What is under test is that Home notices.
    await _tapAndWaitForManifestState(
      tester,
      find.byIcon(Icons.delete_outline),
      store,
      (m) => m.isEmpty,
    );
    // The Library's own list has to catch up before popping, or the pop
    // lands while a stale read is still in flight.
    await pumpUntil(
      tester,
      () => find.text('The library is empty. Sync or add a phrase.')
          .evaluate()
          .isNotEmpty,
    );

    // `AppShell`'s settings `onPressed` bumps `_libraryRevision` once the
    // pushed route's Future completes, which re-keys `HomeScreen` and fires a
    // fresh `initState` -> real dart:io `manifest()` read -- the same
    // real-I/O-vs-FakeAsync hazard as the Library screen's own initial load,
    // so this needs the tap-and-first-pump-inside-runAsync treatment rather
    // than `_tapAndLetNavigationSettle`'s fixed-delay-then-exit shape.
    await _tapAndWaitForContent(
      tester,
      find.byTooltip('Back'),
      find.text('No phrases yet.'),
    );

    expect(find.text('No phrases yet.'), findsOneWidget);
    expect(find.byKey(const ValueKey('category-Needs')), findsNothing);
  });
}
