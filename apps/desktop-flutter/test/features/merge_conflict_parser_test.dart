import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/features/changes/merge_conflict_editor.dart';

void main() {
  group('parseConflictFile — basic cases', () {
    test('single conflict block', () {
      final cf = parseConflictFile('a.dart', '<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n');
      expect(cf.blocks.length, 1);
      expect(cf.blocks[0].oursText, 'ours');
      expect(cf.blocks[0].theirsText, 'theirs');
      expect(cf.oursBranch, 'HEAD');
      expect(cf.theirsBranch, 'branch');
    });

    test('multiple conflict blocks', () {
      final cf = parseConflictFile('a.dart',
          'clean\n<<<<<<< HEAD\na\n=======\nb\n>>>>>>> b1\nmiddle\n<<<<<<< HEAD\nc\n=======\nd\n>>>>>>> b2\nend\n');
      expect(cf.blocks.length, 2);
      expect(cf.blocks[0].oursText, 'a');
      expect(cf.blocks[0].theirsText, 'b');
      expect(cf.blocks[1].oursText, 'c');
      expect(cf.blocks[1].theirsText, 'd');
      expect(cf.segments.length, 3);
    });

    test('adjacent conflicts with no clean text between', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< HEAD\na\n=======\nb\n>>>>>>> x\n<<<<<<< HEAD\nc\n=======\nd\n>>>>>>> x\n');
      expect(cf.blocks.length, 2);
      expect(cf.segments[1], '');
    });

    test('clean text before and after', () {
      final cf = parseConflictFile('a.dart',
          'before\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> x\nafter\n');
      expect(cf.segments[0], 'before\n');
      expect(cf.segments[1].contains('after'), isTrue);
      expect(cf.blocks[0].oursText, 'ours');
    });
  });

  group('parseConflictFile — diff3 base markers', () {
    test('parses ||||||| base section', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< HEAD\nours\n|||||||\nbase\n=======\ntheirs\n>>>>>>> x\n');
      expect(cf.blocks.length, 1);
      expect(cf.blocks[0].oursText, 'ours');
      expect(cf.blocks[0].baseText, 'base');
      expect(cf.blocks[0].theirsText, 'theirs');
    });

    test('multi-line base section', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< HEAD\na\nb\n|||||||\nbase1\nbase2\n=======\nc\n>>>>>>> x\n');
      expect(cf.blocks[0].baseText, 'base1\nbase2');
      expect(cf.blocks[0].oursText, 'a\nb');
    });

    test('no base section produces null baseText', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> x\n');
      expect(cf.blocks[0].baseText, isNull);
    });
  });

  group('parseConflictFile — edge cases', () {
    test('empty ours section', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< HEAD\n=======\ntheirs\n>>>>>>> x\n');
      expect(cf.blocks[0].oursText, '');
      expect(cf.blocks[0].theirsText, 'theirs');
    });

    test('empty theirs section', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< HEAD\nours\n=======\n>>>>>>> x\n');
      expect(cf.blocks[0].oursText, 'ours');
      expect(cf.blocks[0].theirsText, '');
    });

    test('both sides empty', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< HEAD\n=======\n>>>>>>> x\n');
      expect(cf.blocks[0].oursText, '');
      expect(cf.blocks[0].theirsText, '');
    });

    test('multi-line ours and theirs', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< HEAD\nline1\nline2\nline3\n=======\nA\nB\n>>>>>>> x\n');
      expect(cf.blocks[0].oursText, 'line1\nline2\nline3');
      expect(cf.blocks[0].theirsText, 'A\nB');
    });

    test('branch names extracted from markers', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< feature/auth\nours\n=======\ntheirs\n>>>>>>> main\n');
      expect(cf.oursBranch, 'feature/auth');
      expect(cf.theirsBranch, 'main');
    });

    test('no branch names uses defaults', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<<\nours\n=======\ntheirs\n>>>>>>>\n');
      expect(cf.oursBranch, 'ours');
      expect(cf.theirsBranch, 'theirs');
    });

    test('conflict markers inside string content are not parsed as markers', () {
      // A line that contains <<<<<<< but doesn't START with it
      final cf = parseConflictFile('a.dart',
          'var s = "<<<<<<< not a marker";\n<<<<<<< HEAD\nreal\n=======\nconflict\n>>>>>>> x\n');
      expect(cf.blocks.length, 1);
      expect(cf.blocks[0].oursText, 'real');
      expect(cf.segments[0], contains('not a marker'));
    });

    test('file with no conflicts produces zero blocks', () {
      final cf = parseConflictFile('a.dart', 'just normal\ncode\nhere\n');
      expect(cf.blocks, isEmpty);
      expect(cf.segments.length, 1);
    });

    test('truncated conflict (missing >>>>>>>) flushes partial block', () {
      final cf = parseConflictFile('a.dart',
          'before\n<<<<<<< HEAD\nours\n=======\ntheirs\n');
      expect(cf.blocks.length, 1);
      expect(cf.blocks[0].oursText, 'ours');
      expect(cf.blocks[0].theirsText.trim(), 'theirs');
      expect(cf.blocks[0].isResolved, isFalse);
      expect(cf.allResolved, isFalse);
    });

    test('truncated conflict mid-ours flushes with empty theirs', () {
      final cf = parseConflictFile('a.dart',
          'before\n<<<<<<< HEAD\npartial content\n');
      expect(cf.blocks.length, 1);
      expect(cf.blocks[0].oursText.trim(), 'partial content');
      expect(cf.blocks[0].theirsText, '');
      expect(cf.allResolved, isFalse);
    });

    test('missing trailing newline', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> x');
      expect(cf.blocks.length, 1);
      expect(cf.blocks[0].oursText, 'ours');
      expect(cf.blocks[0].theirsText, 'theirs');
    });
  });

  group('ConflictBlock — resolvedText', () {
    test('ours returns oursText', () {
      final b = ConflictBlock(index: 0, oursText: 'A', theirsText: 'B');
      b.resolution = ConflictSide.ours;
      expect(b.resolvedText, 'A');
    });

    test('theirs returns theirsText', () {
      final b = ConflictBlock(index: 0, oursText: 'A', theirsText: 'B');
      b.resolution = ConflictSide.theirs;
      expect(b.resolvedText, 'B');
    });

    test('both concatenates ours then theirs', () {
      final b = ConflictBlock(index: 0, oursText: 'A', theirsText: 'B');
      b.resolution = ConflictSide.both;
      expect(b.resolvedText, 'A\nB');
    });

    test('custom returns customText', () {
      final b = ConflictBlock(index: 0, oursText: 'A', theirsText: 'B');
      b.customText = 'C';
      b.resolution = ConflictSide.custom;
      expect(b.resolvedText, 'C');
    });

    test('unresolved returns empty', () {
      final b = ConflictBlock(index: 0, oursText: 'A', theirsText: 'B');
      expect(b.resolvedText, '');
    });
  });

  group('ConflictBlock — heat', () {
    test('identical sides produce zero heat', () {
      final b = ConflictBlock(index: 0, oursText: 'same', theirsText: 'same');
      expect(b.heat, 0.0);
    });

    test('completely different sides with no bias produce high heat', () {
      final b = ConflictBlock(
          index: 0, oursText: 'alpha\nbeta', theirsText: 'gamma\ndelta');
      expect(b.heat, greaterThan(0.7));
    });

    test('strong bias reduces heat', () {
      final b = ConflictBlock(
          index: 0, oursText: 'alpha\nbeta', theirsText: 'gamma\ndelta');
      b.coherenceBias = 0.3;
      final heatWithBias = b.heat;
      b.coherenceBias = null;
      final heatWithout = b.heat;
      expect(heatWithBias, lessThan(heatWithout));
    });

    test('partially overlapping lines produce moderate heat', () {
      final b = ConflictBlock(
          index: 0,
          oursText: 'shared\nunique_ours',
          theirsText: 'shared\nunique_theirs');
      expect(b.heat, greaterThan(0.2));
      expect(b.heat, lessThan(0.8));
    });
  });

  group('ConflictFile — buildResult', () {
    test('reconstructs file from segments and resolved blocks', () {
      final cf = parseConflictFile('a.dart',
          'before\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> x\nafter\n');
      cf.blocks[0].resolution = ConflictSide.ours;
      final result = cf.buildResult();
      expect(result, 'before\nours\nafter\n');
    });

    test('adjacent conflicts get newline separator', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< HEAD\nA\n=======\nB\n>>>>>>> x\n<<<<<<< HEAD\nC\n=======\nD\n>>>>>>> x\n');
      cf.blocks[0].resolution = ConflictSide.ours;
      cf.blocks[1].resolution = ConflictSide.theirs;
      final result = cf.buildResult();
      expect(result, 'A\nD\n');
    });

    test('multiple blocks resolved differently', () {
      final cf = parseConflictFile('a.dart',
          '<<<<<<< HEAD\nA\n=======\nB\n>>>>>>> x\nmid\n<<<<<<< HEAD\nC\n=======\nD\n>>>>>>> x\n');
      cf.blocks[0].resolution = ConflictSide.ours;
      cf.blocks[1].resolution = ConflictSide.theirs;
      final result = cf.buildResult();
      expect(result, 'A\nmid\nD\n');
    });
  });

  group('_uniqueLines', () {
    // Can't test private function directly, but we test it via heat behavior
    test('heat is 0 for identical content', () {
      final b = ConflictBlock(
          index: 0, oursText: 'a\nb\nc', theirsText: 'a\nb\nc');
      expect(b.heat, 0.0);
    });
  });
}
