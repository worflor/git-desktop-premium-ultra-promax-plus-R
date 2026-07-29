// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// provider_stall_test.dart — silence is the only shape a wedge has.
//
// The review path had exactly one way to give up: a 22-minute total
// ceiling. That cannot tell a provider that is WORKING from one that has
// died holding the pipe open, because both look like "no result yet".
// An agentic model legitimately streams tool calls for many minutes, so
// the ceiling had to be generous, so a genuine wedge cost 22 minutes of
// staring at nothing — which is exactly what happened while debugging
// this feature.
//
// The runner now watches for OUTPUT, not just for exit. These pin the
// distinction:
//
//  W1  a process that keeps talking is left alone, even past the stall
//      budget — slow is not dead. Note the budget here is well above
//      the interpreter's own startup cost: a process that has not
//      spoken YET is starting, not stalling, and the budget has to
//      cover that or it kills every cold start (observed while writing
//      this — `dart run` compiles for ~10s before its first byte).
//  W2  a process that goes silent is killed at the stall budget, well
//      before the total ceiling.
//  W3  no stall budget preserves the old behaviour exactly, so callers
//      that have not opted in are unaffected.
//  W4  the caller is TOLD which ceiling tripped, as prose for the user
//      AND as a fact (`ProviderGaveUp.stalled`) the dispatch can act on.
//  W6  the message RENDERS. Every W1-W5 assertion passed while the
//      text said "0 minutes", because none of them looked at the
//      number — the CLI timeout is user-settable to 30s, which makes
//      the stall budget 15s, which `Duration.inMinutes` truncates to
//      zero. A message with a nonsensical number is the same ambiguity
//      this feature exists to remove, wearing a digit.
//  W7  no give-up sentence claims a stop it cannot confirm. The message
//      was assembled from two independent booleans — "and was stopped"
//      baked into the cause, "; termination was not confirmed" stapled
//      on after — so a total timeout whose kill did not land said both
//      in one breath, and the caller-facing sentence said "stopped"
//      regardless. All four combinations are asserted here because the
//      contradicting one is the combination nothing else can reach: a
//      kill that fails to confirm needs an unkillable process.
//  W8  the ceiling that trips is the one that actually expired first.
//      Waiting a fixed poll interval meant both ceilings were only ever
//      examined at poll boundaries, so a total budget that ran out
//      between two polls was reported as a STALL if the silence budget
//      had also passed by the time anyone looked — telling the user
//      their provider was stuck when it was merely over its time. The
//      wait now ends at whichever ceiling comes first, so the cause is
//      the true one and neither budget overshoots.
//  W9  a failed provider run keeps the one line that explains it. The
//      piggyback used to discard codex's stderr on a non-zero exit, so
//      an expired login reached the user as an unrelated complaint from
//      the HTTP fallback that ran afterwards.
// W10  the invocation shapes SHARE the configured cap. Each used to get
//      it in full, so a wedged provider cost the cap once per shape:
//      measured at 17m46s to report a stall that was detected at 4
//      minutes, four times over. A cap the user sets is a bound on the
//      operation, not a per-shape allowance.
// W11  a provider that has not spoken YET is starting, not stalling. A
//      cold-cache review ships ~1M tokens of context and the model
//      prefills them with nothing on the wire; measured against the
//      real CLIs, first output arrives in seconds for a small prompt
//      but the big ones ran past a 4-minute silence budget and were
//      killed mid-prefill — the expensive runs, the ones a user most
//      wants to finish. Silence only means something once the child has
//      shown it can speak; before that the total ceiling governs.
// W12  the give-up message counts BYTES. It counted decoded chunk
//      length, which is UTF-16 code units, and called them bytes — a
//      number that silently lies the moment a provider says anything
//      non-ASCII, which is most of them.
// W13  a child that never speaks says so. The evidence clause hung off
//      the stall branch, and a stall can only fire after the child has
//      spoken, so the one case the clause was written for — "it never
//      sent anything at all" — could not be reached.
// W14  a provider still streaming when its TOTAL budget expires is not
//      described as having gone quiet. The evidence clause was worded
//      for the stall case and then reused on both ceilings, which
//      invented a symptom: a run that was merely long read as a wedge.
// W15  a provider waiting on a command it ANNOUNCED is not a wedge.
//      codex exec reports each command as item.started/item.completed
//      and says nothing while one runs, so a slow command outlasts the
//      silence budget. Traced from a real run: a review ran
//      `flutter test test/backend/provider_stall_test.dart` — this very
//      file, whose job is to wait out timeouts — and was killed four
//      minutes in with the command still running.
// W16  a provider that ANNOUNCED a command may be silent for as long as
//      the command runs — the busy predicate restarts the silence
//      budget. This is the end-to-end witness for the restart path in
//      _awaitExit, which W15 (the pure parser) cannot see: the mutation
//      audit found runObservedProcessForTesting did not even expose the
//      predicate, so the wiring had no test at all.
// W17  the derivation of the silence budget from the total cap has its
//      own witness. W5 drives the runner with an explicit stallTimeout,
//      so a flat-budget regression in stallBudgetFor shipped with W5
//      green — proven by mutation.
//  W5  the budget is reachable for a SHORT total cap. antigravity and
//      copilot are capped at 3 minutes total exactly because their
//      headless paths hang; a flat 4-minute stall budget could never
//      fire for them, so the providers most likely to need the signal
//      were the only ones that could not get it. Fixing the timing
//      without fixing the message would leave "Provider command timed
//      out." on screen — the exact ambiguity the budget exists to
//      remove, just arriving sooner.

@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/ai.dart';

/// The real Dart SDK binary.
///
/// NOT `Platform.resolvedExecutable`: inside `flutter test` that is
/// flutter_tester, which does not run scripts — the child silently
/// never started, every call came back null, and W2 "passed" for
/// exactly the wrong reason (it asserts null). Same shape as the
/// MaterialIcons lookup in widget_harness: derive the SDK from
/// FLUTTER_ROOT, or from the tester's own path, and THROW rather than
/// skip if it cannot be found.
String _dartExecutable() {
  final exe = Platform.isWindows ? 'dart.exe' : 'dart';
  final probes = <String>[];
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) probes.add(root);
  final self = File(Platform.resolvedExecutable).absolute.path;
  final marker =
      '${Platform.pathSeparator}bin${Platform.pathSeparator}'
      'cache${Platform.pathSeparator}';
  final cut = self.indexOf(marker);
  if (cut > 0) probes.add(self.substring(0, cut));
  for (final base in probes) {
    final f = File(
      '$base${Platform.pathSeparator}bin'
      '${Platform.pathSeparator}cache${Platform.pathSeparator}dart-sdk'
      '${Platform.pathSeparator}bin${Platform.pathSeparator}$exe',
    );
    if (f.existsSync()) return f.path;
  }
  throw StateError(
    'provider_stall_test: no dart SDK binary found under $probes — '
    'the harness cannot spawn a child and every assertion would be '
    'vacuous.',
  );
}

void main() {
  final dart = _dartExecutable();

  group('W10: invocation shapes share one budget', () {
    final start = DateTime.utc(2026, 7, 29, 12);
    const cap = Duration(minutes: 8);
    final deadline = start.add(cap);

    test('the first shape gets the whole cap', () {
      expect(attemptSlice(deadline: deadline, now: start, cap: cap), cap);
    });

    test('a later shape gets only what is left', () {
      final slice = attemptSlice(
        deadline: deadline,
        now: start.add(const Duration(minutes: 5)),
        cap: cap,
      );
      expect(slice, const Duration(minutes: 3),
          reason: 'five minutes were already spent stalling');
    });

    test('a spent budget yields no shape at all', () {
      expect(
          attemptSlice(
            deadline: deadline,
            now: start.add(const Duration(minutes: 8)),
            cap: cap,
          ),
          isNull,
          reason: 'running one more shape could only spend time the user '
              'said they did not have');
      expect(
          attemptSlice(
            deadline: deadline,
            now: start.add(const Duration(minutes: 30)),
            cap: cap,
          ),
          isNull);
    });
  });

  group('W9: a failed run keeps the line that explains it', () {
    test('prefers the line the tool marked as an error', () {
      const stderr = '''
2026-07-29T03:32:56Z ERROR codex_login::auth: Failed to refresh token: your
starting session
2026-07-29T03:32:57Z ERROR codex: Your access token could not be refreshed.
''';
      expect(meaningfulErrorLine(stderr),
          contains('access token could not be refreshed'),
          reason: 'the actionable line, not whatever happened to be last');
    });

    test('falls back to the last line with content', () {
      expect(meaningfulErrorLine('warming up\n\nno such model\n\n'),
          'no such model');
    });

    test('says nothing when there is nothing to say', () {
      expect(meaningfulErrorLine('   \n\n'), isNull,
          reason: 'an empty reason is worse than none — it reads as a '
              'message the app failed to fill in');
    });

    test('truncates rather than pasting a log into a sentence', () {
      final long = 'ERROR ${'x' * 500}';
      final line = meaningfulErrorLine(long, maxLength: 40)!;
      expect(line.length, lessThanOrEqualTo(41));
      expect(line, endsWith('…'));
    });
  });

  group('W7: a give-up sentence never claims an unconfirmed stop', () {
    const total = Duration(minutes: 5);
    const stall = Duration(seconds: 30);

    GiveUp giveUp({required bool stalled, required bool terminated}) => GiveUp(
      stalled: stalled,
      stall: stall,
      total: total,
      terminated: terminated,
    );

    for (final stalled in [true, false]) {
      final which = stalled ? 'stall' : 'total';

      test('$which ceiling, kill confirmed: says it was stopped', () {
        final g = giveUp(stalled: stalled, terminated: true);
        for (final line in [g.diagnostics, g.advice]) {
          expect(line, contains('was stopped'));
          expect(line, isNot(contains('could not be confirmed')));
        }
      });

      test('$which ceiling, kill unconfirmed: never says it was stopped', () {
        final g = giveUp(stalled: stalled, terminated: false);
        for (final line in [g.diagnostics, g.advice]) {
          expect(
            line,
            contains('could not be confirmed stopped'),
            reason:
                'the reader has to learn the process may still be '
                'running',
          );
          expect(
            line,
            isNot(contains('and was stopped')),
            reason:
                'asserting a stop and then denying it in the same '
                'sentence is the defect',
          );
        }
      });
    }

    test('the cause survives in both audiences', () {
      final stalledOut = giveUp(stalled: true, terminated: true);
      expect(stalledOut.diagnostics, contains('no output for 30 seconds'));
      expect(stalledOut.advice, contains('stuck'));
      expect(
        stalledOut.advice,
        contains('restart Manifold'),
        reason: 'the person waiting gets the remedy',
      );

      final timedOut = giveUp(stalled: false, terminated: true);
      expect(timedOut.diagnostics, contains('5 minutes budget'));
      expect(
        timedOut.advice,
        isNot(contains('restart Manifold')),
        reason:
            'a job that ran long is not a wedge; advising a restart '
            'would train the user to restart for nothing',
      );
    });
  });

  /// A child that prints [ticks] lines one second apart, then sleeps
  /// [silentFor] seconds without saying anything. Dart is used as the
  /// interpreter because the test host is guaranteed to have it.
  Future<File> chatterScript(Directory dir, int ticks, int silentFor) async {
    final f = File('${dir.path}${Platform.pathSeparator}chatter.dart');
    await f.writeAsString('''
import 'dart:io';
Future<void> main() async {
  for (var i = 0; i < $ticks; i++) {
    stdout.writeln('tick \$i');
    await stdout.flush();
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  await Future<void>.delayed(const Duration(seconds: $silentFor));
  stdout.writeln('done');
}
''');
    return f;
  }

  late Directory tmp;
  setUp(() async => tmp = await Directory.systemTemp.createTemp('stall_test'));
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('W11: silence before the first byte is not a stall', () async {
    // Says nothing for 30 seconds, then speaks and exits. The silence
    // budget is 10s — it must NOT fire, because nothing has arrived yet
    // and there is no evidence of a wedge.
    final script = File('${tmp.path}${Platform.pathSeparator}late.dart');
    await script.writeAsString('''
import 'dart:io';
Future<void> main() async {
  await Future<void>.delayed(const Duration(seconds: 30));
  stdout.writeln('first token at last');
}
''');
    final r = await runObservedProcessForTesting(
      dart,
      ['run', script.path],
      timeout: const Duration(seconds: 120),
      stallTimeout: const Duration(seconds: 10),
    );
    expect(r, isNotNull,
        reason: 'a long prefill is not a wedge — killing it here is how '
            'a cold-cache review died at four minutes');
    expect(r!.stdout, contains('first token at last'));
  });

  test('W12: the byte count is bytes, not code units', () async {
    // Two lines of decidedly non-ASCII, then silence. Every character
    // here costs more UTF-8 bytes than UTF-16 code units, so the two
    // readings cannot be confused for each other.
    const line = 'héllo → 世界';
    final script = File('${tmp.path}${Platform.pathSeparator}utf8.dart');
    await script.writeAsString('''
import 'dart:io';
Future<void> main() async {
  stdout.writeln('$line');
  await stdout.flush();
  await Future<void>.delayed(const Duration(seconds: 120));
}
''');
    String? reason;
    final r = await runObservedProcessForTesting(
      dart,
      ['run', script.path],
      timeout: const Duration(seconds: 150),
      stallTimeout: const Duration(seconds: 20),
      onGiveUp: (gave) => reason = gave.message,
    );
    expect(r, isNull);
    final wrote = utf8.encode('$line\n').length;
    const codeUnits = '$line\n'.length;
    expect(wrote, greaterThan(codeUnits), reason: 'the fixture must be able '
        'to tell the two readings apart');
    expect(reason, contains('$wrote bytes'),
        reason: 'the number has to mean what the sentence says it means');
    expect(reason, isNot(contains('$codeUnits bytes')));
  });

  test('W13: a child that never speaks says exactly that', () async {
    // Silent from birth, so the STALL can never fire — only the total
    // ceiling can. That branch has to carry the evidence too, or the
    // one case worth distinguishing is the one nobody is told about.
    final script = File('${tmp.path}${Platform.pathSeparator}mute.dart');
    await script.writeAsString('''
import 'dart:io';
Future<void> main() async {
  await Future<void>.delayed(const Duration(seconds: 120));
}
''');
    String? reason;
    final r = await runObservedProcessForTesting(
      dart,
      ['run', script.path],
      timeout: const Duration(seconds: 25),
      stallTimeout: const Duration(seconds: 10),
      onGiveUp: (gave) => reason = gave.message,
    );
    expect(r, isNull);
    expect(reason, contains('never sent anything at all'));
    expect(reason, contains('budget'),
        reason: 'the total ceiling is what tripped, and it must say so');
    expect(reason, isNot(contains('no output for')),
        reason: 'silence from a child that never started talking is not a '
            'stall — it is simply a child that never answered');
  });

  test('W14: a talker that outlives its total budget did not go quiet',
      () async {
    // Talks every second and never stops, so the STALL can never fire
    // and the total ceiling is what ends it. It was streaming at the
    // moment we gave up, and the message must not say otherwise.
    final script = await chatterScript(tmp, 60, 0);
    String? reason;
    final r = await runObservedProcessForTesting(
      dart,
      ['run', script.path],
      timeout: const Duration(seconds: 25),
      stallTimeout: const Duration(seconds: 20),
      onGiveUp: (gave) => reason = gave.message,
    );
    expect(r, isNull);
    expect(reason, contains('budget'),
        reason: 'the total ceiling is what tripped');
    expect(reason, contains('bytes by then'),
        reason: 'it had plenty to say, right up to the end');
    expect(reason, isNot(contains('going quiet')),
        reason: 'inventing a symptom sends the reader hunting a wedge '
            'that never happened');
    expect(reason, isNot(contains('no output for')));
  });

  group('W15: an announced command is work, not silence', () {
    String started(String id) =>
        '{"type":"item.started","item":{"id":"$id",'
        '"type":"command_execution","command":"flutter test"}}';
    String completed(String id) =>
        '{"type":"item.completed","item":{"id":"$id",'
        '"type":"command_execution","exit_code":0}}';

    test('an unmatched start means a command is still running', () {
      expect(agentAwaitingCommand(started('item_7')), isTrue);
    });

    test('a matched pair means it finished', () {
      expect(
          agentAwaitingCommand(
              '${started('item_7')}\n${completed('item_7')}'),
          isFalse);
    });

    test('the LAST command is the one that counts', () {
      final stream = [
        started('item_1'),
        completed('item_1'),
        started('item_2'),
      ].join('\n');
      expect(agentAwaitingCommand(stream), isTrue,
          reason: 'an earlier command finishing says nothing about the one '
              'running now');
    });

    test('an overlapping command is still tracked', () {
      // A starts, B starts, B finishes. A is still running, and only a
      // set can say so — tracking the newest id alone reported idle and
      // got the provider killed mid-command.
      final stream = [
        started('item_1'),
        started('item_2'),
        completed('item_2'),
      ].join('\n');
      expect(agentAwaitingCommand(stream), isTrue);

      final both = '$stream\n${completed('item_1')}';
      expect(agentAwaitingCommand(both), isFalse,
          reason: 'and idle once every announced command has reported');
    });

    test('a torn tail is not mistaken for a running command', () {
      final stream =
          '${started('item_1')}\n${completed('item_1')}\n'
          '{"type":"item.star';
      expect(agentAwaitingCommand(stream), isFalse,
          reason: 'the stream arrives in chunks; half a line is not '
              'evidence of anything');
    });

    test('a plain message is not a command', () {
      const msg = '{"type":"item.started","item":{"id":"item_3",'
          '"type":"agent_message"}}';
      expect(agentAwaitingCommand(msg), isFalse,
          reason: 'only a command execution explains a long silence');
    });

    test('empty output claims nothing', () {
      expect(agentAwaitingCommand(''), isFalse);
    });
  });

  test('W16: an announced command excuses the silence it causes',
      () async {
    // Speaks once — a codex-style item.started for a command — then goes
    // silent well past the stall budget, then completes the command and
    // exits. With the busy predicate wired the runner must wait; the
    // same child WITHOUT the predicate is killed as a wedge, which is
    // the pair of outcomes that proves the restart path is live.
    final script = File('${tmp.path}${Platform.pathSeparator}announce.dart');
    await script.writeAsString('''
import 'dart:io';
Future<void> main() async {
  stdout.writeln('{"type":"item.started","item":{"id":"item_1",'
      '"type":"command_execution","command":"flutter test"}}');
  await stdout.flush();
  await Future<void>.delayed(const Duration(seconds: 25));
  stdout.writeln('{"type":"item.completed","item":{"id":"item_1",'
      '"type":"command_execution","exit_code":0}}');
}
''');
    final busy = await runObservedProcessForTesting(
      dart,
      ['run', script.path],
      timeout: const Duration(seconds: 90),
      stallTimeout: const Duration(seconds: 10),
      isBusy: agentAwaitingCommand,
    );
    expect(busy, isNotNull,
        reason: 'the child told us exactly what it was waiting on — '
            'killing it is the codex-review misdiagnosis replayed');
    expect(busy!.stdout, contains('item.completed'));

    final unaware = await runObservedProcessForTesting(
      dart,
      ['run', script.path],
      timeout: const Duration(seconds: 90),
      stallTimeout: const Duration(seconds: 10),
    );
    expect(unaware, isNull,
        reason: 'without the predicate the same silence is a stall — '
            'if this survives, the stall budget itself has stopped '
            'working and W16 is passing vacuously');
  });

  test('W17: the silence budget derives from the total cap', () {
    expect(stallBudgetFor(const Duration(minutes: 3)),
        const Duration(seconds: 90),
        reason: 'the 3-minute-capped providers exist BECAUSE their '
            'headless paths hang; a budget they cannot reach is no '
            'budget');
    expect(stallBudgetFor(const Duration(minutes: 20)),
        const Duration(minutes: 4),
        reason: 'long caps saturate at the flat ceiling');
    expect(stallBudgetFor(const Duration(seconds: 30)),
        const Duration(seconds: 15));
  });

  test('W1: a process that keeps talking is left alone', () async {
    // 25 seconds of chatter against a 20-second stall budget. Every gap
    // is one second, so nothing is ever silent for long — and the run
    // outlives the budget, which is the whole point of measuring
    // SILENCE rather than duration.
    final script = await chatterScript(tmp, 25, 0);
    final sw = Stopwatch()..start();
    final r = await runObservedProcessForTesting(
      dart,
      ['run', script.path],
      timeout: const Duration(seconds: 120),
      stallTimeout: const Duration(seconds: 20),
    );
    sw.stop();
    expect(r, isNotNull, reason: 'a talking process must not be killed');
    expect(r!.exitCode, 0);
    expect(r.stdout, contains('done'));
    expect(
      sw.elapsed.inSeconds,
      greaterThan(20),
      reason: 'it really did run past the stall budget while talking',
    );
  });

  test(
    'W2: a process that goes silent is killed at the stall budget',
    () async {
      // Talks briefly, then says nothing for two minutes. The total
      // ceiling is 150s and the stall budget 25s: being killed on the
      // budget rather than the ceiling IS the fix.
      final script = await chatterScript(tmp, 2, 120);
      final sw = Stopwatch()..start();
      final r = await runObservedProcessForTesting(
        dart,
        ['run', script.path],
        timeout: const Duration(seconds: 150),
        stallTimeout: const Duration(seconds: 25),
      );
      sw.stop();
      expect(r, isNull, reason: 'a silent process is reported as failed');
      expect(
        sw.elapsed.inSeconds,
        lessThan(100),
        reason:
            'killed on SILENCE, well before the 150s ceiling — took '
            '${sw.elapsed.inSeconds}s',
      );
    },
  );

  test('W3: without a stall budget the old behaviour is unchanged', () async {
    // Same silent script, no stall budget: it must run to completion
    // under the total ceiling, exactly as before this change.
    final script = await chatterScript(tmp, 1, 3);
    final r = await runObservedProcessForTesting(dart, [
      'run',
      script.path,
    ], timeout: const Duration(seconds: 150));
    expect(r, isNotNull);
    expect(r!.exitCode, 0);
    expect(r.stdout, contains('done'));
  });

  test('W4: the give-up reason names which ceiling tripped', () async {
    final silent = await chatterScript(tmp, 1, 120);
    String? stallReason;
    var stalled = false;
    final r = await runObservedProcessForTesting(
      dart,
      ['run', silent.path],
      timeout: const Duration(seconds: 150),
      stallTimeout: const Duration(seconds: 25),
      onGiveUp: (gave) {
        stallReason = gave.message;
        stalled = gave.stalled;
      },
    );
    expect(r, isNull);
    expect(
      stallReason,
      isNotNull,
      reason: 'the caller must be told, not just telemetry',
    );
    expect(
      stallReason,
      contains('no output'),
      reason: 'it names SILENCE as the cause',
    );
    expect(
      stallReason,
      contains('stuck'),
      reason: 'and says plainly that it was not working',
    );
    expect(
      stalled,
      isTrue,
      reason: 'the dispatch skips further shapes that deliver the prompt '
          'the same way, so the cause has to arrive as a FACT rather '
          'than as prose it would have to grep',
    );
  });

  test('W5: a short total cap still gets a reachable stall budget', () async {
    // Total 30s, stall 10s: the stall must trip FIRST, the way a
    // 3-minute-capped provider now gets a 90-second silence budget
    // instead of an unreachable 4-minute one.
    final silent = await chatterScript(tmp, 1, 120);
    String? reason;
    final sw = Stopwatch()..start();
    final r = await runObservedProcessForTesting(
      dart,
      ['run', silent.path],
      timeout: const Duration(seconds: 30),
      stallTimeout: const Duration(seconds: 10),
      onGiveUp: (gave) => reason = gave.message,
    );
    sw.stop();
    expect(r, isNull);
    expect(
      reason,
      contains('no output'),
      reason: 'the stall tripped, not the total cap',
    );
    expect(
      sw.elapsed.inSeconds,
      lessThan(28),
      reason: 'and it tripped BEFORE the 30s ceiling',
    );
  });

  test('W8: the cause is the ceiling that expired first', () async {
    // Total 12s, silence 13s: the total budget runs out first, by one
    // second. Under a 5-second poll nobody looked until 15s, by which
    // point BOTH had passed and silence — checked first — took the
    // blame.
    final silent = await chatterScript(tmp, 1, 120);
    String? reason;
    final r = await runObservedProcessForTesting(
      dart,
      ['run', silent.path],
      timeout: const Duration(seconds: 12),
      stallTimeout: const Duration(seconds: 13),
      onGiveUp: (gave) => reason = gave.message,
    );
    expect(r, isNull);
    expect(
      reason,
      contains('12 seconds budget'),
      reason: 'the total ceiling expired first and must be the one named',
    );
    expect(
      reason,
      isNot(contains('no output')),
      reason: 'the process was still inside its silence budget — calling '
          'it stuck sends the user chasing a hang that was not there',
    );
  });

  test(
    'W6: a sub-minute budget renders as seconds, never "0 minutes"',
    () async {
      final silent = await chatterScript(tmp, 1, 120);
      String? reason;
      final r = await runObservedProcessForTesting(
        dart,
        ['run', silent.path],
        timeout: const Duration(seconds: 40),
        stallTimeout: const Duration(seconds: 12),
        onGiveUp: (gave) => reason = gave.message,
      );
      expect(r, isNull);
      expect(reason, isNotNull);
      expect(
        reason,
        isNot(contains('0 minutes')),
        reason: 'the number has to mean something',
      );
      expect(
        reason,
        contains('12 seconds'),
        reason: 'a 12-second budget says twelve seconds',
      );
    },
  );
}
