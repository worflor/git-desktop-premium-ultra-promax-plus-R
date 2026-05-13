import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'tool_detection.dart' show isOnPath;
import 'win_job_object.dart';

enum WickPosture { decisive, exploring, reaching, flinching }

WickPosture _parsePosture(String s) => switch (s) {
      'decisive' => WickPosture.decisive,
      'exploring' => WickPosture.exploring,
      'reaching' => WickPosture.reaching,
      _ => WickPosture.flinching,
    };

class WickReason {
  final String kind;
  final String? viaLane;
  final String? viaExternalId;

  const WickReason({required this.kind, this.viaLane, this.viaExternalId});

  factory WickReason.fromJson(Map<String, dynamic> j) => WickReason(
        kind: j['kind'] as String? ?? 'faint',
        viaLane: j['via_lane'] as String?,
        viaExternalId: j['via_external_id'] as String?,
      );
}

class WickUnit {
  final String id;
  final String text;
  final int tokens;
  final int rank;
  final WickReason reason;
  final String lane;

  const WickUnit({
    required this.id,
    required this.text,
    required this.tokens,
    required this.rank,
    required this.reason,
    required this.lane,
  });

  factory WickUnit.fromJson(Map<String, dynamic> j) => WickUnit(
        id: j['id'] as String? ?? '',
        text: j['text'] as String? ?? '',
        tokens: j['tokens'] as int? ?? 0,
        rank: j['rank'] as int? ?? 0,
        reason: WickReason.fromJson(
            j['reason'] as Map<String, dynamic>? ?? const {}),
        lane: j['lane'] as String? ?? 'peripheral',
      );

  String get filePath => id.split('#').first;
  String get fileName => filePath.split('/').last;
}

class WickQueryResponse {
  final List<WickUnit> packet;
  final WickPosture posture;
  final double confidence;
  final double elapsedMs;

  const WickQueryResponse({
    required this.packet,
    required this.posture,
    required this.confidence,
    required this.elapsedMs,
  });

  factory WickQueryResponse.fromJson(Map<String, dynamic> j) =>
      WickQueryResponse(
        packet: (j['packet'] as List<dynamic>?)
                ?.map((u) => WickUnit.fromJson(u as Map<String, dynamic>))
                .toList() ??
            const [],
        posture: _parsePosture(j['posture'] as String? ?? ''),
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
        elapsedMs: (j['elapsed_ms'] as num?)?.toDouble() ?? 0.0,
      );
}

class WickInfo {
  final int units;
  final int structuralEdges;
  final int transportEdges;

  const WickInfo({
    required this.units,
    required this.structuralEdges,
    required this.transportEdges,
  });

  factory WickInfo.fromJson(Map<String, dynamic> j) => WickInfo(
        units: j['units'] as int? ?? 0,
        structuralEdges: j['structural_edges'] as int? ?? 0,
        transportEdges: j['transport_edges'] as int? ?? 0,
      );
}

class WickResult<T> {
  final T? data;
  final String? error;
  bool get ok => error == null;
  const WickResult.ok(T this.data) : error = null;
  const WickResult.err(String this.error) : data = null;
}

Future<bool> isWickInstalled({String? customPath}) async {
  if (customPath != null && customPath.isNotEmpty) {
    return File(customPath).exists();
  }
  return isOnPath('wick');
}

String _wickExe(String? customPath) =>
    (customPath != null && customPath.isNotEmpty) ? customPath : 'wick';

String wickDbPath(String repoPath) {
  final sep = Platform.pathSeparator;
  return '$repoPath$sep.manifold${sep}wick.db';
}

Future<WickResult<void>> wickIndex(
  String repoPath, {
  String? customPath,
  Duration timeout = const Duration(minutes: 5),
}) async {
  Process? process;
  try {
    final db = wickDbPath(repoPath);
    await Directory('$repoPath${Platform.pathSeparator}.manifold')
        .create(recursive: true);
    process = await Process.start(
      _wickExe(customPath),
      ['index', repoPath, '--db', db],
      workingDirectory: repoPath,
    );
    WinJobObject.assignProcess(process.pid);
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    unawaited(process.stdout.drain<void>());
    final exitCode = await process.exitCode.timeout(timeout);
    final stderr = await stderrFuture;
    if (exitCode != 0) {
      return WickResult.err(
          stderr.trim().isNotEmpty ? stderr.trim() : 'exit $exitCode');
    }
    return const WickResult.ok(null);
  } on TimeoutException {
    process?.kill();
    return const WickResult.err('index timed out');
  } on ProcessException catch (e) {
    return WickResult.err(e.message);
  } catch (e) {
    return WickResult.err(e.toString());
  }
}

/// Cancellable query handle. Caller holds one instance and passes it
/// to each `wickQuery` call — the previous process is killed before
/// spawning the next, scoped to the caller's lifecycle.
class WickQueryHandle {
  Process? _process;
  void cancel() { _process?.kill(); _process = null; }
}

Future<WickResult<WickQueryResponse>> wickQuery(
  String repoPath,
  String query, {
  String? customPath,
  WickQueryHandle? handle,
  int budget = 1500,
  Duration timeout = const Duration(seconds: 10),
}) async {
  Process? process;
  try {
    handle?.cancel();
    final db = wickDbPath(repoPath);
    process = await Process.start(
      _wickExe(customPath),
      [
        'query', query,
        '--db', db,
        '--budget', '$budget',
        '--format', 'json',
      ],
      workingDirectory: repoPath,
    );
    WinJobObject.assignProcess(process.pid);
    handle?._process = process;
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    final stdout = await process.stdout
        .transform(utf8.decoder)
        .join()
        .timeout(timeout);
    final exitCode = await process.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () { process!.kill(); return -1; },
    );
    final stderr = await stderrFuture;
    if (handle?._process == process) handle?._process = null;
    if (exitCode != 0) {
      return WickResult.err(
          stderr.trim().isNotEmpty ? stderr.trim() : 'exit $exitCode');
    }
    final json = jsonDecode(stdout.trim()) as Map<String, dynamic>;
    return WickResult.ok(WickQueryResponse.fromJson(json));
  } on TimeoutException {
    process?.kill();
    if (handle?._process == process) handle?._process = null;
    return const WickResult.err('query timed out');
  } on ProcessException catch (e) {
    return WickResult.err(e.message);
  } on FormatException catch (e) {
    return WickResult.err('bad json: ${e.message}');
  } catch (e) {
    return WickResult.err(e.toString());
  }
}

Future<WickResult<WickInfo>> wickInfo(String repoPath, {String? customPath}) async {
  try {
    final db = wickDbPath(repoPath);
    final result = await Process.run(
      _wickExe(customPath),
      ['info', '--json', '--db', db],
      workingDirectory: repoPath,
    );
    if (result.exitCode != 0) {
      return WickResult.err(
          (result.stderr as String?)?.trim() ?? 'exit ${result.exitCode}');
    }
    final json = jsonDecode((result.stdout as String).trim())
        as Map<String, dynamic>;
    return WickResult.ok(WickInfo.fromJson(json));
  } on ProcessException catch (e) {
    return WickResult.err(e.message);
  } on FormatException catch (e) {
    return WickResult.err('bad json: ${e.message}');
  } catch (e) {
    return WickResult.err(e.toString());
  }
}
