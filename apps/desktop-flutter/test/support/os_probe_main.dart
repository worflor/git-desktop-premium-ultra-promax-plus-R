// os_probe_main.dart — the Linux-side emitter for the cross-OS differential
// harness.
//
// This is a plain `flutter_test` suite with exactly one test: compute the
// shared probe corpus (os_probe_corpus.dart) and print it as JSON wrapped
// in unique markers. test/fuzz/cross_os_differential_test.dart runs this
// file under WSL2's native-Linux Flutter SDK via `flutter test`, captures
// stdout, and slices out the JSON between the markers.
//
// Deliberately trivial — all the actual logic lives in the shared corpus
// so both OSes run byte-for-byte the same code path.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'os_probe_corpus.dart';

void main() {
  test('emit OS probe as marked JSON', () {
    final probe = computeOsProbe();
    final encoded = jsonEncode(probe);
    // Markers are deliberately unlikely to appear in any probe output and
    // contain no whitespace, so a simple substring slice on the captured
    // stdout is enough to recover the payload even if `flutter test`
    // interleaves other lines (progress dots, package:test JSON reporter
    // noise, etc.) around this print.
    // ignore: avoid_print
    print('OSPROBE_BEGIN${encoded}OSPROBE_END');
    expect(probe, isNotEmpty);
  });
}
