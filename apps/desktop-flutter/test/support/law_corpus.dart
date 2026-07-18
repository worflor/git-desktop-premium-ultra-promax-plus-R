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

  /// `lazyFromSpool(` call sites — the raw-path spool-document engine entry.
  /// Feature code must name its ownership mode (adoptSpool / viewSpool)
  /// instead; see the spool-ownership law.
  int lazyFromSpoolCalls = 0;

  /// Whole-content file reads: `readAsString(Sync)` / `readAsBytes(Sync)`.
  /// The unbudgeted-ingestion surface — each site either carries its own
  /// bound, runs inside a worker isolate, or routes through
  /// AnalysisAdmission (backend/analysis_admission.dart). An unbudgeted read
  /// over working-tree content is the repo-switch system-OOM bug class.
  int contentReads = 0;

  /// Git invocations that materialize UNBOUNDED output as a String: a
  /// `runGit`/`_git` call whose argv literal contains `diff`, `show`, or
  /// `blame` without a bounding flag (`--name-only`, `--numstat`,
  /// `--name-status`, `--stat`). This is the ingestion vector [contentReads]
  /// is structurally blind to — no file is read, yet a working tree's whole
  /// patch lands in RAM. Sites belong behind `admitGitDiffText`
  /// (backend/admitted_git.dart) or a spool transport.
  int unboundedGitReads = 0;

  /// `LruCache<_, T>` constructions whose value type `T` is a dart:ui
  /// disposable (TextPainter/Image/Picture/Paragraph) but which do NOT
  /// pass an `onEvict:` argument — every evicted value then leaks its
  /// native resources. Each entry is the value type name, for the message.
  final List<String> lruDisposableNoEvict = [];
}

/// dart:ui-ish handles that own native resources freed only by an explicit
/// `dispose()` — an LruCache of these must release on eviction.
const _disposableValueTypes = {'TextPainter', 'Image', 'Picture', 'Paragraph'};

/// Top-level `const List<String> NAME = ['a', 'b'];` declarations, by name.
/// Only literal elements are recorded — a const built from other consts stays
/// unknown, and the laws that use this treat unknown as "can't see", never as
/// "safe".
Map<String, List<String>> _collectConstStringLists(CompilationUnit unit) {
  final out = <String, List<String>>{};
  for (final decl in unit.declarations) {
    if (decl is! TopLevelVariableDeclaration) continue;
    if (!decl.variables.isConst) continue;
    for (final v in decl.variables.variables) {
      final init = v.initializer;
      if (init is! ListLiteral) continue;
      out[v.name.lexeme] = [
        for (final e in init.elements)
          if (e is SimpleStringLiteral) e.value,
      ];
    }
  }
  return out;
}

class _FactsVisitor extends RecursiveAstVisitor<void> {
  _FactsVisitor(this.facts, this.constLists);
  final FileFacts facts;
  final Map<String, List<String>> constLists;

  static const _rawWriteNames = {
    'writeAsString',
    'writeAsBytes',
    'writeAsStringSync',
    'writeAsBytesSync',
  };
  static const _contentReadNames = {
    'readAsString',
    'readAsBytes',
    'readAsStringSync',
    'readAsBytesSync',
  };
  static const _spawnNames = {'run', 'start', 'runSync'};
  static const _gitRunNames = {'runGit', '_git', '_gitRaw', '_runGitCommand'};
  /// Subcommands whose output scales with repo CONTENT, not repo shape.
  static const _unboundedGitVerbs = {'diff', 'show', 'blame'};
  /// Flags that reduce those to a summary (bounded by file COUNT).
  static const _boundingGitFlags = {
    '--name-only',
    '--name-status',
    '--numstat',
    '--shortstat',
    '--stat',
    '--quiet',
    '-s',
  };

  /// Counts a git call as unbounded when its argv names a content-scaling
  /// verb and carries no bounding flag. Argv is read through file-local const
  /// spreads (`[..._kDiffCmd, hash]`), which is where the verb usually lives
  /// once a codebase centralizes its flags. Argv this cannot resolve (a
  /// variable, a computed list) is NOT counted — the law reads what it can
  /// see, and the baseline makes the visible set shrink-only.
  void _countUnboundedGit(MethodInvocation node) {
    for (final arg in node.argumentList.arguments) {
      if (arg is! ListLiteral) continue;
      final parts = _argvStrings(arg);
      if (!parts.any(_unboundedGitVerbs.contains)) continue;
      if (parts.any(_boundingGitFlags.contains)) continue;
      facts.unboundedGitReads++;
      return;
    }
  }

  /// Literal strings of an argv list, expanding a spread of a known
  /// file-local const list.
  List<String> _argvStrings(ListLiteral argv) {
    final parts = <String>[];
    for (final e in argv.elements) {
      if (e is SimpleStringLiteral) {
        parts.add(e.value);
      } else if (e is SpreadElement) {
        final target = e.expression;
        if (target is SimpleIdentifier) {
          parts.addAll(constLists[target.name] ?? const []);
        } else if (target is ListLiteral) {
          parts.addAll(_argvStrings(target));
        }
      }
    }
    return parts;
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName.name;
    final target = node.target;
    final targetSource = target is SimpleIdentifier ? target.name : null;

    if (_spawnNames.contains(name) && targetSource == 'Process') {
      facts.processSpawns++;
    }
    if (_rawWriteNames.contains(name)) facts.rawWrites++;
    if (_contentReadNames.contains(name)) facts.contentReads++;
    if (_gitRunNames.contains(name)) _countUnboundedGit(node);
    if (name == 'openWrite') facts.openWrites++;
    if (name == 'now' && targetSource == 'DateTime') facts.wallClock++;
    if (name == 'Random' && node.argumentList.arguments.isEmpty) {
      facts.wallClock++;
    }
    if (name == 'writeFileAtomic' || name == 'writeFileAtomicString') {
      facts.callsWriteFileAtomic = true;
    }
    if (name == 'lazyFromSpool') facts.lazyFromSpoolCalls++;
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
        'package root (flutter test does this by default)',
      );
    }

    final files = <LawFile>[];
    final entries =
        libDir
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
    // Pre-pass: file-local const string lists, so argv assembled by spreading
    // one (`[..._kDiffCmd, hash]`) is readable. Without this the git-argv law
    // is blind to exactly the sites that centralized their flags — the
    // careful ones.
    final constLists = _collectConstStringLists(parsed.unit);
    parsed.unit.accept(_FactsVisitor(facts, constLists));

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
        for (final e in parsed.errors) '${f.path}:${e.offset}: ${e.message}',
      ],
      facts: facts,
    );
  }
}
