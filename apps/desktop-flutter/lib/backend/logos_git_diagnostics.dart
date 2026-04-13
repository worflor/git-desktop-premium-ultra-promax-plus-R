// ═════════════════════════════════════════════════════════════════════════
// logos_git_diagnostics.dart — observability for the Logos engine
//
// Replaces the `catch (_) { return ''; }` pattern that was silently
// swallowing every failure. Every build, cache hit, failure, and
// diffusion call flows through here. The tail is a bounded ring buffer
// so long-running sessions don't grow unboundedly.
//
// Stateless-ish — one static instance. Hook into a debug panel or
// audit store later; for now, errors surface to debugPrint and tests
// can assert on them.
// ═════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';

/// A single event in the engine's life. Kept compact so we can hold
/// thousands without bloat.
class LogosGitEvent {
  final DateTime at;
  final String repoPath;
  final LogosGitEventKind kind;
  final String? message;
  final Duration? duration;
  final int? nodes;
  final String? stack;

  const LogosGitEvent({
    required this.at,
    required this.repoPath,
    required this.kind,
    this.message,
    this.duration,
    this.nodes,
    this.stack,
  });

  @override
  String toString() {
    final parts = <String>[
      at.toIso8601String(),
      kind.name,
      repoPath,
      if (nodes != null) '${nodes}n',
      if (duration != null) '${duration!.inMilliseconds}ms',
      if (message != null) message!,
    ];
    return parts.join(' | ');
  }
}

enum LogosGitEventKind { build, cacheHit, failure, diffuse }

class LogosGitDiagnostics {
  LogosGitDiagnostics._();
  static final LogosGitDiagnostics instance = LogosGitDiagnostics._();

  /// Bounded ring of recent events. Oldest drops when we overflow.
  final List<LogosGitEvent> _events = <LogosGitEvent>[];
  static const int _maxEvents = 256;

  List<LogosGitEvent> recent({int limit = 32}) {
    if (_events.length <= limit) return List.unmodifiable(_events);
    return List.unmodifiable(_events.sublist(_events.length - limit));
  }

  int get buildCount =>
      _events.where((e) => e.kind == LogosGitEventKind.build).length;
  int get failureCount =>
      _events.where((e) => e.kind == LogosGitEventKind.failure).length;

  void recordBuild({
    required String repoPath,
    required int nodes,
    required Duration duration,
  }) {
    _push(LogosGitEvent(
      at: DateTime.now(),
      repoPath: repoPath,
      kind: LogosGitEventKind.build,
      nodes: nodes,
      duration: duration,
    ));
  }

  void recordCacheHit(String repoPath, Duration duration) {
    _push(LogosGitEvent(
      at: DateTime.now(),
      repoPath: repoPath,
      kind: LogosGitEventKind.cacheHit,
      duration: duration,
    ));
  }

  void recordDiffuse({
    required String repoPath,
    required int sourceCount,
    required Duration duration,
    required double temperature,
  }) {
    _push(LogosGitEvent(
      at: DateTime.now(),
      repoPath: repoPath,
      kind: LogosGitEventKind.diffuse,
      duration: duration,
      message: 'sources=$sourceCount t=${temperature.toStringAsFixed(2)}',
    ));
  }

  void recordFailure(
    String repoPath,
    String message,
    Duration duration, [
    StackTrace? stack,
  ]) {
    _push(LogosGitEvent(
      at: DateTime.now(),
      repoPath: repoPath,
      kind: LogosGitEventKind.failure,
      message: message,
      duration: duration,
      stack: stack?.toString(),
    ));
    // Visible to developers, never to users. Wire to audit later.
    if (kDebugMode) {
      debugPrint('[LogosGit] FAILURE $repoPath: $message');
      if (stack != null) debugPrint(stack.toString());
    }
  }

  void clear() => _events.clear();

  void _push(LogosGitEvent event) {
    _events.add(event);
    if (_events.length > _maxEvents) {
      _events.removeAt(0);
    }
  }
}
