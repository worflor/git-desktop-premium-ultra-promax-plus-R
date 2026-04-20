import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/aperture_sweep.dart';
import '../backend/dtos.dart';
import '../backend/git.dart';

/// Precomputed aperture-sweep bundle for a single repo. The sweep
/// itself is heavy (several spectral-basis builds per sample), so
/// the state holds the sweep plus derived event/trajectory lists
/// produced by [detectCompoundEvents] and friends, indexed per repo.
/// Cheap to read, expensive to build.
class RepositoryRingsData {
  final ApertureSweep sweep;
  final List<ApertureEvent> events;
  final List<CenterOfGravityStratum> centerTrajectory;
  final Map<String, String> observableClassification;

  const RepositoryRingsData({
    required this.sweep,
    required this.events,
    required this.centerTrajectory,
    required this.observableClassification,
  });
}

class RepositoryXrayState extends ChangeNotifier {
  final Map<String, RepositoryXraySnapshotData> _snapshots = {};
  final Map<String, String> _fingerprints = {};
  final Map<String, DateTime> _computedAt = {};
  final Map<String, String?> _errors = {};
  final Set<String> _loading = {};

  /// Rings (aperture-sweep) data per repo — keyed by repo path, not
  /// by fingerprint, but discarded when [invalidateAllExcept] runs
  /// so stale rings don't leak across repo switches.
  final Map<String, RepositoryRingsData> _rings = {};
  final Map<String, String?> _ringsErrors = {};
  final Set<String> _ringsLoading = {};

  /// Per-repo sweep progress in the form (done, total). Populated
  /// while [_ringsLoading] contains the repo; cleared on completion.
  final Map<String, (int, int)> _ringsProgress = {};

  RepositoryXraySnapshotData? snapshotFor(String repoPath) =>
      _snapshots[repoPath];

  String? errorFor(String repoPath) => _errors[repoPath];

  bool isLoading(String repoPath) => _loading.contains(repoPath);

  DateTime? computedAtFor(String repoPath) => _computedAt[repoPath];

  RepositoryRingsData? ringsFor(String repoPath) => _rings[repoPath];
  String? ringsErrorFor(String repoPath) => _ringsErrors[repoPath];
  bool isLoadingRings(String repoPath) => _ringsLoading.contains(repoPath);
  (int, int)? ringsProgressFor(String repoPath) => _ringsProgress[repoPath];

  void invalidateAllExcept(String? repoPath) {
    if (repoPath == null) {
      _snapshots.clear();
      _fingerprints.clear();
      _computedAt.clear();
      _errors.clear();
      _loading.clear();
      _rings.clear();
      _ringsErrors.clear();
      _ringsLoading.clear();
      _ringsProgress.clear();
      notifyListeners();
      return;
    }

    final removedAny = _snapshots.keys.any((key) => key != repoPath) ||
        _fingerprints.keys.any((key) => key != repoPath) ||
        _errors.keys.any((key) => key != repoPath) ||
        _loading.any((key) => key != repoPath) ||
        _rings.keys.any((key) => key != repoPath) ||
        _ringsErrors.keys.any((key) => key != repoPath) ||
        _ringsLoading.any((key) => key != repoPath);
    _snapshots.removeWhere((key, _) => key != repoPath);
    _fingerprints.removeWhere((key, _) => key != repoPath);
    _computedAt.removeWhere((key, _) => key != repoPath);
    _errors.removeWhere((key, _) => key != repoPath);
    _loading.removeWhere((key) => key != repoPath);
    _rings.removeWhere((key, _) => key != repoPath);
    _ringsErrors.removeWhere((key, _) => key != repoPath);
    _ringsLoading.removeWhere((key) => key != repoPath);
    _ringsProgress.removeWhere((key, _) => key != repoPath);
    if (removedAny) {
      notifyListeners();
    }
  }

  Future<void> loadForRepo(String repoPath, {bool forceRefresh = false}) async {
    if (_loading.contains(repoPath)) {
      return;
    }

    if (!forceRefresh && _snapshots.containsKey(repoPath)) {
      final fingerprintResult = await getRepositoryXrayFingerprint(repoPath);
      if (fingerprintResult.ok &&
          fingerprintResult.data != null &&
          _fingerprints[repoPath] == fingerprintResult.data) {
        return;
      }
    }

    _loading.add(repoPath);
    _errors[repoPath] = null;
    notifyListeners();

    try {
      final result = await getRepositoryXray(repoPath, forceRefresh: forceRefresh);
      if (result.ok && result.data != null) {
        _snapshots[repoPath] = result.data!;
        _fingerprints[repoPath] = result.data!.header.fingerprint;
        final parsedComputedAt =
            DateTime.tryParse(result.data!.header.computedAt);
        if (parsedComputedAt != null) {
          _computedAt[repoPath] = parsedComputedAt;
        }
        _errors.remove(repoPath);
      } else {
        _errors[repoPath] = result.error ?? 'Failed to compute Repo X-Ray.';
      }
    } catch (error) {
      _errors[repoPath] = error.toString();
    } finally {
      _loading.remove(repoPath);
      notifyListeners();
    }
  }

  /// Trigger an aperture-sweep probe on [repoPath]. Safe to call
  /// repeatedly — a second call while the first is in flight is a
  /// no-op; a call after successful completion is a no-op unless
  /// [forceRefresh] is true. Results land in [ringsFor] and listeners
  /// are notified when loading state changes or results arrive.
  Future<void> loadRingsForRepo(
    String repoPath, {
    bool forceRefresh = false,
  }) async {
    if (_ringsLoading.contains(repoPath)) return;
    if (!forceRefresh && _rings.containsKey(repoPath)) return;

    _ringsLoading.add(repoPath);
    _ringsErrors[repoPath] = null;
    // Initial progress total is a guess — adaptive sampling may
    // inflate it as refinement schedules more samples.
    _ringsProgress[repoPath] = (0, 8);
    notifyListeners();

    // Streaming buffer — samples arrive one-at-a-time as they
    // complete, so we keep a live [RepositoryRingsData] growing
    // inside _rings. The UI watching [ringsFor] gets to render
    // partial results immediately instead of waiting for the whole
    // sweep to finish.
    final streaming = <ApertureSample>[];
    void republish() {
      if (streaming.isEmpty) return;
      final liveSweep = ApertureSweep(
        samples: List<ApertureSample>.unmodifiable(
            [...streaming]..sort((a, b) => a.window.compareTo(b.window))),
        computedAt: DateTime.now(),
        headHash: '',
      );
      _rings[repoPath] = RepositoryRingsData(
        sweep: liveSweep,
        events: detectCompoundEvents(liveSweep),
        centerTrajectory: centerOfGravityTrajectory(liveSweep),
        observableClassification: classifyObservables(liveSweep),
      );
    }

    // Coalesce streaming notifications: samples often land in
    // tight clusters (a batch of 3 completing within a few ms of each
    // other), and a listener storm of N notifies triggers N full
    // widget rebuilds even though the UI could show them all in a
    // single frame. One microtask per quiescent event-loop turn —
    // batched, without visible latency.
    var notifyScheduled = false;
    void scheduleNotify() {
      if (notifyScheduled) return;
      notifyScheduled = true;
      scheduleMicrotask(() {
        notifyScheduled = false;
        notifyListeners();
      });
    }

    try {
      final result = await collectApertureSweep(
        repoPath,
        onProgress: (done, total) {
          _ringsProgress[repoPath] = (done, total);
          scheduleNotify();
        },
        onSample: (sample) {
          streaming.add(sample);
          republish();
          scheduleNotify();
        },
      );
      if (result.ok && result.data != null) {
        // Replace the streamed provisional result with the
        // authoritative final sweep (same content, but with the real
        // headHash and a settled ordering).
        final sweep = result.data!;
        _rings[repoPath] = RepositoryRingsData(
          sweep: sweep,
          events: detectCompoundEvents(sweep),
          centerTrajectory: centerOfGravityTrajectory(sweep),
          observableClassification: classifyObservables(sweep),
        );
        _ringsErrors.remove(repoPath);
      } else if (streaming.isEmpty) {
        _ringsErrors[repoPath] =
            result.error ?? 'Failed to compute aperture sweep.';
      }
      // If streaming produced samples but the sweep ultimately
      // returned an error, keep the partial result — it's still
      // informative — and drop the error so the UI doesn't flip to
      // a failure state over a cosmetic issue.
    } catch (error) {
      if (streaming.isEmpty) {
        _ringsErrors[repoPath] = error.toString();
      }
    } finally {
      _ringsLoading.remove(repoPath);
      _ringsProgress.remove(repoPath);
      notifyListeners();
    }
  }
}
