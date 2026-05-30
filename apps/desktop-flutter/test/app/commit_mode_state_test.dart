import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/commit_mode_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('unknown path defaults to false', () {
    final state = CommitModeState();
    expect(state.commitOnlyFor('/repo/app'), isFalse);
  });

  test('commit-only choice persists and reloads', () async {
    final state = CommitModeState();
    state.setCommitOnly('/repo/app', true);
    await state.flushPendingSaveForTesting();

    final loaded = CommitModeState();
    await loaded.load();
    expect(loaded.commitOnlyFor('/repo/app'), isTrue);
  });

  test('paths are independent', () async {
    final state = CommitModeState();
    state.setCommitOnly('/repo/a', true);
    await state.flushPendingSaveForTesting();

    final loaded = CommitModeState();
    await loaded.load();
    expect(loaded.commitOnlyFor('/repo/a'), isTrue);
    expect(loaded.commitOnlyFor('/repo/b'), isFalse);
  });

  test('setting false removes the key and stores no false entries', () async {
    final state = CommitModeState();
    state.setCommitOnly('/repo/app', true);
    state.setCommitOnly('/repo/app', false);
    await state.flushPendingSaveForTesting();

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('commit_mode');
    final json = raw == null ? const {} : jsonDecode(raw) as Map;
    expect(json.containsKey('/repo/app'), isFalse);

    final loaded = CommitModeState();
    await loaded.load();
    expect(loaded.commitOnlyFor('/repo/app'), isFalse);
  });

  test('toggle flips the stored value', () async {
    final state = CommitModeState();
    state.toggle('/repo/app');
    expect(state.commitOnlyFor('/repo/app'), isTrue);
    state.toggle('/repo/app');
    expect(state.commitOnlyFor('/repo/app'), isFalse);
  });

  test('corrupt persisted json falls back to defaults', () async {
    SharedPreferences.setMockInitialValues({'commit_mode': '{not json'});

    final state = CommitModeState();
    await state.load();
    expect(state.commitOnlyFor('/repo/app'), isFalse);
  });
}
