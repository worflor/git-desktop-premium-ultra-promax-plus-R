import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/backend/wick.dart';

void main() {
  group('WickQueryResponse.fromJson', () {
    test('parses a full response', () {
      final json = <String, dynamic>{
        'query': 'how does auth work',
        'packet': [
          {
            'id': 'lib/auth/service.dart#chunk2',
            'text': 'handles session token validation',
            'tokens': 120,
            'rank': 0,
            'reason': {
              'kind': 'direct',
              'is_probe': true,
            },
            'lane': 'primary',
          },
          {
            'id': 'lib/auth/session.dart#chunk0',
            'text': 'manages active sessions',
            'tokens': 80,
            'rank': 1,
            'reason': {'kind': 'neighborhood'},
            'lane': 'context',
          },
        ],
        'posture': 'decisive',
        'confidence': 0.92,
        'elapsed_ms': 3.5,
      };

      final response = WickQueryResponse.fromJson(json);
      expect(response.packet.length, 2);
      expect(response.posture, WickPosture.decisive);
      expect(response.confidence, closeTo(0.92, 0.01));
      expect(response.elapsedMs, closeTo(3.5, 0.1));
    });

    test('parses empty packet', () {
      final json = <String, dynamic>{
        'packet': [],
        'posture': 'flinching',
        'confidence': 0.0,
        'elapsed_ms': 1.0,
      };
      final response = WickQueryResponse.fromJson(json);
      expect(response.packet, isEmpty);
      expect(response.posture, WickPosture.flinching);
    });

    test('handles missing fields gracefully', () {
      final response = WickQueryResponse.fromJson(const {});
      expect(response.packet, isEmpty);
      expect(response.posture, WickPosture.flinching);
      expect(response.confidence, 0.0);
    });
  });

  group('WickUnit.fromJson', () {
    test('parses all fields', () {
      final unit = WickUnit.fromJson(const {
        'id': 'lib/auth/service.dart#chunk2',
        'text': 'validates tokens and refreshes sessions',
        'tokens': 150,
        'rank': 0,
        'reason': {'kind': 'direct', 'via_lane': 'section-hierarchy'},
        'lane': 'primary',
      });
      expect(unit.id, 'lib/auth/service.dart#chunk2');
      expect(unit.text, 'validates tokens and refreshes sessions');
      expect(unit.tokens, 150);
      expect(unit.rank, 0);
      expect(unit.reason.kind, 'direct');
      expect(unit.reason.viaLane, 'section-hierarchy');
      expect(unit.lane, 'primary');
    });

    test('filePath strips chunk suffix', () {
      final unit = WickUnit.fromJson(const {
        'id': 'lib/backend/auth.dart#chunk3',
        'text': '',
        'tokens': 0,
        'rank': 0,
        'reason': {'kind': 'faint'},
        'lane': 'peripheral',
      });
      expect(unit.filePath, 'lib/backend/auth.dart');
      expect(unit.fileName, 'auth.dart');
    });

    test('filePath works without chunk suffix', () {
      final unit = WickUnit.fromJson(const {
        'id': 'README.md',
        'text': '',
        'tokens': 0,
        'rank': 0,
        'reason': {'kind': 'probe'},
        'lane': 'primary',
      });
      expect(unit.filePath, 'README.md');
      expect(unit.fileName, 'README.md');
    });
  });

  group('WickPosture parsing', () {
    test('parses all posture variants', () {
      expect(
        WickQueryResponse.fromJson(const {
          'posture': 'decisive',
          'confidence': 1,
          'elapsed_ms': 0,
        }).posture,
        WickPosture.decisive,
      );
      expect(
        WickQueryResponse.fromJson(const {
          'posture': 'exploring',
          'confidence': 1,
          'elapsed_ms': 0,
        }).posture,
        WickPosture.exploring,
      );
      expect(
        WickQueryResponse.fromJson(const {
          'posture': 'reaching',
          'confidence': 1,
          'elapsed_ms': 0,
        }).posture,
        WickPosture.reaching,
      );
      expect(
        WickQueryResponse.fromJson(const {
          'posture': 'flinching',
          'confidence': 1,
          'elapsed_ms': 0,
        }).posture,
        WickPosture.flinching,
      );
    });

    test('defaults unknown posture to flinching', () {
      expect(
        WickQueryResponse.fromJson(const {
          'posture': 'unknown_value',
          'confidence': 0,
          'elapsed_ms': 0,
        }).posture,
        WickPosture.flinching,
      );
    });
  });

  group('WickInfo.fromJson', () {
    test('parses info response', () {
      final info = WickInfo.fromJson(const {
        'units': 1234,
        'structural_edges': 5678,
        'transport_edges': 910,
      });
      expect(info.units, 1234);
      expect(info.structuralEdges, 5678);
      expect(info.transportEdges, 910);
    });
  });

  group('WickResult', () {
    test('ok result', () {
      final r = WickResult.ok(42);
      expect(r.ok, isTrue);
      expect(r.data, 42);
      expect(r.error, isNull);
    });

    test('err result', () {
      final r = WickResult<int>.err('failed');
      expect(r.ok, isFalse);
      expect(r.data, isNull);
      expect(r.error, 'failed');
    });
  });
}
