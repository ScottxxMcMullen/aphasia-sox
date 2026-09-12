import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Several widgets under test (`HomeScreen`, `CategoryScreen`, `ManageScreen`,
// `AppShell`) kick off real dart:io reads (via `LibraryStore`) from
// `initState` as fire-and-forget Futures — nothing in `initState` is awaited
// by `pumpWidget`. Real dart:io awaited inside a fire-and-forget Future
// never resolves under Flutter test binding's FakeAsync zone, so the
// `pumpWidget` call that triggers `initState` must run inside the same
// `runAsync()` call as a trailing short real delay — otherwise the initial
// `FutureBuilder` is stuck showing a `CircularProgressIndicator` forever and
// any later `pumpAndSettle()` hangs waiting for its animation to settle.
// See https://api.flutter.dev/flutter/flutter_test/WidgetTester/runAsync.html.
//
// The same applies to assertions: a bare `await store.manifest()` in a test
// body issues its read in the FakeAsync zone, where it never completes and
// nothing times it out, so the whole run hangs. Read through `runAsync`.
Future<void> pumpAndLetInitialLoadSettle(WidgetTester tester, Widget widget) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(widget);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
}

// The same FakeAsync problem, for a gesture rather than a first build: an
// `onTap`/`onLongPress` callback is a `VoidCallback`, so the async handler it
// starts is fire-and-forget and its real dart:io work never resolves unless
// the gesture and a trailing real delay share one `runAsync` call.
//
// Deliberately `pump()`, not `pumpAndSettle()`, afterwards: handlers here
// show a SnackBar, whose auto-dismiss timer is created inside runAsync's real
// zone. `pumpAndSettle()` would wait for a timer that nothing services once
// control is back in the FakeAsync zone, and hang.
Future<void> tapAndLetRealIoSettle(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pump();
}

// Like [tapAndLetRealIoSettle], but for a tap whose fire-and-forget chain
// hops through several real awaits. A fixed delay is a race under load —
// running the whole suite puts several test files' file I/O on the same
// disk — and if the body (and then `tearDown`, deleting the temp dir) moves
// on before the write lands, it fails with a `PathAccessException` after the
// test has already reported its result. Polling for the outcome inside the
// same runAsync call avoids guessing a delay.
// Waits for the tree to catch up with a real read that was issued after an
// interaction — `_reload()`-style `setState(() => future = store.manifest())`
// resolves on its own schedule, so the single `pump()` that follows an
// interaction helper is often one frame too early. Pumps inside `runAsync` so
// the read it is waiting on can actually complete.
Future<void> pumpUntil(WidgetTester tester, bool Function() satisfied) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 100; i++) {
      await tester.pump();
      if (satisfied()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pump();
}

Future<void> tapAndWaitFor(
  WidgetTester tester,
  Finder finder,
  Future<bool> Function() isDone,
) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    for (var i = 0; i < 100; i++) {
      if (await isDone()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pump();
}
