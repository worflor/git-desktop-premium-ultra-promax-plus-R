import '../../backend/dtos.dart';
import '../../backend/git.dart';
import '../../backend/git_result.dart';
import 'palette_entry.dart';

class PaletteGitCache {
  List<BranchInfo>? branches;
  List<StashEntryData>? stashes;
  List<TagEntryData>? tags;

  Future<void> warm(String repoPath) async {
    final results = await Future.wait([
      listBranches(repoPath),
      listStashes(repoPath),
      listTags(repoPath),
    ]);
    final br = results[0] as GitResult<List<BranchInfo>>;
    final st = results[1] as GitResult<List<StashEntryData>>;
    final tg = results[2] as GitResult<List<TagEntryData>>;
    branches = br.ok ? br.data : null;
    stashes = st.ok ? st.data : null;
    tags = tg.ok ? tg.data : null;
  }

  void clear() {
    branches = null;
    stashes = null;
    tags = null;
  }
}

Future<List<PaletteEntry>> searchWithCache(
  String repoPath,
  String query,
  PaletteGitCache cache,
) async {
  final results = await Future.wait([
    _filterBranches(cache.branches, query),
    _searchCommits(repoPath, query),
    _filterFiles(repoPath, query),
    _filterStashes(cache.stashes, query),
    _filterTags(cache.tags, query),
  ]);
  return results.expand((e) => e).toList();
}

Future<List<PaletteEntry>> _filterBranches(
  List<BranchInfo>? branches,
  String query,
) async {
  if (branches == null) return [];
  final q = query.toLowerCase();
  return branches
      .where((b) => b.name.toLowerCase().contains(q))
      .take(15)
      .map(
        (b) => PaletteEntry(
          id: 'branch.${b.name}',
          label: b.name,
          subtitle: b.current ? 'current' : b.upstream,
          category: PaletteCategory.branch,
          actionType: PaletteActionType.execute,
          chipLabel: b.current
              ? 'HEAD'
              : b.gone
                  ? 'GONE'
                  : b.upstream != null
                      ? 'REMOTE'
                      : 'LOCAL',
        ),
      )
      .toList();
}

Future<List<PaletteEntry>> _searchCommits(
  String repoPath,
  String query,
) async {
  if (query.length < 3) return [];
  final result = await searchCommits(repoPath, query);
  if (!result.ok) return [];
  return result.data!
      .take(10)
      .map(
        (c) => PaletteEntry(
          id: 'commit.${c.commitHash}',
          label: c.subject,
          subtitle: '${c.shortHash} — ${c.authorName}',
          category: PaletteCategory.commit,
          actionType: PaletteActionType.execute,
          chipLabel: _commitAgeChip(c.authoredAt),
          refPath: c.commitHash,
        ),
      )
      .toList();
}

String _commitAgeChip(String authoredAt) {
  try {
    final age = DateTime.now().difference(DateTime.parse(authoredAt));
    if (age.inDays == 0) return 'TODAY';
    if (age.inDays < 7) return '${age.inDays}d';
    if (age.inDays < 30) return '${(age.inDays / 7).round()}w';
    if (age.inDays < 365) return '${(age.inDays / 30).round()}m';
    return '${(age.inDays / 365).round()}y';
  } catch (_) {
    return '';
  }
}

Future<List<PaletteEntry>> _filterFiles(
  String repoPath,
  String query,
) async {
  if (query.length < 2) return [];
  final result = await getRepositoryStatus(repoPath);
  if (!result.ok) return [];
  final q = query.toLowerCase();
  return result.data!.files
      .where((f) => f.path.toLowerCase().contains(q))
      .take(15)
      .map(
        (f) => PaletteEntry(
          id: 'file.${f.path}',
          label: f.path,
          subtitle: f.hasStagedChange ? 'staged' : 'modified',
          category: PaletteCategory.file,
          actionType: PaletteActionType.execute,
          chipLabel: _fileStatusChip(f),
          refPath: f.path,
        ),
      )
      .toList();
}

String _fileStatusChip(RepositoryStatusFile f) {
  if (f.isConflicted) return 'U';
  if (f.isUntracked) return '?';
  final sc = f.stagedCode;
  if (sc.isNotEmpty) return sc;
  final uc = f.unstagedCode;
  if (uc.isNotEmpty) return uc;
  return 'M';
}

Future<List<PaletteEntry>> _filterStashes(
  List<StashEntryData>? stashes,
  String query,
) async {
  if (stashes == null) return [];
  final q = query.toLowerCase();
  return stashes
      .where((s) => s.message.toLowerCase().contains(q))
      .take(10)
      .map(
        (s) => PaletteEntry(
          id: 'stash.${s.index}',
          label: s.message,
          subtitle: 'stash@{${s.index}}',
          category: PaletteCategory.stash,
          actionType: PaletteActionType.execute,
          chipLabel: '#${s.index}',
        ),
      )
      .toList();
}

Future<List<PaletteEntry>> _filterTags(
  List<TagEntryData>? tags,
  String query,
) async {
  if (tags == null) return [];
  final q = query.toLowerCase();
  return tags
      .where((t) => t.name.toLowerCase().contains(q))
      .take(15)
      .map(
        (t) => PaletteEntry(
          id: 'tag.${t.name}',
          label: t.name,
          subtitle: t.subject,
          category: PaletteCategory.tag,
          actionType: PaletteActionType.execute,
          chipLabel: t.tagType == 'tag' ? 'AN' : 'LW',
        ),
      )
      .toList();
}
