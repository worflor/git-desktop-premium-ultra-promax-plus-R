// law_corpus.dart — the parsed source corpus behind test/laws/.
//
// Loads every Dart file under lib/ ONCE per test run, parses it with
// package:analyzer (real AST — no regex false positives from comments or
// look-alike identifiers), and extracts the per-file facts the structural
// laws assert over: imports, string-literal contents, side-effect call
// counts (Process spawns, raw file writes, wall-clock reads), and the
// codex `--sandbox read-only` argv adjacency.
//
// Pure Dart, no flutter_test import — usable from any harness.

import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// One lib/ source file: raw bytes, source text, parsed unit, and the
/// extracted facts the laws consume.
class LawFile {
  LawFile({
    required this.path,
    required this.bytes,
    required this.source,
    required this.unit,
    required this.syntaxErrors,
    required this.facts,
  });

  /// '/'-separated path relative to the package root, e.g.
  /// `lib/backend/git.dart` — stable across Windows/WSL.
  final String path;
  final List<int> bytes;
  final String source;
  final CompilationUnit unit;

  /// Syntax diagnostics from the parse. Non-empty means either a genuinely
  /// broken file or a language feature newer than the pinned analyzer —
  /// both are law violations (L0) because every other law's counts would
  /// silently undercount on an unparsed file.
  final List<String> syntaxErrors;

  final FileFacts facts;
}

/// Facts extracted from one file in a single AST pass.
class FileFacts {
  /// Import URIs as written (`dart:ffi`, `package:analyzer/...`).
  final List<String> imports = [];

  /// Every string-literal fragment's text content: simple literals plus the
  /// literal parts of interpolations. Comments are NOT included — a law
  /// matching on these matches real runtime strings only.
  final List<String> stringLiterals = [];

  /// `Process.run` / `Process.start` / `Process.runSync` call sites.
  int processSpawns = 0;

  /// Raw truncating file writes: `writeAsString(Sync)` / `writeAsBytes(Sync)`.
  int rawWrites = 0;

  /// `openWrite(` call sites (append-mode sinks — persistence surface too).
  int openWrites = 0;

  /// Wall-clock / nondeterminism reads: `DateTime.now()` and *unseeded*
  /// `Random()` (a seeded `Random(n)` is deterministic and not counted).
  int wallClock = 0;

  /// `'--sandbox'` string literals that appear as a list element.
  int sandboxFlags = 0;

  /// `'--sandbox'` list elements NOT immediately followed by `'read-only'`.
  int sandboxAdjacencyViolations = 0;

  /// Calls `writeFileAtomic` / `writeFileAtomicString` (the durable seam).
  bool callsWriteFileAtomic = false;

  /// `LruCache<_, T>` constructions whose value type `T` is a dart:ui
  /// disposable (TextPainter/Image/Picture/Paragraph) but which do NOT
  /// pass an `onEvict:` argument — every evicted value then leaks its
  /// native resources. Each entry is the value type name, for the message.
  final List<String> lruDisposableNoEvict = [];
}

/// dart:ui-ish handles that own native resources freed only by an explicit
/// `dispose()` — an LruCache of these must release on eviction.
const _disposableValueTypes = {
  'TextPainter',
  'Image',
  'Picture',
  'Paragraph',
};

class _FactsVisitor extends RecursiveAstVisitor<void> {
  _FactsVisitor(this.facts);
  final FileFacts facts;

  static const _rawWriteNames = {
    'writeAsString',
    'writeAsBytes',
    'writeAsStringSync',
    'writeAsBytesSync',
  };
  static const _spawnNames = {'run', 'start', 'runSync'};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final target = node.target;
    final targetSource = target is SimpleIdentifier ? target.name : null;

    if (_spawnNames.contains(name) && targetSource == 'Process') {
      facts.processSpawns++;
    }
    if (_rawWriteNames.contains(name)) facts.rawWrites++;
    if (name == 'openWrite') facts.openWrites++;
    if (name == 'now' && targetSource == 'DateTime') facts.wallClock++;
    if (name == 'Random' && node.argumentList.arguments.isEmpty) {
      facts.wallClock++;
    }
    if (name == 'writeFileAtomic' || name == 'writeFileAtomicString') {
      facts.callsWriteFileAtomic = true;
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final ctor = node.constructorName;
    final typeName = ctor.type.name.lexeme;
    if (typeName == 'Random' && node.argumentList.arguments.isEmpty) {
      facts.wallClock++;
    }
    if (typeName == 'DateTime' && ctor.name?.name == 'now') {
      facts.wallClock++;
    }
    if (typeName == 'LruCache') {
      // Second type argument is the value type: LruCache<K, V>.
      final typeArgs = ctor.type.typeArguments?.arguments;
      if (typeArgs != null && typeArgs.length == 2) {
        final valueType = typeArgs[1];
        // Unwrap a bare named type; anything else (a nested generic like
        // List<TextPainter>) is not a directly-held disposable and is out
        // of scope for this law.
        final vName = valueType is NamedType ? valueType.name.lexeme : null;
        if (vName != null && _disposableValueTypes.contains(vName)) {
          final hasOnEvict = node.argumentList.arguments
              .whereType<NamedExpression>()
              .any((a) => a.name.label.name == 'onEvict');
          if (!hasOnEvict) facts.lruDisposableNoEvict.add(vName);
        }
      }
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    facts.stringLiterals.add(node.value);
    super.visitSimpleStringLiteral(node);
  }

  @override
  void visitInterpolationString(InterpolationString node) {
    facts.stringLiterals.add(node.value);
    super.visitInterpolationString(node);
  }

  @override
  void visitListLiteral(ListLiteral node) {
    final elements = node.elements;
    for (var i = 0; i < elements.length; i++) {
      final e = elements[i];
      if (e is SimpleStringLiteral && e.value == '--sandbox') {
        facts.sandboxFlags++;
        final next = i + 1 < elements.length ? elements[i + 1] : null;
        final ok = next is SimpleStringLiteral && next.value == 'read-only';
        if (!ok) facts.sandboxAdjacencyViolations++;
      }
    }
    super.visitListLiteral(node);
  }
}

/// The whole-lib/ corpus, loaded and parsed once per process.
class LawCorpus {
  LawCorpus._(this.files);

  final List<LawFile> files;

  static LawCorpus? _cached;

  static LawCorpus load({String root = '.'}) {
    final cached = _cached;
    if (cached != null) return cached;

    final libDir = Directory('$root/lib');
    if (!libDir.existsSync()) {
      throw StateError(
          'law corpus: ${libDir.path} not found — tests must run from the '
          'package root (flutter test does this by default)');
    }

    final files = <LawFile>[];
    final entries = libDir
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final f in entries) {
      files.add(parseOne(f, root: root));
    }
    return _cached = LawCorpus._(files);
  }

  /// Parse a single file into a [LawFile]. Public so laws that reason about
  /// files OUTSIDE lib/ (e.g. the torn-write test's import list) reuse the
  /// same machinery.
  static LawFile parseOne(File f, {String root = '.'}) {
    final bytes = f.readAsBytesSync();
    final source = String.fromCharCodes(bytes).isEmpty
        ? ''
        : f.readAsStringSync(); // proper UTF-8 decode for the parser
    final parsed = parseString(
      content: source,
      featureSet: FeatureSet.latestLanguageVersion(),
      path: f.path,
      throwIfDiagnostics: false,
    );
    final facts = FileFacts();
    for (final d in parsed.unit.directives) {
      if (d is ImportDirective) {
        final uri = d.uri.stringValue;
        if (uri != null) facts.imports.add(uri);
      }
    }
    parsed.unit.accept(_FactsVisitor(facts));

    var rel = f.path.replaceAll('\\', '/');
    final anchor = rel.indexOf('lib/');
    final testAnchor = rel.indexOf('test/');
    if (anchor >= 0 && (testAnchor < 0 || anchor < testAnchor)) {
      rel = rel.substring(anchor);
    } else if (testAnchor >= 0) {
      rel = rel.substring(testAnchor);
    }

    return LawFile(
      path: rel,
      bytes: bytes,
      source: source,
      unit: parsed.unit,
      syntaxErrors: [
        for (final e in parsed.errors)
          '${f.path}:${e.offset}: ${e.message}',
      ],
      facts: facts,
    );
  }
}
