// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_desktop/backend/storage_paths.dart';

final bool _isTty = stderr.hasTerminal;

void main(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    _printUsage();
    exit(0);
  }
  if (args.first == '--version' || args.first == '-v') {
    _printVersion();
    exit(0);
  }

  final method = args.first;
  final params = _parseParams(args.skip(1).toList());
  final jsonOutput = params.remove('json') == 'true';

  try {
    final connection = await _connect(Map.of(params));
    if (connection == null) {
      stderr.writeln('manifold is not running.');
      exit(1);
    }

    if (!params.containsKey('repo')) {
      final gitRoot = await _resolveGitRoot();
      if (gitRoot != null) params['repo'] = gitRoot;
    }

    final slow = const {
      'review', 'review-evidence', 'muse', 'impact', 'dream', 'deadcode',
      'index', 'shake', 'commit-message',
    }.contains(method);
    if (slow) {
      final repo = params['repo'] as String? ?? '.';
      final short = repo.split('/').last.split('\\').last;
      final subject = params['commit'] as String? ??
          params['range'] as String? ??
          (params['last'] == 'true' ? 'HEAD' : null);
      _status('$method · $short${subject == null ? '' : ' · $subject'}');
    }
    final sw = Stopwatch()..start();

    final request = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
      'id': 1,
    });

    connection.add(_frame(request));
    await connection.flush();

    final buffer = <int>[];
    await for (final chunk in connection) {
      buffer.addAll(chunk);
      while (buffer.length >= 4) {
        final len = ByteData.sublistView(
          Uint8List.fromList(buffer.sublist(0, 4)),
        ).getUint32(0, Endian.big);
        if (buffer.length < 4 + len) break;
        final body = utf8.decode(buffer.sublist(4, 4 + len));
        buffer.removeRange(0, 4 + len);
        final decoded = jsonDecode(body);
        if (decoded is Map && !decoded.containsKey('id')) {
          _handleProgress(decoded as Map<String, dynamic>);
          continue;
        }
        sw.stop();
        _clearStatus();
        if (jsonOutput) {
          stdout.writeln(
            const JsonEncoder.withIndent('  ').convert(decoded),
          );
        } else {
          _prettyPrint(method, decoded, sw.elapsedMilliseconds);
        }
        await stdout.flush();
        await connection.close();
        return;
      }
    }
    await connection.close();
  } catch (e) {
    _clearStatus();
    stderr.writeln('error: $e');
    exit(1);
  }
}

// ── Progress display ──────────────────────────────────────────────

String _statusLine = '';

void _status(String text) {
  final changed = text != _statusLine;
  _statusLine = text;
  if (_isTty) {
    stderr.write('\x1B[2m  $text\x1B[0m');
  } else if (changed) {
    // No terminal to animate a status line in place, so emit each DISTINCT
    // phase as a plain, newline-terminated line. Without this, a piped caller
    // (an agent capturing stderr) saw nothing at all for the whole run — a
    // `review` could sit silent for minutes while the frames streamed past
    // unrendered. The frames always arrive; only the drawing was TTY-gated.
    // Deduped against the last line so a repeated phase does not spam, and on
    // stderr so stdout stays clean for `--json`.
    stderr.writeln('  $text');
  }
}

void _updateStatus(String text) {
  final changed = text != _statusLine;
  _statusLine = text;
  if (_isTty) {
    stderr.write('\r\x1B[K\x1B[2m  $text\x1B[0m');
  } else if (changed) {
    // Off-TTY: one plain line per distinct phase (see [_status]).
    stderr.writeln('  $text');
  }
}

void _clearStatus() {
  if (_isTty && _statusLine.isNotEmpty) {
    stderr.write('\r\x1B[K');
  }
  _statusLine = '';
}

void _handleProgress(Map<String, dynamic> decoded) {
  final params = decoded['params'] as Map<String, dynamic>?;
  if (params == null) return;
  final phase = params['phase'] as String? ?? '';
  final detail = params['detail'] as String? ?? '';
  final text = detail.isEmpty ? phase : '$phase  $detail';
  _updateStatus(text);
}

// ── Connection ────────────────────────────────────────────────────

Future<Socket?> _connect(Map<String, dynamic> params) async {
  final ipcDir = _ipcDir();
  if (ipcDir == null || !await Directory(ipcDir).exists()) return null;

  final cwd = params.remove('repo') as String? ?? Directory.current.path;

  final locks = <_LockInfo>[];
  await for (final entity in Directory(ipcDir).list()) {
    if (entity is! File || !entity.path.endsWith('.lock')) continue;
    try {
      final content = await entity.readAsString();
      final data = jsonDecode(content);
      if (data is Map && data['port'] is int && data['pid'] is int) {
        locks.add(_LockInfo(
          port: data['port'] as int,
          pid: data['pid'] as int,
          workspace: (data['workspace'] as String?) ?? '',
          file: entity,
        ));
      }
    } catch (_) {}
  }
  if (locks.isEmpty) return null;

  final normalized = cwd.replaceAll('\\', '/').toLowerCase();
  locks.sort((a, b) {
    final aN = a.workspace.replaceAll('\\', '/').toLowerCase();
    final bN = b.workspace.replaceAll('\\', '/').toLowerCase();
    final aMatch = normalized.startsWith(aN) ? aN.length : 0;
    final bMatch = normalized.startsWith(bN) ? bN.length : 0;
    return bMatch.compareTo(aMatch);
  });

  for (final lock in locks) {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        lock.port,
        timeout: const Duration(seconds: 2),
      );
      if (!params.containsKey('repo') && lock.workspace.isNotEmpty) {
        params['repo'] = lock.workspace;
      }
      return socket;
    } catch (_) {}
  }
  return null;
}

class _LockInfo {
  final int port;
  final int pid;
  final String workspace;
  final File file;
  const _LockInfo({
    required this.port,
    required this.pid,
    required this.workspace,
    required this.file,
  });
}

String? _ipcDir() => StoragePaths.ipcDirPathSync();

Map<String, dynamic> _parseParams(List<String> args) {
  final params = <String, dynamic>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--')) {
      final key = arg.substring(2);
      if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
        params[key] = args[++i];
      } else {
        params[key] = 'true';
      }
    } else if (!params.containsKey('_positional')) {
      params.putIfAbsent(_positionalKey(args, i), () => arg);
    }
  }
  return params;
}

String _positionalKey(List<String> args, int index) {
  return 'query';
}

Future<String?> _resolveGitRoot() async {
  try {
    final result = await Process.run('git', ['rev-parse', '--show-toplevel']);
    if (result.exitCode == 0) return (result.stdout as String).trim();
  } catch (_) {}
  return null;
}

Uint8List _frame(String json) {
  final bytes = utf8.encode(json);
  final frame = ByteData(4 + bytes.length);
  frame.setUint32(0, bytes.length, Endian.big);
  final out = frame.buffer.asUint8List();
  out.setRange(4, 4 + bytes.length, bytes);
  return out;
}

// ── Formatting helpers ────────────────────────────────────────────

String _dim(String s) => _isTty ? '\x1B[2m$s\x1B[0m' : s;
String _bold(String s) => _isTty ? '\x1B[1m$s\x1B[0m' : s;
String _yellow(String s) => _isTty ? '\x1B[33m$s\x1B[0m' : s;

String _fmtTokens(int t) {
  if (t >= 1000) return '${(t / 1000).toStringAsFixed(1)}k';
  return '$t';
}

String _timeFmt(int ms) {
  final s = ms / 1000;
  if (s < 10) return '${s.toStringAsFixed(1)}s';
  return '${s.round()}s';
}

// ── Pretty printers ──────────────────────────────────────────────

void _printDeadCode(Map<String, dynamic> result, int elapsedMs) {
  if (result['note'] != null) {
    stdout.writeln(_dim(result['note'].toString()));
    return;
  }
  final packages = result['packages'] as List<dynamic>? ?? [];
  final fullyDead = result['fullyDead'] as List<dynamic>? ?? [];
  final zombies = result['testZombies'] as List<dynamic>? ?? [];
  for (final pkg in packages) {
    final pm = pkg as Map<String, dynamic>;
    if (pm['hasAppEntry'] == false) {
      stdout.writeln('${_bold(pm['package'].toString())} '
          '${_dim('${pm['libFiles']} lib files · no app entry, reachability N/A')}');
    } else {
      stdout.writeln('${_bold(pm['package'].toString())} '
          '${_dim('${pm['alive']}/${pm['libFiles']} reachable · ${pm['dead']} dead · ${pm['joints']} joints')}');
    }
  }
  stdout.writeln('\n${_bold('Fully dead')} '
      '${_dim('(referenced by nothing): ${fullyDead.length}')}');
  for (final d in fullyDead) {
    stdout.writeln('  ${(d as Map<String, dynamic>)['path']}');
  }
  stdout.writeln('\n${_bold('Test-zombies')} '
      '${_dim('(only a test imports, dead in-app): ${zombies.length}')}');
  for (final z in zombies) {
    stdout.writeln('  ${(z as Map<String, dynamic>)['path']}');
  }
  final joints = result['joints'] as List<dynamic>? ?? [];
  stdout.writeln('\n${_bold('Load-bearing joints')} '
      '${_dim('(delete → N files orphaned): ${joints.length}')}');
  for (final j in joints.take(15)) {
    final jm = j as Map<String, dynamic>;
    stdout.writeln('  ${jm['load'].toString().padLeft(4)}  ${jm['path']}');
  }
  if (joints.length > 15) {
    stdout.writeln(_dim('  … ${joints.length - 15} more'));
  }
  stdout.writeln(_dim('\n${(elapsedMs / 1000).toStringAsFixed(1)}s'));
}

void _prettyPrint(String method, dynamic decoded, int elapsedMs) {
  if (decoded is! Map) {
    stdout.writeln(decoded);
    return;
  }
  if (decoded.containsKey('error')) {
    final err = decoded['error'];
    final errMsg = err is Map ? err['message'] : null;
    stderr.writeln('error: ${errMsg ?? err}');
    exit(1);
  }
  final result = decoded['result'] as Map<String, dynamic>?;
  if (result == null) {
    stdout.writeln('(no result)');
    return;
  }
  switch (method) {
    case 'review':
      _printReview(result, elapsedMs);
      break;
    case 'index':
      _printIndex(result, elapsedMs);
      break;
    case 'shake':
      _printShake(result, elapsedMs);
      break;
    case 'commit-message':
      // The message ALONE on stdout, so `manifold commit-message | git commit
      // -F -` works and an agent can use the output without parsing anything.
      // Everything else goes to stderr where it cannot contaminate it.
      stdout.write(result['message'] ?? '');
      if (!(result['message'] as String? ?? '').endsWith('\n')) {
        stdout.writeln();
      }
      _printCommitMessageMeta(result, elapsedMs);
      break;
    case 'state':
      _printState(result);
      break;
    case 'review-evidence':
      _printEvidence(result, elapsedMs);
      break;
    case 'muse':
      _printMuse(result, elapsedMs);
      break;
    case 'deadcode':
      _printDeadCode(result, elapsedMs);
      break;
    case 'status':
      stdout.writeln('${result['branch']} '
          '↑${result['ahead']} ↓${result['behind']}');
      for (final f in (result['files'] as List<dynamic>? ?? [])) {
        final fm = f as Map<String, dynamic>;
        stdout.writeln('  ${fm['staged']}${fm['unstaged']} ${fm['path']}');
      }
      break;
    case 'repos':
      for (final r in (result['repos'] as List<dynamic>? ?? [])) {
        final rm = r as Map<String, dynamic>;
        final active = rm['active'] == true ? '* ' : '  ';
        final engine = rm['engineReady'] == true ? ' ${_dim('[engine]')}' : '';
        stdout.writeln('$active${rm['path']}$engine');
      }
      break;
    case 'blast-radius':
      stdout.writeln('Blast radius for ${(result['seeds'] as List<dynamic>).join(', ')}:');
      for (final r in (result['results'] as List<dynamic>? ?? [])) {
        final rm = r as Map<String, dynamic>;
        final anchor = rm['anchor'] != null ? ' ${_dim('via ${rm['anchor']}')}' : '';
        stdout.writeln('  ${_pad(rm['coupling'])} ${rm['path']}$anchor');
      }
      break;
    case 'coherence':
      stdout.writeln(
        'Coherence: ${_bold('${result['coherence']}')} ${_dim('(${result['assessment']})')}',
      );
      break;
    case 'suggest':
      final suggestions = result['suggestions'] as List<dynamic>? ?? [];
      if (suggestions.isEmpty) {
        stdout.writeln(_dim('No suggestions.'));
      } else {
        for (final s in suggestions) {
          final sm = s as Map<String, dynamic>;
          stdout.writeln('  ${sm['score']}  ${sm['path']}  ${_dim('via ${sm['anchor']}')}');
        }
      }
      break;
    case 'profile':
      stdout.writeln(result['file']);
      stdout.writeln('  volatility  ${result['volatility']} ${_dim('z=${result['volZ']}')}');
      stdout.writeln('  integrity   ${result['integrity']}');
      stdout.writeln('  centrality  ${result['centrality']}');
      stdout.writeln('  touches     ${result['touchCount']}');
      break;
    case 'architecture':
      for (final c in (result['subsystems'] as List<dynamic>? ?? [])) {
        final cm = c as Map<String, dynamic>;
        final density = cm['density'] ?? 0;
        stdout.writeln(
          '${_bold(cm['label'] as String)} ${_dim('${cm['fileCount']} files · density $density')}',
        );
        for (final f in (cm['sample'] as List<dynamic>? ?? [])) {
          stdout.writeln('  $f');
        }
        if ((cm['sample'] as List<dynamic>? ?? []).length < (cm['fileCount'] as int? ?? 0)) {
          stdout.writeln(_dim('  ...'));
        }
      }
      break;
    case 'explain':
      stdout.writeln('${result['file']}: ${result['summary']}');
      break;
    case 'recent':
      for (final c in (result['commits'] as List<dynamic>? ?? [])) {
        final cm = c as Map<String, dynamic>;
        stdout.writeln('  ${_dim(cm['hash'] as String)} ${cm['subject']}');
      }
      break;
    case 'dream':
      stdout.writeln(result['phrase'] ?? _dim('(no dream)'));
      break;
    case 'search':
      for (final r in (result['results'] as List<dynamic>? ?? [])) {
        final rm = r as Map<String, dynamic>;
        stdout.writeln('  ${_pad(rm['relevance'])} ${rm['path']}');
      }
      break;
    case 'test-map':
      for (final t in (result['tests'] as List<dynamic>? ?? [])) {
        final tm = t as Map<String, dynamic>;
        stdout.writeln('  ${_pad(tm['coupling'])} ${tm['path']}');
      }
      break;
    case 'who-knows':
      for (final e in (result['experts'] as List<dynamic>? ?? [])) {
        final em = e as Map<String, dynamic>;
        stdout.writeln(
          '  ${((em['share'] as num) * 100).round()}%  ${em['email']} ${_dim('(${em['commits']})')}',
        );
      }
      break;
    case 'impact':
      stdout.writeln('Sources:');
      for (final s in (result['sources'] as List<dynamic>? ?? [])) {
        final sm = s as Map<String, dynamic>;
        stdout.writeln('  ${_pad(sm['weight'])} ${sm['path']}');
      }
      stdout.writeln('Ripple:');
      for (final r in (result['ripple'] as List<dynamic>? ?? [])) {
        final rm = r as Map<String, dynamic>;
        stdout.writeln('  φ${_pad(rm['phi'])} ${rm['path']}');
      }
      break;
    default:
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(result),
      );
  }
}

/// Provenance for a generated commit message, on STDERR.
///
/// stdout carries the message and nothing else so it can be piped straight
/// into `git commit -F -`; a byte of decoration there would end up in the
/// commit. The reader still deserves to know which model wrote it.
void _printCommitMessageMeta(Map<String, dynamic> result, int elapsedMs) {
  if (!_isTty) return;
  final files = result['files'] as Map<String, dynamic>?;
  final model = (result['model'] as String? ?? '?').split('/').last;
  final settings =
      (result['settings'] as Map<String, dynamic>?)?['commitMessage']
          as Map<String, dynamic>?;
  final shape = settings == null
      ? ''
      : ' · ${settings['structure']}/${settings['voice']}';
  stderr.writeln(_dim('  ${files?['reviewed'] ?? '?'}/${files?['total'] ?? '?'}'
      ' files · $model$shape · ${_timeFmt(elapsedMs)}'));
}

void _printState(Map<String, dynamic> result) {
  String slot(Map<String, dynamic>? m) {
    if (m == null) return '?';
    final model = (m['model'] as String? ?? '').trim();
    final effort = m['effort'] as String?;
    final fast = m['fast'] == true ? ' fast' : '';
    return '${model.isEmpty ? '(none selected)' : model}'
        '${effort == null ? '' : ' · $effort'}$fast';
  }

  final ai = result['ai'] as Map<String, dynamic>? ?? const {};
  stdout.writeln(' ${_bold('AI')}  '
      '${_dim('guardrail ${ai['guardrailStage']} · '
          '${ai['readOnly'] == true ? 'read-only' : 'read-write'}'
          '${ai['categoriesLoaded'] == true ? '' : ' · providers not yet '
              'discovered'}')}');
  stdout.writeln('');

  final cm = result['commitMessage'] as Map<String, dynamic>?;
  stdout.writeln(' ${_bold('commit-message')}  ${slot(cm)}');
  if (cm != null) {
    stdout.writeln(_dim('   ${cm['structure']} · ${cm['voice']} · '
        '${cm['coverage']}'
        '${cm['customPrompt'] == true ? ' · custom prompt' : ''}'));
  }

  final rv = result['review'] as Map<String, dynamic>?;
  stdout.writeln(' ${_bold('review')}          ${slot(rv)}');
  if (rv != null) {
    stdout.writeln(_dim('   double-check '
        '${rv['doubleCheck'] == true ? 'on' : 'off'}'
        '${rv['customPrompt'] == true ? ' · custom prompt' : ''}'));
  }

  stdout.writeln(' ${_bold('shake')}           '
      '${_dim('shares review settings')}');

  final muse = result['muse'] as Map<String, dynamic>?;
  if (muse != null) {
    stdout.writeln(' ${_bold('muse')}');
    stdout.writeln('   brainstorm      ${slot(
        muse['brainstorm'] as Map<String, dynamic>?)}');
    stdout.writeln('   synthesis       ${slot(
        muse['synthesis'] as Map<String, dynamic>?)}');
    final strands = muse['strands'] as List<dynamic>? ?? const [];
    stdout.writeln('   strands         ${strands.map((e) {
      final m = e as Map<String, dynamic>;
      return m['count'] == 1 ? '${m['kind']}' : '${m['kind']}×${m['count']}';
    }).join(', ')}');
    if (muse['customPrompt'] == true) {
      stdout.writeln(_dim('   custom prompt'));
    }
  }

  final vocab = result['strandVocabulary'] as List<dynamic>? ?? const [];
  if (vocab.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln(_dim(' strands available: ${vocab.join(', ')}'));
  }
}

/// Trim a long region name from the LEFT, keeping the tail.
///
/// A monorepo path is informative at its end and boilerplate at its start:
/// `apps/desktop-flutter/lib/backend` and `apps/desktop-flutter/lib/features`
/// differ in their last segment and agree for thirty characters before it.
/// Cutting the front keeps the part that distinguishes one region from
/// another. Not done in the planner — the label is the real name, and how
/// much of it fits on a terminal line is the terminal's business.
String _elideLeft(String s, int max) =>
    s.length <= max ? s : '…${s.substring(s.length - max + 1)}';

void _printShake(Map<String, dynamic> result, int elapsedMs) {
  final domain = result['domainFiles'] as int? ?? 0;
  final examined = result['examinedFiles'] as int? ?? 0;
  final pendingFiles = result['pendingFiles'] as int? ?? 0;
  final pendingRegions = result['pendingRegions'] as int? ?? 0;
  final pct = domain == 0 ? 0 : (examined * 100 / domain).round();

  stdout.writeln(
    ' ${_bold('$examined/$domain')} files examined ${_dim('($pct%)')} · '
    '$pendingRegions region${pendingRegions == 1 ? '' : 's'} pending '
    '${_dim('($pendingFiles files)')} · ${_timeFmt(elapsedMs)}',
  );
  if (result['engineReady'] == false) {
    stdout.writeln(_dim('   engine cold — grouping by directory, ordering by '
        'path'));
  }
  // Said once instead of on all sixty-eight region names.
  final prefix = result['commonPrefix']?.toString() ?? '';
  if (prefix.isNotEmpty) {
    stdout.writeln(_dim('   under $prefix/'));
  }

  // What was deliberately left out, always stated. A sweep that quietly skips
  // things reports a coverage it does not have.
  final excluded = result['excluded'] as Map<String, dynamic>? ?? const {};
  final parts = <String>[];
  for (final entry in excluded.entries) {
    final count = (entry.value as Map<String, dynamic>?)?['count'] as int? ?? 0;
    if (count > 0) parts.add('$count ${entry.key}');
  }
  if (parts.isNotEmpty) {
    stdout.writeln(_dim('   excluded: ${parts.join(' · ')}'));
  }
  stdout.writeln('');

  if (result['planOnly'] == true) {
    final regions = result['regions'] as List<dynamic>? ?? const [];
    if (regions.isEmpty) {
      stdout.writeln(_dim(' Nothing pending — every file has been examined '
          'at its current content.'));
      return;
    }
    // "never examined" on every line distinguishes nothing; say it once when
    // it is universal, and per-line only when it actually separates regions.
    final allNew = regions.every((r) =>
        (r as Map<String, dynamic>)['unexamined'] == true);
    stdout.writeln('${_bold(' Next up')}'
        '${allNew ? _dim('   (nothing here has been examined yet)') : ''}');
    for (final r in regions) {
      final rm = r as Map<String, dynamic>;
      final files = rm['files'] as int? ?? 0;
      final unreviewed = rm['neverHumanReviewed'] as int? ?? 0;
      final marks = <String>[
        if (!allNew && rm['unexamined'] == true) 'new',
        // A count only earns its place when it is not simply "all of them".
        if (unreviewed > 0 && unreviewed < files) '$unreviewed unreviewed',
        if (unreviewed > 0 && unreviewed == files) 'none reviewed',
      ];
      stdout.writeln('   ${files.toString().padLeft(3)}  '
          '${_elideLeft(rm['label'] as String, 54)}'
          '${marks.isEmpty ? '' : ' ${_dim('· ${marks.join(' · ')}')}'}');
    }
    return;
  }

  final audited = result['audited'] as List<dynamic>? ?? const [];
  if (audited.isEmpty) {
    stdout.writeln(_dim(' Nothing to shake — the sweep is complete.'));
    return;
  }
  for (final a in audited) {
    final am = a as Map<String, dynamic>;
    if (am['error'] != null) {
      stdout.writeln(' ${_yellow('▲')} ${am['region']}  '
          '${_dim(am['error'].toString())}');
      continue;
    }
    stdout.writeln(' ${_bold('${am['score']}')}  ${am['verdict']} · '
        '${am['region']}');
    stdout.writeln('   ${am['summary']}');
    stdout.writeln('');
    for (final f in (am['findings'] as List<dynamic>? ?? const [])) {
      final fm = f as Map<String, dynamic>;
      final sev = (fm['severity'] as String?) ?? '';
      final marker = sev == 'warn' || sev == 'critical' ? _yellow('▲') : '△';
      stdout.writeln(' $marker ${_bold(fm['title'] as String)}  ${_dim(sev)}');
      if (fm['file'] != null) stdout.writeln('   ${_dim(fm['file'] as String)}');
      stdout.writeln('   ${fm['evidence']}');
      final why = fm['why'] as String?;
      if (why != null && why.isNotEmpty) {
        stdout.writeln('   ${_dim('→ $why')}');
      }
      stdout.writeln('');
    }
    final obs = am['observations'] as List<dynamic>? ?? const [];
    if (obs.isNotEmpty) {
      stdout.writeln(
          _dim(' ${obs.length} observation${obs.length == 1 ? '' : 's'}'));
      for (final o in obs) {
        stdout.writeln(' ${_dim('·')} ${(o as Map<String, dynamic>)['title']}');
      }
      stdout.writeln('');
    }
  }

  if (result['complete'] == true) {
    stdout.writeln(_dim(' Sweep complete — every file examined at its '
        'current content.'));
  } else {
    stdout.writeln(_dim(' $pendingRegions region'
        '${pendingRegions == 1 ? '' : 's'} still pending. Run again to '
        'continue; the ledger remembers.'));
  }
}

void _printIndex(Map<String, dynamic> result, int elapsedMs) {
  final engine = result['engine'] as Map<String, dynamic>? ?? const {};
  final coupling = result['coupling'] as Map<String, dynamic>? ?? const {};
  final repo = result['repo']?.toString() ?? '?';
  final short = repo.split('/').last.split('\\').last;

  final state = result['checkOnly'] == true
      ? 'checked'
      : result['alreadyKnown'] == true
          ? 'already indexed'
          : 'indexed';
  stdout.writeln(' ${_bold(short)}  ${_dim('$state · ${_timeFmt(elapsedMs)}')}');
  stdout.writeln(_dim('   $repo'));
  stdout.writeln('');

  stdout.writeln('   ${'branch'.padRight(12)}${result['branch'] ?? '?'}');
  stdout.writeln('   ${'commits'.padRight(12)}${result['commits'] ?? 0}');
  stdout.writeln('   ${'tracked'.padRight(12)}${result['trackedFiles'] ?? 0} files');

  if (engine['ready'] == true) {
    stdout.writeln('   ${'engine'.padRight(12)}${engine['graphFiles']} files · '
        '${engine['commitsOnAxis']} commits on axis '
        '${_dim('(${_timeFmt(engine['ms'] as int? ?? 0)})')}');
  } else {
    stdout.writeln('   ${'engine'.padRight(12)}'
        '${_yellow('unavailable')} ${_dim(engine['error']?.toString() ?? '')}');
  }
  stdout.writeln('   ${'coupling'.padRight(12)}'
      '${coupling['ready'] == true ? 'ready' : _yellow('unavailable')}');

  // The one property that makes reviewing history impossible.
  if (result['shallow'] == true) {
    stdout.writeln('');
    stdout.writeln(_yellow(' ▲ shallow clone'));
    stdout.writeln(_dim('   The oldest commits have no parent here, so they '
        'cannot be reviewed.'));
    stdout.writeln(_dim('   Run `git fetch --unshallow` to review the full '
        'history.'));
  }
  if (result['commits'] == 0) {
    stdout.writeln('');
    stdout.writeln(_dim(' No commits yet — there is nothing to review until '
        'the first one.'));
  }
}

void _printReview(Map<String, dynamic> result, int elapsedMs) {
  // A result map without its core fields is a FAILURE, not a quiet
  // review — rendering it as "null · ?/? files · No findings." (observed
  // after a 100-minute app-side provider hang) is the worst possible
  // outcome: it reads as a clean bill. Fail loudly, exit nonzero.
  if (result['score'] == null || result['summary'] == null) {
    _failEmptyResult('review', elapsedMs);
  }
  final files = result['files'] as Map<String, dynamic>?;
  final reviewed = files?['reviewed'] ?? '?';
  final total = files?['total'] ?? '?';
  final model = (result['model'] as String? ?? '?').split('/').last;
  final score = result['score'];
  final verdict = result['verdict'] ?? '';
  final enrichment = result['enrichment'] as Map<String, dynamic>?;
  final coupling = enrichment?['coupling'] == true;
  final symbols = enrichment?['symbols'] == true;
  final inTok = result['inputTokens'] as int? ?? 0;
  final outTok = result['outputTokens'] as int? ?? 0;

  // Header
  final tokenStr = inTok > 0
      ? ' · ${_fmtTokens(inTok)} in → ${_fmtTokens(outTok)} out'
      : '';
  stdout.writeln(
    ' ${_bold('$score')}  $verdict · $reviewed/$total files · $model · ${_timeFmt(elapsedMs)}'
    '${coupling || symbols ? ' · ${coupling ? '✓' : '–'}c ${symbols ? '✓' : '–'}s' : ''}'
    '$tokenStr',
  );
  // What was actually reviewed, as the resolver described it — "commit
  // a1b2c3d — subject", "main...feature (12 commits)". Worth its own line
  // because a review of the wrong revision looks exactly like a review of the
  // right one.
  final scope = result['scope']?.toString() ?? '';
  if (scope.isNotEmpty) stdout.writeln(_dim('   $scope'));
  stdout.writeln('');
  stdout.writeln(' ${result['summary']}');
  stdout.writeln('');

  // Findings
  final findings = result['findings'] as List<dynamic>? ?? [];
  if (findings.isNotEmpty) {
    for (final f in findings) {
      final fm = f as Map<String, dynamic>;
      final sev = (fm['severity'] as String?) ?? '';
      final marker = sev == 'warn' || sev == 'critical'
          ? _yellow('▲') : '△';
      final sevLabel = sev.isNotEmpty ? _dim(sev) : '';
      stdout.writeln(' $marker ${_bold(fm['title'] as String)}  $sevLabel');
      final loc = fm['file'] as String?;
      if (loc != null) {
        final hunk = fm['hunk'] as String?;
        stdout.writeln('   ${_dim(hunk != null ? '$loc $hunk' : loc)}');
      }
      stdout.writeln('   ${fm['evidence']}');
      final why = fm['why'] as String?;
      if (why != null && why.isNotEmpty) {
        stdout.writeln('   ${_dim('→ $why')}');
      }
      stdout.writeln('');
    }
  }

  // Observations — compact
  final obs = result['observations'] as List<dynamic>? ?? [];
  if (obs.isNotEmpty) {
    stdout.writeln(_dim(' ${obs.length} observation${obs.length == 1 ? '' : 's'}'));
    for (final o in obs) {
      final om = o as Map<String, dynamic>;
      stdout.writeln(' ${_dim('·')} ${om['title']}');
    }
  }

  if (findings.isEmpty && obs.isEmpty) {
    stdout.writeln(_dim(' No findings.'));
  }
}

/// The shared empty-result failure: loud, actionable, nonzero exit.
Never _failEmptyResult(String what, int elapsedMs) {
  stderr.writeln(
      'error: $what returned an empty result after ${_timeFmt(elapsedMs)} — '
      'app-side failure or a hung AI provider. Retry; if it persists, '
      'restart Manifold.');
  exit(2);
}

String _p3(dynamic v) => (v as num?)?.toStringAsFixed(3) ?? '?';

void _printEvidence(Map<String, dynamic> result, int elapsedMs) {
  final files = result['files'] as Map<String, dynamic>?;
  final reviewed = files?['reviewed'] ?? '?';
  final total = files?['total'] ?? '?';
  final diag = result['diagnostics'] as Map<String, dynamic>?;
  final promptChars = result['promptChars'] as int? ?? 0;
  final diffChars = result['diffChars'] as int? ?? 0;

  stdout.writeln(
    ' evidence · $reviewed/$total files · ${_timeFmt(elapsedMs)} · '
    '${_fmtTokens(diffChars)} diff → ${_fmtTokens(promptChars)} prompt',
  );
  stdout.writeln('');

  if (diag == null) {
    stdout.writeln(_dim(' (no diagnostics)'));
    return;
  }

  String ms(dynamic micros) =>
      '${((micros as int? ?? 0) / 1000).toStringAsFixed(1)}ms';

  // Phase timings
  final t = diag['timingMicros'] as Map<String, dynamic>? ?? {};
  stdout.writeln(_bold(' phases'));
  stdout.writeln('   git        ${ms(t['gitDerivation'])}');
  stdout.writeln('   diffusion  ${ms(t['logosDiffusion'])}');
  stdout.writeln('   bundle     ${ms(t['diffBundle'])}');
  stdout.writeln('   assembly   ${ms(t['producerAssembly'])}');
  stdout.writeln('   telemetry  ${ms(t['telemetryAwait'])}');
  stdout.writeln('   ${_dim('total')}      ${ms(t['total'])}');
  stdout.writeln('');

  // Channels + partition
  final ch = diag['channels'] as Map<String, dynamic>? ?? {};
  final dif = diag['diffusion'] as Map<String, dynamic>? ?? {};
  stdout.writeln(_bold(' channels'));
  stdout.writeln('   ranked ${ch['ranked']}  residuals ${ch['residuals']}  '
      'transport ${ch['transportPull']}  inquiry ${ch['inquirySteps']}');
  final part = dif['partition'] as Map<String, dynamic>?;
  if (part != null) {
    stdout.writeln('   partition  ctx ${_p3(part['ctx'])}  meta ${_p3(part['meta'])}  '
        'nbhd ${_p3(part['nbhd'])}  flow ${_p3(part['flow'])}');
  } else {
    stdout.writeln(_dim('   partition  (cold-start — no spectral basis)'));
  }
  stdout.writeln('');

  // Producers, sorted by wall time
  final producers = diag['producers'] as List<dynamic>? ?? [];
  if (producers.isNotEmpty) {
    stdout.writeln('${_bold(' producers')} ${_dim('(budget→produced · ms)')}');
    final sorted = [...producers]
      ..sort((a, b) => ((b as Map)['elapsedMicros'] as int)
          .compareTo((a as Map)['elapsedMicros'] as int));
    for (final p in sorted) {
      final pm = p as Map<String, dynamic>;
      final empty = pm['empty'] == true ? _yellow(' ∅') : '';
      stdout.writeln('   ${(pm['id'] as String).padRight(24)} '
          '${_fmtTokens(pm['budgetChars'] as int)}→${_fmtTokens(pm['producedChars'] as int)}  '
          '${ms(pm['elapsedMicros'])}$empty');
    }
    stdout.writeln('');
  }

  // Gaps
  final gaps = diag['gaps'] as List<dynamic>? ?? [];
  if (gaps.isEmpty) {
    stdout.writeln(_dim(' no gaps'));
  } else {
    stdout.writeln(
        _yellow(' ${gaps.length} gap${gaps.length == 1 ? '' : 's'}'));
    for (final g in gaps) {
      stdout.writeln(' ${_dim('·')} $g');
    }
  }
}

void _printMuse(Map<String, dynamic> result, int elapsedMs) {
  // Same empty-result guard as review: a field-less map is a failure.
  if (result['brainstormModel'] == null && result['model'] == null) {
    _failEmptyResult('muse', elapsedMs);
  }
  final files = result['files'] as Map<String, dynamic>?;
  final reviewed = files?['reviewed'] ?? '?';
  final total = files?['total'] ?? '?';
  final model = (result['brainstormModel'] ?? result['model'] ?? '?')
      .toString().split('/').last;
  final enrichment = result['enrichment'] as Map<String, dynamic>?;
  final coupling = enrichment?['coupling'] == true;
  final symbols = enrichment?['symbols'] == true;
  final tokens = result['tokens'] as Map<String, dynamic>?;
  final totalIn = tokens?['totalIn'] as int? ?? 0;
  final totalOut = tokens?['totalOut'] as int? ?? 0;

  // Header
  final tokenStr = totalIn > 0
      ? ' · ${_fmtTokens(totalIn)} in → ${_fmtTokens(totalOut)} out'
      : '';
  stdout.writeln(
    ' muse · $reviewed/$total files · $model · ${_timeFmt(elapsedMs)}'
    '${coupling || symbols ? ' · ${coupling ? '✓' : '–'}c ${symbols ? '✓' : '–'}s' : ''}'
    '$tokenStr',
  );
  stdout.writeln('');

  // Proposals grouped by tier
  final proposals = result['proposals'] as List<dynamic>? ?? [];
  String? lastTier;
  for (final p in proposals) {
    final pm = p as Map<String, dynamic>;
    if (pm['tier'] != lastTier) {
      lastTier = pm['tier'] as String?;
      stdout.writeln(_dim(' ${(lastTier ?? 'unknown').toUpperCase()}'));
    }
    stdout.writeln(' ${_bold('·')} ${_bold(pm['title'] as String)}');
    stdout.writeln('   ${pm['vision']}');
    final foothold = pm['foothold'] as String?;
    if (foothold != null && foothold.isNotEmpty) {
      stdout.writeln('   ${_dim('foothold:')} $foothold');
    }
    final cites = (pm['citations'] as List<dynamic>?)?.join(', ') ?? '';
    if (cites.isNotEmpty) stdout.writeln('   ${_dim(cites)}');
    stdout.writeln('');
  }

  if (proposals.isEmpty) {
    stdout.writeln(_dim(' No proposals.'));
  }
}

String _pad(dynamic v) {
  final s = v is double ? v.toStringAsFixed(4) : '$v';
  return s.padLeft(7);
}

void _printVersion() {
  // Mirrors BuildInfo.versionDisplay without importing app code: BuildInfo
  // lives behind package:flutter, and this binary must stay runnable on the
  // plain Dart VM.
  const versionDefine = String.fromEnvironment('MANIFOLD_VERSION');
  const shaDefine = String.fromEnvironment('MANIFOLD_GIT_SHA');
  final version = versionDefine.isEmpty
      ? 'dev'
      : (shaDefine.isEmpty
          ? versionDefine
          : '$versionDefine '
              '(${shaDefine.substring(0, shaDefine.length < 7 ? shaDefine.length : 7)})');
  stdout.writeln('manifold $version');
  stdout.writeln('© 2026 Woflo Labs');
  stdout.writeln(
    'GPL-3.0-or-later with the Manifold-Woflo exception; '
    'research components under WLCSL-1.0. See LICENSE.md.',
  );
}

void _printUsage() {
  stdout.writeln('''
manifold — CLI bridge to the running Manifold git client.

Usage: manifold <command> [options]

Commands:
  status                        Branch, ahead/behind, dirty files
  state                         What Manifold is configured to do: models,
                                strands, prompts, commit format
  commit-message                Write the commit message for the current
                                change (message alone on stdout)
  index [--check]               Validate a repo, warm its engine, register it
  shake [--plan] [--regions N]  Audit the CODEBASE region by region, resuming
                                where the last run stopped (--plan: no AI call)
  review [--files <paths>]      AI code review (default: dirty files)
  review --last                 Review the newest commit
  review --commit <rev>         Review any single commit
  review --range <A..B>         Review a range (A...B measures from merge base)
  review-evidence [--files ..]  Gathered review evidence + telemetry (no model call)
  deadcode                      Files no live surface imports (dead + test-zombies)
  muse [--files <paths>]        AI brainstorm (default: dirty files)
  muse --strands <list>         Brainstorm with exactly these strands,
                                e.g. `--strands vertigo,ghost` or `spark:3`
  blast-radius --files <paths>  Co-change neighbors
  suggest --files <paths>       Coupled files you might have missed
  coherence --files <paths>     How cohesive is a file set (0-1)
  profile --file <path>         Volatility, integrity, centrality
  test-map --files <paths>      Tests coupled to source files
  who-knows --file <path>       Expert authors for a file
  search --query <text>         Semantic code search
  architecture                  Spectral subsystem map
  dream                         Logos phrase for current diff
  impact --diff <text>          Predicted ripple of a diff
  diff [--file <path>]          Raw diff text
  repos                         List known repos
  ping                          Health check
  help                          API schema

Options:
  --json           Structured JSON-RPC output
  --repo <path>    Target repo (default: cwd)
  --commit <rev>   Review one commit instead of the working tree
  --range <spec>   Review a revision range: A..B compares the endpoints,
                   A...B compares from their merge base
  --last           Shorthand for --commit HEAD
  --plan           shake: show the order and coverage, spend no model call
  --regions <n>    shake: how many regions to audit this run (default 1)
  --reset          shake: forget what has been examined and sweep afresh
  --strands <list> muse: comma-separated strands to carry INSTEAD of the
                   configured loadout; `name:count` asks for several
  --existing <msg> commit-message: a draft to improve rather than replace

Every AI command reports the settings it ran under under `settings` in
--json output, so an agent never has to guess which model answered.
                   (--commit, --range and --last name different revisions;
                    pass at most one — together they are refused, never ranked)
  --limit <n>      Cap results
  --model <id>     Override model selection
  --budget <chars>  Token budget for context
  --version, -v    Print version and license summary

File params accept: --files, --file, --path, --seeds, --changed.
With --commit/--range they SCOPE the revision diff rather than select
dirty files.

Any command works on a repo Manifold has never been told about — point it
at a git checkout and it resolves from the working directory. `index`
registers one so it appears as a project.

© 2026 Woflo Labs · GPL-3.0-or-later with the Manifold-Woflo exception; research components under WLCSL-1.0. See LICENSE.md.
''');
}
