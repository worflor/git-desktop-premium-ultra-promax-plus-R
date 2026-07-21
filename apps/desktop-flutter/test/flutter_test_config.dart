// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// flutter_test_config.dart — global harness config, applied to EVERY test
// in this package by flutter_test's convention (this file wraps each
// test file's main()).
//
// Leak tracking: the dynamic counterpart of the analyzer's close_sinks /
// cancel_subscriptions error tier. Every `testWidgets` body is watched by
// leak_tracker via the FlutterMemoryAllocations instrumentation baked
// into the framework's debug build: a disposable created during the test
// (controller, notifier, image, ticker) that is garbage-collected without
// dispose() — or disposed but never released — fails the test that
// created it, naming the object and its allocation site. Plain test()
// bodies (the backend suites) are unaffected.
//
// Scope guard: leak checks add per-object bookkeeping. If a suite ever
// needs to opt out (e.g. a profiling run), use LeakTesting.settings =
// LeakTesting.settings.withIgnoredAll() locally — do NOT remove this file.

import 'dart:async';

import 'package:leak_tracker_flutter_testing/leak_tracker_flutter_testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // Diagnostics writes telemetry in the background from backend tests too.
  // Install the in-memory platform before test code can schedule that work;
  // otherwise MissingPluginExceptions flood the runner and distort timing.
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  LeakTesting.enable();
  LeakTesting.settings = LeakTesting.settings.withIgnored(
    classes: [
      // Process-lifetime singleton (WindowActivity.instance): created
      // lazily on first touch, deliberately never disposed — one per
      // app run, not a leak. Everything else must dispose.
      'WindowActivity',
    ],
  );
  await testMain();
}
