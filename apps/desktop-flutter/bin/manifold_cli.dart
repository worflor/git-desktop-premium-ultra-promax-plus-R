import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:git_desktop/backend/storage_paths.dart';

void main(List<String> args) async {
  if (args.isEmpty || args.first == '--help' || args.first == '-h') {
    _printUsage();
    exit(0);
  }

  final method = args.first;
  final params = _parseParams(args.skip(1).toList());
  final jsonOutput = params.remove('json') == 'true';

  try {
    // Pass a copy so _connect's repo removal doesn't eat the
    // command's own --repo param (needed by 'switch').
    final connection = await _connect(Map.of(params));
    if (connection == null) {
      stderr.writeln('Manifold is not running.');
      exit(1);
    }

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
      if (buffer.length >= 4) {
        final len = ByteData.sublistView(
          Uint8List.fromList(buffer.sublist(0, 4)),
        ).getUint32(0, Endian.big);
        if (buffer.length >= 4 + len) {
          final body = utf8.decode(buffer.sublist(4, 4 + len));
          final decoded = jsonDecode(body);
          if (jsonOutput) {
            stdout.writeln(
              const JsonEncoder.withIndent('  ').convert(decoded),
            );
          } else {
            _prettyPrint(method, decoded);
          }
          break;
        }
      }
    }
    await connection.close();
  } catch (e) {
    stderr.writeln('Error: $e');
    exit(1);
  }
}

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

  // Pick the lock whose workspace best matches the cwd.
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
      // If --repo wasn't explicit, thread the workspace so the server
      // knows which repo to target.
      if (!params.containsKey('repo') && lock.workspace.isNotEmpty) {
        params['repo'] = lock.workspace;
      }
      return socket;
    } catch (_) {
      // Stale lock — try next or give up.
    }
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
  // Map positional args to the param name the command expects.
  return 'query';
}

Uint8List _frame(String json) {
  final bytes = utf8.encode(json);
  final frame = ByteData(4 + bytes.length);
  frame.setUint32(0, bytes.length, Endian.big);
  final out = frame.buffer.asUint8List();
  out.setRange(4, 4 + bytes.length, bytes);
  return out;
}

void _prettyPrint(String method, dynamic decoded) {
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
    case 'status':
      stdout.writeln('${result['branch']} '
          '↑${result['ahead']} ↓${result['behind']}');
      final files = result['files'] as List? ?? [];
      for (final f in files) {
        stdout.writeln('  ${f['staged']}${f['unstaged']} ${f['path']}');
      }
      break;
    case 'repos':
      for (final r in (result['repos'] as List? ?? [])) {
        final active = r['active'] == true ? '* ' : '  ';
        final engine = r['engineReady'] == true ? ' [engine]' : '';
        stdout.writeln('$active${r['path']}$engine');
      }
      break;
    case 'blast-radius':
      stdout.writeln('Blast radius for ${(result['seeds'] as List).join(', ')}:');
      for (final r in (result['results'] as List? ?? [])) {
        final anchor = r['anchor'] != null ? ' (via ${r['anchor']})' : '';
        stdout.writeln(
          '  ${_pad(r['coupling'])} ${r['path']}$anchor',
        );
      }
      break;
    case 'coherence':
      stdout.writeln(
        'Coherence: ${result['coherence']} (${result['assessment']})',
      );
      break;
    case 'suggest':
      final suggestions = result['suggestions'] as List? ?? [];
      if (suggestions.isEmpty) {
        stdout.writeln('No suggestions.');
      } else {
        for (final s in suggestions) {
          stdout.writeln('  ${s['score']}  ${s['path']}  (via ${s['anchor']})');
        }
      }
      break;
    case 'profile':
      stdout.writeln('${result['file']}');
      stdout.writeln('  volatility: ${result['volatility']} (z=${result['volZ']})');
      stdout.writeln('  integrity:  ${result['integrity']}');
      stdout.writeln('  centrality: ${result['centrality']}');
      stdout.writeln('  touches:    ${result['touchCount']}');
      break;
    case 'architecture':
      for (final c in (result['subsystems'] as List? ?? [])) {
        final density = c['density'] ?? 0;
        stdout.writeln(
          '${c['label']} (${c['fileCount']} files, density ${density})',
        );
        for (final f in (c['sample'] as List? ?? [])) {
          stdout.writeln('  $f');
        }
        if ((c['sample'] as List? ?? []).length < (c['fileCount'] as int? ?? 0)) {
          stdout.writeln('  ...');
        }
      }
      break;
    case 'explain':
      stdout.writeln('${result['file']}: ${result['summary']}');
      break;
    case 'recent':
      for (final c in (result['commits'] as List? ?? [])) {
        stdout.writeln(
          '  ${c['hash']} ${c['subject']}',
        );
      }
      break;
    case 'dream':
      stdout.writeln(result['phrase'] ?? '(no dream)');
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
          '  ${(e['share'] * 100).round()}%  ${e['email']} (${e['commits']})',
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

String _pad(dynamic v) {
  final s = v is double ? v.toStringAsFixed(4) : '$v';
  return s.padLeft(7);
}

void _printUsage() {
  stdout.writeln('''
manifold — read-only CLI bridge to the running Manifold git client.

Usage: manifold <command> [options]

Commands:
  help                          Machine-readable API schema
  ping                          Health check (engine readiness)
  status                        Branch, ahead/behind, dirty files
  repos                         List known repos
  diff [--file <path>]          Get diff text
  blast-radius --files <paths>  Co-change neighbors (what breaks)
  context --files <paths>       Optimal reading list by coupling
  coherence --files <paths>     How cohesive is a file set (0-1)
  suggest --files <paths>       Coupled files you might have missed
  profile --file <path>         Volatility, integrity, centrality
  test-map --files <paths>      Tests coupled to source files
  architecture                  Spectral subsystem map
  who-knows --file <path>       Expert authors for a file
  search --query <text>         Semantic code search
  dream                         Logos commit phrase for current diff
  impact --diff <text>          Predicted ripple of a diff

Options:
  --json           Raw JSON-RPC output
  --repo <path>    Target repo (default: CWD match)
  --limit <n>      Cap results
  --budget <chars>  Token budget for context command

All commands are read-only. Engine commands wait up to 15s for warmup.
File params accept: --files, --file, --path, --seeds, --changed.
''');
}
