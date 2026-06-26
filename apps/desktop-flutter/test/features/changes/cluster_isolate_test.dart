// The ChangesetController runs `clusterFiles` inside `Isolate.run` for
// changesets above its size threshold. That path is only correct if every
// argument survives the isolate boundary and yields byte-identical clustering.
// These tests pin that: the same `clusterFiles` call run inline vs. via
// `Isolate.run` must produce identical results.

import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/file_coupling.dart';
import 'package:git_desktop/backend/logos_core.dart' show CsrGraph;

FileCouplingMatrix _matrix(Map<String, Map<String, double>> jaccard) =>
    FileCouplingMatrix(
      jaccard: jaccard,
      spectral: const {},
      headHash: 'test',
      commitsAnalyzed: 200,
    );

void _expectSame(FileClusters a, FileClusters b) {
  expect(a.orderedPaths, b.orderedPaths);
  expect(a.byPath, b.byPath);
  expect(a.clusterCount, b.clusterCount);
  expect(a.dominantAxisByCluster, b.dominantAxisByCluster);
}

void main() {
  group('clusterFiles isolate parity (the ≥96-file gate path)', () {
    test('matrix + impact signals + conflict/include sets cross identically',
        () async {
      final paths = ['a.dart', 'b.dart', 'c.dart', 'd.dart'];
      final matrix = _matrix({
        'a.dart': {'b.dart': 0.9},
        'b.dart': {'a.dart': 0.9},
        'c.dart': {'d.dart': 0.8},
        'd.dart': {'c.dart': 0.8},
      });
      final impact = {
        for (final p in paths)
          p: const FileImpactSignal(adds: 10, dels: 2, binary: false),
      };
      FileClusters run() => clusterFiles(
            paths,
            matrix,
            impactSignals: impact,
            conflictedPaths: const {'a.dart'},
            includedPaths: const {'b.dart'},
          );
      _expectSame(run(), await Isolate.run(run));
    });

    test('ClusterEngineView projection survives the boundary', () async {
      final paths = ['x.dart', 'y.dart'];
      final view = ClusterEngineView(
        graph: CsrGraph(
          n: 2,
          indptr: Int32List.fromList([0, 1, 2]),
          indices: Int32List.fromList([1, 0]),
          values: Float64List.fromList([1.0, 1.0]),
        ),
        pathToId: const {'x.dart': 0, 'y.dart': 1},
        nodePaths: const ['x.dart', 'y.dart'],
      );
      final matrix = _matrix(const {});
      FileClusters run() => clusterFiles(paths, matrix, engine: view);
      _expectSame(run(), await Isolate.run(run));
    });
  });
}
