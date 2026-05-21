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

    final slow = const {'review', 'muse', 'impact', 'dream'}.contains(method);
    if (slow) {
      final repo = params['repo'] as String? ?? '.';
      final short = repo.split('/').last.split('\\').last;
      _status('$method · $short');
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
          _handleProgress(decoded);
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
  _statusLine = text;
  if (_isTty) {
    stderr.write('\x1B[2m  $text\x1B[0m');
  }
}

void _updateStatus(String text) {
  _statusLine = text;
  if (_isTty) {
    stderr.write('\r\x1B[K\x1B[2m  $text\x1B[0m');
  }
}

void _clearStatus() {
  if (_isTty && _statusLine.isNotEmpty) {
    stderr.write('\r\x1B[K');
  }
  _statusLine = '';
}

void _handleProgress(Map decoded) {
  final params = decoded['params'] as Map?;
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

void _prettyPrint(String method, dynamic decoded, int elapsedMs) {
  if (decoded is! Map) {
    stdout.writeln(decoded);
    return;
  }
  if (decoded.containsKey('error')) {
    final err = decoded['error'];
    stderr.writeln('error: ${err['message'] ?? err}');
    exit(1);
  }
  final result = decoded['result'];
  if (result == null) {
    stdout.writeln('(no result)');
    return;
  }
  switch (method) {
    case 'review':
      _printReview(result, elapsedMs);
      break;
    case 'muse':
      _printMuse(result, elapsedMs);
      break;
    case 'status':
      stdout.writeln('${result['branch']} '
          '↑${result['ahead']} ↓${result['behind']}');
      for (final f in (result['files'] as List? ?? [])) {
        stdout.writeln('  ${f['staged']}${f['unstaged']} ${f['path']}');
      }
      break;
    case 'repos':
      for (final r in (result['repos'] as List? ?? [])) {
        final active = r['active'] == true ? '* ' : '  ';
        final engine = r['engineReady'] == true ? ' ${_dim('[engine]')}' : '';
        stdout.writeln('$active${r['path']}$engine');
      }
      break;
    case 'blast-radius':
      stdout.writeln('Blast radius for ${(result['seeds'] as List).join(', ')}:');
      for (final r in (result['results'] as List? ?? [])) {
        final anchor = r['anchor'] != null ? ' ${_dim('via ${r['anchor']}')}' : '';
        stdout.writeln('  ${_pad(r['coupling'])} ${r['path']}$anchor');
      }
      break;
    case 'coherence':
      stdout.writeln(
        'Coherence: ${_bold('${result['coherence']}')} ${_dim('(${result['assessment']})')}',
      );
      break;
    case 'suggest':
      final suggestions = result['suggestions'] as List? ?? [];
      if (suggestions.isEmpty) {
        stdout.writeln(_dim('No suggestions.'));
      } else {
        for (final s in suggestions) {
          stdout.writeln('  ${s['score']}  ${s['path']}  ${_dim('via ${s['anchor']}')}');
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
      for (final c in (result['subsystems'] as List? ?? [])) {
        final density = c['density'] ?? 0;
        stdout.writeln(
          '${_bold(c['label'])} ${_dim('${c['fileCount']} files · density $density')}',
        );
        for (final f in (c['sample'] as List? ?? [])) {
          stdout.writeln('  $f');
        }
        if ((c['sample'] as List? ?? []).length < (c['fileCount'] as int? ?? 0)) {
          stdout.writeln(_dim('  ...'));
        }
      }
      break;
    case 'explain':
      stdout.writeln('${result['file']}: ${result['summary']}');
      break;
    case 'recent':
      for (final c in (result['commits'] as List? ?? [])) {
        stdout.writeln('  ${_dim(c['hash'])} ${c['subject']}');
      }
      break;
    case 'dream':
      stdout.writeln(result['phrase'] ?? _dim('(no dream)'));
      break;
    case 'search':
      for (final r in (result['results'] as List? ?? [])) {
        stdout.writeln('  ${_pad(r['relevance'])} ${r['path']}');
      }
      break;
    case 'test-map':
      for (final t in (result['tests'] as List? ?? [])) {
        stdout.writeln('  ${_pad(t['coupling'])} ${t['path']}');
      }
      break;
    case 'who-knows':
      for (final e in (result['experts'] as List? ?? [])) {
        stdout.writeln(
          '  ${(e['share'] * 100).round()}%  ${e['email']} ${_dim('(${e['commits']})')}',
        );
      }
      break;
    case 'impact':
      stdout.writeln('Sources:');
      for (final s in (result['sources'] as List? ?? [])) {
        stdout.writeln('  ${_pad(s['weight'])} ${s['path']}');
      }
      stdout.writeln('Ripple:');
      for (final r in (result['ripple'] as List? ?? [])) {
        stdout.writeln('  φ${_pad(r['phi'])} ${r['path']}');
      }
      break;
    default:
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert(result),
      );
  }
}

void _printReview(Map result, int elapsedMs) {
  final files = result['files'] as Map?;
  final reviewed = files?['reviewed'] ?? '?';
  final total = files?['total'] ?? '?';
  final model = (result['model'] as String? ?? '?').split('/').last;
  final score = result['score'];
  final verdict = result['verdict'] ?? '';
  final enrichment = result['enrichment'] as Map?;
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
  stdout.writeln('');
  stdout.writeln(' ${result['summary']}');
  stdout.writeln('');

  // Findings
  final findings = result['findings'] as List? ?? [];
  if (findings.isNotEmpty) {
    for (final f in findings) {
      final sev = (f['severity'] as String?) ?? '';
      final marker = sev == 'warn' || sev == 'critical'
          ? _yellow('▲') : '△';
      final sevLabel = sev.isNotEmpty ? _dim(sev) : '';
      stdout.writeln(' $marker ${_bold(f['title'])}  $sevLabel');
      final loc = f['file'] as String?;
      if (loc != null) {
        final hunk = f['hunk'] as String?;
        stdout.writeln('   ${_dim(hunk != null ? '$loc $hunk' : loc)}');
      }
      stdout.writeln('   ${f['evidence']}');
      final why = f['why'] as String?;
      if (why != null && why.isNotEmpty) {
        stdout.writeln('   ${_dim('→ $why')}');
      }
      stdout.writeln('');
    }
  }

  // Observations — compact
  final obs = result['observations'] as List? ?? [];
  if (obs.isNotEmpty) {
    stdout.writeln(_dim(' ${obs.length} observation${obs.length == 1 ? '' : 's'}'));
    for (final o in obs) {
      stdout.writeln(' ${_dim('·')} ${o['title']}');
    }
  }

  if (findings.isEmpty && obs.isEmpty) {
    stdout.writeln(_dim(' No findings.'));
  }
}

void _printMuse(Map result, int elapsedMs) {
  final files = result['files'] as Map?;
  final reviewed = files?['reviewed'] ?? '?';
  final total = files?['total'] ?? '?';
  final model = (result['brainstormModel'] ?? result['model'] ?? '?')
      .toString().split('/').last;
  final enrichment = result['enrichment'] as Map?;
  final coupling = enrichment?['coupling'] == true;
  final symbols = enrichment?['symbols'] == true;
  final tokens = result['tokens'] as Map?;
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
  final proposals = result['proposals'] as List? ?? [];
  String? lastTier;
  for (final p in proposals) {
    if (p['tier'] != lastTier) {
      lastTier = p['tier'] as String?;
      stdout.writeln(_dim(' ${(lastTier ?? 'unknown').toUpperCase()}'));
    }
    stdout.writeln(' ${_bold('·')} ${_bold(p['title'])}');
    stdout.writeln('   ${p['vision']}');
    final foothold = p['foothold'] as String?;
    if (foothold != null && foothold.isNotEmpty) {
      stdout.writeln('   ${_dim('foothold:')} $foothold');
    }
    final cites = (p['citations'] as List?)?.join(', ') ?? '';
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

void _printUsage() {
  stdout.writeln('''
manifold — CLI bridge to the running Manifold git client.

Usage: manifold <command> [options]

Commands:
  status                        Branch, ahead/behind, dirty files
  review [--files <paths>]      AI code review (default: dirty files)
  muse [--files <paths>]        AI brainstorm (default: dirty files)
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
  --limit <n>      Cap results
  --model <id>     Override model selection
  --budget <chars>  Token budget for context

File params accept: --files, --file, --path, --seeds, --changed.
''');
}
