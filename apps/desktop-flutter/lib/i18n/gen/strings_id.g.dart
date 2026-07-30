///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsId extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsId({
    Map<String, Node>? overrides,
    PluralResolver? cardinalResolver,
    PluralResolver? ordinalResolver,
    TranslationMetadata<AppLocale, Translations>? meta,
  }) : assert(
         overrides == null,
         'Set "translation_overrides: true" in order to enable this feature.',
       ),
       $meta =
           meta ??
           TranslationMetadata(
             locale: AppLocale.id,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <id>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsId _root = this; // ignore: unused_field

  @override
  TranslationsId $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsId(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$app$id app = _Translations$app$id._(_root);
  @override
  late final _Translations$backend$id backend = _Translations$backend$id._(
    _root,
  );
  @override
  late final _Translations$branches$id branches = _Translations$branches$id._(
    _root,
  );
  @override
  late final _Translations$changes$id changes = _Translations$changes$id._(
    _root,
  );
  @override
  late final _Translations$common$id common = _Translations$common$id._(_root);
  @override
  late final _Translations$diff$id diff = _Translations$diff$id._(_root);
  @override
  late final _Translations$filament$id filament = _Translations$filament$id._(
    _root,
  );
  @override
  late final _Translations$history$id history = _Translations$history$id._(
    _root,
  );
  @override
  late final _Translations$historySurgery$id historySurgery =
      _Translations$historySurgery$id._(_root);
  @override
  late final _Translations$onboarding$id onboarding =
      _Translations$onboarding$id._(_root);
  @override
  late final _Translations$orrery$id orrery = _Translations$orrery$id._(_root);
  @override
  late final _Translations$palette$id palette = _Translations$palette$id._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$id releaseNotes =
      _Translations$releaseNotes$id._(_root);
  @override
  late final _Translations$repoSummary$id repoSummary =
      _Translations$repoSummary$id._(_root);
  @override
  late final _Translations$review$id review = _Translations$review$id._(_root);
  @override
  late final _Translations$settings$id settings = _Translations$settings$id._(
    _root,
  );
  @override
  late final _Translations$sync$id sync = _Translations$sync$id._(_root);
  @override
  late final _Translations$xray$id xray = _Translations$xray$id._(_root);
}

// Path: app
class _Translations$app$id extends Translations$app$en {
  _Translations$app$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => 'Pengaturan';
  @override
  String get panelReleaseNotes => 'Catatan Rilis';
  @override
  String get panelFilamentFindings => 'Temuan Filament';
  @override
  String get filamentFindingsUpper => 'TEMUAN FILAMENT';
  @override
  late final _Translations$app$cheatsheet$id cheatsheet =
      _Translations$app$cheatsheet$id._(_root);
  @override
  String get commandPaletteTooltip => 'Command palette   /';
  @override
  String get newDeskFallback => 'desk baru';
  @override
  String get deskFallback => 'desk';
  @override
  String get currentDeskFallback => 'saat ini';
  @override
  String get noRepositoryOpen => 'Tidak ada repository yang terbuka';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Tidak bisa membuka sebagai desk: ${error}';
  @override
  String couldNotDetectForge({required Object error}) =>
      'Tidak bisa mendeteksi forge: ${error}';
  @override
  String get cannotFetchPrNoForge =>
      'Tidak bisa mengambil PR: forge tidak terdeteksi untuk repo ini.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      'Timpa ${ref} dengan versi terbaru dari remote?';
  @override
  String get overwrite => 'Timpa';
  @override
  String couldntFetchPr({required Object error}) =>
      'Tidak bisa mengambil PR: ${error}';
  @override
  String get promoteDeskToPr => 'Naikkan desk jadi PR';
  @override
  String get applyToMain => 'Terapkan ke main';
  @override
  String updateDeskFrom({required Object target, required Object source}) =>
      'Perbarui ${target} dari ${source}';
  @override
  String bringChangesFromHere({required Object source}) =>
      'Bawa perubahan dari ${source} ke sini';
  @override
  String get editLocalPr => 'Edit PR lokal';
  @override
  String get discardLocalPr => 'Buang PR lokal';
  @override
  String get closeDesk => 'Tutup desk';
  @override
  String couldntPromote({required Object error}) => 'Gagal menaikkan: ${error}';
  @override
  String get commitOrShelveBeforeApplying =>
      'Commit atau simpan dulu perubahan desk sebelum menerapkan.';
  @override
  String get couldNotResolveMainWorktree =>
      'Tidak bisa menemukan path worktree utama.';
  @override
  String couldntPromoteDesk({required Object error}) =>
      'Tidak bisa menaikkan desk: ${error}';
  @override
  String get couldntDetermineBaseBranch =>
      'Tidak bisa menentukan base branch untuk desk ini.';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'Base dan head PR adalah branch yang sama (${branch}) — tidak ada yang diterapkan.';
  @override
  String appliedBranchToBase({required Object branch, required Object base}) =>
      '${branch} diterapkan ke ${base}';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
    n,
    other: '${target} diperbarui ke ${source} (${n} commit).',
  );
  @override
  String get fastForwardFailedFallback =>
      'Fast-forward tidak bisa mendarat bersih — menampilkan pratinjau patch sebagai gantinya.';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
    n,
    other: '${target} unggul ${n} commit di depan ${source}.',
  );
  @override
  String deskUpToDate({required Object target, required Object source}) =>
      '${target} sudah sejalan dengan ${source}.';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      'Ada perubahan belum di-commit di ${target} — menampilkan pratinjau sebagai patch.';
  @override
  String updateDeskFromLower({
    required Object target,
    required Object source,
  }) => 'perbarui ${target} dari ${source}';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      'Tidak ada update untuk dibawa dari ${source}.';
  @override
  String get updatePrepFailed => 'Persiapan update gagal';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => 'bawa perubahan dari ${source} ke ${target}';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      'Tidak ada perubahan yang bisa di-patch dari ${source} ke ${target}.';
  @override
  String get patchPrepFailed => 'Persiapan patch gagal';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label}: ${error}';
  @override
  String get titleHint => 'judul';
  @override
  String get bodyHint => 'isi';
  @override
  String get bodyOptionalHint => 'isi (opsional)';
  @override
  String get draftLower => 'draf';
  @override
  String get cancelLower => 'batal';
  @override
  String get saveLower => 'simpan';
  @override
  String couldntSave({required Object error}) =>
      'Tidak bisa menyimpan: ${error}';
  @override
  String get stashedNoOtherDesk =>
      'Perubahan di-stash — tidak ada desk lain untuk menerapkannya. Pakai git stash pop untuk memulihkan.';
  @override
  String get suggestedSource => 'sumber yang disarankan';
  @override
  String tooltipModifiedCount({required Object n}) => '${n} diubah';
  @override
  String tooltipAheadCount({required Object n}) => '${n} di depan';
  @override
  String tooltipBehindCount({required Object n}) => '${n} di belakang';
  @override
  String get focusedEdits => 'editan terfokus';
  @override
  String get editsSpreadAcrossSubsystems =>
      'editan tersebar ke banyak subsistem';
  @override
  String get editsTouchingManySubsystems => 'editan menyentuh banyak subsistem';
  @override
  String get focusedBranch => 'branch terfokus';
  @override
  String get branchSpansMultipleSubsystems =>
      'branch merentang beberapa subsistem';
  @override
  String get structurallyDivergentFromMainline =>
      'menyimpang secara struktural dari mainline';
  @override
  String get localPr => 'PR lokal';
  @override
  String lastTouched({required Object time}) => 'terakhir disentuh ${time}';
  @override
  String driftGroupCount({required Object n, required Object dir}) =>
      '${n} di ${dir}';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => 'Perubahan belum di-commit';
  @override
  String get closeDeskQuestion => 'Tutup desk?';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file belum di-commit.',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} commit di depan main.',
      );
  @override
  String get willRemoveWorktreeDirectory =>
      'Ini akan menghapus direktori worktree.';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file berubah',
      );
  @override
  String get shelveHere => 'Simpan di sini';
  @override
  String get discardAndClose => 'Buang & tutup';
  @override
  String get noRepository => 'tidak ada repository';
  @override
  String get issuePromotedToRemote => 'Issue dinaikkan ke remote.';
  @override
  String get pushedToRemote => 'Sudah di-push ke remote.';
  @override
  String get pulledFromRemote => 'Sudah di-pull dari remote.';
  @override
  String get remoteIssueNotFound => 'issue remote tidak ditemukan';
  @override
  String importedIssueLocally({required Object id}) =>
      '#${id} diimpor secara lokal.';
  @override
  String get issueAbandoned => 'Issue ditinggalkan.';
  @override
  String get abandonIssue => 'Tinggalkan issue';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      'Hapus permanen issue lokal #${id}? Ini menghapus ref-nya dan tidak bisa dibatalkan.';
  @override
  String get abandon => 'Tinggalkan';
  @override
  String publishedBranch({required Object branch}) =>
      '${branch} dipublikasikan.';
  @override
  String get publishingEllipsis => 'Mempublikasikan…';
  @override
  String get publish => 'Publikasikan';
  @override
  String get noRemoteConfigured =>
      'Tidak ada remote yang dikonfigurasi untuk repository ini.';
  @override
  String get jumpToDesk => 'Lompat ke desk';
  @override
  String get arrowOpen => '→ buka';
  @override
  String get openOnANewDesk => 'Buka di desk baru';
  @override
  String get plusDesk => '+ desk';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'nama-branch-baru';
  @override
  String get escLower => 'esc';
  @override
  String get plusNewDesk => '+ desk baru';
  @override
  String get fromHeadEllipsis => 'dari HEAD...';
  @override
  String get viewAllBranches => 'Lihat semua branch';
  @override
  String get issuesLower => 'issues';
  @override
  String get newIssueLower => 'issue baru';
  @override
  String get noneLinked => 'belum ada tautan';
  @override
  String get noOpenIssues => 'tidak ada issue terbuka';
  @override
  String get createAndPushLower => 'buat + push';
  @override
  String get createLower => 'buat';
  @override
  String get remoteLower => 'remote';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => 'Naikkan ke remote';
  @override
  String get pushToRemote => 'Push ke remote';
  @override
  String get pullFromRemote => 'Pull dari remote';
  @override
  String get importLabel => 'Impor';
  @override
  String get failedToCreateRepository => 'Gagal membuat repository.';
  @override
  String get openRepositoryLower => 'buka repository';
  @override
  String get newRepositoryLower => 'repository baru';
  @override
  String get back => 'Kembali';
  @override
  String get openRepositoryDialogTitle => 'Buka Repository';
  @override
  String get createRepositoryDialogTitle => 'Buat Repository';
  @override
  String get cloneTargetDialogTitle => 'Target Clone';
  @override
  String get cloneToDialogTitle => 'Clone ke';
  @override
  String get exportToDialogTitle => 'Ekspor ke';
  @override
  String get createFromTemplateInDialogTitle => 'Buat dari template di';
  @override
  String get notAGitRepoInitConfirm =>
      'Bukan repository git. Inisialisasi satu di sini?';
  @override
  String get repositoryUrlRequired => 'URL repository wajib diisi.';
  @override
  String get failedToCloneRepository => 'Gagal meng-clone repository.';
  @override
  String cloningEllipsis({required Object name}) => 'Meng-clone ${name}...';
  @override
  String get cloneCancelled => 'Clone dibatalkan.';
  @override
  String get noProjectsYet => 'Belum ada proyek';
  @override
  String get dissolveGroup => 'Bubarkan grup';
  @override
  String get projectsHeader => 'Proyek';
  @override
  String get cloneLabel => 'Clone';
  @override
  String get createLabel => 'Buat';
  @override
  String get openLabel => 'Buka';
  @override
  String get repositoryUrlPlaceholder => 'URL Repository';
  @override
  String get projectNameOrFullPathPlaceholder =>
      'nama-proyek atau path lengkap';
  @override
  String get pathToProjectPlaceholder => '/path/ke/proyek';
  @override
  String get cloneToFolderPathPlaceholder => 'Path folder tujuan clone';
  @override
  String get switchToCreateRepo => 'Beralih ke Buat repo';
  @override
  String get explorer => 'Explorer';
  @override
  String get terminal => 'Terminal';
  @override
  String get cloneUrl => 'URL Clone';
  @override
  String get copyPath => 'Salin path';
  @override
  String get export => 'Ekspor';
  @override
  String get readme => 'README';
  @override
  String get duplicate => 'Duplikat';
  @override
  String get template => 'Template';
  @override
  String get forgetThisProject => 'Lupakan proyek ini';
  @override
  String get aiKindCommitMessage => 'pesan commit';
  @override
  String get aiKindReview => 'review';
  @override
  String get aiKindMuse => 'muse';
  @override
  String get aiKindPresent => 'present';
  @override
  String get aiKindDebug => 'debug';
  @override
  String aiStatusRunning({required Object kind}) => '${kind} berjalan';
  @override
  String aiStatusFailedUnread({required Object kind}) =>
      '${kind} gagal (belum dibaca)';
  @override
  String aiStatusReadyUnread({required Object kind}) =>
      '${kind} siap (belum dibaca)';
  @override
  String get filesLower => 'file';
  @override
  String get commitsLower => 'commit';
  @override
  String get undoLabel => 'Undo';
  @override
  String get goLabel => 'gas';
  @override
  String countdownSeconds({required Object n}) => '${n}s';
  @override
  String get collapseGlyph => '▲ ciutkan';
  @override
  String moreLinesGlyph({required Object n}) => '▼ ${n} baris lagi';
}

// Path: backend
class _Translations$backend$id extends Translations$backend$en {
  _Translations$backend$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$id ops = _Translations$backend$ops$id._(
    _root,
  );
  @override
  late final _Translations$backend$mergeOutcome$id mergeOutcome =
      _Translations$backend$mergeOutcome$id._(_root);
}

// Path: branches
class _Translations$branches$id extends Translations$branches$en {
  _Translations$branches$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => 'Menjalankan review AI…';
  @override
  String prNumberLabel({required Object number}) => 'PR #${number}';
  @override
  String get findings => 'TEMUAN';
  @override
  String get observations => 'OBSERVASI';
  @override
  String get renameEllipsis => 'Ganti nama…';
  @override
  String get publish => 'Publikasikan';
  @override
  String publishFailed({required Object error}) => 'Publikasi gagal: ${error}';
  @override
  String couldntOpenDesk({required Object error}) =>
      'Tidak bisa membuka desk: ${error}';
  @override
  String syncFailed({required Object error}) => 'Sync gagal: ${error}';
  @override
  String get renameBranchTitle => 'Ganti nama branch';
  @override
  String get newNameHint => 'nama baru';
  @override
  String get rename => 'Ganti nama';
  @override
  String invalidBranchName({required Object name}) =>
      '\'${name}\' bukan nama branch yang valid.';
  @override
  String renameFailed({required Object error}) => 'Ganti nama gagal: ${error}';
  @override
  String deletingBranch({required Object name}) => 'Menghapus ${name}';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '\'${name}\' terbuka di desk \'${desk}\'.';
  @override
  String get openDesk => 'Buka desk';
  @override
  String openInDeskShort({required Object desk}) => 'buka di desk \'${desk}\'';
  @override
  String get couldNotPinBranch =>
      'tidak bisa mem-pin tip branch; penghapusan dilewati';
  @override
  String get couldNotPinTag => 'tidak bisa mem-pin tag; penghapusan dilewati';
  @override
  String deletingTag({required Object name}) => 'Menghapus tag ${name}';
  @override
  String get applyToActiveChanges => 'Terapkan ke perubahan aktif…';
  @override
  String get couldNotLoadPrDiff => 'Tidak bisa memuat diff PR.';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}: ${title}';
  @override
  String mergeIntoDesk({required Object branch}) => 'Merge ke ${branch}…';
  @override
  String get checkoutThisPr => 'Checkout PR ini';
  @override
  String get mergeIntoNewDesk => 'Merge ke desk baru…';
  @override
  String get pushToForge => 'Push ke forge';
  @override
  String get linkToIssue => 'Tautkan ke issue…';
  @override
  String get gitPatch => '↓ git patch';
  @override
  String get copyBranchName => 'Salin nama branch';
  @override
  String copiedRef({required Object ref}) => 'Menyalin "${ref}"';
  @override
  String get reviewPr => 'Review PR';
  @override
  String get openInBrowser => 'Buka di browser';
  @override
  String get markAsRead => 'Tandai sudah dibaca';
  @override
  String get markAsUnread => 'Tandai belum dibaca';
  @override
  String get replaceLocalCommitsTitle => 'Ganti commit lokal?';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref} punya commit lokal yang tidak ada di head PR remote. Memperbaruinya akan menggantinya dengan versi terbaru dari remote.';
  @override
  String get update => 'Perbarui';
  @override
  String couldntFetchPr({required Object error}) =>
      'Tidak bisa mengambil PR: ${error}';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Tidak bisa membuka sebagai desk: ${error}';
  @override
  String couldntOpenInBrowser({required Object error}) =>
      'Tidak bisa membuka di browser: ${error}';
  @override
  String get noIssuesYetLocal =>
      'Belum ada issue. Buka satu upstream, atau pakai "+ issue lokal baru" di lensa issue.';
  @override
  String get remotePrsLinkLocalOnly =>
      'PR remote hanya bisa ditautkan ke issue lokal. Buat satu dengan "+ issue lokal baru".';
  @override
  String linkPrToIssues({required Object number}) =>
      'Tautkan PR #${number} ke issue';
  @override
  String get noPrsYetLocal =>
      'Belum ada PR. Buka satu upstream, atau naikkan desk jadi PR.';
  @override
  String get remoteIssuesLinkLocalOnly =>
      'Issue remote hanya bisa ditautkan ke PR lokal. Naikkan desk jadi PR dulu.';
  @override
  String linkIssueToPrs({required Object number}) =>
      'Tautkan issue #${number} ke PR';
  @override
  String couldntToggleLink({required Object error}) =>
      'Tidak bisa menoggle tautan: ${error}';
  @override
  String get openPatchDialogTitle => 'Buka patch (.patch / .diff)';
  @override
  String get clipboardNoText => 'Clipboard tidak berisi teks.';
  @override
  String get clipboardPatchLabel => 'clipboard.patch';
  @override
  String failedToOpenPatch({required Object error}) =>
      'Gagal membuka patch: ${error}';
  @override
  String get patchEmptyOrUnparseable =>
      'Patch kosong atau tidak bisa di-parse.';
  @override
  String get prPushedToForge => 'PR di-push ke forge.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      'Timpa ${ref} dengan versi terbaru dari remote?';
  @override
  String get overwrite => 'Timpa';
  @override
  String get loadingBranchesTitle => 'Memuat branch';
  @override
  String get loadingBranchesMessage => 'Membaca branch dan tag lokal.';
  @override
  String get branchesUnavailableTitle => 'Branch tidak tersedia';
  @override
  String get filterPullRequestsHint => 'filter pull request…';
  @override
  String get filterIssuesHint => 'filter issue…';
  @override
  String get branchNameHint => 'nama branch';
  @override
  String get tagsNewestFirst => 'tag, terbaru dulu';
  @override
  String get tagsOldestFirst => 'tag, terlama dulu';
  @override
  String get flipSortDirection => 'balik arah urutan';
  @override
  String get readingPullRequests => 'Membaca pull request…';
  @override
  String get noOpenPullRequests => 'Tidak ada pull request terbuka';
  @override
  String get noPullRequestsHint => 'Buka satu dari branch, atau naikkan desk.';
  @override
  String get noPrsMatchFilters => 'Tidak ada PR yang cocok dengan filter ini';
  @override
  String get toggleFiltersRowAbove => 'Matikan filter di baris atas.';
  @override
  String get issuesNewestFirst => 'issue, terbaru dulu';
  @override
  String get issuesOldestFirst => 'issue, terlama dulu';
  @override
  String get issuesHeading => 'ISSUE';
  @override
  String get readingIssuesLower => 'membaca issue…';
  @override
  String get noOpenIssues => 'Tidak ada issue terbuka';
  @override
  String get noIssuesHint => '+ baru untuk melacak pekerjaan dan bug.';
  @override
  String get nothingMatches => 'Tidak ada yang cocok';
  @override
  String get toggleFiltersAbove => 'Matikan filter di atas.';
  @override
  String get bucketFresh => 'SEGAR';
  @override
  String get bucketThisWeek => 'MINGGU INI';
  @override
  String get bucketStalled => 'MANDEK';
  @override
  String get bucketOlder => 'LEBIH LAMA';
  @override
  String get couldNotResolveMainWorktree =>
      'Tidak bisa menemukan path worktree utama.';
  @override
  String couldntSubmitReview({required Object error}) =>
      'Tidak bisa mengirim review: ${error}';
  @override
  String get reviewAiNotAvailable => 'Review AI belum tersedia.';
  @override
  String get noReviewModelConfigured =>
      'Tidak ada model review yang dikonfigurasi.';
  @override
  String get deskFallback => 'desk';
  @override
  String deskUncommittedChanges({
    required num n,
    required Object branch,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
    n,
    other:
        '${branch} punya ${n} perubahan belum di-commit — commit atau stash dulu.',
  );
  @override
  String get targetDeskNoBranch => 'Desk target tidak punya branch.';
  @override
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      'Merge PR #${number} ke ${branch}';
  @override
  String get conflictCheckUnavailableVersion =>
      'Pemeriksaan konflik tidak tersedia — butuh git 2.38+';
  @override
  String get conflictCheckUnavailable => 'Pemeriksaan konflik tidak tersedia';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'AKAN KONFLIK · ${n} file',
      );
  @override
  String plusMore({required Object n}) => '+${n} lagi';
  @override
  String get rebase => 'Rebase';
  @override
  String get squash => 'Squash';
  @override
  String get mergeCommit => 'Merge commit';
  @override
  String noDeskForBranch({required Object branch}) =>
      'Tidak ada desk untuk branch ${branch}';
  @override
  String get mergeAnyway => 'Merge saja';
  @override
  String get readingIssues => 'Membaca issue…';
  @override
  String get openUpstreamOrLocal => 'Buka satu upstream, atau buka yang lokal.';
  @override
  String get noIssuesMatchFilters =>
      'Tidak ada issue yang cocok dengan filter ini';
  @override
  String couldntCreateIssue({required Object error}) =>
      'Tidak bisa membuat issue: ${error}';
  @override
  String get promoteToRemote => 'Naikkan ke remote';
  @override
  String get pushToRemote => 'Push ke remote';
  @override
  String get pullFromRemote => 'Pull dari remote';
  @override
  String get import => 'Impor';
  @override
  String get linkToPr => 'Tautkan ke PR…';
  @override
  String get abandon => 'Tinggalkan';
  @override
  String get issuePromotedToRemote => 'Issue dinaikkan ke remote.';
  @override
  String get issuePushedToRemote => 'Di-push ke remote.';
  @override
  String get issuePulledFromRemote => 'Di-pull dari remote.';
  @override
  String issueImportedLocally({required Object number}) =>
      '#${number} diimpor secara lokal.';
  @override
  String get abandonIssueTitle => 'Tinggalkan issue';
  @override
  String abandonIssueMessage({required Object id}) =>
      'Hapus permanen issue lokal #${id}? Ini menghapus ref-nya dan tidak bisa dibatalkan.';
  @override
  String couldntAbandon({required Object error}) =>
      'Tidak bisa meninggalkan: ${error}';
  @override
  String couldntPostComment({required Object error}) =>
      'Tidak bisa mengirim komentar: ${error}';
  @override
  String couldntCloseIssue({required Object error}) =>
      'Tidak bisa menutup issue: ${error}';
  @override
  String couldntAddLabel({required Object error}) =>
      'Tidak bisa menambah label: ${error}';
  @override
  String get lensBranches => 'BRANCHES';
  @override
  String get lensPrs => 'PRs';
  @override
  String get patchUp => '↑ patch';
  @override
  String get syncRibbon => '⇅ sync';
  @override
  String get kbHeading => 'KEYBOARD';
  @override
  String get kbNavigateRows => 'navigasi baris';
  @override
  String get kbExpandCollapse => 'perluas / ciutkan baris terfokus';
  @override
  String get kbCheckoutPr => 'checkout PR terfokus secara lokal';
  @override
  String get kbApproveReview => 'setujui · review';
  @override
  String get kbRequestChanges => 'minta perubahan';
  @override
  String get kbFocusSearch => 'fokus ke pencarian';
  @override
  String get kbSwitchLens => 'ganti lensa (branches · prs)';
  @override
  String get kbToggleOverlay => 'toggle overlay ini';
  @override
  String get kbPressToDismiss => 'tekan di mana saja untuk menutup';
  @override
  String get overrideScarTooltip =>
      'di-merge dengan check gagal atau tanpa review yang menyetujui — selidiki dulu dalam kondisi genting';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file tumpang tindih dengan kerja belum di-commit-mu',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '#${pr}  (${n} file)',
      );
  @override
  String get prStateDraft => 'DRAFT';
  @override
  String get localBadge => 'LOKAL';
  @override
  String get myReviewPending => 'review-mu menunggu';
  @override
  String get myReviewApproved => 'kamu ✓';
  @override
  String get myReviewChangesRequested => 'kamu ✗ meminta perubahan';
  @override
  String get myReviewCommented => 'kamu berkomentar';
  @override
  String get myReviewDefault => 'kamu';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '${count} komentar · terakhir dari penulis ditampilkan';
  @override
  String get tailLastComment => 'komentar terakhir';
  @override
  String tailLastReviewState({required Object state}) =>
      'review terakhir · ${state}';
  @override
  String get tailLastReview => 'review terakhir';
  @override
  String tailLastCheckState({required Object state}) =>
      'check terakhir · ${state}';
  @override
  String get tailLastCommit => 'commit terakhir';
  @override
  String get tailLastActivity => 'aktivitas terakhir';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'menutup ${n} issue — klik untuk melompat',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'ditangani oleh ${n} PR — klik untuk melompat',
      );
  @override
  String get checksLabel => 'check';
  @override
  String get reviewersLabel => 'reviewer';
  @override
  String get conflictsLabel => 'konflik';
  @override
  String exportFailed({required Object error}) => 'Ekspor gagal: ${error}';
  @override
  String get readingFiles => 'membaca file…';
  @override
  String get noDetailAvailable => 'tidak ada detail tersedia';
  @override
  String get noFilesReported => 'tidak ada file dilaporkan';
  @override
  String get readingGitHistory => 'membaca history git…';
  @override
  String get knowsThisCode => 'tahu kode ini';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} commit pada file-file ini dalam setahun terakhir',
      );
  @override
  String get willFight => 'AKAN BENTROK';
  @override
  String orbitalPartnerCos({required Object cos}) =>
      'partner orbital — cos ${cos}';
  @override
  String get orbitLabel => 'orbit';
  @override
  String get touchesYourLocalWork => 'MENYENTUH KERJA LOKALMU';
  @override
  String get mergingWillConflict =>
      'merge kemungkinan akan konflik dengan perubahan belum di-commit-mu';
  @override
  String get closesHeading => 'MENUTUP';
  @override
  String get filesHeading => 'FILE';
  @override
  String get orientAligned => 'sejajar';
  @override
  String get orientAdjacent => 'bersebelahan';
  @override
  String get orientOrthogonal => 'ortogonal';
  @override
  String shapeField({required Object v}) => 'field ${v}';
  @override
  String shapeSource({required Object v}) => 'source ${v}';
  @override
  String shapeSrcDelta({required Object v}) => 'srcΔ ${v}';
  @override
  String shapeFldDelta({required Object v}) => 'fldΔ ${v}';
  @override
  String shapeHf({required Object v}) => 'hf ${v}';
  @override
  String shapeHo({required Object v}) => 'ho ${v}';
  @override
  String shapeRg({required Object v}) => 'rg ${v}';
  @override
  String shapeFlowG({required Object v}) => 'g ${v}';
  @override
  String shapeFlowC({required Object v}) => 'c ${v}';
  @override
  String shapeFlowH({required Object v}) => 'h ${v}';
  @override
  String shapeStress({required Object v}) => 'stress ${v}';
  @override
  String shapeWit({required Object v}) => 'wit ${v}';
  @override
  String resonanceReadout({required Object v}) => 'resonansi ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      'biasanya bergerak bersama file di PR ini\n(${path})';
  @override
  String get prStateDraftLower => 'draf';
  @override
  String get keystoneTooltip => 'keystone — file jembatan seluruh repo';
  @override
  String get reviewNoteHint => 'tinggalkan catatan (opsional)…';
  @override
  String get reviewComment => 'komentar';
  @override
  String get reviewRequestChanges => 'minta perubahan';
  @override
  String get reviewApprove => '✓ setujui';
  @override
  String get actionPatchDown => '↓ patch';
  @override
  String get actionPrReview => '✦ pr review';
  @override
  String get actionOpenAsDesk => '⊞ buka sebagai desk';
  @override
  String get actionCheckout => '[c] checkout';
  @override
  String get actionMerge => '[m] merge ▾';
  @override
  String get mergeMenuMergeCommit => 'merge commit';
  @override
  String get mergeMenuSquash => 'squash & merge';
  @override
  String get mergeMenuRebase => 'rebase & merge';
  @override
  String get deleteBranchAfter => 'hapus branch setelahnya';
  @override
  String checkDurationSec({required Object n}) => '${n}s';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m}m ${s}s';
  @override
  String assignedTo({required Object names}) => 'ditugaskan: ${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '${n} percakapan · ${time}';
  @override
  String get readingThread => 'membaca thread…';
  @override
  String get addressedByHeading => 'DITANGANI OLEH';
  @override
  String get descriptionHeading => 'DESKRIPSI';
  @override
  String get threadHeading => 'THREAD';
  @override
  String get replyHint => 'balas…';
  @override
  String get assignMe => 'tugaskan aku';
  @override
  String get closeLower => 'tutup';
  @override
  String get postReply => '↩ kirim';
  @override
  String get remoteProviderUnavailable => 'Provider remote tidak tersedia';
  @override
  String get noRecognisedRemoteHost =>
      'Tidak ada host remote yang dikenali untuk repo ini.';
  @override
  String get corpseGone => 'hilang';
  @override
  String get corpseAbsorbed => 'terserap';
  @override
  String get corpseSquashed => 'di-squash';
  @override
  String absorbedDeliveredIn({required Object hash}) => 'dikirim di ${hash}';
  @override
  String get absorbedNoChanges => 'merge tidak menambah perubahan';
  @override
  String get corpseTagUpstreamGone => 'upstream hilang';
  @override
  String corpseTagAbsorbed({required Object receipt}) => 'terserap, ${receipt}';
  @override
  String get corpseTagSquashed => 'di-squash dan di-merge';
  @override
  String semanticsCurrentBranch({required Object name}) =>
      '${name}, branch saat ini';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}, tracking ${upstream}';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}, ${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) =>
      '${label}, worktree terbuka';
  @override
  String semanticsIdle({required Object name, required Object phrase}) =>
      '${name}, ${phrase}';
  @override
  String semanticsCorpse({
    required Object name,
    required Object tag,
    required Object phrase,
  }) => '${name}, ${tag}, ${phrase}';
  @override
  String get crossLinkDesk => 'desk';
  @override
  String get crossLinkPr => 'PR';
  @override
  String get crossLinkPrDraft => 'PR · draf';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} issue',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) => '→ tracking: ${upstream}';
  @override
  String get checkoutButton => 'Checkout';
  @override
  String get createBranch => 'Buat branch';
  @override
  String get newBranchName => 'Nama branch baru';
  @override
  String newBranchNameError({required Object error}) =>
      'Nama branch baru — ${error}';
  @override
  String get forceDelete => 'Paksa?';
  @override
  String get annotated => 'beranotasi';
  @override
  String get applyCheckFailed => 'apply --check gagal';
  @override
  String get openPatchFrom => 'BUKA PATCH DARI';
  @override
  String get patchFromFile => 'dari file…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => 'dari clipboard';
  @override
  String get patchFromClipboardHint => 'tempel teks';
  @override
  String get patchPreviewHeading => 'PRATINJAU PATCH';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => 'di-stage.';
  @override
  String get appliedDone => 'diterapkan.';
  @override
  String get opening => 'membuka…';
  @override
  String get mergeEditor => '⇋ merge editor';
  @override
  String get staging => 'men-stage…';
  @override
  String get applying => 'menerapkan…';
  @override
  String get stage => 'stage';
  @override
  String get apply => 'terapkan';
  @override
  String get refineHint => 'perhalus… (mis. "drop juga perubahan logger-nya")';
  @override
  String get reverseArmedTooltip =>
      'siaga — apply berikutnya akan me-REVERT patch (-R)';
  @override
  String get reverseDisarmedTooltip =>
      'siagakan reverse (-R) — batalkan alih-alih menerapkan';
  @override
  String get reverseArmedLabel => '⟲ reverse ✓';
  @override
  String get reverseLabel => '⟲ reverse';
  @override
  String get untouchedHeading => '⚠ TAK TERSENTUH';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${count} dari ${n} file tidak ada di patch',
      );
  @override
  String get staysConflicted =>
      'file-file ini akan tetap konflik — menerapkannya tidak akan mengstage-nya';
  @override
  String get orWith => 'ATAU DENGAN';
  @override
  String get noAiModelConfigured => 'tidak ada model AI dikonfigurasi';
  @override
  String applyWithPatchFrom({required Object label}) =>
      'terapkan dengan patch dari ${label}';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => 'terapkan dengan patch dari ${label}  ·  ${model}';
  @override
  String get patching => 'mem-patch…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  terapkan dengan patch dari ${label}';
  @override
  String get orWithAnotherModel => 'atau dengan model lain';
  @override
  String get applyCheckPassed =>
      'git apply --check lolos — patch akan diterapkan dengan bersih';
  @override
  String get gitApplyCheckFailed => 'git apply --check gagal';
  @override
  String get appliesClean => 'diterapkan bersih';
  @override
  String get willNotApply => 'tidak akan diterapkan';
  @override
  String get newLocalIssue => 'issue lokal baru';
  @override
  String get filterHint => 'filter…';
  @override
  String get nothingToLink => 'Belum ada yang bisa ditautkan.';
  @override
  String get nothingMatchesDot => 'Tidak ada yang cocok.';
  @override
  String get relevantHeading => 'RELEVAN';
  @override
  String get allHeading => 'SEMUA';
  @override
  String get doneLower => 'selesai';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => 'Issue lokal baru';
  @override
  String get titleHint => 'judul';
  @override
  String get bodyHint => 'isi (markdown)';
  @override
  String get cancelLower => 'batal';
  @override
  String get createLower => 'buat';
  @override
  String get deleteFailed => 'penghapusan gagal';
  @override
  String reviewFailed({required Object error}) => 'Review gagal: ${error}';
  @override
  String get resolutionFailed => 'resolusi gagal';
  @override
  String get patchBlocksNoCover =>
      'model mengembalikan blok patch yang tidak mencakup file yang gagal';
  @override
  String get applyFailed => 'penerapan gagal';
  @override
  String get emptyOrUnparseablePatch =>
      'model mengembalikan patch kosong atau tidak bisa di-parse';
  @override
  String noModelConfiguredFor({required Object label}) =>
      'tidak ada model dikonfigurasi untuk "${label}"';
  @override
  String get checksHeading => 'PEMERIKSAAN';
  @override
  String get peopleHeading => 'ORANG';
  @override
  String get conversationHeading => 'PERCAKAPAN';
}

// Path: changes
class _Translations$changes$id extends Translations$changes$en {
  _Translations$changes$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$id usage =
      _Translations$changes$usage$id._(_root);
  @override
  late final _Translations$changes$tabs$id tabs =
      _Translations$changes$tabs$id._(_root);
  @override
  late final _Translations$changes$tabStrip$id tabStrip =
      _Translations$changes$tabStrip$id._(_root);
  @override
  late final _Translations$changes$select$id select =
      _Translations$changes$select$id._(_root);
  @override
  late final _Translations$changes$constellationToggle$id constellationToggle =
      _Translations$changes$constellationToggle$id._(_root);
  @override
  late final _Translations$changes$nudgeChip$id nudgeChip =
      _Translations$changes$nudgeChip$id._(_root);
  @override
  late final _Translations$changes$minimap$id minimap =
      _Translations$changes$minimap$id._(_root);
  @override
  late final _Translations$changes$tagInput$id tagInput =
      _Translations$changes$tagInput$id._(_root);
  @override
  late final _Translations$changes$composer$id composer =
      _Translations$changes$composer$id._(_root);
  @override
  late final _Translations$changes$commit$id commit =
      _Translations$changes$commit$id._(_root);
  @override
  late final _Translations$changes$rebase$id rebase =
      _Translations$changes$rebase$id._(_root);
  @override
  late final _Translations$changes$editor$id editor =
      _Translations$changes$editor$id._(_root);
  @override
  late final _Translations$changes$editorTitles$id editorTitles =
      _Translations$changes$editorTitles$id._(_root);
  @override
  late final _Translations$changes$askHint$id askHint =
      _Translations$changes$askHint$id._(_root);
  @override
  late final _Translations$changes$fileMenu$id fileMenu =
      _Translations$changes$fileMenu$id._(_root);
  @override
  late final _Translations$changes$multiFileMenu$id multiFileMenu =
      _Translations$changes$multiFileMenu$id._(_root);
  @override
  late final _Translations$changes$ignoreMenu$id ignoreMenu =
      _Translations$changes$ignoreMenu$id._(_root);
  @override
  late final _Translations$changes$discard$id discard =
      _Translations$changes$discard$id._(_root);
  @override
  late final _Translations$changes$snack$id snack =
      _Translations$changes$snack$id._(_root);
  @override
  late final _Translations$changes$trace$id trace =
      _Translations$changes$trace$id._(_root);
  @override
  late final _Translations$changes$cleanTree$id cleanTree =
      _Translations$changes$cleanTree$id._(_root);
  @override
  late final _Translations$changes$guardrail$id guardrail =
      _Translations$changes$guardrail$id._(_root);
  @override
  late final _Translations$changes$dropHint$id dropHint =
      _Translations$changes$dropHint$id._(_root);
  @override
  late final _Translations$changes$diffEmpty$id diffEmpty =
      _Translations$changes$diffEmpty$id._(_root);
  @override
  late final _Translations$changes$shelvePill$id shelvePill =
      _Translations$changes$shelvePill$id._(_root);
  @override
  late final _Translations$changes$stashAction$id stashAction =
      _Translations$changes$stashAction$id._(_root);
  @override
  late final _Translations$changes$stashContents$id stashContents =
      _Translations$changes$stashContents$id._(_root);
  @override
  late final _Translations$changes$stashFile$id stashFile =
      _Translations$changes$stashFile$id._(_root);
  @override
  late final _Translations$changes$fileRow$id fileRow =
      _Translations$changes$fileRow$id._(_root);
  @override
  late final _Translations$changes$resolveStrip$id resolveStrip =
      _Translations$changes$resolveStrip$id._(_root);
  @override
  late final _Translations$changes$badge$id badge =
      _Translations$changes$badge$id._(_root);
  @override
  late final _Translations$changes$review$id review =
      _Translations$changes$review$id._(_root);
  @override
  late final _Translations$changes$commitBtn$id commitBtn =
      _Translations$changes$commitBtn$id._(_root);
  @override
  late final _Translations$changes$shapeBtn$id shapeBtn =
      _Translations$changes$shapeBtn$id._(_root);
  @override
  late final _Translations$changes$dejaVu$id dejaVu =
      _Translations$changes$dejaVu$id._(_root);
  @override
  late final _Translations$changes$identity$id identity =
      _Translations$changes$identity$id._(_root);
  @override
  late final _Translations$changes$staleScope$id staleScope =
      _Translations$changes$staleScope$id._(_root);
  @override
  late final _Translations$changes$finding$id finding =
      _Translations$changes$finding$id._(_root);
  @override
  late final _Translations$changes$muse$id muse =
      _Translations$changes$muse$id._(_root);
  @override
  late final _Translations$changes$debug$id debug =
      _Translations$changes$debug$id._(_root);
  @override
  late final _Translations$changes$includeSummary$id includeSummary =
      _Translations$changes$includeSummary$id._(_root);
  @override
  late final _Translations$changes$status$id status =
      _Translations$changes$status$id._(_root);
  @override
  late final _Translations$changes$stash$id stash =
      _Translations$changes$stash$id._(_root);
  @override
  late final _Translations$changes$tooltips$id tooltips =
      _Translations$changes$tooltips$id._(_root);
  @override
  late final _Translations$changes$mergeEditor$id mergeEditor =
      _Translations$changes$mergeEditor$id._(_root);
  @override
  late final _Translations$changes$conflictResolution$id conflictResolution =
      _Translations$changes$conflictResolution$id._(_root);
  @override
  late final _Translations$changes$mergeFlow$id mergeFlow =
      _Translations$changes$mergeFlow$id._(_root);
  @override
  late final _Translations$changes$constellation$id constellation =
      _Translations$changes$constellation$id._(_root);
}

// Path: common
class _Translations$common$id extends Translations$common$en {
  _Translations$common$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => ', ';
  @override
  String get cancel => 'Batal';
  @override
  String get close => 'Tutup';
  @override
  String get save => 'Simpan';
  @override
  String get delete => 'Hapus';
  @override
  String get retry => 'Coba lagi';
  @override
  String get copy => 'Salin';
  @override
  String get copied => 'Tersalin';
  @override
  String get done => 'Selesai';
  @override
  String get loading => 'Memuat…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} commit',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} branch',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} commit lokal',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} commit remote',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file konflik',
      );
  @override
  late final _Translations$common$time$id time = _Translations$common$time$id._(
    _root,
  );
  @override
  late final _Translations$common$size$id size = _Translations$common$size$id._(
    _root,
  );
}

// Path: diff
class _Translations$diff$id extends Translations$diff$en {
  _Translations$diff$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$id status =
      _Translations$diff$status$id._(_root);
  @override
  late final _Translations$diff$toolbar$id toolbar =
      _Translations$diff$toolbar$id._(_root);
  @override
  late final _Translations$diff$hunkDropdown$id hunkDropdown =
      _Translations$diff$hunkDropdown$id._(_root);
  @override
  String stagingFailed({required Object error}) =>
      'Stage sebagian gagal: ${error}';
  @override
  late final _Translations$diff$trail$id trail = _Translations$diff$trail$id._(
    _root,
  );
  @override
  late final _Translations$diff$pinned$id pinned =
      _Translations$diff$pinned$id._(_root);
  @override
  late final _Translations$diff$hunkHint$id hunkHint =
      _Translations$diff$hunkHint$id._(_root);
  @override
  late final _Translations$diff$binary$id binary =
      _Translations$diff$binary$id._(_root);
  @override
  late final _Translations$diff$media$id media = _Translations$diff$media$id._(
    _root,
  );
}

// Path: filament
class _Translations$filament$id extends Translations$filament$en {
  _Translations$filament$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => 'Tidak ada repository yang terbuka.';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      'memindai ${scanned} / ${total} file…';
  @override
  String findingsAcrossFiles({required Object count, required Object files}) =>
      '${count} temuan di ${files} file';
  @override
  String copiedFindings({required Object count}) => '${count} temuan tersalin';
  @override
  String get copy => 'SALIN';
  @override
  String get noFindings => 'Tidak ada temuan alur eksekusi.';
  @override
  late final _Translations$filament$severity$id severity =
      _Translations$filament$severity$id._(_root);
  @override
  late final _Translations$filament$kind$id kind =
      _Translations$filament$kind$id._(_root);
  @override
  String lineLabel({required Object line}) => 'B${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$id extends Translations$history$en {
  _Translations$history$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$id commitLede =
      _Translations$history$commitLede$id._(_root);
  @override
  late final _Translations$history$seismograph$id seismograph =
      _Translations$history$seismograph$id._(_root);
  @override
  late final _Translations$history$worldline$id worldline =
      _Translations$history$worldline$id._(_root);
  @override
  late final _Translations$history$contextMenu$id contextMenu =
      _Translations$history$contextMenu$id._(_root);
  @override
  late final _Translations$history$cherryPick$id cherryPick =
      _Translations$history$cherryPick$id._(_root);
  @override
  late final _Translations$history$revert$id revert =
      _Translations$history$revert$id._(_root);
  @override
  late final _Translations$history$reflog$id reflog =
      _Translations$history$reflog$id._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'Commit itu lebih dalam dari ${n} commit yang dimuat.',
      );
  @override
  String deleteTagFailed({required Object error}) =>
      'Gagal menghapus tag: ${error}';
  @override
  String get loadingTitle => 'Memuat history';
  @override
  String get loadingMessage => 'Membaca commit terbaru.';
  @override
  String get unavailableTitle => 'History tidak tersedia';
  @override
  String get toggleWorldline => 'Toggle worldline';
  @override
  String get pageTitle => 'History';
  @override
  String get viewingLast => 'Melihat terakhir';
  @override
  String get commitsUnit => 'commit';
  @override
  String get noCommitSelectedTitle => 'Tidak ada commit dipilih';
  @override
  String get noCommitSelectedMessage =>
      'Pilih sebuah commit untuk memeriksa perubahannya.';
  @override
  String get loadingCommitTitle => 'Memuat commit';
  @override
  String get loadingCommitMessage => 'Membaca detail commit.';
  @override
  String get commitUnavailableTitle => 'Commit tidak tersedia';
  @override
  String get couldNotLoadCommit => 'Tidak bisa memuat commit.';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => 'Muat reflog';
  @override
  String get createTag => 'Buat tag';
  @override
  String get newTagName => 'Nama tag baru';
  @override
  String newTagNameError({required Object error}) => 'Nama tag baru — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file · semua perubahan',
      );
  @override
  String get allChangesLabel => 'semua perubahan';
  @override
  late final _Translations$history$rebase$id rebase =
      _Translations$history$rebase$id._(_root);
  @override
  late final _Translations$history$inFlight$id inFlight =
      _Translations$history$inFlight$id._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$id extends Translations$historySurgery$en {
  _Translations$historySurgery$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$id chrome =
      _Translations$historySurgery$chrome$id._(_root);
  @override
  late final _Translations$historySurgery$select$id select =
      _Translations$historySurgery$select$id._(_root);
  @override
  late final _Translations$historySurgery$understand$id understand =
      _Translations$historySurgery$understand$id._(_root);
  @override
  late final _Translations$historySurgery$confirm$id confirm =
      _Translations$historySurgery$confirm$id._(_root);
  @override
  late final _Translations$historySurgery$execute$id execute =
      _Translations$historySurgery$execute$id._(_root);
  @override
  late final _Translations$historySurgery$verify$id verify =
      _Translations$historySurgery$verify$id._(_root);
  @override
  late final _Translations$historySurgery$forcePush$id forcePush =
      _Translations$historySurgery$forcePush$id._(_root);
}

// Path: onboarding
class _Translations$onboarding$id extends Translations$onboarding$en {
  _Translations$onboarding$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$id nav =
      _Translations$onboarding$nav$id._(_root);
  @override
  late final _Translations$onboarding$naming$id naming =
      _Translations$onboarding$naming$id._(_root);
  @override
  late final _Translations$onboarding$theme$id theme =
      _Translations$onboarding$theme$id._(_root);
  @override
  late final _Translations$onboarding$repo$id repo =
      _Translations$onboarding$repo$id._(_root);
  @override
  late final _Translations$onboarding$preview$id preview =
      _Translations$onboarding$preview$id._(_root);
}

// Path: orrery
class _Translations$orrery$id extends Translations$orrery$en {
  _Translations$orrery$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$id header =
      _Translations$orrery$header$id._(_root);
  @override
  late final _Translations$orrery$status$id status =
      _Translations$orrery$status$id._(_root);
  @override
  late final _Translations$orrery$legend$id legend =
      _Translations$orrery$legend$id._(_root);
  @override
  late final _Translations$orrery$node$id node = _Translations$orrery$node$id._(
    _root,
  );
  @override
  late final _Translations$orrery$milestone$id milestone =
      _Translations$orrery$milestone$id._(_root);
  @override
  late final _Translations$orrery$structure$id structure =
      _Translations$orrery$structure$id._(_root);
  @override
  late final _Translations$orrery$rail$id rail = _Translations$orrery$rail$id._(
    _root,
  );
  @override
  late final _Translations$orrery$selection$id selection =
      _Translations$orrery$selection$id._(_root);
  @override
  late final _Translations$orrery$findingKind$id findingKind =
      _Translations$orrery$findingKind$id._(_root);
  @override
  late final _Translations$orrery$findings$id findings =
      _Translations$orrery$findings$id._(_root);
  @override
  late final _Translations$orrery$anchor$id anchor =
      _Translations$orrery$anchor$id._(_root);
  @override
  late final _Translations$orrery$compare$id compare =
      _Translations$orrery$compare$id._(_root);
}

// Path: palette
class _Translations$palette$id extends Translations$palette$en {
  _Translations$palette$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get active => 'aktif';
  @override
  late final _Translations$palette$prefixes$id prefixes =
      _Translations$palette$prefixes$id._(_root);
  @override
  late final _Translations$palette$chips$id chips =
      _Translations$palette$chips$id._(_root);
  @override
  late final _Translations$palette$predictive$id predictive =
      _Translations$palette$predictive$id._(_root);
  @override
  late final _Translations$palette$topTouched$id topTouched =
      _Translations$palette$topTouched$id._(_root);
  @override
  late final _Translations$palette$coherence$id coherence =
      _Translations$palette$coherence$id._(_root);
  @override
  late final _Translations$palette$keystone$id keystone =
      _Translations$palette$keystone$id._(_root);
  @override
  late final _Translations$palette$repoSub$id repoSub =
      _Translations$palette$repoSub$id._(_root);
  @override
  late final _Translations$palette$desks$id desks =
      _Translations$palette$desks$id._(_root);
  @override
  late final _Translations$palette$actions$id actions =
      _Translations$palette$actions$id._(_root);
  @override
  late final _Translations$palette$tools$id tools =
      _Translations$palette$tools$id._(_root);
  @override
  late final _Translations$palette$gitCommands$id gitCommands =
      _Translations$palette$gitCommands$id._(_root);
  @override
  late final _Translations$palette$pr$id pr = _Translations$palette$pr$id._(
    _root,
  );
  @override
  late final _Translations$palette$ai$id ai = _Translations$palette$ai$id._(
    _root,
  );
  @override
  late final _Translations$palette$undo$id undo =
      _Translations$palette$undo$id._(_root);
  @override
  late final _Translations$palette$navigation$id navigation =
      _Translations$palette$navigation$id._(_root);
  @override
  late final _Translations$palette$settings$id settings =
      _Translations$palette$settings$id._(_root);
  @override
  late final _Translations$palette$info$id info =
      _Translations$palette$info$id._(_root);
  @override
  late final _Translations$palette$debug$id debug =
      _Translations$palette$debug$id._(_root);
  @override
  late final _Translations$palette$dev$id dev = _Translations$palette$dev$id._(
    _root,
  );
  @override
  late final _Translations$palette$historySurgery$id historySurgery =
      _Translations$palette$historySurgery$id._(_root);
  @override
  late final _Translations$palette$orrery$id orrery =
      _Translations$palette$orrery$id._(_root);
  @override
  late final _Translations$palette$command$id command =
      _Translations$palette$command$id._(_root);
  @override
  late final _Translations$palette$search$id search =
      _Translations$palette$search$id._(_root);
  @override
  late final _Translations$palette$wick$id wick =
      _Translations$palette$wick$id._(_root);
  @override
  late final _Translations$palette$gitCache$id gitCache =
      _Translations$palette$gitCache$id._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$id extends Translations$releaseNotes$en {
  _Translations$releaseNotes$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$id about =
      _Translations$releaseNotes$about$id._(_root);
  @override
  late final _Translations$releaseNotes$legal$id legal =
      _Translations$releaseNotes$legal$id._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$id extends Translations$repoSummary$en {
  _Translations$repoSummary$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$id backbone =
      _Translations$repoSummary$backbone$id._(_root);
  @override
  late final _Translations$repoSummary$glance$id glance =
      _Translations$repoSummary$glance$id._(_root);
  @override
  late final _Translations$repoSummary$heading$id heading =
      _Translations$repoSummary$heading$id._(_root);
  @override
  String get historyStarvedCaveat =>
      'Pemeringkatan terbatas: graf kopling tidak punya edge (clone baru atau terlalu sedikit commit). Urutan file mencerminkan ukuran, bukan sentralitas struktural.';
  @override
  late final _Translations$repoSummary$pitch$id pitch =
      _Translations$repoSummary$pitch$id._(_root);
  @override
  late final _Translations$repoSummary$region$id region =
      _Translations$repoSummary$region$id._(_root);
  @override
  late final _Translations$repoSummary$shape$id shape =
      _Translations$repoSummary$shape$id._(_root);
}

// Path: review
class _Translations$review$id extends Translations$review$en {
  _Translations$review$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get unresolved => 'belum selesai';
  @override
  String get done => 'selesai';
  @override
  String get ack => 'dicatat';
  @override
  String get reply => 'balas';
  @override
  String get pleaseFix => 'tolong perbaiki';
  @override
  String get draft => 'draf';
  @override
  String get engine => 'engine';
  @override
  String get moved => 'dipindah';
  @override
  String get yourTurn => 'giliranmu';
  @override
  String get drafts => 'draf';
  @override
  String get publish => 'publikasikan';
  @override
  String get discard => 'buang';
  @override
  String get saveDraft => 'simpan draf';
  @override
  String get cancel => 'batal';
  @override
  String get verdictApprove => 'setujui';
  @override
  String get verdictRequestChanges => 'minta perubahan';
  @override
  String get verdictComment => 'komentar';
  @override
  String get caughtUp => 'sudah terkini';
  @override
  String get sinceLastLook => 'sejak terakhir kamu lihat';
  @override
  String get fullDiff => 'diff lengkap';
  @override
  String get commentHint => 'tulis komentar';
  @override
  String outdatedLastSeen({required Object round}) =>
      'usang · terakhir dilihat R${round}';
  @override
  String resolvedByFmt({required Object verb, required Object who}) =>
      '${verb} · ${who}';
  @override
  String waitingOnFmt({required Object who}) => 'menunggu ${who}';
  @override
  String roundChip({required Object round}) => 'R${round}';
  @override
  String filesSinceLastLook({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        one: '1 file sejak terakhir kamu lihat',
        other: '${n} file sejak terakhir kamu lihat',
      );
  @override
  String unresolvedCountFmt({required Object n}) => '${n} belum selesai';
  @override
  String draftCountFmt({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        one: '1 draf',
        other: '${n} draf',
      );
  @override
  String startReviewFailed({required Object error}) =>
      'Tidak bisa memulai review: ${error}';
  @override
  String get anchorUnavailable =>
      'Baris itu tidak bisa ditambatkan — file terlalu besar atau tidak tersedia.';
  @override
  String reviewActionFailed({required Object error}) =>
      'Aksi review gagal: ${error}';
  @override
  String get lensTooLarge =>
      'Perbandingan itu terlalu besar untuk ditampilkan di sini — tetap di diff lengkap.';
  @override
  String get lensEmpty => 'Tidak ada yang berubah di antara snapshot ini.';
  @override
  String get reopen => 'buka lagi';
  @override
  String get notBlocking => 'jangan tunggu aku';
  @override
  String get markReviewed => 'sudah direview';
  @override
  String newComments({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        one: '1 komentar baru',
        other: '${n} komentar baru',
      );
  @override
  String get handTo => 'serahkan ke';
  @override
  String get heading => 'TINJAUAN';
  @override
  String get identityNeeded => 'Atur identitas git untuk meninjau';
  @override
  String get fileUnreadable =>
      'File itu tidak dapat dibaca di sini — terlalu besar atau tidak ada di ronde ini.';
  @override
  String get timeNow => 'baru saja';
  @override
  String timeMinutesFmt({required Object n}) => '${n} mnt';
  @override
  String timeHoursFmt({required Object n}) => '${n} jam';
  @override
  String timeDaysFmt({required Object n}) => '${n} hr';
  @override
  String get standingApproved => 'disetujui';
  @override
  String get standingChangesRequested => 'perubahan diminta';
  @override
  String get commentOnChange => 'Komentari perubahan ini';
  @override
  String get commentOnFile => 'Komentari berkas ini';
  @override
  String get imageNotLoaded => 'gambar tidak dimuat';
  @override
  String get nothingBlocking => 'tidak ada yang menghambat';
}

// Path: settings
class _Translations$settings$id extends Translations$settings$en {
  _Translations$settings$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$id language =
      _Translations$settings$language$id._(_root);
  @override
  late final _Translations$settings$sectionLabels$id sectionLabels =
      _Translations$settings$sectionLabels$id._(_root);
  @override
  late final _Translations$settings$errors$id errors =
      _Translations$settings$errors$id._(_root);
  @override
  late final _Translations$settings$promptStatus$id promptStatus =
      _Translations$settings$promptStatus$id._(_root);
  @override
  late final _Translations$settings$clearData$id clearData =
      _Translations$settings$clearData$id._(_root);
  @override
  List<String> get guardrailStageLabels => [
    'Longgar',
    'Seimbang',
    'Ketat',
    'Paranoid',
  ];
  @override
  late final _Translations$settings$guardrailMacro$id guardrailMacro =
      _Translations$settings$guardrailMacro$id._(_root);
  @override
  late final _Translations$settings$guardrails$id guardrails =
      _Translations$settings$guardrails$id._(_root);
  @override
  late final _Translations$settings$appearance$id appearance =
      _Translations$settings$appearance$id._(_root);
  @override
  late final _Translations$settings$retention$id retention =
      _Translations$settings$retention$id._(_root);
  @override
  late final _Translations$settings$navigation$id navigation =
      _Translations$settings$navigation$id._(_root);
  @override
  late final _Translations$settings$behaviour$id behaviour =
      _Translations$settings$behaviour$id._(_root);
  @override
  late final _Translations$settings$retentionClear$id retentionClear =
      _Translations$settings$retentionClear$id._(_root);
  @override
  late final _Translations$settings$channels$id channels =
      _Translations$settings$channels$id._(_root);
  @override
  late final _Translations$settings$pollResult$id pollResult =
      _Translations$settings$pollResult$id._(_root);
  @override
  late final _Translations$settings$keybindingProfile$id keybindingProfile =
      _Translations$settings$keybindingProfile$id._(_root);
  @override
  late final _Translations$settings$apiKeys$id apiKeys =
      _Translations$settings$apiKeys$id._(_root);
  @override
  late final _Translations$settings$shortcuts$id shortcuts =
      _Translations$settings$shortcuts$id._(_root);
  @override
  late final _Translations$settings$toggles$id toggles =
      _Translations$settings$toggles$id._(_root);
  @override
  late final _Translations$settings$diffDiffability$id diffDiffability =
      _Translations$settings$diffDiffability$id._(_root);
  @override
  late final _Translations$settings$modelSlots$id modelSlots =
      _Translations$settings$modelSlots$id._(_root);
  @override
  late final _Translations$settings$modelPicker$id modelPicker =
      _Translations$settings$modelPicker$id._(_root);
  @override
  late final _Translations$settings$aiFeatures$id aiFeatures =
      _Translations$settings$aiFeatures$id._(_root);
  @override
  late final _Translations$settings$commitEditor$id commitEditor =
      _Translations$settings$commitEditor$id._(_root);
  @override
  late final _Translations$settings$review$id review =
      _Translations$settings$review$id._(_root);
  @override
  late final _Translations$settings$museHint$id museHint =
      _Translations$settings$museHint$id._(_root);
  @override
  late final _Translations$settings$museEditor$id museEditor =
      _Translations$settings$museEditor$id._(_root);
  @override
  late final _Translations$settings$museStage$id museStage =
      _Translations$settings$museStage$id._(_root);
  @override
  late final _Translations$settings$lensAxis$id lensAxis =
      _Translations$settings$lensAxis$id._(_root);
  @override
  late final _Translations$settings$logosLens$id logosLens =
      _Translations$settings$logosLens$id._(_root);
  @override
  late final _Translations$settings$sortGuide$id sortGuide =
      _Translations$settings$sortGuide$id._(_root);
  @override
  late final _Translations$settings$piggyback$id piggyback =
      _Translations$settings$piggyback$id._(_root);
  @override
  late final _Translations$settings$diffStage$id diffStage =
      _Translations$settings$diffStage$id._(_root);
  @override
  late final _Translations$settings$undoScope$id undoScope =
      _Translations$settings$undoScope$id._(_root);
  @override
  late final _Translations$settings$undoWindow$id undoWindow =
      _Translations$settings$undoWindow$id._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$id guardrailPhrase =
      _Translations$settings$guardrailPhrase$id._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$id reviewGuideHint =
      _Translations$settings$reviewGuideHint$id._(_root);
  @override
  late final _Translations$settings$commitFormat$id commitFormat =
      _Translations$settings$commitFormat$id._(_root);
  @override
  late final _Translations$settings$commitPreview$id commitPreview =
      _Translations$settings$commitPreview$id._(_root);
  @override
  late final _Translations$settings$externalTools$id externalTools =
      _Translations$settings$externalTools$id._(_root);
  @override
  late final _Translations$settings$apiUsage$id apiUsage =
      _Translations$settings$apiUsage$id._(_root);
  @override
  late final _Translations$settings$gitea$id gitea =
      _Translations$settings$gitea$id._(_root);
  @override
  late final _Translations$settings$wick$id wick =
      _Translations$settings$wick$id._(_root);
  @override
  late final _Translations$settings$integrations$id integrations =
      _Translations$settings$integrations$id._(_root);
  @override
  late final _Translations$settings$reduceMotion$id reduceMotion =
      _Translations$settings$reduceMotion$id._(_root);
  @override
  late final _Translations$settings$resetQuit$id resetQuit =
      _Translations$settings$resetQuit$id._(_root);
  @override
  late final _Translations$settings$diagnostics$id diagnostics =
      _Translations$settings$diagnostics$id._(_root);
  @override
  late final _Translations$settings$telemetry$id telemetry =
      _Translations$settings$telemetry$id._(_root);
  @override
  late final _Translations$settings$flowEngine$id flowEngine =
      _Translations$settings$flowEngine$id._(_root);
  @override
  late final _Translations$settings$museStrands$id museStrands =
      _Translations$settings$museStrands$id._(_root);
  @override
  late final _Translations$settings$cliPiggyback$id cliPiggyback =
      _Translations$settings$cliPiggyback$id._(_root);
  @override
  late final _Translations$settings$header$id header =
      _Translations$settings$header$id._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$id diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$id._(_root);
  @override
  late final _Translations$settings$release$id release =
      _Translations$settings$release$id._(_root);
  @override
  late final _Translations$settings$providerStatus$id providerStatus =
      _Translations$settings$providerStatus$id._(_root);
  @override
  late final _Translations$settings$meridiem$id meridiem =
      _Translations$settings$meridiem$id._(_root);
  @override
  late final _Translations$settings$offenders$id offenders =
      _Translations$settings$offenders$id._(_root);
}

// Path: sync
class _Translations$sync$id extends Translations$sync$en {
  _Translations$sync$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$id actions =
      _Translations$sync$actions$id._(_root);
  @override
  late final _Translations$sync$panel$id panel = _Translations$sync$panel$id._(
    _root,
  );
  @override
  late final _Translations$sync$forcePush$id forcePush =
      _Translations$sync$forcePush$id._(_root);
}

// Path: xray
class _Translations$xray$id extends Translations$xray$en {
  _Translations$xray$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$id board = _Translations$xray$board$id._(
    _root,
  );
  @override
  late final _Translations$xray$cadence$id cadence =
      _Translations$xray$cadence$id._(_root);
  @override
  late final _Translations$xray$cards$id cards = _Translations$xray$cards$id._(
    _root,
  );
  @override
  late final _Translations$xray$cardTitle$id cardTitle =
      _Translations$xray$cardTitle$id._(_root);
  @override
  late final _Translations$xray$grain$id grain = _Translations$xray$grain$id._(
    _root,
  );
  @override
  late final _Translations$xray$header$id header =
      _Translations$xray$header$id._(_root);
  @override
  late final _Translations$xray$hotspot$id hotspot =
      _Translations$xray$hotspot$id._(_root);
  @override
  late final _Translations$xray$inspector$id inspector =
      _Translations$xray$inspector$id._(_root);
  @override
  late final _Translations$xray$loadingCard$id loadingCard =
      _Translations$xray$loadingCard$id._(_root);
  @override
  late final _Translations$xray$metabolism$id metabolism =
      _Translations$xray$metabolism$id._(_root);
  @override
  late final _Translations$xray$multi$id multi = _Translations$xray$multi$id._(
    _root,
  );
  @override
  late final _Translations$xray$recency$id recency =
      _Translations$xray$recency$id._(_root);
  @override
  late final _Translations$xray$rings$id rings = _Translations$xray$rings$id._(
    _root,
  );
  @override
  late final _Translations$xray$stats$id stats = _Translations$xray$stats$id._(
    _root,
  );
  @override
  late final _Translations$xray$stratumLabel$id stratumLabel =
      _Translations$xray$stratumLabel$id._(_root);
  @override
  late final _Translations$xray$summary$id summary =
      _Translations$xray$summary$id._(_root);
  @override
  late final _Translations$xray$tabs$id tabs = _Translations$xray$tabs$id._(
    _root,
  );
  @override
  late final _Translations$xray$trajectory$id trajectory =
      _Translations$xray$trajectory$id._(_root);
  @override
  late final _Translations$xray$verdict$id verdict =
      _Translations$xray$verdict$id._(_root);
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$id extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Keyboard';
  @override
  String get sectionNavigate => 'navigasi';
  @override
  String get sectionStaging => 'staging';
  @override
  String get sectionBranchesPrs => 'branch & PR';
  @override
  String get changes => 'Changes';
  @override
  String get history => 'History';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Pindah (selalu)';
  @override
  String get commandPalette => 'Command Palette';
  @override
  String get elevatedPalette => 'Elevated Palette';
  @override
  String get dismiss => 'Tutup';
  @override
  String get refresh => 'Refresh';
  @override
  String get nextPrevChange => 'Perubahan berikut / sebelum';
  @override
  String get toggleLine => 'Toggle baris';
  @override
  String get toggleHunk => 'Toggle hunk';
  @override
  String get toggleFile => 'Toggle file';
  @override
  String get pinContext => 'Pin konteks';
  @override
  String get commit => 'Commit';
  @override
  String get acceptAiHint => 'Terima saran AI';
  @override
  String get undo => 'Undo';
  @override
  String get navigate => 'Navigasi';
  @override
  String get expand => 'Perluas';
  @override
  String get checkoutPr => 'Checkout PR';
  @override
  String get approve => 'Setujui';
  @override
  String get requestChanges => 'Minta perubahan';
  @override
  String profileSwitchHint({required Object profile}) =>
      'Profil ${profile} · ganti di Pengaturan';
}

// Path: backend.ops
class _Translations$backend$ops$id extends Translations$backend$ops$en {
  _Translations$backend$ops$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'Merge';
  @override
  String get pull => 'Pull';
  @override
  String get apply => 'Terapkan';
  @override
  String get switchOp => 'Pindah';
  @override
  String get sync => 'Sync';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$id
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '${op} dibatalkan.';
  @override
  String complete({required Object op}) => '${op} selesai.';
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'Sisa ${n} konflik — selesaikan di halaman Changes.',
      );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} konflik terselesaikan.',
      );
  @override
  String uncommittedEdits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file punya perubahan yang belum di-commit — commit dulu.',
      );
}

// Path: changes.usage
class _Translations$changes$usage$id extends Translations$changes$usage$en {
  _Translations$changes$usage$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '${input} masuk · ${output} keluar';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} masuk · ${cached} cache · ${out} keluar';
  @override
  String get inWord => 'masuk';
  @override
  String get cachedWord => 'cache';
  @override
  String get outWord => 'keluar';
  @override
  String tipIn({required Object value}) => '${value}  masuk';
  @override
  String tipCacheRead({required Object value}) => '${value}  baca cache';
  @override
  String tipCacheWrite({required Object value}) => '${value}  tulis cache';
  @override
  String tipOut({required Object value}) => '${value}  keluar';
  @override
  String tipReasoning({required Object value}) => '${value}  penalaran';
  @override
  String tipWallClock({required Object value}) => '${value}s  waktu nyata';
}

// Path: changes.tabs
class _Translations$changes$tabs$id extends Translations$changes$tabs$en {
  _Translations$changes$tabs$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => 'Changes';
  @override
  String get empty => 'Kosong';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$id
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => 'Tab Diff Baru';
}

// Path: changes.select
class _Translations$changes$select$id extends Translations$changes$select$en {
  _Translations$changes$select$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => 'Pilih semua';
  @override
  String get deselectAll => 'Batalkan semua';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$id
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => 'kembali ke daftar';
  @override
  String get atlas => 'atlas, lihat kandidat commit';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$id
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\nterkopel dengan ${anchor} · ${pct}%${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$id extends Translations$changes$minimap$en {
  _Translations$changes$minimap$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => 'baru';
  @override
  String get roleBridge => 'jembatan';
  @override
  String get roleHub => 'hub';
  @override
  String get roleLeaf => 'daun';
  @override
  String get roleConnected => 'terhubung';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => 'berubah bersama ${name}';
  @override
  String get newFile => 'file baru';
  @override
  String nearOtherChanges({required Object count, required Object dir}) =>
      'dekat ${count} perubahan lain di ${dir}';
  @override
  String usuallyChangesWithFile({required Object name}) =>
      '${name} biasanya berubah bersama file ini';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$id
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'tag...';
}

// Path: changes.composer
class _Translations$changes$composer$id
    extends Translations$changes$composer$en {
  _Translations$changes$composer$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => 'pesan commit...';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$id extends Translations$changes$commit$en {
  _Translations$changes$commit$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => 'Commit perubahan';
  @override
  String get primaryCommitChangesDetail =>
      'Detached HEAD: commit lokal tanpa sync.';
  @override
  String get primaryPublish => 'Commit & publikasikan';
  @override
  String get primaryPublishDetail =>
      'Buat commit dan publikasikan branch ini dalam satu langkah.';
  @override
  String get primarySync => 'Commit & sync';
  @override
  String get primarySyncDetail =>
      'Buat commit, lalu rekonsiliasi dan kirim branch.';
  @override
  String get primaryPush => 'Commit & push';
  @override
  String get primaryPushDetail => 'Buat commit dan langsung push.';
  @override
  String get amendLast => 'Amend commit terakhir';
  @override
  String amendAnd({required Object action}) => 'Amend & ${action}';
  @override
  String get chooseFile =>
      'Pilih setidaknya satu file untuk commit berikutnya.';
  @override
  String get writeMessage => 'Tulis pesan commit dulu.';
  @override
  String get committing => 'Meng-commit';
  @override
  String get committingSync => 'Meng-commit dan sync';
  @override
  String get committed => 'Ter-commit.';
  @override
  String get undoFailed => 'Undo gagal.';
  @override
  String get working => 'Mengerjakan…';
  @override
  String get commitOnly => 'Commit saja';
  @override
  String get noRuntimeModels =>
      'Tidak ada model hasil-discovery runtime yang tersedia untuk pesan commit.';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\nTidak bisa memulihkan staging file yang dikecualikan; periksa index sebelum mencoba lagi.';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      'Ter-commit ${summary} (${hash}).';
  @override
  String get restoreFailedSync =>
      'Tidak bisa men-stage ulang pilihan file yang dikecualikan; sync dilewati. Periksa index sebelum sync.';
  @override
  String get noModelLabel => 'Tidak ada model';
  @override
  String get chooseBeforeGenerate =>
      'Pilih setidaknya satu file sebelum membuat.';
  @override
  String get aiUnavailable => 'AI pesan-commit belum tersedia.';
  @override
  String get generateFailed => 'Pembuatan gagal.';
  @override
  String get stageFailed => 'Gagal men-stage file.';
  @override
  String get commitFailed => 'Commit gagal.';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => 'Ter-commit ${summary} (${hash}) dan menjalankan ${operation}.';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
    n,
    other: 'Ter-commit ${summary} (${hash}); ${n} konflik terselesaikan.',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} konflik tersisa untuk diselesaikan.',
      );
  @override
  String syncBlocked({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
    n,
    other:
        'Commit berhasil, tapi sync terhalang oleh ${n} file yang belum di-commit.',
  );
  @override
  String syncStalled({required Object message}) =>
      'Commit berhasil, tapi sync mandek: ${message}';
  @override
  String syncFailed({required Object message}) =>
      'Commit berhasil, tapi sync gagal: ${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$id extends Translations$changes$rebase$en {
  _Translations$changes$rebase$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => 'Tidak bisa melanjutkan rebase.';
}

// Path: changes.editor
class _Translations$changes$editor$id extends Translations$changes$editor$en {
  _Translations$changes$editor$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => 'Tutup editor';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$id
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    'wahai git-log terkasih',
    'maaf-git-kan aku karena aku telah…',
    'beri nama momen ini',
    'cuap terus',
    'bicaralah!',
    'ibumu sebuah dangling reference dan ayahmu berbau titik koma',
  ];
  @override
  List<String> get short => [
    'oh?',
    'halo:)',
    'btw:',
    'beberapa kata',
    'versi sopannya',
    'tinggalkan catatan',
    'tadi mau bilang apa..?',
    'ayo, keluarkan',
  ];
  @override
  List<String> get mid => [
    'sebagai catatan',
    'bilang ke dirimu di masa depan',
    'tapi dulu?',
    'gimana jadinya',
    'dengan kata-katamu sendiri',
    'kamu ngapain tadi?',
    'dicatat',
    'kamu menarik perhatianku',
  ];
  @override
  List<String> get long => [
    'mimpi-mimpimu, dong',
    'bilang sesuatu yang manis',
    '... lalu aku bilang:',
    'anak cucu menanti',
    'menulis lebih banyak membuat bug-mu lenyap',
    'wah',
    'kitab suci',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$id extends Translations$changes$askHint$en {
  _Translations$changes$askHint$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) =>
      'ronde ${n} — perhalus atau tambah konteks.';
  @override
  String get symptom => 'jelaskan gejalanya.';
  @override
  String get broken => 'apa yang rusak?';
  @override
  String get bug => 'jelaskan bug-nya.';
  @override
  String get error => 'tempel error-nya.';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$id
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => 'Riak';
  @override
  String get includeCoChanges => 'Sertakan co-change';
  @override
  String deleteFile({required Object name}) => 'Hapus ${name}…';
  @override
  String discardChangesTo({required Object name}) =>
      'Buang perubahan pada ${name}…';
  @override
  String get ignore => 'Abaikan';
  @override
  String get diffTabFromSelection => 'Tab Diff dari pilihan';
  @override
  String addSelectedToTab({required Object name}) =>
      'Tambah pilihan ke ${name}';
  @override
  String diffTabFromFile({required Object name}) => 'Tab Diff dari ${name}';
  @override
  String addFileToTab({required Object file, required Object tab}) =>
      'Tambah ${file} ke ${tab}';
  @override
  String get copyFilePath => 'Salin path file';
  @override
  String get showInExplorer => 'Tampilkan di Explorer';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$id
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => 'terkopel erat';
  @override
  String get cohesionLoose => 'terkait longgar';
  @override
  String get cohesionScattered => 'tersebar secara struktural';
  @override
  String get clusterOne => 'semua dalam satu klaster';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      'merentang ${count} klaster (${parts} file)';
  @override
  String clusterSpans({required Object count}) => 'merentang ${count} klaster';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} file · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) =>
      '${file} biasanya berubah bersama grup ini';
  @override
  String get splitToNewTab => 'Pisah ke tab baru';
  @override
  String copyPaths({required Object count}) => 'Salin ${count} path';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$id
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => 'ekstensi .${ext}';
  @override
  String allSelected({required Object count}) => 'Semua ${count} terpilih';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'Terkopel dengan ${n} file yang disertakan',
      );
  @override
  String get updateFailed => 'Gagal memperbarui .gitignore.';
}

// Path: changes.discard
class _Translations$changes$discard$id extends Translations$changes$discard$en {
  _Translations$changes$discard$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => 'Hapus ${name}?';
  @override
  String discardTitle({required Object name}) =>
      'Buang perubahan pada ${name}?';
  @override
  String deleteBody({required Object path}) =>
      '${path} akan dihapus dari disk. Ini tidak bisa dibatalkan dari dalam aplikasi.';
  @override
  String discardBody({required Object path}) =>
      'Semua perubahan pada ${path} akan dikembalikan ke keadaannya di HEAD. Ini tidak bisa dibatalkan.';
  @override
  String get discard => 'Buang';
  @override
  String deletingFile({required Object name}) => 'Menghapus ${name}';
  @override
  String discardingFile({required Object name}) => 'Membuang ${name}';
  @override
  String get discardFailed => 'Gagal membuang perubahan.';
  @override
  String discardManyTitle({required Object count}) =>
      'Buang perubahan pada ${count} file?';
  @override
  String get discardManyBody =>
      'File yang di-track akan dikembalikan ke keadaannya di HEAD; file yang tak di-track akan dihapus dari disk. Ini tidak bisa dibatalkan.';
  @override
  String discardManyConfirm({required Object count}) => 'Buang ${count}';
  @override
  String discardingManyFiles({required Object count}) =>
      'Membuang ${count} file';
  @override
  String failedOpenExplorer({required Object error}) =>
      'Gagal membuka file explorer: ${error}';
  @override
  String get someFailed => 'Beberapa pembuangan gagal.';
}

// Path: changes.snack
class _Translations$changes$snack$id extends Translations$changes$snack$en {
  _Translations$changes$snack$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => 'Worktree sama — tidak ada yang dituang.';
  @override
  String diffFailed({required Object error}) => 'Diff gagal: ${error}';
  @override
  String get deskEmpty =>
      'Desk tidak punya apa pun di depanmu — tuangan kosong.';
  @override
  String sourceDesk({required Object label}) => 'desk ${label}';
  @override
  String shelfReadFailed({required Object error}) => 'Baca rak gagal: ${error}';
  @override
  String get shelfEmpty => 'Rak kosong — tidak ada yang dituang.';
  @override
  String sourceShelf({required Object label}) => 'rak ${label}';
  @override
  String noModelConfigured({required Object label}) =>
      'Tidak ada model dikonfigurasi untuk "${label}".';
  @override
  String fetchFailed({required Object error}) => 'Fetch gagal: ${error}';
}

// Path: changes.trace
class _Translations$changes$trace$id extends Translations$changes$trace$en {
  _Translations$changes$trace$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Jejak verifikasi';
  @override
  String get draftReview => 'Draf review';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$id
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Working tree bersih';
  @override
  String get subtitle => 'Tidak ada perubahan staged atau unstaged terdeteksi.';
  @override
  String get noUpstream => '  ·  tanpa upstream';
  @override
  String get ahead => ' di depan';
  @override
  String get behind => ' di belakang';
  @override
  String get refreshing => 'Menyegarkan...';
  @override
  String get refresh => 'Refresh';
  @override
  String get check => 'cek';
  @override
  String get checkTooltip => 'Fetch dan refresh lokal.';
  @override
  String get sync => '& sync';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$id
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'Longgar';
  @override
  String get balanced => 'Seimbang';
  @override
  String get strict => 'Ketat';
  @override
  String get paranoid => 'Paranoid';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$id
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf =>
      'jatuhkan untuk membawa perubahan dari rak ini ke sini';
  @override
  String get fromDesk =>
      'jatuhkan untuk membawa perubahan dari desk ini ke sini';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$id
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Tidak ada file dipilih';
  @override
  String get message =>
      'Pilih sebuah file yang berubah untuk memeriksa diff-nya.';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$id
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String shelveN({required Object count}) => '↓ rak ${count}';
  @override
  String get shelve => '↓ rak';
  @override
  String shelvedCount({required Object count, required Object glyph}) =>
      '${count} di-rak ${glyph}';
}

// Path: changes.stashAction
class _Translations$changes$stashAction$id
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => 'ambil';
  @override
  String get peek => 'intip';
  @override
  String get toss => 'buang';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$id
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get reading => 'membaca rak…';
  @override
  String get empty => 'rak kosong';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$id
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get binary => 'bin';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$id extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => 'commit baris yang di-stage saja';
  @override
  String get doubleClickToggle => 'klik ganda: toggle seluruh grup';
  @override
  String get repoRoot => 'Root repository';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$id
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'membaca ${n} file · menyusun resolusi…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} konflik di ${files}',
      );
  @override
  String get resolve => 'Selesaikan';
  @override
  String get orWith => 'ATAU DENGAN';
  @override
  String resolveWith({required Object label}) => 'selesaikan dengan ${label}';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      'selesaikan dengan ${label}  ·  ${model}';
  @override
  String get resolving => 'menyelesaikan…';
  @override
  String resolveWithGlyph({required Object label}) =>
      '↵  selesaikan dengan ${label}';
  @override
  String get orWithAnother => 'atau dengan model lain';
}

// Path: changes.badge
class _Translations$changes$badge$id extends Translations$changes$badge$en {
  _Translations$changes$badge$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => 'Edit di-stage';
  @override
  String get edited => 'Diedit';
  @override
  String get stagedAdd => 'Tambah di-stage';
  @override
  String get added => 'Ditambah';
  @override
  String get stagedDelete => 'Hapus di-stage';
  @override
  String get deleted => 'Dihapus';
  @override
  String get stagedRename => 'Ganti nama di-stage';
  @override
  String get renamed => 'Diganti nama';
  @override
  String get stagedCopy => 'Salin di-stage';
  @override
  String get copied => 'Disalin';
  @override
  String get conflict => 'Konflik';
  @override
  String get stagedTypeChange => 'Ganti tipe di-stage';
  @override
  String get typeChanged => 'Tipe berubah';
  @override
  String get untracked => 'Tak di-track';
}

// Path: changes.review
class _Translations$changes$review$id extends Translations$changes$review$en {
  _Translations$changes$review$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Code review';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file disertakan',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} hunk',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => 'Review tidak tersedia';
  @override
  String get backToDiff => 'Kembali ke diff';
  @override
  String get verified => 'Terverifikasi';
  @override
  String get draftOnly => 'Draf saja';
  @override
  String get runAgain => 'Jalankan lagi';
  @override
  String draftShownBelow({required Object error}) =>
      '${error} Draf review ditampilkan di bawah.';
  @override
  String get hideTrace => 'Sembunyikan jejak';
  @override
  String get showTrace => 'Tampilkan jejak';
  @override
  String get showVerificationTrace => 'Tampilkan jejak verifikasi';
  @override
  String get whyLanded => 'Kenapa review ini mendarat di sini';
  @override
  String get noFindings => 'Tidak ada temuan';
  @override
  String get findings => 'Temuan';
  @override
  String get noEvidenceIssues =>
      'Tidak ada masalah berbukti yang muncul untuk cakupan commit ini.';
  @override
  String get observations => 'Observasi';
  @override
  String get chooseBeforeReview => 'Pilih setidaknya satu file sebelum review.';
  @override
  String get aiUnavailable => 'Review AI belum tersedia.';
  @override
  String get failed => 'Review gagal.';
  @override
  String get noRuntimeModels =>
      'Tidak ada model hasil-discovery runtime yang tersedia untuk review commit.';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$id
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => 'Beralih ke: ${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$id
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => 'bertanya dengan ${cat}…';
  @override
  String askWith({required Object cat}) => 'tanya dengan ${cat}';
  @override
  String get noModel => 'tidak ada model AI dikonfigurasi';
  @override
  String nextTooltip({required Object cat}) =>
      'berikutnya: ${cat}  ·  shift-klik untuk sebelumnya';
  @override
  String get onlyOne => 'hanya satu kategori AI dikonfigurasi';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$id extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required num n,
    required Object pct,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
    n,
    other:
        '${pct}% déjà vu — ${n} edge hantu dari timeline yang dibuang menyentuh diff ini',
  );
  @override
  String get label => 'déjà vu';
}

// Path: changes.identity
class _Translations$changes$identity$id
    extends Translations$changes$identity$en {
  _Translations$changes$identity$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'tidak ada identitas commit dikonfigurasi';
  @override
  String asName({required Object name}) => 'sebagai ${name}';
  @override
  String asNameEmail({required Object name, required Object email}) =>
      'sebagai ${name} <${email}>';
  @override
  String asNameSpace({required Object name}) => 'sebagai ${name} ';
  @override
  String emailAngle({required Object email}) => '<${email}>';
  @override
  String get firstCommit => '\ncommit pertama di repo ini';
  @override
  String get newToRepo => '\nbaru di repo ini';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$id
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get message => 'pilihan berubah sejak ini dijalankan';
  @override
  String get rerun => 'jalankan ulang';
}

// Path: changes.finding
class _Translations$changes$finding$id extends Translations$changes$finding$en {
  _Translations$changes$finding$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => 'Buka diff';
  @override
  String get recorded => 'tercatat';
  @override
  String get dismiss => 'Tutup';
}

// Path: changes.muse
class _Translations$changes$muse$id extends Translations$changes$muse$en {
  _Translations$changes$muse$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => 'kamu menarik ini';
  @override
  String fromIdea({required Object text}) => 'dari ide: "${text}"';
  @override
  String get foothold => 'pijakan — ';
  @override
  String get brainstormSpew => 'semburan brainstorm';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => 'Salin ${count}';
  @override
  String get clear => 'Bersihkan';
  @override
  String get chooseBeforeMuse =>
      'Pilih setidaknya satu file sebelum memanggil muse.';
  @override
  String get aiUnavailable => 'Muse AI belum tersedia.';
  @override
  String get failed => 'Muse gagal.';
  @override
  String get noRuntimeModels =>
      'Tidak ada model hasil-discovery runtime yang tersedia untuk muse.';
  @override
  String get needsModel =>
      'Muse butuh setidaknya satu model yang dikonfigurasi.';
  @override
  String get dreaming => 'muse sedang bermimpi...';
}

// Path: changes.debug
class _Translations$changes$debug$id extends Translations$changes$debug$en {
  _Translations$changes$debug$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Debug';
  @override
  String round({required Object n}) => '· ronde ${n}';
  @override
  String get clear => 'bersihkan';
  @override
  String get close => 'tutup';
  @override
  String get analyzing => 'menganalisis gejala…';
  @override
  String get describeSymptom => 'jelaskan sebuah gejala, lalu tekan debug.';
  @override
  String get evidenceFor => 'untuk';
  @override
  String get evidenceAgainst => 'tapi';
  @override
  String get narrowDown => 'yang bisa membantu mempersempit:';
  @override
  String get failed => 'Debug gagal.';
  @override
  String get refinementFailed => 'Penghalusan debug gagal.';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$id
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'Tidak ada';
  @override
  String stagedSuffix({required Object count}) => ' · ${count} di-stage';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'Semua ${n} file${staged}',
      );
  @override
  String partial({
    required Object count,
    required Object n,
    required Object staged,
  }) => '${count} dari ${n}${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      'Semua ${n}${staged}';
}

// Path: changes.status
class _Translations$changes$status$id extends Translations$changes$status$en {
  _Translations$changes$status$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => 'Status repository tidak tersedia';
  @override
  String get loadingTitle => 'Memuat status repository';
  @override
  String get loadingMessage => 'Membaca working tree.';
}

// Path: changes.stash
class _Translations$changes$stash$id extends Translations$changes$stash$en {
  _Translations$changes$stash$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts =>
      'Stash diterapkan dengan konflik — selesaikan di halaman Changes (entri stash tetap disimpan).';
  @override
  String get couldNotPop => 'Tidak bisa mem-pop stash.';
  @override
  String get listChanged => 'Daftar stash berubah; drop dilewati. Coba lagi.';
  @override
  String get droppingStash => 'Mem-drop stash';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$id
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => 'membuat pesan commit...';
  @override
  String get commitPreparing => 'menyiapkan pesan-commit...';
  @override
  String get commitSelectFile =>
      'pilih setidaknya satu file untuk membuat pesan commit.';
  @override
  String get commitConfigure =>
      'atur pesan-commit di Pengaturan > Behavioural Dynamics > Commit Messages.';
  @override
  String get fastFallback => 'cepat';
  @override
  String commitGenerateWith({required Object label}) =>
      'buat pesan commit dengan model ${label}';
  @override
  String get museConsulting => 'berkonsultasi dengan muse...';
  @override
  String get showMuse => 'tampilkan muse';
  @override
  String get museSelectFile => 'pilih setidaknya satu file untuk muse.';
  @override
  String get showMuseError => 'tampilkan error muse';
  @override
  String get museAsk => 'minta arahan pada muse';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'minta arahan pada muse\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => 'kualitas';
  @override
  String get reviewing => 'me-review...';
  @override
  String get showReview => 'tampilkan review';
  @override
  String get reviewPreparing => 'menyiapkan review commit...';
  @override
  String get reviewSelectFile => 'pilih setidaknya satu file untuk di-review.';
  @override
  String get reviewConfigure => 'atur review AI di pengaturan.';
  @override
  String get viewingReview => 'melihat review';
  @override
  String reviewWith({required Object guardrail, required Object label}) =>
      'review ${guardrail} dengan model ${label}';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$id
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => 'milikmu';
  @override
  String get resolutionTheirs => 'milik mereka';
  @override
  String get resolutionCustom => 'kustom';
  @override
  String get keepBoth => 'simpan keduanya';
  @override
  late final _Translations$changes$mergeEditor$trust$id trust =
      _Translations$changes$mergeEditor$trust$id._(_root);
  @override
  String get allResolved => 'semua terselesaikan';
  @override
  String get resolveEasy => 'selesaikan konflik mudah';
  @override
  String get base => 'base';
  @override
  String get cancel => 'batal';
  @override
  String get save => 'simpan';
  @override
  String get complete => 'selesai';
  @override
  String get nextFile => 'file berikutnya';
  @override
  String get edit => 'edit';
  @override
  String get auto => 'otomatis';
  @override
  String get undo => 'undo';
  @override
  late final _Translations$changes$mergeEditor$keyHints$id keyHints =
      _Translations$changes$mergeEditor$keyHints$id._(_root);
  @override
  String get favoredTooltip =>
      'diunggulkan secara struktural oleh analisis kopling';
  @override
  String get newOnBothSides => '(baru di kedua sisi)';
  @override
  String writeFailed({required Object error}) =>
      'Gagal menulis file yang terselesaikan: ${error}';
  @override
  String neighborsCoChanged({required Object changed, required Object total}) =>
      '${changed}/${total} tetangga co-change';
  @override
  String integrity({required Object pct}) => 'integritas ${pct}%';
  @override
  String reviewer({required Object name}) => 'reviewer: ${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$id
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      'Tidak ada model dikonfigurasi untuk "${category}". Set satu di Pengaturan → AI.';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file sensitif dilewati — selesaikan manual.',
      );
  @override
  String get couldNotReadFiles => 'Tidak bisa membaca file konflik apa pun.';
  @override
  String blockedSecret({required Object secret}) =>
      'Terblokir — sebuah file konflik tampak berisi ${secret}. Selesaikan manual.';
  @override
  String resolutionFailed({required Object error}) =>
      'Resolusi gagal: ${error}';
  @override
  String mergeResolutionLabel({
    required Object resolved,
    required Object total,
    required Object category,
  }) => '◇ resolusi merge · ${resolved}/${total} file · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object conflicts,
    required Object files,
  }) => '${op} · ${conflicts} di ${files}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} konflik',
      );
  @override
  String get mergeEditorButton => '⇋ merge editor';
  @override
  String get noAiModel => 'tidak ada model AI';
  @override
  String get later => 'nanti';
  @override
  String get discard => 'buang';
  @override
  String get resolveWithAi => '◇ selesaikan dengan AI';
  @override
  String get otherModel => 'model lain';
  @override
  String withModel({required Object model}) => 'dengan ${model}';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$id
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$id op =
      _Translations$changes$mergeFlow$op$id._(_root);
  @override
  String get pushFailed => 'Push gagal';
  @override
  String get rebasedAndPushed => 'Di-rebase dan di-push.';
  @override
  String switchedTo({required Object name}) => 'Berpindah ke ${name}.';
  @override
  String get switchFailed => 'Perpindahan gagal.';
  @override
  String switchedToCarried({required Object name}) =>
      'Berpindah ke ${name} (perubahan terbawa).';
  @override
  String get alreadyUpToDate => 'Sudah paling baru.';
  @override
  String merged({required Object upstream, required Object n}) =>
      'Di-merge ${upstream} (${n} file).';
  @override
  String get rebaseNotConverge => 'Rebase tidak konvergen — selesaikan manual.';
  @override
  String get rebased => 'Di-rebase.';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'Di-rebase (${n} file terselesaikan).',
      );
  @override
  String get detachedHead =>
      'Tidak bisa sync: keadaan detached HEAD. Checkout sebuah branch dulu.';
  @override
  String get publishFailed => 'Publikasi gagal.';
  @override
  String get noRemote =>
      'Tidak ada remote dikonfigurasi. Tambahkan satu untuk mempublikasikan branch ini.';
  @override
  String get failed => 'gagal';
}

// Path: changes.constellation
class _Translations$changes$constellation$id
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => 'STRUKTUR';
  @override
  String get axisCoChange => 'CO-CHANGE';
  @override
  String get axisSpectralProfile => 'PROFIL SPEKTRAL';
  @override
  String get axisPathSiblings => 'SAUDARA PATH';
  @override
  String get axisDiffStructure => 'STRUKTUR DIFF';
  @override
  String get axisSpectral => 'SPEKTRAL';
  @override
  String get titleUnsorted => 'TAK TERURUT';
  @override
  String get titleSingleton => 'TUNGGAL';
  @override
  String get titleMixed => 'CAMPURAN';
  @override
  String get untie => 'lepas';
  @override
  String get bind => 'ikat';
  @override
  String get emptyClusters => 'belum ada klaster';
}

// Path: common.time
class _Translations$common$time$id extends Translations$common$time$en {
  _Translations$common$time$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get now => 'sekarang';
  @override
  String get justNow => 'baru saja';
  @override
  String get today => 'HARI INI';
  @override
  String minutesAgo({required Object n}) => '${n}mnt lalu';
  @override
  String hoursAgo({required Object n}) => '${n}j lalu';
  @override
  String daysAgo({required Object n}) => '${n}h lalu';
  @override
  String weeksAgo({required Object n}) => '${n}mg lalu';
  @override
  String monthsAgo({required Object n}) => '${n}bl lalu';
  @override
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        one: '${n}th lalu',
        other: '${n}th lalu',
      );
  @override
  String minutesShort({required Object n}) => '${n}mnt';
  @override
  String hoursShort({required Object n}) => '${n}j';
  @override
  String daysShort({required Object n}) => '${n}h';
  @override
  String weeksShort({required Object n}) => '${n}mg';
  @override
  String monthsShort({required Object n}) => '${n}bl';
  @override
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        one: '${n}th',
        other: '${n}th',
      );
  @override
  String commitMonthsShort({required Object n}) => '${n}bl';
  @override
  String get idle => 'diam';
  @override
  String idleDays({required Object n}) => 'diam ${n} hari';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'diam ${n} tahun',
      );
  @override
  List<String> get monthAbbrevs => [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];
}

// Path: common.size
class _Translations$common$size$id extends Translations$common$size$en {
  _Translations$common$size$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String bytes({required Object n}) => '${n} B';
  @override
  String kb({required Object n}) => '${n} KB';
  @override
  String mb({required Object n}) => '${n} MB';
  @override
  String gb({required Object n}) => '${n} GB';
}

// Path: diff.status
class _Translations$diff$status$id extends Translations$diff$status$en {
  _Translations$diff$status$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Memuat diff';
  @override
  String get loadingMessage => 'Membaca perubahan file.';
  @override
  String get unavailableTitle => 'Diff tidak tersedia';
  @override
  String get noChangesTitle => 'Tidak ada perubahan';
  @override
  String get noChangesMessage =>
      'File ini tidak punya konten diff untuk ditampilkan.';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$id extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => 'cari di diff...';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} baris',
      );
  @override
  String get blameLoading => 'blame...';
  @override
  String get blame => 'blame';
  @override
  String get wearMapOn => 'keausan · on';
  @override
  String get wearMapOnHint => 'peta keausan aktif — klik untuk menyembunyikan';
  @override
  String get wearMapOffHint => 'tampilkan peta keausan (heatmap aktivitas)';
  @override
  String get trailBadge => '· jejak';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$id
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => 'Lompat ke blok perubahan. Git menyebutnya hunk.';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} perubahan',
      );
}

// Path: diff.trail
class _Translations$diff$trail$id extends Translations$diff$trail$en {
  _Translations$diff$trail$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'memuat jejak...';
  @override
  String get noHistory => 'tidak ada history ditemukan';
  @override
  String get nowWorkingCopy => 'sekarang · working copy';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$id extends Translations$diff$pinned$en {
  _Translations$diff$pinned$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => 'memuat konteks yang dipin';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => 'Sinyal';
  @override
  String get echoesTitle => 'Gema';
  @override
  String get technicalLedger => 'Buku Besar Teknis';
  @override
  String get noSecondaryCues => 'Tidak ada petunjuk sekunder terdeteksi.';
  @override
  String get linkedPaths => 'Path Tertaut';
  @override
  String moreCount({required Object n}) => '+${n} lagi';
  @override
  String get localSeam => 'Sambungan lokal';
  @override
  String get sharedOwnership => 'kepemilikan bersama';
  @override
  String get historyWarmingUp => 'History sedang memanas';
  @override
  String echoesTotal({required Object n}) => '${n} TOTAL';
  @override
  String get noEchoes => 'Tidak ada gema di diff ini.';
  @override
  String openRelatedFile({required Object name}) => 'Buka file terkait ${name}';
  @override
  String inspectFile({required Object name}) => 'periksa ${name}';
  @override
  String get jumpEcho => 'lompat ke gema';
  @override
  String get copyLine => 'salin baris';
  @override
  String get signalTempo => 'T';
  @override
  String get signalNovelty => 'N';
  @override
  String get signalReach => 'R';
  @override
  late final _Translations$diff$pinned$tempo$id tempo =
      _Translations$diff$pinned$tempo$id._(_root);
  @override
  late final _Translations$diff$pinned$tone$id tone =
      _Translations$diff$pinned$tone$id._(_root);
  @override
  late final _Translations$diff$pinned$summary$id summary =
      _Translations$diff$pinned$summary$id._(_root);
  @override
  late final _Translations$diff$pinned$tightness$id tightness =
      _Translations$diff$pinned$tightness$id._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept} (${tightness})';
  @override
  String get storyWhyThisMatters => 'Kenapa ini penting';
  @override
  String get storyConfidence => 'Keyakinan';
  @override
  String get storySecondarySignal => 'Sinyal sekunder';
  @override
  String get storyNeighbourhood => 'Lingkungan';
  @override
  String neighbourhoodDetail({required Object name}) =>
      'Baris ini berada dekat dengan ${name} di medan codebase saat ini.';
  @override
  String get propagationLane => 'Jalur perambatan';
  @override
  String propagationLaneNamed({required Object lane}) =>
      'Jalur perambatan: ${lane}';
  @override
  late final _Translations$diff$pinned$witness$id witness =
      _Translations$diff$pinned$witness$id._(_root);
  @override
  late final _Translations$diff$pinned$integrity$id integrity =
      _Translations$diff$pinned$integrity$id._(_root);
  @override
  late final _Translations$diff$pinned$related$id related =
      _Translations$diff$pinned$related$id._(_root);
  @override
  late final _Translations$diff$pinned$axis$id axis =
      _Translations$diff$pinned$axis$id._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$id extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n} tersembunyi';
  @override
  String get landing => 'mendarat';
}

// Path: diff.binary
class _Translations$diff$binary$id extends Translations$diff$binary$en {
  _Translations$diff$binary$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) =>
      '${size} MB (terlalu besar untuk pratinjau)';
  @override
  String get unableToLoadBlob => 'Tidak bisa memuat blob';
  @override
  String get omittedKindMedia => 'media';
  @override
  String get omittedKindBinary => 'biner';
  @override
  String omittedStub({required Object kind}) => '${kind} · tersembunyi';
}

// Path: diff.media
class _Translations$diff$media$id extends Translations$diff$media$en {
  _Translations$diff$media$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => 'Tidak bisa mendekode gambar';
  @override
  String sizeLabel({required Object format, required Object size}) =>
      '${format}  ${size}';
  @override
  String sizeDelta({
    required Object oldSize,
    required Object newSize,
    required Object sign,
    required Object delta,
  }) => '${oldSize} → ${newSize}  (${sign}${delta})';
  @override
  String get stateAdded => 'ditambahkan';
  @override
  String get stateDeleted => 'dihapus';
  @override
  String get stateModified => 'diubah';
  @override
  String get fallbackFormatName => 'Biner';
}

// Path: filament.severity
class _Translations$filament$severity$id
    extends Translations$filament$severity$en {
  _Translations$filament$severity$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get critical => 'kritis';
  @override
  String get warn => 'peringatan';
  @override
  String get info => 'info';
  @override
  String get joint => 'sendi';
}

// Path: filament.kind
class _Translations$filament$kind$id extends Translations$filament$kind$en {
  _Translations$filament$kind$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => 'nilai usang';
  @override
  String get temporalShift => 'pergeseran temporal';
  @override
  String get contextInversion => 'inversi konteks';
  @override
  String get contradictoryFlow => 'alur bertentangan';
}

// Path: history.commitLede
class _Translations$history$commitLede$id
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$id semantics =
      _Translations$history$commitLede$semantics$id._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$id
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '(root)';
  @override
  String dirTrackLabel({required Object name}) => '(${name})';
  @override
  String moreLabel({required Object n}) => '+${n} lagi';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file di ${path}/',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file lagi',
      );
  @override
  String get breadcrumbAll => 'semua';
  @override
  String breadcrumbCurrentFocus({required Object target}) =>
      'Fokus saat ini: ${target}';
  @override
  String get breadcrumbViewAllChanges => 'Lihat semua perubahan di commit ini';
  @override
  String breadcrumbDrillUpTo({required Object target}) => 'Naik ke ${target}';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
    n,
    other: '${n} file  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} subdir',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}, ${adds} ditambah, ${dels} dihapus';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
    n,
    other: '${n} file, ${adds} ditambah, ${dels} dihapus',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} hunk',
      );
  @override
  String get largestChangeInView => 'perubahan terbesar di tampilan ini';
  @override
  String get conflictedTag => 'konflik';
  @override
  String get dirtyTag => 'kotor';
  @override
  String get drillInTag => 'selami';
  @override
  String get changeTypeRenamed => 'diganti nama';
  @override
  String get changeTypeCopied => 'disalin';
  @override
  String get changeTypeTypechange => 'ganti tipe';
  @override
  String get changeTypeConflict => 'konflik';
  @override
  String get coreFile => 'file inti';
  @override
  String get staleFile => 'usang';
  @override
  String get filterPathHint => 'filter path';
  @override
  String get escHint => 'esc';
}

// Path: history.worldline
class _Translations$history$worldline$id
    extends Translations$history$worldline$en {
  _Translations$history$worldline$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => 'Tutup worldline';
  @override
  String get dragToOpenWorldline => 'Seret untuk membuka worldline';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$id
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => 'branch saat ini';
  @override
  String applyCommitOnto({required Object branch}) =>
      'Terapkan perubahan commit ke ${branch}';
  @override
  String revertCommitOn({required Object branch}) =>
      'Revert perubahan commit di ${branch}';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$id
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Cherry-pick dijeda. Selesaikan sisa konflik di halaman Changes.';
  @override
  String failed({required Object error}) => 'Cherry-pick gagal: ${error}';
  @override
  String pickedResolved({required Object short}) =>
      'Cherry-pick ${short} (konflik terselesaikan)';
  @override
  String picked({required Object short}) => 'Cherry-pick ${short}';
}

// Path: history.revert
class _Translations$history$revert$id extends Translations$history$revert$en {
  _Translations$history$revert$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Revert dijeda. Selesaikan sisa konflik di halaman Changes.';
  @override
  String failed({required Object error}) => 'Revert gagal: ${error}';
  @override
  String revertedResolved({required Object short}) =>
      'Revert ${short} (konflik terselesaikan)';
  @override
  String reverted({required Object short}) => 'Revert ${short}';
}

// Path: history.reflog
class _Translations$history$reflog$id extends Translations$history$reflog$en {
  _Translations$history$reflog$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => 'Buat branch dari sini…';
  @override
  String get copyCommitHash => 'Salin hash commit';
  @override
  String get createBranchDialogTitle => 'Buat branch dari entri reflog';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      'Jangkar: ${short}  ·  ${summary}';
  @override
  String get branchNameHint => 'nama branch';
  @override
  String get createAction => 'Buat';
  @override
  String createBranchFailed({required Object error}) =>
      'Gagal membuat branch: ${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      'Branch "${name}" dibuat di ${short}.';
}

// Path: history.rebase
class _Translations$history$rebase$id extends Translations$history$rebase$en {
  _Translations$history$rebase$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) =>
      'Commit pertama tidak bisa ${action}';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'Rebase ${n} commit',
      );
  @override
  String get resetLabel => 'reset';
  @override
  String get dragToReorderHint =>
      'seret untuk menata ulang, pilih aksi tiap commit';
  @override
  String get newMessageHint => 'pesan baru';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => 'Mulai Rebase';
}

// Path: history.inFlight
class _Translations$history$inFlight$id
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'SEDANG JALAN';
  @override
  String get deskFallbackLabel => 'desk';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$id
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Bedah History';
  @override
  String get alphaBadge => 'alpha';
  @override
  String get dryRunBadge => 'DRY RUN';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$id
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get prompt => 'Pilih file untuk dihapus dari history';
  @override
  String selectedCount({required Object n}) => '${n} dipilih';
  @override
  String get searchHint => 'cari...';
  @override
  String get readingTree => 'membaca tree...';
  @override
  String get continueDisabled => 'pilih file untuk lanjut';
  @override
  String get continueEnabled => 'lanjut →';
  @override
  String toPurgeCount({required Object n}) => '${n} untuk dibersihkan';
  @override
  String get analyzing => 'menganalisis...';
  @override
  String get riskLow => 'risiko rendah';
  @override
  String get riskModerate => 'risiko sedang';
  @override
  String get riskHigh => 'risiko tinggi';
  @override
  String get impactCommitsLabel => 'commit';
  @override
  String get impactBranchesLabel => 'branch';
  @override
  String get impactWorktreesLabel => 'worktree';
  @override
  String get impactCouplingLabel => 'kopling';
  @override
  String get impactCouplingIsland => 'pulau';
  @override
  String impactCouplingNeighbors({required Object n}) => '${n} tetangga';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$id
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get heading => 'Cara kerjanya';
  @override
  String get backupTitle => 'Backup';
  @override
  String get backupBody =>
      'Setiap ref branch dan tag disalin ke namespace backup sebelum apa pun berubah. Jika ada yang salah, satu klik memulihkan keadaan semula.';
  @override
  String get rewriteTitle => 'Tulis ulang';
  @override
  String get rewriteBody =>
      'Setiap commit ditelusuri dari root ke tip. Untuk tiap commit yang memuat file target, commit baru dibuat dengan file-file itu dihapus dari tree. Rantai parent dipetakan ulang untuk menjaga topologi. ';
  @override
  String rewriteSummary({required Object affected, required Object total}) =>
      '${affected} dari ${total} commit akan ditulis ulang.';
  @override
  String get updateRefsTitle => 'Perbarui ref';
  @override
  String get updateRefsBody =>
      'Pointer branch dan tag dipindah ke SHA commit baru. Objek lama masih ada sampai garbage collection. ';
  @override
  String worktreesNeedRecheckout({required Object n}) =>
      '${n} worktree-mu perlu di-checkout ulang.';
  @override
  String get noWorktreesAffected => 'Tidak ada worktree yang terpengaruh.';
  @override
  String get forcePushTitle => 'Force-push';
  @override
  String get forcePushBody =>
      'Setelah memverifikasi pembersihan, kamu memilih branch mana yang di-force-push. Memakai --force-with-lease sehingga gagal dengan aman jika ada orang lain yang push di antaranya.';
  @override
  String get plumbingNote =>
      'Berbeda dari filter-repo atau BFG, ini berjalan sepenuhnya lewat perintah plumbing git (cat-file, mktree, commit-tree, update-ref). Tanpa dependensi eksternal. Pelacakan rename mengikuti satu rantai per file — jika sebuah file disalin dan kedua salinan diganti nama secara terpisah, verifikasi hasil pembersihan setelah eksekusi.';
  @override
  String get back => '← Kembali';
  @override
  String get continueLabel => 'Aku paham, lanjut →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$id
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) =>
      '${n} commit akan ditulis ulang';
  @override
  String get forcePushRequired =>
      'Force-push akan diperlukan untuk branch remote';
  @override
  String worktreesRecheckout({required Object n}) =>
      '${n} worktree perlu di-checkout ulang';
  @override
  String stashesInvalid({required Object n}) =>
      '${n} stash mungkin jadi tidak valid';
  @override
  String get heading => 'Operasi ini menulis ulang history git';
  @override
  String get subheading => 'Tidak bisa dibatalkan otomatis setelah force-push.';
  @override
  String typeHint({required Object word}) => 'ketik ${word}';
  @override
  String get goBack => 'Kembali';
  @override
  String get begin => 'Mulai Bedah';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$id
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => 'Menyiapkan...';
  @override
  String get backingUpRefs => 'Mem-backup ref...';
  @override
  String get rewritingCommits => 'Menulis ulang commit...';
  @override
  String get updatingRefs => 'Memperbarui ref...';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$id
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get complete => 'Bedah Selesai';
  @override
  String get failed => 'Bedah Gagal';
  @override
  String get commitsRewrittenLabel => 'Commit ditulis ulang';
  @override
  String get refsUpdatedLabel => 'Ref diperbarui';
  @override
  String get oldHeadLabel => 'HEAD lama';
  @override
  String get newHeadLabel => 'HEAD baru';
  @override
  String get purgeVerifiedLabel => 'Pembersihan terverifikasi';
  @override
  String get purgeClean => 'bersih';
  @override
  String get purgeTracesRemain => 'JEJAK TERSISA';
  @override
  String get displacedWorktrees => 'Worktree Tergeser';
  @override
  String get undoSurgery => 'Batalkan Bedah';
  @override
  String get rolledBack => 'Dikembalikan ke ref backup.';
  @override
  String get done => 'Selesai';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$id
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => 'mem-push...';
  @override
  String get forcePushAll => 'Force Push Semua';
  @override
  String get confirmPush => 'konfirmasi push';
  @override
  String get cancel => 'batal';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$id extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get back => 'Kembali';
  @override
  String get continueLabel => 'Lanjut';
  @override
  String get letsGo => 'Ayo mulai';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$id
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'ini apa buat kamu?';
  @override
  String get questionEmphasis => 'ini';
  @override
  String get iAmPrefix => 'Aku ';
  @override
  String get iAmSuffix => ' , Git Client pribadimu.';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$id
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'dandani ${name}.';
  @override
  String get themesHeader => 'TEMA';
  @override
  String get keybindingsHeader => 'KEYBINDING';
  @override
  String get previewBadge => 'pratinjau';
  @override
  String get useDefaults => 'pakai bawaan';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$id extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => 'arahkan ${name} ke sesuatu.';
  @override
  String get later => 'nanti aja';
  @override
  late final _Translations$onboarding$repo$doors$id doors =
      _Translations$onboarding$repo$doors$id._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$id cloneForm =
      _Translations$onboarding$repo$cloneForm$id._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$id pickers =
      _Translations$onboarding$repo$pickers$id._(_root);
  @override
  late final _Translations$onboarding$repo$errors$id errors =
      _Translations$onboarding$repo$errors$id._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$id
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$id panels =
      _Translations$onboarding$preview$panels$id._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$id sidebar =
      _Translations$onboarding$preview$sidebar$id._(_root);
  @override
  late final _Translations$onboarding$preview$changes$id changes =
      _Translations$onboarding$preview$changes$id._(_root);
  @override
  late final _Translations$onboarding$preview$history$id history =
      _Translations$onboarding$preview$history$id._(_root);
  @override
  late final _Translations$onboarding$preview$branches$id branches =
      _Translations$onboarding$preview$branches$id._(_root);
  @override
  late final _Translations$onboarding$preview$diff$id diff =
      _Translations$onboarding$preview$diff$id._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$id extends Translations$orrery$header$en {
  _Translations$orrery$header$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => 'Scrub';
  @override
  String get modeCompare => 'Banding';
  @override
  String get lodModules => 'Modul';
  @override
  String get lodFiles => 'File';
}

// Path: orrery.status
class _Translations$orrery$status$id extends Translations$orrery$status$en {
  _Translations$orrery$status$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'Melacak manifold melintasi history…';
  @override
  String get loadError => 'Tidak bisa membaca history repo ini.';
  @override
  String get notEnoughHistory =>
      'Belum cukup history untuk memplot trajektori.';
  @override
  String get notEnoughHistoryDetail =>
      'Orrery butuh beberapa commit untuk dipetakan.';
}

// Path: orrery.legend
class _Translations$orrery$legend$id extends Translations$orrery$legend$en {
  _Translations$orrery$legend$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get central => 'sentral';
  @override
  String get peripheral => 'periferal';
}

// Path: orrery.node
class _Translations$orrery$node$id extends Translations$orrery$node$en {
  _Translations$orrery$node$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get module => 'modul';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} file';
  @override
  String fileFallback({required Object id}) => 'file #${id}';
  @override
  String nodeFallback({required Object id}) => 'node #${id}';
  @override
  String get rootModule => '(root)';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$id
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => 'genesis';
  @override
  String get now => 'sekarang';
  @override
  String get reorganized => 'direorganisasi';
  @override
  String becameArchetype({required Object archetype}) => 'menjadi ${archetype}';
  @override
  String get snapshot => 'snapshot';
}

// Path: orrery.structure
class _Translations$orrery$structure$id
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get forming => 'membentuk…';
  @override
  String get canonical => 'kanonik';
  @override
  String get connectivity => 'konektivitas';
  @override
  String get rigidity => 'kekakuan';
  @override
  String get entropy => 'entropi';
}

// Path: orrery.rail
class _Translations$orrery$rail$id extends Translations$orrery$rail$en {
  _Translations$orrery$rail$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => 'STRUKTUR';
  @override
  String get fieldLabel => 'MEDAN';
  @override
  String get findingsLabel => 'TEMUAN';
  @override
  String get selectedLabel => 'TERPILIH';
  @override
  String get noFindings =>
      'Tidak ada peristiwa struktural terdeteksi di history ini.';
}

// Path: orrery.selection
class _Translations$orrery$selection$id
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => 'Tidak hadir pada titik history ini.';
  @override
  String get roleCentral =>
      'Sentral-kopling — perubahan di sini beriak ke seluruh sistem.';
  @override
  String get rolePeripheral =>
      'Periferal — terkopel longgar, kebanyakan berubah sendiri.';
  @override
  String get roleMid => 'Struktur-tengah — terkopel sedang.';
  @override
  String get driftOutward => ' Menghanyut keluar — melepas kopling.';
  @override
  String get driftInward => ' Menghanyut ke dalam — mengintegrasi.';
  @override
  String get driftHolding => ' Mempertahankan posisinya.';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$id
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get hub => 'HUB';
  @override
  String get driftOut => 'MENGHANYUT KELUAR';
  @override
  String get driftIn => 'MENGHANYUT MASUK';
  @override
  String get tangle => 'MERUWET';
  @override
  String get clarify => 'MENJERNIH';
  @override
  String get regime => 'REORG';
  @override
  String get thrash => 'MERACAU';
  @override
  String get reshuffle => 'MENGOCOK ULANG';
  @override
  String get forecast => 'PRAKIRAAN';
}

// Path: orrery.findings
class _Translations$orrery$findings$id extends Translations$orrery$findings$en {
  _Translations$orrery$findings$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      'Konektivitas terus menurun dan mendekati titik terendahnya — jika ini bertahan, codebase menuju perpecahan jadi dua bagian yang terkopel longgar. Putuskan sekarang apakah itu memang niatnya.';
  @override
  String get forecastConsolidate =>
      'Konektivitas terus naik menuju puncaknya — jika ini bertahan, codebase mengonsolidasi jadi satu massa yang terkopel erat. Waspadai ia mengeras jadi monolit.';
  @override
  String thrash({required Object name}) =>
      '${name} terus direorganisasi bolak-balik — banyak gejolak struktural, sedikit pergerakan bersih. Selesaikan koplingnya atau berhenti menyentuhnya.';
  @override
  String get reshuffle =>
      'Commit ini tampak rutin tapi diam-diam menggeser file mana yang sentral — bentuk keseluruhan bertahan sementara struktur mengocok ulang di bawahnya. Tinjau dengan cermat.';
  @override
  String hub({required Object name}) =>
      '${name} berada di inti struktural — sistem bereorganisasi di sekitarnya. Perlakukan perubahan di sini sebagai berdaya ledak tinggi.';
  @override
  String driftOut({required Object name}) =>
      '${name} telah menghanyut dari inti ke tepi — ia melepas kopling dari sistem. Entah sedang dipensiunkan, atau diam-diam membusuk.';
  @override
  String driftIn({required Object name}) =>
      '${name} telah bermigrasi ke inti — ia jadi penopang beban. Pastikan ia teruji baik sebelum lebih banyak yang bergantung padanya.';
  @override
  String get regime =>
      'Codebase bereorganisasi tajam di sini — konektivitasnya melonjak. Tinjau apa yang memisah atau menyatu.';
  @override
  String get tangleTrend =>
      'Sepanjang history-nya codebase cenderung menuju struktur yang lebih ruwet — konektivitasnya makin padat dan kurang modular.';
  @override
  String get clarifyTrend =>
      'Sepanjang history-nya codebase cenderung menuju struktur yang lebih bersih — ia memisah jadi modul-modul yang lebih jelas.';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$id extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get core => 'inti';
  @override
  String get drift => 'hanyut';
  @override
  String get trend => 'tren';
  @override
  String get thrash => 'racau';
}

// Path: orrery.compare
class _Translations$orrery$compare$id extends Translations$orrery$compare$en {
  _Translations$orrery$compare$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => 'PERUBAHAN';
  @override
  String get movers => 'PENGGERAK';
  @override
  String get noMovers => 'Tidak ada file yang berpindah antara frame ini.';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => 'file';
  @override
  String get deltaConnectivity => 'konektivitas';
  @override
  String get deltaRigidity => 'kekakuan';
  @override
  String get deltaEntropy => 'entropi';
  @override
  String get wayOutward => 'keluar';
  @override
  String get wayInward => 'ke dalam';
  @override
  String get wayShifted => 'bergeser';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$id
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'tanya: [pertanyaan]';
  @override
  String get nearHint => 'dekat: [file]';
  @override
  String get whoHint => 'siapa: [file]';
  @override
  String get logHint => 'log: [pesan]';
  @override
  String get runHint => 'jalankan: [tool]';
  @override
  String askLabel({required Object name, required Object body}) =>
      'Tanya ${name}: ${body}';
  @override
  String nearSubtitle({required Object path, required Object phi}) =>
      '${path} · φ=${phi}';
  @override
  String whoReviewersLabel({required Object name, required Object reviewers}) =>
      '${name} — ${reviewers}';
  @override
  String whoReviewersSubtitle({
    required Object path,
    required Object count,
    required Object touches,
  }) => '${path} · ${count} reviewer · ${touches} sentuhan';
  @override
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches} sentuhan';
  @override
  String whoTouchesSubtitle({required Object path}) =>
      '${path} · tidak ada reviewer tercatat';
}

// Path: palette.chips
class _Translations$palette$chips$id extends Translations$palette$chips$en {
  _Translations$palette$chips$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get ai => 'AI';
  @override
  String get near => 'DEKAT';
  @override
  String get who => 'SIAPA';
  @override
  String get term => 'TERM';
  @override
  String get gui => 'GUI';
  @override
  String get dev => 'DEV';
  @override
  String get debug => 'DEBUG';
  @override
  String get alpha => 'ALPHA';
  @override
  String get hot => 'PANAS';
  @override
  String get key => 'KEY';
  @override
  String get web => 'WEB';
  @override
  String get sys => 'SYS';
  @override
  String get clip => 'CLIP';
  @override
  String get sync => 'SYNC';
  @override
  String get force => 'FORCE';
  @override
  String get pr => 'PR';
  @override
  String get draft => 'DRAFT';
  @override
  String get undo => 'UNDO';
  @override
  String get thm => 'THM';
  @override
  String get ver => 'VER';
  @override
  String get desk => 'DESK';
  @override
  String get det => 'DET';
  @override
  String get main => 'MAIN';
  @override
  String get head => 'HEAD';
  @override
  String get gone => 'HILANG';
  @override
  String get remote => 'REMOTE';
  @override
  String get local => 'LOKAL';
  @override
  String get an => 'AN';
  @override
  String get lw => 'LW';
}

// Path: palette.predictive
class _Translations$palette$predictive$id
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '${percent}% momentum';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$id
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count} sentuhan · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$id
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) => 'Koherensi staging: ${percent}%';
  @override
  String subtitle({required Object count}) => '${count} file';
}

// Path: palette.keystone
class _Translations$palette$keystone$id
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · keystone ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$id extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => 'Changes di ${name}';
  @override
  String history({required Object name}) => 'History di ${name}';
  @override
  String branches({required Object name}) => 'Branches di ${name}';
  @override
  String terminal({required Object name}) => 'Terminal di ${name}';
  @override
  String generateCommit({required Object name}) => 'Buat Commit · ${name}';
  @override
  String reviewChanges({required Object name}) => 'Review Perubahan di ${name}';
  @override
  String muse({required Object name}) => 'Muse di ${name}';
}

// Path: palette.desks
class _Translations$palette$desks$id extends Translations$palette$desks$en {
  _Translations$palette$desks$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => 'worktree utama';
  @override
  String get detached => 'detached';
  @override
  String dirty({required Object count}) => '${count} kotor';
}

// Path: palette.actions
class _Translations$palette$actions$id extends Translations$palette$actions$en {
  _Translations$palette$actions$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => 'Buka di Browser';
  @override
  String get terminal => 'Terminal';
  @override
  String get revealInFiles => 'Tampilkan di File';
  @override
  String get copyPath => 'Salin Path';
  @override
  String get copyBranch => 'Salin Branch';
}

// Path: palette.tools
class _Translations$palette$tools$id extends Translations$palette$tools$en {
  _Translations$palette$tools$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => 'Luncurkan ${label}';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$id
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => 'Fetch';
  @override
  String get pull => 'Pull';
  @override
  String pullBehind({required Object count}) => '${count} di belakang';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => 'Push';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} commit',
      );
  @override
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits} ke ${upstream}';
  @override
  String get forcePush => 'Force Push';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      'Tidak bisa force-push: tidak ada upstream untuk ${branch}.';
  @override
  String get commit => 'Commit';
  @override
  String get stageAll => 'Stage Semua';
  @override
  String get unstageAll => 'Unstage Semua';
  @override
  String get discardAll => 'Buang Semua';
  @override
  String get createBranch => 'Buat Branch';
  @override
  String get deleteBranch => 'Hapus Branch';
  @override
  String get renameBranch => 'Ganti Nama Branch';
  @override
  String get stash => 'Stash';
  @override
  String get stashPop => 'Stash Pop';
  @override
  String get stashApply => 'Stash Apply';
  @override
  String get stashDrop => 'Stash Drop';
  @override
  String get createTag => 'Buat Tag';
  @override
  String get cherryPick => 'Cherry-pick';
  @override
  String get revert => 'Revert';
  @override
  String get stashConflictMessage =>
      'Stash diterapkan dengan konflik. Selesaikan di halaman Changes.';
}

// Path: palette.pr
class _Translations$palette$pr$id extends Translations$palette$pr$en {
  _Translations$palette$pr$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get create => 'Buat PR';
  @override
  String get merge => 'Merge PR';
  @override
  String get markReady => 'Tandai PR Siap';
}

// Path: palette.ai
class _Translations$palette$ai$id extends Translations$palette$ai$en {
  _Translations$palette$ai$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => 'Buat Commit';
  @override
  String get reviewChanges => 'Review Perubahan';
  @override
  String get runMuse => 'Jalankan Muse';
  @override
  String debugRepo({required Object name}) => 'Debug ${name}';
  @override
  String get describeSymptom => 'jelaskan sebuah gejala';
  @override
  String viewResult({required Object kind}) => 'Lihat ${kind}';
  @override
  String get unseenResult => 'hasil belum dilihat';
  @override
  String runningResult({required Object kind}) => 'AI: ${kind}…';
  @override
  String get running => 'berjalan';
  @override
  String get kindCommitMessage => 'Pesan Commit';
  @override
  String get kindCodeReview => 'Code Review';
  @override
  String get kindMuseResult => 'Hasil Muse';
  @override
  String get kindPresentation => 'Presentasi';
  @override
  String get kindDebugResult => 'Hasil Debug';
}

// Path: palette.undo
class _Translations$palette$undo$id extends Translations$palette$undo$en {
  _Translations$palette$undo$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => 'Batal: ${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$id
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get changes => 'Changes';
  @override
  String get history => 'History';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => 'Pengaturan';
  @override
  String get refresh => 'Refresh';
}

// Path: palette.settings
class _Translations$palette$settings$id
    extends Translations$palette$settings$en {
  _Translations$palette$settings$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => 'Kurangi Gerakan';
  @override
  String get animateLogoUnfocused => 'Animasikan Logo Saat Tak Fokus';
  @override
  String get instantBlameHover => 'Blame Instan Saat Hover';
  @override
  String get autoSelectChanges => 'Pilih Otomatis Perubahan';
  @override
  String get fetchOnlineIssues => 'Ambil Issue Online';
  @override
  String get rememberWip => 'Ingat Pekerjaan Berjalan';
  @override
  String get hideAiFeatures => 'Sembunyikan Fitur AI';
  @override
  String get crashReporting => 'Laporan Crash';
  @override
  String get aiReadOnly => 'AI Baca-saja';
  @override
  String get stashCabinetExpanded => 'Lemari Stash Terbuka';
  @override
  String get fileSortInverted => 'Urutan File Terbalik';
}

// Path: palette.info
class _Translations$palette$info$id extends Translations$palette$info$en {
  _Translations$palette$info$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$id extends Translations$palette$debug$en {
  _Translations$palette$debug$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => 'Status Engine';
  @override
  String get engineStatusSubtitle => 'Diagnostik spectral engine LogosGit';
  @override
  String get fileCoupling => 'Kopling File';
  @override
  String get fileCouplingSubtitle =>
      'Tetangga co-change terdekat untuk file yang di-stage';
  @override
  String get themeSpecimen => 'Contoh Tema';
  @override
  String get themeSpecimenSubtitle =>
      'Semua warna, ikon, tier teks, dan geometri';
}

// Path: palette.dev
class _Translations$palette$dev$id extends Translations$palette$dev$en {
  _Translations$palette$dev$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => 'Uji Merge Editor';
  @override
  String get testHistorySurgery => 'Uji Bedah History';
  @override
  String get back => 'kembali';
  @override
  String get cancel => 'batal';
  @override
  String get buildingConflicts => 'membangun konflik uji dari history…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$id
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Bedah History';
  @override
  String get subtitle =>
      'Tulis ulang history untuk menghapus file secara permanen';
}

// Path: palette.orrery
class _Translations$palette$orrery$id extends Translations$palette$orrery$en {
  _Translations$palette$orrery$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle => 'Scrub history struktural repo melalui manifold';
}

// Path: palette.command
class _Translations$palette$command$id extends Translations$palette$command$en {
  _Translations$palette$command$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label} selesai';
  @override
  String failed({required Object label, required Object message}) =>
      '${label} gagal: ${message}';
  @override
  String get copy => 'Salin';
}

// Path: palette.search
class _Translations$palette$search$id extends Translations$palette$search$en {
  _Translations$palette$search$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => 'cari semuanya...';
  @override
  String get hintElevated => 'elevated — semua aksi';
  @override
  String get emptyTypeToSearch => 'ketik untuk mencari';
  @override
  String get emptyNoResults => 'tidak ada hasil';
}

// Path: palette.wick
class _Translations$palette$wick$id extends Translations$palette$wick$en {
  _Translations$palette$wick$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'wick';
  @override
  String get coupledFallback => 'terkopel';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$id
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'saat ini';
  @override
  String get staged => 'di-stage';
  @override
  String get modified => 'diubah';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$id
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$id whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$id._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$id spectralEngine =
      _Translations$releaseNotes$about$spectralEngine$id._(_root);
  @override
  late final _Translations$releaseNotes$about$whereGoing$id whereGoing =
      _Translations$releaseNotes$about$whereGoing$id._(_root);
}

// Path: releaseNotes.legal
class _Translations$releaseNotes$legal$id
    extends Translations$releaseNotes$legal$en {
  _Translations$releaseNotes$legal$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get copyright => '© 2026 Woflo Labs';
  @override
  String get license =>
      'GPL-3.0-or-later · inti riset community-source WLCSL · tanpa jaminan';
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$id
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} baris',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$id
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file.',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} baris (${bytes}).',
      );
  @override
  String roles({required Object parts}) => 'Peran — ${parts}.';
  @override
  String showingNofM({required Object active, required Object total}) =>
      'Menampilkan ${active} dari ${total} file, diperingkat berdasarkan sentralitas struktural.';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$id
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => 'Sekilas';
  @override
  String get core => 'Inti';
  @override
  String get gettingStarted => 'Memulai';
  @override
  String get regions => 'Region';
  @override
  String get shape => 'Bentuk';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$id
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) =>
      'Repository tanpa file teks yang bisa dibaca${detail}.';
  @override
  String emptyBinary({required Object n}) => '${n} biner';
  @override
  String emptyUnreadable({required Object n}) => '${n} tak terbaca';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'Repository dengan ${n} file aktif.',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'Repository dengan ${n} file aktif — ${regions}.',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$id
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => 'Semua di bawah `${dir}`.';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} inti',
      );
  @override
  String get bodyCoreSeparator => ', ';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file',
      );
  @override
  String connectsTo({required Object linked}) => 'Terhubung ke: ${linked}.';
  @override
  String get filesLabel => 'File:';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$id
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get bulk =>
      'Codebase yang terhubung rapat: sebagian besar file ikut serta dalam satu lingkungan besar berbagi perubahan.';
  @override
  String get crystalline =>
      'Codebase berbentuk kisi: kopling seragam dan teratur antar file dengan struktur lokal yang bisa ditebak.';
  @override
  String get goe =>
      'Codebase yang saling terhubung kaya: kopling menyebar antar file tanpa tulang punggung dominan.';
  @override
  String get modular =>
      'Codebase modular: beberapa region kohesif dengan kopling silang terbatas. Kerja di satu region jarang mengganggu region lain.';
  @override
  String get poisson =>
      'Codebase terkopel longgar: file kebanyakan berkembang sendiri-sendiri, dengan perubahan bersama sesekali.';
  @override
  String get tree =>
      'Codebase berbentuk pohon: satu tulang punggung dominan dengan cabang bergantung. Perubahan biasanya merambat keluar dari inti.';
}

// Path: settings.language
class _Translations$settings$language$id
    extends Translations$settings$language$en {
  _Translations$settings$language$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Bahasa';
  @override
  String get summary =>
      'Bahasa UI untuk aplikasi ini. Output git, log, dan diagnostik tetap Inggris agar laporan bug tetap bisa dicari.';
  @override
  String get label => 'BAHASA TAMPILAN';
  @override
  String get systemDefault => 'Bawaan sistem';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      'Mengikuti bahasa OS-mu (${resolved})';
  @override
  String get disclosureSource => 'Bahasa sumber, ditulis oleh para pengembang.';
  @override
  String disclosureAi({required Object model}) =>
      'Diterjemahkan mesin oleh ${model}, belum ditinjau manusia. Koreksi dipersilakan.';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) => 'Diterjemahkan mesin oleh ${model}. ${percent}% ditinjau manusia.';
  @override
  String get disclosureHuman => 'Terjemahan manusia, dirawat oleh komunitas.';
  @override
  String reviewedBy({required Object names}) => 'Ditinjau oleh ${names}.';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$id
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => 'Preferensi';
  @override
  String get shortcuts => 'Pintasan';
  @override
  String get behaviour => 'Perilaku';
  @override
  String get aiProviders => 'Provider AI';
  @override
  String get modelSlots => 'Slot Model';
  @override
  String get tools => 'Tools';
  @override
  String get diagnostics => 'Diagnostik';
  @override
  String get offenders => 'Pelanggar';
  @override
  String get release => 'Rilis';
}

// Path: settings.errors
class _Translations$settings$errors$id extends Translations$settings$errors$en {
  _Translations$settings$errors$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile => 'Gagal menyimpan profil guardrail.';
  @override
  String get saveRetentionPolicy => 'Gagal menyimpan kebijakan retensi.';
  @override
  String get saveUpdateChannel => 'Gagal menyimpan channel update.';
  @override
  String get saveModelSelection => 'Gagal menyimpan pilihan model AI.';
  @override
  String get saveModelAlias => 'Gagal menyimpan alias model.';
  @override
  String get saveCommitMessageModelSlot =>
      'Gagal menyimpan slot model pesan commit.';
  @override
  String get saveReviewModelSlot => 'Gagal menyimpan slot model review.';
  @override
  String get saveCommitMessageCustomPrompt =>
      'Gagal menyimpan prompt kustom pesan commit.';
  @override
  String get saveReviewGuide => 'Gagal menyimpan panduan review.';
  @override
  String get saveMuseNotes => 'Gagal menyimpan catatan muse.';
  @override
  String get saveReviewDoubleCheck => 'Gagal menyimpan mode cek-ganda review.';
  @override
  String get saveApiPiggybackCli => 'Gagal menyimpan CLI piggyback API.';
  @override
  String get saveCliTimeout => 'Gagal menyimpan batas waktu CLI.';
  @override
  String get stopAllCli => 'Tidak bisa menghentikan sesi CLI yang berjalan.';
  @override
  String clearLocalData({required Object error}) =>
      'Tidak bisa membersihkan data lokal: ${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$id
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get editing => 'Mengedit';
  @override
  String get saving => 'Menyimpan';
  @override
  String get saveFailed => 'Penyimpanan gagal';
}

// Path: settings.clearData
class _Translations$settings$clearData$id
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => 'Bersihkan data lokal';
  @override
  String get clear => 'Bersihkan';
  @override
  String get confirmDiagnostics =>
      'Bersihkan sampel diagnostik lokal dan pengukuran waktu performa?';
  @override
  String get confirmAudit => 'Bersihkan catatan metadata audit AI lokal?';
  @override
  String get confirmAll =>
      'Bersihkan semua sampel diagnostik lokal dan catatan metadata audit AI?';
  @override
  String get confirmWipeAll =>
      'Hapus semua data aplikasi lokal — termasuk daftar repo terkini — dan keluar? Repo git-mu yang sebenarnya di disk tidak disentuh.';
  @override
  String get confirmReset =>
      'Reset data aplikasi lokal dan keluar?\n\nPengaturan, tema, onboarding, preferensi AI, telemetri, dan cache engram dibersihkan. Daftar repo terkinimu tetap ada.';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$id
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'longgar';
  @override
  String get balanced => 'seimbang';
  @override
  String get strict => 'ketat';
  @override
  String get paranoid => 'paranoid';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$id
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Guardrail';
  @override
  String get summary => 'Seberapa jeli otomatisasi di seluruh pengalaman.';
}

// Path: settings.appearance
class _Translations$settings$appearance$id
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Tampilan';
  @override
  String get summary => 'Suasana dan atmosfer antarmuka global.';
}

// Path: settings.retention
class _Translations$settings$retention$id
    extends Translations$settings$retention$en {
  _Translations$settings$retention$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Retensi Data Lokal';
  @override
  String get summaryDiagnostics => 'Kebijakan retensi diagnostik.';
  @override
  String get summaryWithAudit => 'Kebijakan retensi diagnostik dan audit AI.';
  @override
  String get unitDays => 'hari';
  @override
  String get unitMb => 'MB';
  @override
  String get includesNote =>
      'Termasuk diagnostik, pengukuran waktu performa, dan metadata.';
}

// Path: settings.navigation
class _Translations$settings$navigation$id
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Navigasi dan Dinamika';
  @override
  String get summaryShortcuts => 'Pintasan dan perilaku antarmuka.';
  @override
  String get summaryWithAi => 'Pintasan, perilaku antarmuka, dan routing AI.';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$id
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Dinamika Perilaku';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$id
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get diag => 'Diag';
  @override
  String get audit => 'Audit';
  @override
  String get all => 'Semua';
  @override
  String get clearsHint => '<-- membersihkan';
}

// Path: settings.channels
class _Translations$settings$channels$id
    extends Translations$settings$channels$en {
  _Translations$settings$channels$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get stable => 'STABLE';
  @override
  String get beta => 'BETA';
  @override
  String get dev => 'DEV';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$id
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => 'paling baru';
  @override
  String updateAvailable({required Object version}) => '${version} tersedia';
  @override
  String get notConfigured => 'tidak ada server update';
  @override
  String notFound({required Object channel}) => 'tidak ada rilis ${channel}';
  @override
  String get unreachable => 'tak terjangkau';
  @override
  String get badManifest => 'manifest rusak';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$id
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Profil keybinding';
  @override
  String get porcelain => 'Porcelain';
  @override
  String get numeric => 'Numerik';
  @override
  String get porcelainDescription => 'Pintasan berakor (G lalu C, H, B…).';
  @override
  String get numericDescription => 'Pintasan numerik satu-tombol (1, 2, 3…).';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$id
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get keyHintDefault => 'api key';
  @override
  String get endpointHint => 'endpoint';
  @override
  String get test => 'Uji';
  @override
  String get hide => 'Sembunyikan';
  @override
  String get show => 'Tampilkan';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$id
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => 'navigasi';
  @override
  String get staging => 'staging';
  @override
  String get branchesPrs => 'branch & PR';
  @override
  String get modifiers => 'modifier';
  @override
  String get changes => 'Changes';
  @override
  String get history => 'History';
  @override
  String get branches => 'Branches';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Pindah (selalu)';
  @override
  String get search => 'Cari';
  @override
  String get dismiss => 'Tutup';
  @override
  String get refresh => 'Refresh';
  @override
  String get shortcuts => 'Pintasan';
  @override
  String get nextChange => 'Perubahan berikut';
  @override
  String get prevChange => 'Perubahan sebelum';
  @override
  String get toggleLine => 'Toggle baris';
  @override
  String get toggleHunk => 'Toggle hunk';
  @override
  String get toggleFile => 'Toggle file';
  @override
  String get pinContext => 'Pin konteks';
  @override
  String get commit => 'Commit';
  @override
  String get acceptHint => 'Terima saran';
  @override
  String get undo => 'Undo';
  @override
  String get navigateRow => 'Navigasi';
  @override
  String get expand => 'Perluas';
  @override
  String get checkout => 'Checkout';
  @override
  String get approve => 'Setujui';
  @override
  String get requestChanges => 'Minta perubahan';
  @override
  String get selectRange => 'Pilih rentang';
  @override
  String get extendedMenu => 'Menu diperluas';
}

// Path: settings.toggles
class _Translations$settings$toggles$id
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'Mode AI baca-saja';
  @override
  String get aiReadOnlyDescription =>
      'Mencegah AI menulis atau men-stage perubahan secara otomatis.';
  @override
  String get logoMotionLabel => 'Logo beranimasi saat tab tak aktif';
  @override
  String get logoMotionDescriptionEnabled =>
      'Ia dirancang efisien, jangan lukai perasaannya';
  @override
  String get logoMotionDescriptionDisabled => ':(';
  @override
  String get rememberWipLabel => 'Ingat pekerjaan berjalan';
  @override
  String get rememberWipDescription =>
      'Simpan draf commit dan pilihan file-mu antar sesi.';
  @override
  String get stashCabinetLabel => 'Lemari stash mulai terbuka';
  @override
  String get stashCabinetDescription =>
      'Tampilkan laci lemari arsip terbuka secara default saat repo punya rak.';
  @override
  String get instantBlameLabel => 'Blame instan saat hover';
  @override
  String get instantBlameDescription =>
      'Lewati jeda 180ms sebelum info blame muncul di baris diff.';
  @override
  String get autoSelectLabel => 'Pilih otomatis perubahan baru';
  @override
  String get autoSelectDescription =>
      'File yang baru di-track atau berubah otomatis ditambahkan ke pilihan commit.';
  @override
  String get changeIdLabel => 'Tulis header change-id';
  @override
  String get changeIdDescription =>
      'Menambahkan header identitas change-id pada commit baru (konvensi Jujutsu, GitButler, dan Gerrit). Setiap commit ditulis ulang sekali tepat setelah dibuat.';
  @override
  String get fetchIssuesLabel => 'Ambil issue online saat branch dimuat';
  @override
  String get fetchIssuesDescription =>
      'Tarik detail PR dan issue dari provider git-mu di latar belakang saat halaman branches dibuka.';
  @override
  String get hateAiLabel => 'Aku benci AI';
  @override
  String get hateAiDescription =>
      'Usir semua fitur bertenaga LLM. Logos tetap berjalan karena ia cuma matematika spektral.';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$id
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'kemampu-diff-an diff';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$id
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => 'Memuat provider...';
  @override
  String get refreshingProviders => 'Menyegarkan diagnostik provider...';
  @override
  String get routeDescription =>
      'Ganti nama dan arahkan konfigurasi ke model provider mana pun yang terdeteksi.';
  @override
  String get loadingCategories => 'Memuat kategori model...';
  @override
  String get noOptions =>
      'Belum ada opsi model tersedia. Deteksi dulu CLI AI lokal yang kompatibel.';
  @override
  String get slotsAppearWhenAvailable =>
      'Pengaturan slot-model akan muncul di sini begitu model provider tersedia.';
  @override
  String get effortDefault => 'default';
  @override
  String get noModelsForSlot => 'Tidak ada model terdeteksi untuk slot ini.';
  @override
  String viaProvider({required Object provider}) => 'via ${provider}';
  @override
  String get customModelId => 'id model kustom';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$id
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) =>
      'tidak ada model cocok dengan "${query}"';
  @override
  String get noModels => 'tidak ada model tersedia';
  @override
  String get filterHint => 'filter model...';
  @override
  String get warming => 'memanas…';
  @override
  String get detailsUnavailable => 'detail tidak tersedia';
  @override
  String get free => 'gratis';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$id
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription =>
      'Susun pesan commit dari perubahan yang di-stage sesuai preferensi struktur, suara, dan cakupanmu.';
  @override
  String get reviewDescription =>
      'Review cakupan commit saat ini sebelum kamu commit.';
  @override
  String get museDescription =>
      'Orakel tiga-fase yang brainstorm lalu menyintesis arah maju untuk diff.';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$id
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => 'Panduan Gaya';
  @override
  String get styleGuideHint =>
      'Opsional. Suara / nada / larangan. Format di atas menangani kerangkanya.';
}

// Path: settings.review
class _Translations$settings$review$id extends Translations$settings$review$en {
  _Translations$settings$review$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Catatan tambahan untuk ikut di-review';
  @override
  String get doubleCheckLabel => 'Cek-ganda review';
  @override
  String get doubleCheckDescription =>
      'Jalankan lintasan verifikasi kedua sebelum menampilkan laporan akhir.';
}

// Path: settings.museHint
class _Translations$settings$museHint$id
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get loose =>
      'ada yang mau diarahkan pelan-pelan? suasana hati lagi baik hari ini.';
  @override
  String get balanced =>
      'apa yang perlu didalami, apa yang dilewati. jujur, tanpa kasar.';
  @override
  String get strict =>
      'standarnya. larangannya. apa yang tak akan dibiarkan muse lolos.';
  @override
  String get paranoid =>
      'setel lensanya. di frekuensi apa manifold harus berdengung?';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$id
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Catatan tambahan untuk muse';
}

// Path: settings.museStage
class _Translations$settings$museStage$id
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => 'BRAINSTORM';
  @override
  String get synthesize => 'SINTESIS';
  @override
  String get slot => 'slot';
  @override
  String get ideaCountLoose => '~12 ide';
  @override
  String get ideaCountBalanced => '~16 ide';
  @override
  String get ideaCountStrict => '~20 ide';
  @override
  String get ideaCountParanoid => '~24 ide';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  guardrail: ${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$id
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get folder => 'FOLDER';
  @override
  String get history => 'HISTORY';
  @override
  String get far => 'JAUH';
  @override
  String get near => 'DEKAT';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$id
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => 'peta modul';
  @override
  String get repoCenters => 'pusat repo';
  @override
  String get neighbors => 'tetangga';
  @override
  String get toTouch => 'apa yang disentuh berikutnya';
  @override
  String get relevanceEngine => 'engine relevansi';
  @override
  String get description =>
      'membaca bagaimana file bergerak bersama lintas struktur, history, dan ritme, jadi Manifold tahu apa yang penting, bukan cuma apa yang berubah.';
  @override
  String get withinReach => 'dalam jangkauan';
  @override
  String get gate => 'gerbang';
  @override
  String get nearest => 'terdekat';
  @override
  String get warming => 'memanas';
  @override
  String get emptyOpenRepo =>
      'buka sebuah repo untuk\nmelihat lensa secara langsung';
  @override
  String get emptyNoFiles =>
      'tidak ada file dalam\njangkauan — seret\nke arah HISTORY';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$id
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Panduan urutan perubahan';
  @override
  String get related =>
      'File yang berubah bersamaan mengelompok bersama. Perkara utama dulu; konteks menyusul.';
  @override
  String get relatedInverted =>
      'Perubahan terisolasi lebih dulu. Klaster yang terkopel erat tenggelam ke bawah.';
  @override
  String get alphabetical =>
      'Cukup A → Z berdasarkan path. Tanpa peduli huruf besar/kecil, angka diurutkan alami.';
  @override
  String get alphabeticalInverted =>
      'Cukup Z → A berdasarkan path. Tanpa peduli huruf besar/kecil, angka diurutkan alami.';
  @override
  String get impact =>
      'Perubahan terberat muncul dulu. Churn dibobot; biner dan file baru dinaikkan.';
  @override
  String get impactInverted =>
      'Perubahan teringan muncul dulu. Kemenangan cepat di atas; yang berat menunggu.';
  @override
  String get nearRelated => 'yang terkait dekat';
  @override
  String get alphabeticalShort => 'alfabetis';
  @override
  String get byImpact => 'berdasarkan dampak';
  @override
  String get flipped => 'dibalik';
  @override
  String get peek => 'intip';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$id
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'Model API memakai';
  @override
  String get codexNotDetected => 'codex tidak terdeteksi';
  @override
  String get dormant => 'DORMAN';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$id
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => 'viewer';
  @override
  String get media => 'media';
  @override
  String get binary => 'biner';
  @override
  String get hidden => 'tersembunyi';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$id
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => 'aksi destruktif';
  @override
  String get discards => 'pembuangan';
  @override
  String get commits => 'commit';
  @override
  String get commitPush => 'commit + push';
  @override
  String get all => 'semua';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$id
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Jendela undo';
  @override
  String get off => 'Mati';
  @override
  String descriptionInstant({required Object scope}) =>
      '${scope} difinalisasi seketika.';
  @override
  String descriptionDelayed({required Object seconds, required Object scope}) =>
      '${seconds}s sebelum ${scope} difinalisasi.';
  @override
  String get cycleScopeTooltip =>
      'Klik untuk menggilir cakupan · seret naik/turun di slider juga bisa';
  @override
  String get resetTooltip => 'Reset setiap aksi agar memakai jendela default';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$id
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => 'Kemungkinan aman berarti aman';
  @override
  String get proper => 'Bacaan yang benar, logika, integrasi, pola';
  @override
  String get lookAgain => 'Lihat lagi. Mungkin ada yang bersembunyi';
  @override
  String get assumeWrong => 'Anggap ada yang salah. Temukan';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$id
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh =>
      'mis. Fokus pada logika tingkat-tinggi dan bug besar. Ringkas dan pemaaf.';
  @override
  String get surfaceBugs =>
      'mis. Munculkan potensi bug, inkonsistensi arsitektur, dan kegagalan edge case.';
  @override
  String get scrutinize =>
      'mis. Telisik setiap baris untuk optimasi, keamanan, dan kepatuhan pola.';
  @override
  String get trustNothing =>
      'mis. Jangan percaya apa pun. Pertanyakan setiap efek samping. Perlakukan tiap baris sebagai potensi kegagalan.';
  @override
  String get optional =>
      'Panduan opsional tentang apa yang harus diperhatikan review.';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$id
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Format';
  @override
  String get peek => 'intip';
  @override
  String get structure => 'Struktur';
  @override
  String get voice => 'Suara';
  @override
  String get coverage => 'Cakupan';
  @override
  String get structureTitleBody => 'judul + isi';
  @override
  String get structureTitleOnly => 'judul saja';
  @override
  String get structureFreeform => 'bebas';
  @override
  String get voiceVerbLed => 'berorientasi aksi';
  @override
  String get voiceDescriptive => 'deskriptif';
  @override
  String get voiceNarrative => 'naratif';
  @override
  String get coverageEssentials => 'esensial';
  @override
  String get coverageBalanced => 'seimbang';
  @override
  String get coverageEverything => 'semuanya';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$id
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$id title =
      _Translations$settings$commitPreview$title$id._(_root);
  @override
  late final _Translations$settings$commitPreview$base$id base =
      _Translations$settings$commitPreview$base$id._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$id
  balancedSuffix = _Translations$settings$commitPreview$balancedSuffix$id._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$id
  everythingSuffix = _Translations$settings$commitPreview$everythingSuffix$id._(
    _root,
  );
}

// Path: settings.externalTools
class _Translations$settings$externalTools$id
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Tools Eksternal';
  @override
  String get summary =>
      'Klik-kanan sebuah proyek di sidebar untuk membukanya dengan salah satu ini. Argumen memakai {path} untuk folder proyek.';
  @override
  String get detecting => 'Mendeteksi tools terpasang…';
  @override
  String get allPresetsAdded =>
      'Semua preset yang dikenal sudah ditambahkan. Pakai “+ Custom” untuk menambah lagi.';
  @override
  String get noToolsConfigured =>
      'Belum ada tools dikonfigurasi. Tambahkan satu di atas.';
  @override
  String get categoryAi => 'ai';
  @override
  String get categoryEditors => 'editor';
  @override
  String get categoryExplore => 'jelajah';
  @override
  String get categoryOps => 'ops';
  @override
  String get categoryGitOps => 'git ops';
  @override
  String get nameHint => 'Nama';
  @override
  String get commandHint => 'command';
  @override
  String get test => 'uji';
  @override
  String get removeTool => 'Hapus tool';
  @override
  String get modeTerminal => 'terminal';
  @override
  String get modeDetached => 'detached';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$id
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      '${used}${limit} bulan ini';
}

// Path: settings.gitea
class _Translations$settings$gitea$id extends Translations$settings$gitea$en {
  _Translations$settings$gitea$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Token Gitea';
  @override
  String get hostHint => 'host';
  @override
  String get tokenHint => 'token';
  @override
  String get save => 'simpan';
}

// Path: settings.wick
class _Translations$settings$wick$id extends Translations$settings$wick$en {
  _Translations$settings$wick$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => 'Pilih executable wick';
  @override
  String get connected => 'wick · terhubung';
  @override
  String get pathToExecutable => 'wick · path ke executable';
  @override
  String get off => 'mati';
  @override
  String get disableHint => 'Matikan integrasi wick';
  @override
  String get enableHint => 'Aktifkan integrasi wick';
}

// Path: settings.integrations
class _Translations$settings$integrations$id
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => '& Integrasi';
  @override
  String get alpha => 'alpha';
  @override
  String get planned => 'direncanakan';
  @override
  String get lspComingSoon => 'lsp · segera hadir';
  @override
  String get alphaMathConnected => 'alpha-math · terhubung';
  @override
  String get alphaMathComingSoon => 'alpha-math · segera hadir';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$id
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Kurangi gerakan';
  @override
  String get subtitleStill => 'Diam… seperti es?';
  @override
  String get subtitleFlow => 'Mengalir seperti air.';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$id
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => 'RESET & KELUAR';
  @override
  String get keepRepos => 'SIMPAN REPO';
  @override
  String get wipeAll => 'HAPUS SEMUA';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$id
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => 'Diagnostik Command';
  @override
  String get networkFlowTelemetry => 'Telemetri Aliran Jaringan';
  @override
  String get clearSamples => 'Bersihkan Sampel';
  @override
  String get clearMetrics => 'Bersihkan Metrik';
  @override
  String get clearTimings => 'Bersihkan Timing';
  @override
  String get recalibrate => 'KALIBRASI ULANG';
  @override
  String get ok => 'ok';
  @override
  String get noCommandTimings =>
      'Belum ada timing command tertangkap. Jalankan aksi normal untuk mengisi diagnostik.';
  @override
  String get noBackendSamples =>
      'Belum ada sampel command backend tertangkap. Jalankan aksi git dan pengaturan untuk mengisi log ini.';
  @override
  String get noDiffSessions =>
      'Belum ada sesi render diff tertangkap. Buka dan gulir diff file untuk mengisi panel ini.';
  @override
  String get noUiSessions =>
      'Belum ada sesi timing UI tertangkap. Buka panel dan navigasi rute untuk mengisi panel ini.';
  @override
  String get recentOperations => 'Operasi Terkini';
  @override
  String get recentBackendOperations => 'Operasi Backend Terkini';
  @override
  String get recentDiffSessions => 'Sesi Diff Terkini';
  @override
  String get recentUiTimings => 'Timing UI Terkini';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} command unik',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} command bercakup',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} peristiwa terinstrumentasi',
      );
  @override
  String summaryCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryBackend({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryDiff({required Object sessions, required Object jank}) =>
      '${sessions} | jank ${jank}%';
  @override
  String summaryUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';
  @override
  List<String> get headersCommand => ['command', 'p50', 'keandalan', 'rentang'];
  @override
  List<String> get headersBackend => ['cakupan', 'p50', 'p95', 'kegagalan'];
  @override
  List<String> get headersDiff => [
    'renderer',
    'paint pertama',
    'frame p95',
    'raster p95',
    'jank',
  ];
  @override
  List<String> get headersUi => ['peristiwa', 'p50', 'kegagalan', 'rentang'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$id
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} sampel',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} command',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} sesi',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} peristiwa',
      );
  @override
  String stability({required Object pct}) => '${pct}% stabilitas';
  @override
  String metaCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String metaDiff({required Object sessions, required Object stability}) =>
      '${sessions} | ${stability}';
  @override
  String metaUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';
}

// Path: settings.flowEngine
class _Translations$settings$flowEngine$id
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => 'alur-eksekusi';
  @override
  String get description =>
      'simulasikan osilator pada kode. memunculkan jalur eksekusi rapuh sebelum mengkristal jadi bug.';
  @override
  String get idle => 'diam';
  @override
  String get emptyOpenRepo => 'buka sebuah repo untuk\nmelihat analisis alur';
  @override
  String get scanning => 'memindai';
  @override
  String get analysing => 'menganalisis file\ndi lensa…';
  @override
  String get fragility => 'kerapuhan';
  @override
  String get findings => 'temuan';
  @override
  String get gap => 'jeda';
  @override
  String get clean => 'bersih';
  @override
  String get severity => 'keparahan';
  @override
  String get critical => 'kritis';
  @override
  String get warn => 'peringatan';
  @override
  String get info => 'info';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$id
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get spark => 'percikan inspirasi · langkah berikutnya yang segera';
  @override
  String get current => 'arus di air · perluasan bermasa-kini';
  @override
  String get horizon => 'menatap ke cakrawala · arah yang menjangkau';
  @override
  String get fever => 'terbangun dari mimpi demam · provokasi';
  @override
  String get echo => 'gema melintasi ngarai · analogi di tempat lain';
  @override
  String get vertigo => 'vertigo di tepi jurang · risiko yang bersebelahan';
  @override
  String get ghost => 'hantu dari yang dulu · konteks historis';
  @override
  String get mirror => 'cermin di air tenang · inversi';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$id
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Piggyback CLI';
  @override
  String get clearCacheLabel => 'Bersihkan cache';
  @override
  String get clearCacheTooltip =>
      'Hapus model yang di-cache dan periksa ulang. Membersihkan yang sudah dijatuhkan provider.';
  @override
  String get refreshLabel => 'Segarkan provider';
  @override
  String get refreshTooltip => 'Periksa ulang setiap provider sekarang.';
  @override
  String get body => 'Pipa langsung pesan antarmuka ke biner provider lokal.';
  @override
  String get cliTimeoutLabel => 'Batas waktu per eksekusi';
  @override
  String get cliTimeoutUnitMinutes => 'menit';
  @override
  String get cliTimeoutUnitMinute => 'menit';
  @override
  String get forceStopLabel => 'Hentikan semua sesi';
  @override
  String get forceStopTooltip =>
      'Paksa berhenti setiap eksekusi CLI yang sedang berjalan.';
  @override
  String get forceStopConfirmTitle => 'Hentikan sesi CLI yang berjalan?';
  @override
  String forceStopConfirmBody({required Object count}) =>
      'Ini memaksa berhenti ${count} eksekusi CLI yang sedang berjalan. Outputnya akan hilang.';
  @override
  String get forceStopConfirmAction => 'Hentikan semua';
  @override
  String get forceStopNoneRunning => 'Tidak ada sesi CLI yang berjalan';
  @override
  String get forceStopRecordError => 'Dihentikan — sesi CLI dipaksa berhenti.';
}

// Path: settings.header
class _Translations$settings$header$id extends Translations$settings$header$en {
  _Translations$settings$header$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Preferensi Workspace';
  @override
  String get subtitle =>
      'Atur estetika global, dinamika antarmuka, dan pengaman operasional inti untuk seluruh workspace.';
  @override
  String get releaseNotesTooltip => 'Catatan rilis';
  @override
  String get replayOnboardingTooltip => 'Ulang onboarding';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$id
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Diagnostik Performa';
  @override
  String get copyTrace => 'Salin Trace';
  @override
  String get offenderRanking => 'Peringkat Pelanggar';
  @override
  String get offenderRankingSubtitle => 'Pendorong latensi lintas stream.';
  @override
  String get noOffenders =>
      'Belum ada peringkat pelanggar. Tangkap aktivitas diagnostik untuk mengisi daftar ini.';
}

// Path: settings.release
class _Translations$settings$release$id
    extends Translations$settings$release$en {
  _Translations$settings$release$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Deployment Rilis';
  @override
  String get summary => 'Pengaturan terkait update.';
  @override
  String get deploymentChannel => 'CHANNEL DEPLOYMENT';
  @override
  String get captureCrashDiagnostics => 'Tangkap diagnostik crash';
  @override
  String get comingSoon => 'Segera hadir.';
  @override
  String get checking => 'MEMERIKSA…';
  @override
  String get pollForUpdates => 'CEK UPDATE';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$id
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => 'Mendeteksi...';
  @override
  String get ready => 'Siap';
  @override
  String get notDetected => 'Tidak terdeteksi';
  @override
  String configured({required Object count}) => '${count} dikonfigurasi';
  @override
  String get notConfigured => 'Tidak dikonfigurasi';
  @override
  String get cliManaged => 'Dikelola-CLI';
  @override
  String get connected => 'Terhubung';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} model',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} provider',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$id
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get am => 'AM';
  @override
  String get pm => 'PM';
}

// Path: settings.offenders
class _Translations$settings$offenders$id
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => 'Command';
  @override
  String get diffStream => 'Render Diff';
  @override
  String get uiStream => 'Timing UI';
  @override
  String rendererName({required Object mode}) => 'renderer ${mode}';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95}ms p95 | ${fail}% gagal';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '${jank}% jank | ${frame}ms frame p95';
  @override
  String inStream({required Object stream}) => 'di ${stream}';
}

// Path: sync.actions
class _Translations$sync$actions$id extends Translations$sync$actions$en {
  _Translations$sync$actions$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => 'Sync';
  @override
  String get syncOpenRepoDetail =>
      'Buka sebuah repository untuk mengelola operasi push dan pull.';
  @override
  String get detachedHeadLabel => 'Detached HEAD';
  @override
  String get detachedHeadDetail =>
      'Checkout sebuah branch sebelum push atau pull.';
  @override
  String get publishBranchLabel => 'Publikasikan branch';
  @override
  String publishBranchDetail({required Object branch}) =>
      'Push ${branch} dan set upstream tracking branch-nya.';
  @override
  String get publishButtonLabel => 'Publikasikan';
  @override
  String get syncBranchLabel => 'Sync branch';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => 'Pull ${behindCount} dengan rebase, lalu push ${aheadCount}.';
  @override
  String get syncBranchButtonLabel => 'Pull (rebase) lalu push';
  @override
  String get pushBranchLabel => 'Push branch';
  @override
  String pushBranchDetail({required Object count, required Object upstream}) =>
      'Push ${count} ke ${upstream}.';
  @override
  String get pushBranchButtonLabel => 'Push commit';
  @override
  String get pullUpdatesLabel => 'Pull update';
  @override
  String pullUpdatesDetail({required Object count, required Object upstream}) =>
      'Pull ${count} dari ${upstream}.';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      'Fetch dari ${upstream} dan segarkan status upstream.';
}

// Path: sync.panel
class _Translations$sync$panel$id extends Translations$sync$panel$en {
  _Translations$sync$panel$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Memuat status remote';
  @override
  String get loadingMessage => 'Memeriksa informasi tracking branch.';
  @override
  String get remoteStatusUnavailable => 'Status remote tidak tersedia';
  @override
  String get noUpstream => 'tanpa upstream';
  @override
  String get aheadLabel => 'Di depan';
  @override
  String get behindLabel => 'Di belakang';
  @override
  String get treeLabel => 'Tree';
  @override
  String get runningSync => 'Menjalankan sync…';
  @override
  String get fetching => 'Mengambil…';
  @override
  String get fetchOnly => 'Fetch saja';
  @override
  String get syncFailed => 'Sync gagal';
  @override
  String get forcePushRecoveryLabel => 'Force push (dengan lease)';
  @override
  String get conflictsToResolveTitle => 'Konflik untuk diselesaikan';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} perlu diselesaikan: ${list}';
  @override
  String get resolveConflicts => 'Selesaikan konflik';
  @override
  String get workingEllipsis => 'Mengerjakan…';
  @override
  String lastActivity({required Object operation}) =>
      'Aktivitas terakhir: ${operation}';
  @override
  String get noOutput => 'Tidak ada output.';
  @override
  String resolvedConflicts({required Object count}) =>
      '${count} terselesaikan.';
  @override
  String get cancelledUnchanged => 'Dibatalkan, working tree tidak berubah.';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) =>
      '${count} punya perubahan belum di-commit, commit dulu untuk rebase-sync (${list}).';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      'Tidak bisa force-push: tidak ada upstream yang dikonfigurasi untuk "${branch}".';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$id extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => 'Force push (dengan lease)?';
  @override
  String target({required Object remote, required Object branch}) =>
      'Target: ${remote}/${branch}';
  @override
  String get warning =>
      'Ini menulis ulang branch remote dengan history lokalmu. Dengan lease, operasi dibatalkan jika ada yang push ke remote setelah fetch terakhirmu, tapi perubahan yang sudah di-fetch tetap akan tertimpa. Pakai hanya saat kamu memang bermaksud rebase atau amend yang membuat branch menyimpang.';
  @override
  String get confirmButton => 'Force push';
}

// Path: xray.board
class _Translations$xray$board$id extends Translations$xray$board$en {
  _Translations$xray$board$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => 'bergerak bersama modul lain';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} reviewer',
      );
  @override
  String get territory => 'Teritori';
  @override
  String get unreviewed => 'belum di-review';
}

// Path: xray.cadence
class _Translations$xray$cadence$id extends Translations$xray$cadence$en {
  _Translations$xray$cadence$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} commit · ${days} hari\n${lines}';
  @override
  String burstTooltipSingle({required Object n, required Object label}) =>
      '${n} commit pada ${label}';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      'jeda ${n} hari · ${label}';
  @override
  String reflogTooltip({required Object n, required Object label}) =>
      '${n} peristiwa reflog pada ${label}';
}

// Path: xray.cards
class _Translations$xray$cards$id extends Translations$xray$cards$en {
  _Translations$xray$cards$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$id branchModel =
      _Translations$xray$cards$branchModel$id._(_root);
  @override
  late final _Translations$xray$cards$bursty$id bursty =
      _Translations$xray$cards$bursty$id._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$id hiddenRefs =
      _Translations$xray$cards$hiddenRefs$id._(_root);
  @override
  late final _Translations$xray$cards$keystone$id keystone =
      _Translations$xray$cards$keystone$id._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$id machineHistory =
      _Translations$xray$cards$machineHistory$id._(_root);
  @override
  late final _Translations$xray$cards$migration$id migration =
      _Translations$xray$cards$migration$id._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$id narrowHotspot =
      _Translations$xray$cards$narrowHotspot$id._(_root);
  @override
  late final _Translations$xray$cards$noTags$id noTags =
      _Translations$xray$cards$noTags$id._(_root);
  @override
  late final _Translations$xray$cards$reflog$id reflog =
      _Translations$xray$cards$reflog$id._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$id singleOwner =
      _Translations$xray$cards$singleOwner$id._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$id extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get branches => 'branches';
  @override
  String get bursty => 'meledak';
  @override
  String get hiddenRefs => 'ref tersembunyi';
  @override
  String get machineHeavy => 'berat-mesin';
  @override
  String get migration => 'migrasi';
  @override
  String get narrowHotspot => 'hotspot sempit';
  @override
  String get noTags => 'tanpa tag';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => 'pemilik-tunggal';
}

// Path: xray.grain
class _Translations$xray$grain$id extends Translations$xray$grain$en {
  _Translations$xray$grain$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => 'paling kasar — modul tingkat-atas';
  @override
  String get finest => 'butir terhalus';
  @override
  String get mid => 'butir sedang';
  @override
  String get oneCharacteristic => 'satu skala karakteristik';
}

// Path: xray.header
class _Translations$xray$header$id extends Translations$xray$header$en {
  _Translations$xray$header$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => 'kotor';
  @override
  String get machineChip => 'mesin';
  @override
  String get refresh => 'Refresh';
  @override
  String get refreshing => 'Menyegarkan...';
  @override
  String get title => 'X-Ray Repo';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$id extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => 'tetangga klaster';
  @override
  String get coChangers => 'co-changer';
  @override
  String get keystone => 'keystone';
  @override
  String keystoneScore({required Object score}) => 'keystone  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$id extends Translations$xray$inspector$en {
  _Translations$xray$inspector$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => 'branch';
  @override
  String commitsHumanMachine({required Object n}) => 'manusia · ${n} mesin';
  @override
  String get commitsLabel => 'commit';
  @override
  String get confidenceLabel => 'keyakinan';
  @override
  String get curlLabel => 'curl';
  @override
  String get engineSection => 'engine';
  @override
  String get gradientLabel => 'gradien';
  @override
  String get harmonicLabel => 'harmonik';
  @override
  String get headLabel => 'head';
  @override
  String get hiddenRefsLabel => 'ref tersembunyi';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} merge',
      );
  @override
  String get noTags => 'tanpa tag';
  @override
  String get notesLabel => 'notes';
  @override
  String get openCommit => 'Buka commit';
  @override
  String get pathLabel => 'path';
  @override
  String remoteCount({required Object n}) => '${n} remote';
  @override
  String get renamesLabel => 'penggantian nama';
  @override
  String scannedAt({required Object time}) => 'dipindai ${time}';
  @override
  String selectedCount({required Object n}) => '${n} dipilih';
  @override
  String get shapeLinear => 'linear';
  @override
  String get shapeMergeHeavy => 'berat-merge';
  @override
  String get shapeMostlyLinear => 'sebagian besar linear';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} stash',
      );
  @override
  String get stressLabel => 'stress';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} tag',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} worktree',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$id
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage =>
      'Menyelidik history git, ref, kadensi, dan hotspot.';
  @override
  String get buildingTitle => 'Membangun X-Ray Repo';
  @override
  String get idleMessage =>
      'Buka panel lagi untuk menyelidik repository saat ini.';
  @override
  String get idleTitle => 'X-Ray Repo';
  @override
  String get unavailableTitle => 'X-Ray Repo tidak tersedia';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$id extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => 'waktu-paruh ${n}h';
}

// Path: xray.multi
class _Translations$xray$multi$id extends Translations$xray$multi$en {
  _Translations$xray$multi$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} klaster',
      );
  @override
  String clusterSingle({required Object id}) => 'klaster ${id}';
  @override
  String couplingSuffix({required Object parts}) => 'kopling ${parts}';
  @override
  String externalCount({required Object n}) => '${n} eksternal';
  @override
  String mutualCount({required Object n}) => '${n} timbal balik';
}

// Path: xray.recency
class _Translations$xray$recency$id extends Translations$xray$recency$en {
  _Translations$xray$recency$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n}h';
  @override
  String months({required Object n}) => '${n}bl';
  @override
  String get today => 'hari ini';
  @override
  String weeks({required Object n}) => '${n}mg';
  @override
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        one: '${n}th',
        other: '${n}th',
      );
}

// Path: xray.rings
class _Translations$xray$rings$id extends Translations$xray$rings$en {
  _Translations$xray$rings$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => 'satu struktur menyatu';
  @override
  String get hintSelfSimilar => 'mandiri-serupa';
  @override
  String get oneBlendedBody =>
      'Satu struktur menyatu — belum ada skala modul terpisah yang teruraikan.';
  @override
  String get overHistory => 'Sepanjang history';
  @override
  String get parts => 'bagian';
  @override
  String get readingHint => 'membaca struktur…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} skala',
      );
  @override
  String get scaleDissolved => 'sebuah skala struktural luruh';
  @override
  String get scaleEmerged => 'sebuah skala struktural muncul';
  @override
  String get scaleSpectrum => 'spektrum skala';
  @override
  String get selfSimilarBody =>
      'Mandiri-serupa — struktur berulang lintas skala, tanpa satu level karakteristik.';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} pergeseran di history',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} pergeseran struktural',
      );
  @override
  String get title => 'Lingkaran pertumbuhan';
  @override
  String get unavailable => 'tidak tersedia';
}

// Path: xray.stats
class _Translations$xray$stats$id extends Translations$xray$stats$en {
  _Translations$xray$stats$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get alive => 'hidup';
  @override
  String get files => 'file';
  @override
  String get lastTouched => 'terakhir disentuh';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'pemilik',
      );
  @override
  String get touches => 'sentuhan';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$id
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'saat ini';
  @override
  String get legacy => 'warisan';
  @override
  String get zone => 'zona repo';
}

// Path: xray.summary
class _Translations$xray$summary$id extends Translations$xray$summary$en {
  _Translations$xray$summary$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) => 'Analisis gagal: ${error}';
  @override
  String get analyze => 'Analisis';
  @override
  String get copied => 'Ringkasan disalin ke clipboard.';
  @override
  String get directionHint => 'arah';
  @override
  String get download => 'Unduh';
  @override
  String get emptyState =>
      'Jalankan analisis Logos untuk memetakan struktur dan region repository ini.\n(tw: acakadut nih)';
  @override
  String get exit => 'Keluar';
  @override
  String get generating => 'Membaca repo dan mengklaster fitur…';
  @override
  String get noModel => 'Tidak ada model AI dikonfigurasi.';
  @override
  String get noModelConfigured => 'tidak ada model AI dikonfigurasi';
  @override
  String presentWith({required Object label}) =>
      'presentasikan dengan ${label}';
  @override
  String presentingWith({required Object label}) =>
      'mempresentasikan dengan ${label}…';
  @override
  String get reanalyze => 'Analisis ulang';
  @override
  String get saveDialogTitle => 'Simpan ringkasan repository';
  @override
  String saveFailed({required Object error}) => 'Penyimpanan gagal: ${error}';
  @override
  String get savePresentationDialogTitle => 'Simpan presentasi';
  @override
  String savedTo({required Object path}) => 'Disimpan ke ${path}';
}

// Path: xray.tabs
class _Translations$xray$tabs$id extends Translations$xray$tabs$en {
  _Translations$xray$tabs$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get map => 'Peta';
  @override
  String get signals => 'Sinyal';
  @override
  String get summary => 'Ringkasan';
  @override
  String get time => 'Waktu';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$id extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => 'konektivitas';
  @override
  String events({required Object n}) => '${n} peristiwa';
  @override
  String get openInOrrery => 'Buka di Orrery';
  @override
  String get readingHint => 'membaca history…';
  @override
  String snapshots({required Object n}) => '${n} snapshot';
  @override
  String get steady =>
      'Stabil — tidak ada peristiwa struktural di jendela ini.';
  @override
  String get title => 'Trajektori struktural';
}

// Path: xray.verdict
class _Translations$xray$verdict$id extends Translations$xray$verdict$en {
  _Translations$xray$verdict$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '${pct}% kanonik';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · ${canonical}% kanonik · ${decisive}% menentukan';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$id
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get manual => 'manual';
  @override
  String get safe => 'aman';
  @override
  String get guided => 'terpandu';
  @override
  String get assisted => 'terbantu';
  @override
  String get full => 'penuh';
  @override
  String label({required Object label}) => 'trust: ${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$id
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get accept => 'terima';
  @override
  String get other => 'lainnya';
  @override
  String get both => 'keduanya';
  @override
  String get navigate => 'navigasi';
  @override
  String get jumpNext => 'lompat berikut';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$id
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'merge';
  @override
  String get cherryPick => 'cherry-pick';
  @override
  String get revert => 'revert';
  @override
  String get resolve => 'selesaikan';
  @override
  String get switchOp => 'pindah';
  @override
  String get pull => 'pull';
  @override
  String get rebase => 'rebase';
  @override
  String rebaseOnto({required Object branch, required Object base}) =>
      'rebase ${branch} ke ${base}';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$id
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane =>
      'Pergerakan baru dengan satu pemilik kuat di dekatnya.';
  @override
  String get activeSeam => 'Pergerakan baru dari banyak tangan di dekatnya.';
  @override
  String get stableOwnerLane =>
      'Jalur berumur panjang dengan satu pemilik dominan.';
  @override
  String get sharedLongLivedSeam =>
      'Sambungan bersama yang menumpuk seiring waktu.';
  @override
  String get sharedLane => 'Jalur bersama tanpa satu pemilik dominan.';
  @override
  String get resolving => 'History masih menyusun diri di sekitar baris ini.';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$id
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get hot => 'Panas';
  @override
  String get novel => 'Baru';
  @override
  String get contested => 'Diperebutkan';
  @override
  String get spreading => 'Menyebar';
  @override
  String get stable => 'Stabil';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$id
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => 'Tinggal di ${concept}';
  @override
  String get sitsInLocalSeam => 'Berada di sambungan lokal';
  @override
  String workedMostlyBy({required Object owner}) =>
      'sebagian besar dikerjakan ${owner} di dekatnya';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: 'bergema di ${n} titik lain',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      'periksa ${path} berikutnya${detail}';
  @override
  String inspectDetail({required Object reason}) => ' (${reason})';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$id
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get tight => 'pas ketat';
  @override
  String get close => 'pas dekat';
  @override
  String get loose => 'pas longgar';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$id
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) =>
      'Dukungan terdekat · ${label}';
  @override
  String localizedMove({required Object label}) =>
      'Pergerakan terlokalisasi · ${label}';
  @override
  String surprisingMove({required Object label}) =>
      'Pergerakan mengejutkan · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$id
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => 'Struktur stabil';
  @override
  String get conflictingSignals => 'Sinyal bertentangan';
  @override
  String get novelShape => 'Bentuk baru';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$id
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => 'Cermin test';
  @override
  String get semanticHistorySibling => 'Saudara semantik + history';
  @override
  String get recentCoChange => 'Co-change terbaru';
  @override
  String get semanticSibling => 'Saudara semantik';
  @override
  String get relatedStructure => 'Struktur terkait';
  @override
  String get tightlyBound => 'terikat erat';
  @override
  String get orbiting => 'mengorbit';
  @override
  String get weaklyCoupled => 'terkopel lemah';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$id
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => 'jejak history';
  @override
  String get testMirrorLane => 'jalur cermin test';
  @override
  String get structuralLane => 'jalur struktural';
  @override
  String get semanticNeighbourhood => 'lingkungan semantik';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$id
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => 'kepentingan tinggi';
  @override
  String get importanceModerate => 'kepentingan sedang';
  @override
  String get mostlyAdditions => 'sebagian besar penambahan';
  @override
  String get mostlyDeletions => 'sebagian besar penghapusan';
  @override
  String get tightlyCoupled => 'file yang terkopel erat';
  @override
  String get overlapsWorkingTree => 'tumpang tindih dengan working tree-mu';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$id
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$id open =
      _Translations$onboarding$repo$doors$open$id._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$id clone =
      _Translations$onboarding$repo$doors$clone$id._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$id create =
      _Translations$onboarding$repo$doors$create$id._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$id
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Clone dari URL';
  @override
  String get urlLabel => 'URL Repository';
  @override
  String get targetLabel => 'Folder tujuan';
  @override
  String get browse => 'Jelajahi…';
  @override
  String get clone => 'Clone';
  @override
  String get cloning => 'Meng-clone…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$id
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => 'Buka Repository';
  @override
  String get createRepository => 'Buat Repository';
  @override
  String get cloneTarget => 'Target Clone';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$id
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired => 'URL dan path tujuan wajib diisi.';
  @override
  String get createFailed => 'Gagal membuat repository.';
  @override
  String get cloneFailed => 'Gagal meng-clone repository.';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$id
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get xray => 'x-ray repo';
  @override
  String get settings => 'pengaturan';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$id
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => 'Proyek';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$id
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object staged, required Object total}) =>
      '${staged} dari ${total} file';
  @override
  String stagedCount({required Object n}) => '${n} di-stage';
  @override
  String get commitMessageHint => 'Pesan commit…';
  @override
  String get commitAndPush => 'Commit & push';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$id
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'History';
  @override
  String get viewingLast => 'melihat 20 commit terakhir';
  @override
  String get inFlight => 'SEDANG JALAN';
  @override
  String get you => 'kamu';
  @override
  String get commit1 => 'ajari rubah mengendus sebelum menelan';
  @override
  String get commit2 => 'amber: tahan aroma semalaman';
  @override
  String get commit3 => 'pensiunkan kubis demi amber + duri';
  @override
  String get commit4 => 'duri menjaga gerbang';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$id
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => 'BRANCHES';
  @override
  String get lensPRs => 'PRs';
  @override
  String get absorbed => 'terserap';
  @override
  String get desk => 'desk';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ tracking: ${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$id
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => 'Git client pribadimu.';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$id
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'KENAPA FLUTTER?';
  @override
  String get body =>
      'Versi pertama ini dulunya aplikasi Tauri (Rust + TypeScript). Aku sudah merasa itu lambat. Lalu aku dengar seorang streamer bilang hal yang sama di sebuah stream yang biasanya tidak kutonton, dan itu jadi dorongan untuk akhirnya berpindah. Dia tidak menyarankan Flutter; justru jauh dari itu. Dart kutemukan sendiri, kurakit sebuah prototipe, dan waktu startup turun dari sekitar 15 detik jadi di bawah satu detik. Bagai siang dan malam. Selamat tinggal era Tauri.\n\nPipeline rendering Flutter lebih dekat ke game engine ketimbang DOM, dan untuk aplikasi desktop di mana UI adalah produknya, itu berarti segalanya. Dart ternyata juga bahasa yang benar-benar bagus. Matematika di balik spectral engine diprototipekan di Rust dulu, jadi kerja itu terbawa dengan mulus.\n\nFlutter lintas-platform secara default, yang mana bagus, tapi sifatnya Googley jadi ada beberapa keanehan.';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$id
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'APA ITU SPECTRAL ENGINE?';
  @override
  String get body =>
      'Setiap kali kamu commit, file-file yang kamu ubah bersamaan membentuk pola seiring waktu. Spectral engine membaca commit graph-mu dan menguraikan pola co-change itu jadi sinyal: file mana yang terkopel, seberapa erat, dan peran struktural apa yang mereka mainkan di repo. Pada dasarnya analisis spektral atas history pengembanganmu. Di dalam git client. Dengan sengaja.\n\nMatematikanya baru, jadi aku memperlakukannya seperti game feel: setel, uji, sesuaikan, dan terus lanjut sampai sinyalnya terasa benar.\n\nSinyal-sinyal itu memberi makan segalanya. Seismograf di history, bar yang dilukis di bawah subjek commit, sistem review, Muse, konstelasi file. Seluruh aplikasi bernalar dari lapisan ini ke bawah, bukan sebaliknya.';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$id
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'MAU DIBAWA KE MANA INI?';
  @override
  String get body =>
      'Milestone pertama adalah kesetaraan penuh dengan GitHub Desktop, SourceTree, dan GitKraken. Git client lintas-platform yang terasa cepat dan menangani hal-hal dasar lebih baik dari yang lain. Sebagian besar sudah di sini. Spectral engine sudah memberi kita keunggulan untuk operasi yang membuatmu harus berpikir manual di client lain.\n\nSetelah itu, tujuannya adalah melampaui setiap git client lain dalam kecepatan, aksesibilitas, kecerdasan, dan UX keseluruhan. Ada lebih banyak di pipeline daripada yang diumumkan di sini.';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$id
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$id verbLed =
      _Translations$settings$commitPreview$title$verbLed$id._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$id
  descriptive = _Translations$settings$commitPreview$title$descriptive$id._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$title$narrative$id narrative =
      _Translations$settings$commitPreview$title$narrative$id._(_root);
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$id
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$id verbLed =
      _Translations$settings$commitPreview$base$verbLed$id._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$id
  descriptive = _Translations$settings$commitPreview$base$descriptive$id._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$id narrative =
      _Translations$settings$commitPreview$base$narrative$id._(_root);
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$id
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$id
  verbLed = _Translations$settings$commitPreview$balancedSuffix$verbLed$id._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$id
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$id._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$id
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$id._(_root);
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$id
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$id._(
    TranslationsId root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$id
  verbLed = _Translations$settings$commitPreview$everythingSuffix$verbLed$id._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$id
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$id._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$id
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$id._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$id
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim =>
      'Repository punya cukup permukaan branch untuk mengganjar navigasi yang sadar-branch.';
  @override
  String get broadTitle => 'Model branch punya luas permukaan';
  @override
  String localBranchesDetail({required Object count}) =>
      '${count} branch lokal.';
  @override
  String get localBranchesLabel => 'Branch lokal';
  @override
  String remoteBranchesDetail({required Object count}) =>
      '${count} branch remote.';
  @override
  String get remoteBranchesLabel => 'Branch remote';
  @override
  String get simpleClaim => 'Model branch yang terlihat itu sempit.';
  @override
  String get simpleTitle => 'Model branch sederhana';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$id
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Pekerjaan mendarat dalam ledakan terkonsentrasi ketimbang ritme harian yang rata.';
  @override
  String get title => 'Kadensi pengembangan meledak-ledak';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$id
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) =>
      '${count} ref hidup di luar ruang branch/tag normal.';
  @override
  String evidenceDetail({required Object count}) =>
      '${count} ref di luar heads/remotes/tags.';
  @override
  String get evidenceLabel => 'Ref tersembunyi';
  @override
  String get namespacesLabel => 'Namespace';
  @override
  String get title => 'Namespace Git tersembunyi';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$id
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String claim({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
    n,
    other:
        'Sekelompok kecil file mengemban bobot co-change tak sebanding relatif terhadap jumlah sentuhannya.',
  );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} sentuhan · tarik φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('id'))(
        n,
        other: '${n} file jembatan keystone',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$id
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Commit gaya checkpoint secara material mendistorsi metrik history yang naif.';
  @override
  String machineCommitsDetail({required Object count}) =>
      '${count} commit cocok dengan pola mesin/sesi.';
  @override
  String get machineCommitsLabel => 'Commit mesin';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '${raw} commit mentah vs ${filtered} commit tersaring.';
  @override
  String get rawVsFilteredLabel => 'Mentah vs tersaring';
  @override
  String get title => 'History mesin mendominasi metrik mentah';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$id
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      'History bergeser dari `${older}` ke `${newer}`, mengisyaratkan transisi stack atau permukaan.';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} sentuhan, terakhir aktif ${lastActive}.';
  @override
  String get title => 'Migrasi arsitektur terlihat';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$id
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Sekelompok kecil file dan direktori menyerap porsi perubahan yang tak sebanding.';
  @override
  String get title => 'Konsentrasi hotspot itu sempit';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path} menyumbang ${pct}% dari kumpulan hotspot yang terlihat.';
  @override
  String get topHotspotLabel => 'Hotspot teratas';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      '${count} penulis di potongan history ini.';
  @override
  String get visibleAuthorsLabel => 'Penulis terlihat';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$id
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Tag git tidak dipakai sebagai lapisan rilis atau milestone yang terlihat.';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '${count} endpoint remote dikonfigurasi.';
  @override
  String get remoteEndpointsLabel => 'Endpoint remote';
  @override
  String get tagCountDetail => '0 tag ditemukan.';
  @override
  String get tagCountLabel => 'Jumlah tag';
  @override
  String get title => 'Tidak ada jejak rilis/tag formal';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$id
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Volume reflog mengisyaratkan iterasi lokal terkonsentrasi melampaui commit yang dipublikasikan.';
  @override
  String get peakReflogDayLabel => 'Hari reflog puncak';
  @override
  String get title => 'Sesi editing lokal intens';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$id
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}` adalah ${kind} yang sering disentuh dengan satu penulis terlihat yang jelas.';
  @override
  String ownerCountDetail({required Object count}) =>
      '${count} penulis berbeda.';
  @override
  String get ownerCountLabel => 'Jumlah pemilik';
  @override
  String get title => 'Hotspot pemilik-tunggal';
  @override
  String get touchCountLabel => 'Jumlah sentuhan';
  @override
  String touchDetailFiltered({required Object count}) =>
      '${count} sentuhan di history tersaring.';
  @override
  String touchDetailRaw({required Object count}) =>
      '${count} sentuhan di history mentah.';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$id
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Buka';
  @override
  String get subtitle => 'yang ada';
  @override
  String get hint => 'yang sudah kamu punya';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$id
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Clone';
  @override
  String get subtitle => 'dari URL';
  @override
  String get hint => 'tempel URL remote';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$id
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Buat';
  @override
  String get subtitle => 'baru';
  @override
  String get hint => 'mulai sesuatu yang segar';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$id
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Biarkan rubah melewati kue yang baunya aneh';
  @override
  String get s2 => 'Latih rubah menolak kue yang dirusak sebelum menelan';
  @override
  String get s3 => 'Paksa rubah memeriksa forensik setiap kue di gerbang';
  @override
  String get def => 'Ajari rubah menolak kue busuk';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$id
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$id._(
    TranslationsId root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'rubah kini yang memilih kuenya';
  @override
  String get s2 => 'Rutinitas inspeksi kue, ditanamkan pada rubah';
  @override
  String get s3 =>
      'Forensik pemeriksaan kue, dibenamkan pada rubah lewat pengulangan';
  @override
  String get def => 'Protokol endus-kue, terpasang dalam rubah';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$id
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'rubah mulai melewati kue yang baunya salah';
  @override
  String get s2 =>
      'Duduk bersama rubah dan menelaah kue mana yang harus ditolak';
  @override
  String get s3 =>
      'Menghabiskan sebagian besar sore meyakinkan rubah bahwa tidak setiap kue yang ditawarkan, dengan itikad baik, adalah kue';
  @override
  String get def => 'Meminta rubah mengendus kue sebelum memakannya';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$id
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Rubah melirik. Yang mencurigakan ditinggal.';
  @override
  String get s2 =>
      'Rubah memeriksa tiap token, menolak yang baunya salah, dan mencatat penolakan di teras.';
  @override
  String get s3 =>
      'Rubah mengitari tiap token, mengendus udara dari tiga sudut, menolak yang terbaca salah, dan menunggu sejenak memastikan penolakannya melekat.';
  @override
  String get def =>
      'Rubah kini mengendus tiap token dan dengan sopan menolak yang mencurigakan.';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$id
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$id._(
    TranslationsId root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Lolos halus untuk yang aneh, kebanyakan.';
  @override
  String get s2 =>
      'Penolakan terdokumentasi pada tiap token beraroma salah, dikeluarkan dari teras dan dicatat.';
  @override
  String get s3 =>
      'Penolakan bermeterai per token beraroma salah, dikeluarkan dari teras dengan satu cakar terangkat, satunya diam.';
  @override
  String get def =>
      'Penolakan sopan pada token mencurigakan, dikeluarkan dari teras.';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$id
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$id._(TranslationsId root)
    : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Rubah begitu saja berhenti memakan yang aneh. Gampang.';
  @override
  String get s2 =>
      'Dulu tiap token ditelan tanpa banyak pikir; kini ada jeda, tinjauan yang benar, dan penolakan untuk yang terasa janggal.';
  @override
  String get s3 =>
      'Dulu tiap token ditelan tanpa berpikir. Kini: sebuah jeda. Udara, dihirup. Udara, ditahan. Rubah mengamati papan teras untuk kedutan kecil yang kadang muncul saat ada yang salah, dan baru kemudian keputusan dibuat.';
  @override
  String get def =>
      'Dulu tiap token ditelan tanpa upacara; kini ada endusan dulu.';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$id
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$id._(
    TranslationsId root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Teras aman. Halaman belakang terserah.';
  @override
  String get s2 =>
      ' Teras disapu setiap kali menolak; lumpur halaman belakang diizinkan dalam jam yang tertera.';
  @override
  String get s3 =>
      ' Teras disapu dan disapu ulang; lumpur halaman belakang dikatalog per jejak-cakar dan cuaca, dan rubah berlama-lama di ambang lebih lama dari biasanya.';
  @override
  String get def =>
      ' Teras tetap bersih; halaman belakang menjaga hak lumpurnya.';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$id
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$id._(
    TranslationsId root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Teras oke. Halaman belakang berbuat sesuka halaman belakang.';
  @override
  String get s2 =>
      ' Teras sebagai zona bersih-bukti; halaman belakang sebagai zona lumpur yang ditentukan, jamnya tertera.';
  @override
  String get s3 =>
      ' Teras sebagai ruang bersih tingkat-bukti; halaman belakang sebagai arsip lumpur terkatalog; ambang sebagai tempat rubah berdiri dan berpikir terlalu lama.';
  @override
  String get def => ' Teras bersih; hak lumpur dijaga di halaman belakang.';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$id
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$id._(
    TranslationsId root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Teras aman. Halaman belakang, entahlah.';
  @override
  String get s2 =>
      ' Teras dijaga bersih sesudahnya; rubah mundur ke halaman belakang, tempat berpikir berlangsung.';
  @override
  String get s3 =>
      ' Teras digosok dua kali malam itu. Rubah menyusuri halaman belakang perlahan, berhenti di tiang pagar yang sama seperti biasa, dan menoleh ke teras seolah teras berutang sesuatu.';
  @override
  String get def =>
      ' Teras tetap bersih, meski halaman belakang tetap menang soal martabat.';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$id
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$id._(
    TranslationsId root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Amber di sana. Drift menghanyut. Duri menusuk kalau perlu. Kebanyakan tak terjadi apa-apa.';
  @override
  String get s2 =>
      ' Amber menahan tiap aroma untuk ditinjau. Drift membawa udara hari itu menuju duri gerbang, yang menandai tiap penolakan untuk hitungan malam.';
  @override
  String get s3 =>
      ' Amber menahan tiap aroma dan memberi bobot berbeda tergantung jam. Drift bergerak melintasi teras dengan sudut yang seharusnya tak penting tapi penting. Duri gerbang menusuk sekali untuk penolakan dan dua kali untuk yang hampir terlewat rubah, dan rubah tahu bedanya bahkan saat tak ada yang lain tahu.';
  @override
  String get def =>
      ' Amber menahan aroma. Drift membawanya lanjut. Duri gerbang menangkap yang tak boleh lewat.';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$id
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$id._(
    TranslationsId root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Amber di tiang. Drift di udara. Duri di gerbang. Aman.';
  @override
  String get s2 =>
      ' Amber sebagai saksi-aroma yang ditunjuk; drift sebagai ambien yang dicatat; tanda-duri sebagai rekaman penolakan hari itu, direkonsiliasi saat senja.';
  @override
  String get s3 =>
      ' Amber sebagai saksi-aroma yang keheningannya sendiri adalah sebuah bacaan; drift sebagai ambien berpola yang bergerak salah di hari-hari saat ada yang salah; duri sebagai penjaga-hitungan gerbang, yang tandanya diperiksa rubah sebelum tidur dan lagi sebelum fajar.';
  @override
  String get def =>
      ' Amber sebagai saksi-aroma; drift sebagai konteks ambien; duri sebagai tanda-penolakan gerbang yang diam.';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$id
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$id._(
    TranslationsId root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsId _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Amber ada di sekitar. Drift datang dan pergi. Duri melakukan hal tenangnya. Ya sudah, santai.';
  @override
  String get s2 =>
      ' Amber menyimpan rekaman-aroma hari itu, drift dicatat berdasarkan arah dan jam, dan tanda duri dihitung serta ditandatangani balik oleh teras.';
  @override
  String get s3 =>
      ' Amber menyimpan rekaman-aroma, tapi rubah bersumpah bobotnya lebih berat di pagi-pagi tertentu. Drift bergerak melintasi teras seperti biasanya, yang artinya salah di hari-hari yang penting. Duri gerbang menandai tiap penolakan; rubah keluar saat cahaya pertama untuk menghitungnya, seperti cara kau menghitung anak tangga yang sudah kau hitung.';
  @override
  String get def =>
      ' Amber menyimpan rekaman-aroma, drift menggerakkan udara, dan duri gerbang menangkap yang perlu ditangkap.';
}
