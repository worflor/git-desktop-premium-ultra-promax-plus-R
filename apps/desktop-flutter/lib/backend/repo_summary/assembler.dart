// assembler.dart — render a RepoDoc to markdown.
//
// Summary shape: what the repo is, how it's shaped, which files are
// at its core (with one-line purposes), what the regions are, how to
// get started. Physics stays behind the curtain — no centralities,
// no cohesion, no knees.

import 'types.dart';

/// Render a [RepoDoc] to markdown.
String renderMarkdown(RepoDoc doc) {
  final buf = StringBuffer();

  buf.writeln('# ${doc.repoName}');
  buf.writeln();
  if (doc.elevatorPitch.isNotEmpty) {
    buf.writeln(doc.elevatorPitch);
    buf.writeln();
  }

  if (doc.shape.isNotEmpty) {
    buf.writeln('## Shape');
    buf.writeln();
    buf.writeln(doc.shape);
    buf.writeln();
  }

  buf.writeln('## At a glance');
  buf.writeln();
  _writeGlance(buf, doc);
  if (doc.historyStarved) {
    buf.writeln('- Ranking is limited: the coupling graph had no edges '
        '(fresh clone or too few commits). File order reflects size, '
        'not structural centrality.');
  }
  buf.writeln();

  if (doc.backbone.isNotEmpty) {
    buf.writeln('## Core');
    buf.writeln();
    for (final entry in doc.backbone) {
      final line = StringBuffer();
      line.write('- `${entry.path}` ');
      line.write('(${_plural(entry.lineCount, 'line', 'lines')})');
      line.write(' — ${_regionLabel(entry.regionName)}');
      if (entry.purpose.isNotEmpty) {
        line.write(' · ${entry.purpose}');
      }
      buf.writeln(line.toString());
    }
    buf.writeln();
  }

  if (doc.regions.isNotEmpty) {
    buf.writeln('## Regions');
    buf.writeln();
    for (final r in doc.regions) {
      _writeRegion(buf, r);
    }
  }

  if (doc.gettingStarted.trim().isNotEmpty) {
    buf.writeln('## Getting started');
    buf.writeln();
    buf.writeln(doc.gettingStarted.trim());
    buf.writeln();
  }

  // Keep the generation stamp in an HTML comment so it survives into
  // the raw markdown (useful for debugging cache-regeneration) but
  // doesn't paste into an LLM chat as visible noise.
  final stamp = doc.generatedAt.toUtc().toIso8601String();
  buf.writeln('<!-- generated $stamp -->');
  return buf.toString();
}

void _writeGlance(StringBuffer buf, RepoDoc doc) {
  final g = doc.glance;
  // Reframe as "Showing N of M" when dormant filtering actually
  // dropped files — the reader sees the ratio, not an opaque
  // "omitted" counter.
  final total = doc.totalHarvested;
  if (total > g.activeFileCount && g.activeFileCount > 0) {
    buf.writeln('- Showing ${g.activeFileCount} of $total files, '
        'ranked by structural centrality.');
  } else {
    buf.writeln('- ${_plural(g.activeFileCount, 'file', 'files')}.');
  }
  buf.writeln('- ${_plural(g.activeLines, 'line', 'lines')} '
      '(${_humanBytes(g.activeBytes)}).');
  if (g.roles.isNotEmpty) {
    final parts = g.roles.map((e) => '${e.key}: ${e.value}').join(', ');
    buf.writeln('- Roles — $parts.');
  }
}

void _writeRegion(StringBuffer buf, RegionDoc r) {
  buf.writeln('### ${r.name}');
  buf.writeln();
  if (r.body.isNotEmpty) {
    buf.writeln(r.body);
    buf.writeln();
  }
  if (r.paths.isNotEmpty) {
    buf.writeln('Files:');
    for (final path in r.paths) {
      buf.writeln('- `$path`');
    }
    buf.writeln();
  }
  if (r.neighborNames.isNotEmpty) {
    // neighborNames is already sorted by cross-edge weight in
    // regions.dart; cap the render at the top few so weak ties
    // don't smear the signal.
    const maxNeighbors = 3;
    final topNeighbors = r.neighborNames.take(maxNeighbors).toList();
    final linked = topNeighbors.map(_regionLabel).join(', ');
    buf.writeln('Connects to: $linked.');
    buf.writeln();
  }
}

/// Render a region name as a markdown label. Identifier-shaped names
/// get backticks; prose-shaped names with spaces get italics.
String _regionLabel(String name) {
  final looksLikeIdentifier =
      name.contains('_') || name.contains('.') || !name.contains(' ');
  return looksLikeIdentifier ? '`$name`' : '_${name}_';
}

String _humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _plural(int n, String singular, String plural) {
  return n == 1 ? '$n $singular' : '$n $plural';
}
