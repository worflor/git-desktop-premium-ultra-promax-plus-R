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
class TranslationsTr extends Translations
    with BaseTranslations<AppLocale, Translations> {
  /// You can call this constructor and build your own translation instance of this locale.
  /// Constructing via the enum [AppLocale.build] is preferred.
  TranslationsTr({
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
             locale: AppLocale.tr,
             overrides: overrides ?? {},
             cardinalResolver: cardinalResolver,
             ordinalResolver: ordinalResolver,
           ),
       super(
         cardinalResolver: cardinalResolver,
         ordinalResolver: ordinalResolver,
       );

  /// Metadata for the translations of <tr>.
  @override
  final TranslationMetadata<AppLocale, Translations> $meta;

  late final TranslationsTr _root = this; // ignore: unused_field

  @override
  TranslationsTr $copyWith({
    TranslationMetadata<AppLocale, Translations>? meta,
  }) => TranslationsTr(meta: meta ?? this.$meta);

  // Translations
  @override
  late final _Translations$app$tr app = _Translations$app$tr._(_root);
  @override
  late final _Translations$backend$tr backend = _Translations$backend$tr._(
    _root,
  );
  @override
  late final _Translations$branches$tr branches = _Translations$branches$tr._(
    _root,
  );
  @override
  late final _Translations$changes$tr changes = _Translations$changes$tr._(
    _root,
  );
  @override
  late final _Translations$common$tr common = _Translations$common$tr._(_root);
  @override
  late final _Translations$diff$tr diff = _Translations$diff$tr._(_root);
  @override
  late final _Translations$filament$tr filament = _Translations$filament$tr._(
    _root,
  );
  @override
  late final _Translations$history$tr history = _Translations$history$tr._(
    _root,
  );
  @override
  late final _Translations$historySurgery$tr historySurgery =
      _Translations$historySurgery$tr._(_root);
  @override
  late final _Translations$onboarding$tr onboarding =
      _Translations$onboarding$tr._(_root);
  @override
  late final _Translations$orrery$tr orrery = _Translations$orrery$tr._(_root);
  @override
  late final _Translations$palette$tr palette = _Translations$palette$tr._(
    _root,
  );
  @override
  late final _Translations$releaseNotes$tr releaseNotes =
      _Translations$releaseNotes$tr._(_root);
  @override
  late final _Translations$repoSummary$tr repoSummary =
      _Translations$repoSummary$tr._(_root);
  @override
  late final _Translations$review$tr review = _Translations$review$tr._(_root);
  @override
  late final _Translations$settings$tr settings = _Translations$settings$tr._(
    _root,
  );
  @override
  late final _Translations$sync$tr sync = _Translations$sync$tr._(_root);
  @override
  late final _Translations$xray$tr xray = _Translations$xray$tr._(_root);
}

// Path: app
class _Translations$app$tr extends Translations$app$en {
  _Translations$app$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get panelSettings => 'Ayarlar';
  @override
  String get panelReleaseNotes => 'Sürüm Notları';
  @override
  String get panelFilamentFindings => 'Filament Bulguları';
  @override
  String get filamentFindingsUpper => 'FİLAMENT BULGULARI';
  @override
  late final _Translations$app$cheatsheet$tr cheatsheet =
      _Translations$app$cheatsheet$tr._(_root);
  @override
  String get commandPaletteTooltip => 'Komut paleti   /';
  @override
  String get newDeskFallback => 'yeni desk';
  @override
  String get deskFallback => 'desk';
  @override
  String get currentDeskFallback => 'geçerli';
  @override
  String get noRepositoryOpen => 'Açık depo yok';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Desk olarak açılamadı: ${error}';
  @override
  String couldNotDetectForge({required Object error}) =>
      'Forge algılanamadı: ${error}';
  @override
  String get cannotFetchPrNoForge =>
      'PR alınamıyor: bu depo için forge algılanmadı.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      '${ref}, uzaktaki en son sürümle üzerine yazılsın mı?';
  @override
  String get overwrite => 'Üzerine yaz';
  @override
  String couldntFetchPr({required Object error}) => 'PR alınamadı: ${error}';
  @override
  String get promoteDeskToPr => 'Desk\'i PR\'a yükselt';
  @override
  String get applyToMain => 'main\'e uygula';
  @override
  String updateDeskFrom({required Object target, required Object source}) =>
      '${target}, ${source} ile güncelle';
  @override
  String bringChangesFromHere({required Object source}) =>
      '${source} değişikliklerini buraya getir';
  @override
  String get editLocalPr => 'Yerel PR\'ı düzenle';
  @override
  String get discardLocalPr => 'Yerel PR\'ı iptal et';
  @override
  String get closeDesk => 'Desk\'i kapat';
  @override
  String couldntPromote({required Object error}) => 'Yükseltilemedi: ${error}';
  @override
  String get commitOrShelveBeforeApplying =>
      'Uygulamadan önce desk\'in değişikliklerini commit et veya rafa kaldır.';
  @override
  String get couldNotResolveMainWorktree =>
      'Ana çalışma ağacının yolu çözümlenemedi.';
  @override
  String couldntPromoteDesk({required Object error}) =>
      'Desk yükseltilemedi: ${error}';
  @override
  String get couldntDetermineBaseBranch =>
      'Bu desk için taban dal belirlenemedi.';
  @override
  String prBaseHeadSame({required Object branch}) =>
      'PR tabanı ve ucu aynı dal (${branch}) — uygulanacak bir şey yok.';
  @override
  String appliedBranchToBase({required Object branch, required Object base}) =>
      '${branch}, ${base} üzerine uygulandı';
  @override
  String updatedDeskToDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
    n,
    one: '${target}, ${source} ile güncellendi (${n} commit).',
    other: '${target}, ${source} ile güncellendi (${n} commit).',
  );
  @override
  String get fastForwardFailedFallback =>
      'Fast-forward temiz şekilde inemedi — bunun yerine yama önizlemesi gösteriliyor.';
  @override
  String deskAheadOfDesk({
    required num n,
    required Object target,
    required Object source,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
    n,
    one: '${target}, ${source} dalına göre ${n} commit ileride.',
    other: '${target}, ${source} dalına göre ${n} commit ileride.',
  );
  @override
  String deskUpToDate({required Object target, required Object source}) =>
      '${target} zaten ${source} ile güncel.';
  @override
  String uncommittedPreviewNotice({required Object target}) =>
      '${target} desk\'inde commit edilmemiş değişiklikler var — bunun yerine yama olarak önizleniyor.';
  @override
  String updateDeskFromLower({
    required Object target,
    required Object source,
  }) => '${target}, ${source} ile güncelle';
  @override
  String noUpdatesToBringFrom({required Object source}) =>
      '${source} kaynağından getirilecek güncelleme yok.';
  @override
  String get updatePrepFailed => 'Güncelleme hazırlığı başarısız';
  @override
  String bringChangesFromInto({
    required Object source,
    required Object target,
  }) => '${source} değişikliklerini ${target} desk\'ine getir';
  @override
  String noPatchableChanges({required Object source, required Object target}) =>
      '${source} kaynağından ${target} desk\'ine getirilecek yamalanabilir değişiklik yok.';
  @override
  String get patchPrepFailed => 'Yama hazırlığı başarısız';
  @override
  String failureWithError({required Object label, required Object error}) =>
      '${label}: ${error}';
  @override
  String get titleHint => 'başlık';
  @override
  String get bodyHint => 'gövde';
  @override
  String get bodyOptionalHint => 'gövde (isteğe bağlı)';
  @override
  String get draftLower => 'taslak';
  @override
  String get cancelLower => 'iptal';
  @override
  String get saveLower => 'kaydet';
  @override
  String couldntSave({required Object error}) => 'Kaydedilemedi: ${error}';
  @override
  String get stashedNoOtherDesk =>
      'Değişiklikler zulaya alındı — uygulanacak başka desk yok. Kurtarmak için git stash pop kullan.';
  @override
  String get suggestedSource => 'önerilen kaynak';
  @override
  String tooltipModifiedCount({required Object n}) => '${n} değişti';
  @override
  String tooltipAheadCount({required Object n}) => '${n} ileride';
  @override
  String tooltipBehindCount({required Object n}) => '${n} geride';
  @override
  String get focusedEdits => 'odaklı değişiklikler';
  @override
  String get editsSpreadAcrossSubsystems =>
      'alt sistemlere yayılmış değişiklikler';
  @override
  String get editsTouchingManySubsystems =>
      'birçok alt sisteme dokunan değişiklikler';
  @override
  String get focusedBranch => 'odaklı dal';
  @override
  String get branchSpansMultipleSubsystems =>
      'dal birden çok alt sisteme yayılıyor';
  @override
  String get structurallyDivergentFromMainline =>
      'ana hattan yapısal olarak ayrışmış';
  @override
  String get localPr => 'yerel PR';
  @override
  String lastTouched({required Object time}) => 'en son ${time} dokunuldu';
  @override
  String driftGroupCount({required Object dir, required Object n}) =>
      '${dir} içinde ${n}';
  @override
  String driftSummaryRemainder({
    required Object summary,
    required Object remainder,
  }) => '${summary} +${remainder}';
  @override
  String get uncommittedChanges => 'Commit edilmemiş değişiklikler';
  @override
  String get closeDeskQuestion => 'Desk kapatılsın mı?';
  @override
  String uncommittedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} commit edilmemiş dosya.',
        other: '${n} commit edilmemiş dosya.',
      );
  @override
  String commitsAheadOfMain({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: 'main\'in ${n} commit önünde.',
        other: 'main\'in ${n} commit önünde.',
      );
  @override
  String get willRemoveWorktreeDirectory =>
      'Bu, çalışma ağacı dizinini kaldırır.';
  @override
  String filesChangedCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} dosya değişti',
        other: '${n} dosya değişti',
      );
  @override
  String get shelveHere => 'Buraya rafa kaldır';
  @override
  String get discardAndClose => 'İptal et & kapat';
  @override
  String get noRepository => 'depo yok';
  @override
  String get issuePromotedToRemote => 'Issue uzağa yükseltildi.';
  @override
  String get pushedToRemote => 'Uzağa gönderildi.';
  @override
  String get pulledFromRemote => 'Uzaktan çekildi.';
  @override
  String get remoteIssueNotFound => 'uzak issue bulunamadı';
  @override
  String importedIssueLocally({required Object id}) =>
      '#${id} yerel olarak içe aktarıldı.';
  @override
  String get issueAbandoned => 'Issue bırakıldı.';
  @override
  String get abandonIssue => 'Issue\'yu bırak';
  @override
  String permanentlyRemoveLocalIssueConfirm({required Object id}) =>
      'Yerel issue #${id} kalıcı olarak kaldırılsın mı? Bu, referansını siler ve geri alınamaz.';
  @override
  String get abandon => 'Bırak';
  @override
  String publishedBranch({required Object branch}) => '${branch} yayımlandı.';
  @override
  String get publishingEllipsis => 'Yayımlanıyor…';
  @override
  String get publish => 'Yayımla';
  @override
  String get noRemoteConfigured => 'Bu depo için uzak yapılandırılmamış.';
  @override
  String get jumpToDesk => 'Desk\'e git';
  @override
  String get arrowOpen => '→ aç';
  @override
  String get openOnANewDesk => 'Yeni bir desk\'te aç';
  @override
  String get plusDesk => '+ desk';
  @override
  String get plusSpace => '+ ';
  @override
  String get newBranchNameHint => 'yeni-dal-adı';
  @override
  String get escLower => 'esc';
  @override
  String get plusNewDesk => '+ yeni desk';
  @override
  String get fromHeadEllipsis => 'HEAD\'den...';
  @override
  String get viewAllBranches => 'Tüm dalları gör';
  @override
  String get issuesLower => 'issue\'lar';
  @override
  String get newIssueLower => 'yeni issue';
  @override
  String get noneLinked => 'bağlı yok';
  @override
  String get noOpenIssues => 'açık issue yok';
  @override
  String get createAndPushLower => 'oluştur + push';
  @override
  String get createLower => 'oluştur';
  @override
  String get remoteLower => 'uzak';
  @override
  String issueHashTitle({required Object id, required Object title}) =>
      '#${id} ${title}';
  @override
  String get promoteToRemote => 'Uzağa yükselt';
  @override
  String get pushToRemote => 'Uzağa push et';
  @override
  String get pullFromRemote => 'Uzaktan pull et';
  @override
  String get importLabel => 'İçe aktar';
  @override
  String get failedToCreateRepository => 'Depo oluşturulamadı.';
  @override
  String get openRepositoryLower => 'depo aç';
  @override
  String get newRepositoryLower => 'yeni depo';
  @override
  String get back => 'Geri';
  @override
  String get openRepositoryDialogTitle => 'Depo Aç';
  @override
  String get createRepositoryDialogTitle => 'Depo Oluştur';
  @override
  String get cloneTargetDialogTitle => 'Klon Hedefi';
  @override
  String get cloneToDialogTitle => 'Şuraya klonla';
  @override
  String get exportToDialogTitle => 'Şuraya dışa aktar';
  @override
  String get createFromTemplateInDialogTitle => 'Şablondan şurada oluştur';
  @override
  String get notAGitRepoInitConfirm =>
      'Git deposu değil. Burada bir tane başlatılsın mı?';
  @override
  String get repositoryUrlRequired => 'Depo URL\'si gerekli.';
  @override
  String get failedToCloneRepository => 'Depo klonlanamadı.';
  @override
  String cloningEllipsis({required Object name}) => '${name} klonlanıyor...';
  @override
  String get cloneCancelled => 'Klonlama iptal edildi.';
  @override
  String get noProjectsYet => 'Henüz proje yok';
  @override
  String get dissolveGroup => 'Grubu dağıt';
  @override
  String get projectsHeader => 'Projeler';
  @override
  String get cloneLabel => 'Klonla';
  @override
  String get createLabel => 'Oluştur';
  @override
  String get openLabel => 'Aç';
  @override
  String get repositoryUrlPlaceholder => 'Depo URL\'si';
  @override
  String get projectNameOrFullPathPlaceholder => 'proje-adı veya tam yol';
  @override
  String get pathToProjectPlaceholder => '/proje/yolu';
  @override
  String get cloneToFolderPathPlaceholder => 'Klonlanacak klasör yolu';
  @override
  String get switchToCreateRepo => 'Depo oluşturmaya geç';
  @override
  String get explorer => 'Gezgin';
  @override
  String get terminal => 'Terminal';
  @override
  String get cloneUrl => 'Klon URL\'si';
  @override
  String get copyPath => 'Yolu kopyala';
  @override
  String get export => 'Dışa aktar';
  @override
  String get readme => 'README';
  @override
  String get duplicate => 'Çoğalt';
  @override
  String get template => 'Şablon';
  @override
  String get forgetThisProject => 'Bu projeyi unut';
  @override
  String get aiKindCommitMessage => 'commit mesajı';
  @override
  String get aiKindReview => 'inceleme';
  @override
  String get aiKindMuse => 'muse';
  @override
  String get aiKindPresent => 'sunum';
  @override
  String get aiKindDebug => 'hata ayıklama';
  @override
  String aiStatusRunning({required Object kind}) => '${kind} çalışıyor';
  @override
  String aiStatusFailedUnread({required Object kind}) =>
      '${kind} başarısız (okunmadı)';
  @override
  String aiStatusReadyUnread({required Object kind}) =>
      '${kind} hazır (okunmadı)';
  @override
  String get filesLower => 'dosyalar';
  @override
  String get commitsLower => 'commit\'ler';
  @override
  String get undoLabel => 'Geri al';
  @override
  String get goLabel => 'git';
  @override
  String countdownSeconds({required Object n}) => '${n}sn';
  @override
  String get collapseGlyph => '▲ daralt';
  @override
  String moreLinesGlyph({required Object n}) => '▼ ${n} satır daha';
}

// Path: backend
class _Translations$backend$tr extends Translations$backend$en {
  _Translations$backend$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$backend$ops$tr ops = _Translations$backend$ops$tr._(
    _root,
  );
  @override
  late final _Translations$backend$mergeOutcome$tr mergeOutcome =
      _Translations$backend$mergeOutcome$tr._(_root);
}

// Path: branches
class _Translations$branches$tr extends Translations$branches$en {
  _Translations$branches$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get runningAiReview => 'AI incelemesi çalışıyor…';
  @override
  String prNumberLabel({required Object number}) => 'PR #${number}';
  @override
  String get findings => 'BULGULAR';
  @override
  String get observations => 'GÖZLEMLER';
  @override
  String get renameEllipsis => 'Yeniden adlandır…';
  @override
  String get publish => 'Yayımla';
  @override
  String publishFailed({required Object error}) =>
      'Yayımlama başarısız: ${error}';
  @override
  String couldntOpenDesk({required Object error}) => 'Desk açılamadı: ${error}';
  @override
  String syncFailed({required Object error}) => 'Eşitleme başarısız: ${error}';
  @override
  String get renameBranchTitle => 'Dalı yeniden adlandır';
  @override
  String get newNameHint => 'yeni ad';
  @override
  String get rename => 'Yeniden adlandır';
  @override
  String invalidBranchName({required Object name}) =>
      '\'${name}\' geçerli bir dal adı değil.';
  @override
  String renameFailed({required Object error}) =>
      'Yeniden adlandırma başarısız: ${error}';
  @override
  String deletingBranch({required Object name}) => '${name} siliniyor';
  @override
  String branchOpenInDesk({required Object name, required Object desk}) =>
      '\'${name}\', \'${desk}\' desk\'inde açık.';
  @override
  String get openDesk => 'Desk\'i aç';
  @override
  String openInDeskShort({required Object desk}) => '\'${desk}\' desk\'inde aç';
  @override
  String get couldNotPinBranch => 'dal ucu sabitlenemedi; silme atlandı';
  @override
  String get couldNotPinTag => 'etiket sabitlenemedi; silme atlandı';
  @override
  String deletingTag({required Object name}) => '${name} etiketi siliniyor';
  @override
  String get applyToActiveChanges => 'Etkin değişikliklere uygula…';
  @override
  String get couldNotLoadPrDiff => 'PR diff\'i yüklenemedi.';
  @override
  String prSourceLabel({required Object number, required Object title}) =>
      'PR #${number}: ${title}';
  @override
  String mergeIntoDesk({required Object branch}) =>
      '${branch} dalına merge et…';
  @override
  String get checkoutThisPr => 'Bu PR\'ı checkout et';
  @override
  String get mergeIntoNewDesk => 'Yeni desk\'e merge et…';
  @override
  String get pushToForge => 'Forge\'a push et';
  @override
  String get linkToIssue => 'Issue\'ya bağla…';
  @override
  String get gitPatch => '↓ git patch';
  @override
  String get copyBranchName => 'Dal adını kopyala';
  @override
  String copiedRef({required Object ref}) => '"${ref}" kopyalandı';
  @override
  String get reviewPr => 'PR\'ı incele';
  @override
  String get openInBrowser => 'Tarayıcıda aç';
  @override
  String get markAsRead => 'Okundu olarak işaretle';
  @override
  String get markAsUnread => 'Okunmadı olarak işaretle';
  @override
  String get replaceLocalCommitsTitle => 'Yerel commit\'ler değiştirilsin mi?';
  @override
  String replaceLocalCommitsBody({required Object ref}) =>
      '${ref}, uzak PR ucunda olmayan yerel commit\'lere sahip. Güncellemek onları uzaktaki en son sürümle değiştirir.';
  @override
  String get update => 'Güncelle';
  @override
  String couldntFetchPr({required Object error}) => 'PR alınamadı: ${error}';
  @override
  String couldntOpenAsDesk({required Object error}) =>
      'Desk olarak açılamadı: ${error}';
  @override
  String couldntOpenInBrowser({required Object error}) =>
      'Tarayıcıda açılamadı: ${error}';
  @override
  String get noIssuesYetLocal =>
      'Henüz issue yok. Upstream\'de bir tane aç ya da issue lensinde "+ yeni yerel issue" kullan.';
  @override
  String get remotePrsLinkLocalOnly =>
      'Uzak PR\'lar yalnızca yerel issue\'lara bağlanabilir. "+ yeni yerel issue" ile bir tane oluştur.';
  @override
  String linkPrToIssues({required Object number}) =>
      'PR #${number} ile issue\'ları bağla';
  @override
  String get noPrsYetLocal =>
      'Henüz PR yok. Upstream\'de bir tane aç ya da bir desk\'i PR\'a yükselt.';
  @override
  String get remoteIssuesLinkLocalOnly =>
      'Uzak issue\'lar yalnızca yerel PR\'lara bağlanabilir. Önce bir desk\'i PR\'a yükselt.';
  @override
  String linkIssueToPrs({required Object number}) =>
      'Issue #${number} ile PR\'ları bağla';
  @override
  String couldntToggleLink({required Object error}) =>
      'Bağlantı değiştirilemedi: ${error}';
  @override
  String get openPatchDialogTitle => 'Yama aç (.patch / .diff)';
  @override
  String get clipboardNoText => 'Panoda metin yok.';
  @override
  String get clipboardPatchLabel => 'clipboard.patch';
  @override
  String failedToOpenPatch({required Object error}) =>
      'Yama açılamadı: ${error}';
  @override
  String get patchEmptyOrUnparseable => 'Yama boş ya da ayrıştırılamıyor.';
  @override
  String get prPushedToForge => 'PR forge\'a gönderildi.';
  @override
  String overwriteRefConfirm({required Object ref}) =>
      '${ref}, uzaktaki en son sürümle üzerine yazılsın mı?';
  @override
  String get overwrite => 'Üzerine yaz';
  @override
  String get loadingBranchesTitle => 'Dallar yükleniyor';
  @override
  String get loadingBranchesMessage => 'Yerel dallar ve etiketler okunuyor.';
  @override
  String get branchesUnavailableTitle => 'Dallar kullanılamıyor';
  @override
  String get filterPullRequestsHint => 'pull request\'leri filtrele…';
  @override
  String get filterIssuesHint => 'issue\'ları filtrele…';
  @override
  String get branchNameHint => 'dal adı';
  @override
  String get tagsNewestFirst => 'etiketler, en yeni önce';
  @override
  String get tagsOldestFirst => 'etiketler, en eski önce';
  @override
  String get flipSortDirection => 'sıralama yönünü ters çevir';
  @override
  String get readingPullRequests => 'Pull request\'ler okunuyor…';
  @override
  String get noOpenPullRequests => 'Açık pull request yok';
  @override
  String get noPullRequestsHint => 'Bir daldan aç ya da bir desk\'i yükselt.';
  @override
  String get noPrsMatchFilters => 'Bu filtrelere uyan PR yok';
  @override
  String get toggleFiltersRowAbove => 'Üstteki satırdaki filtreleri kapat.';
  @override
  String get issuesNewestFirst => 'issue\'lar, en yeni önce';
  @override
  String get issuesOldestFirst => 'issue\'lar, en eski önce';
  @override
  String get issuesHeading => 'ISSUE\'LAR';
  @override
  String get readingIssuesLower => 'issue\'lar okunuyor…';
  @override
  String get noOpenIssues => 'Açık issue yok';
  @override
  String get noIssuesHint => 'İş ve hataları izlemek için + yeni.';
  @override
  String get nothingMatches => 'Eşleşme yok';
  @override
  String get toggleFiltersAbove => 'Üstteki filtreleri kapat.';
  @override
  String get bucketFresh => 'TAZE';
  @override
  String get bucketThisWeek => 'BU HAFTA';
  @override
  String get bucketStalled => 'TIKANMIŞ';
  @override
  String get bucketOlder => 'DAHA ESKİ';
  @override
  String get couldNotResolveMainWorktree =>
      'Ana çalışma ağacının yolu çözümlenemedi.';
  @override
  String couldntSubmitReview({required Object error}) =>
      'İnceleme gönderilemedi: ${error}';
  @override
  String get reviewAiNotAvailable => 'İnceleme AI\'ı henüz kullanılamıyor.';
  @override
  String get noReviewModelConfigured => 'İnceleme modeli yapılandırılmadı.';
  @override
  String get deskFallback => 'desk';
  @override
  String deskUncommittedChanges({
    required num n,
    required Object branch,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
    n,
    one:
        '${branch} dalında ${n} commit edilmemiş değişiklik var — önce commit et ya da zulaya al.',
    other:
        '${branch} dalında ${n} commit edilmemiş değişiklik var — önce commit et ya da zulaya al.',
  );
  @override
  String get targetDeskNoBranch => 'Hedef desk\'in dalı yok.';
  @override
  String mergePrIntoDesk({required Object number, required Object branch}) =>
      'PR #${number}, ${branch} dalına merge et';
  @override
  String get conflictCheckUnavailableVersion =>
      'Çakışma kontrolü kullanılamıyor — git 2.38+ gerekli';
  @override
  String get conflictCheckUnavailable => 'Çakışma kontrolü kullanılamıyor';
  @override
  String willConflictFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: 'ÇAKIŞACAK · ${n} dosya',
        other: 'ÇAKIŞACAK · ${n} dosya',
      );
  @override
  String plusMore({required Object n}) => '+${n} daha';
  @override
  String get rebase => 'Rebase';
  @override
  String get squash => 'Squash';
  @override
  String get mergeCommit => 'Merge commit';
  @override
  String noDeskForBranch({required Object branch}) =>
      '${branch} dalı için desk bulunamadı';
  @override
  String get mergeAnyway => 'Yine de merge et';
  @override
  String get readingIssues => 'Issue\'lar okunuyor…';
  @override
  String get openUpstreamOrLocal =>
      'Upstream\'de bir tane aç ya da yerel bir tane aç.';
  @override
  String get noIssuesMatchFilters => 'Bu filtrelere uyan issue yok';
  @override
  String couldntCreateIssue({required Object error}) =>
      'Issue oluşturulamadı: ${error}';
  @override
  String get promoteToRemote => 'Uzağa yükselt';
  @override
  String get pushToRemote => 'Uzağa push et';
  @override
  String get pullFromRemote => 'Uzaktan pull et';
  @override
  String get import => 'İçe aktar';
  @override
  String get linkToPr => 'PR\'a bağla…';
  @override
  String get abandon => 'Bırak';
  @override
  String get issuePromotedToRemote => 'Issue uzağa yükseltildi.';
  @override
  String get issuePushedToRemote => 'Uzağa gönderildi.';
  @override
  String get issuePulledFromRemote => 'Uzaktan çekildi.';
  @override
  String issueImportedLocally({required Object number}) =>
      '#${number} yerel olarak içe aktarıldı.';
  @override
  String get abandonIssueTitle => 'Issue\'yu bırak';
  @override
  String abandonIssueMessage({required Object id}) =>
      'Yerel issue #${id} kalıcı olarak kaldırılsın mı? Bu, referansını siler ve geri alınamaz.';
  @override
  String couldntAbandon({required Object error}) => 'Bırakılamadı: ${error}';
  @override
  String couldntPostComment({required Object error}) =>
      'Yorum gönderilemedi: ${error}';
  @override
  String couldntCloseIssue({required Object error}) =>
      'Issue kapatılamadı: ${error}';
  @override
  String couldntAddLabel({required Object error}) =>
      'Etiket eklenemedi: ${error}';
  @override
  String get lensBranches => 'DALLAR';
  @override
  String get lensPrs => 'PR\'lar';
  @override
  String get patchUp => '↑ patch';
  @override
  String get syncRibbon => '⇅ eşitle';
  @override
  String get kbHeading => 'KLAVYE';
  @override
  String get kbNavigateRows => 'satırlarda gez';
  @override
  String get kbExpandCollapse => 'odaklı satırı genişlet / daralt';
  @override
  String get kbCheckoutPr => 'odaklı PR\'ı yerel olarak checkout et';
  @override
  String get kbApproveReview => 'onayla · incele';
  @override
  String get kbRequestChanges => 'değişiklik iste';
  @override
  String get kbFocusSearch => 'aramaya odaklan';
  @override
  String get kbSwitchLens => 'lens değiştir (dallar · pr\'lar)';
  @override
  String get kbToggleOverlay => 'bu katmanı aç/kapa';
  @override
  String get kbPressToDismiss => 'kapatmak için herhangi bir yere bas';
  @override
  String get overrideScarTooltip =>
      'başarısız kontrollerle ya da onaylayan bir inceleme olmadan birleştirildi — önce ateş altında incele';
  @override
  String filesOverlapUncommitted({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} dosya, commit edilmemiş çalışmanla örtüşüyor',
        other: '${n} dosya, commit edilmemiş çalışmanla örtüşüyor',
      );
  @override
  String collisionPrShared({required num n, required Object pr}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '#${pr}  (${n} dosya)',
        other: '#${pr}  (${n} dosya)',
      );
  @override
  String get prStateDraft => 'TASLAK';
  @override
  String get localBadge => 'YEREL';
  @override
  String get myReviewPending => 'incelemen bekliyor';
  @override
  String get myReviewApproved => 'sen ✓';
  @override
  String get myReviewChangesRequested => 'sen ✗ değişiklik istedin';
  @override
  String get myReviewCommented => 'sen yorum yaptın';
  @override
  String get myReviewDefault => 'sen';
  @override
  String tailCommentsAuthor({required Object count}) =>
      '${count} yorum · sonuncusu yazardan gösteriliyor';
  @override
  String get tailLastComment => 'son yorum';
  @override
  String tailLastReviewState({required Object state}) =>
      'son inceleme · ${state}';
  @override
  String get tailLastReview => 'son inceleme';
  @override
  String tailLastCheckState({required Object state}) =>
      'son kontrol · ${state}';
  @override
  String get tailLastCommit => 'son commit';
  @override
  String get tailLastActivity => 'son etkinlik';
  @override
  String worklineClosesIssues({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} issue\'yu kapatır — atlamak için tıkla',
        other: '${n} issue\'yu kapatır — atlamak için tıkla',
      );
  @override
  String worklineAddressedByPrs({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} PR tarafından ele alınıyor — atlamak için tıkla',
        other: '${n} PR tarafından ele alınıyor — atlamak için tıkla',
      );
  @override
  String get checksLabel => 'kontroller';
  @override
  String get reviewersLabel => 'inceleyiciler';
  @override
  String get conflictsLabel => 'çakışmalar';
  @override
  String exportFailed({required Object error}) =>
      'Dışa aktarma başarısız: ${error}';
  @override
  String get readingFiles => 'dosyalar okunuyor…';
  @override
  String get noDetailAvailable => 'ayrıntı yok';
  @override
  String get noFilesReported => 'dosya bildirilmedi';
  @override
  String get readingGitHistory => 'git geçmişi okunuyor…';
  @override
  String get knowsThisCode => 'bu kodu biliyor';
  @override
  String commitsOnFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: 'son bir yılda bu dosyalarda ${n} commit',
        other: 'son bir yılda bu dosyalarda ${n} commit',
      );
  @override
  String get willFight => 'SAVAŞACAK';
  @override
  String orbitalPartnerCos({required Object cos}) =>
      'yörünge ortağı — cos ${cos}';
  @override
  String get orbitLabel => 'yörünge';
  @override
  String get touchesYourLocalWork => 'YEREL ÇALIŞMANA DOKUNUYOR';
  @override
  String get mergingWillConflict =>
      'birleştirme muhtemelen commit edilmemiş değişikliklerinle çakışacak';
  @override
  String get closesHeading => 'KAPATIR';
  @override
  String get filesHeading => 'DOSYALAR';
  @override
  String get orientAligned => 'hizalı';
  @override
  String get orientAdjacent => 'bitişik';
  @override
  String get orientOrthogonal => 'dik';
  @override
  String shapeField({required Object v}) => 'alan ${v}';
  @override
  String shapeSource({required Object v}) => 'kaynak ${v}';
  @override
  String shapeSrcDelta({required Object v}) => 'kaynakΔ ${v}';
  @override
  String shapeFldDelta({required Object v}) => 'alanΔ ${v}';
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
  String shapeStress({required Object v}) => 'gerilim ${v}';
  @override
  String shapeWit({required Object v}) => 'wit ${v}';
  @override
  String resonanceReadout({required Object v}) => 'rezonans ${v}';
  @override
  String ghostFileTooltip({required Object path}) =>
      'genellikle bu PR\'daki dosyalarla hareket eder\n(${path})';
  @override
  String get prStateDraftLower => 'taslak';
  @override
  String get keystoneTooltip => 'kilit taşı — repo geneli köprü dosya';
  @override
  String get reviewNoteHint => 'bir not bırak (isteğe bağlı)…';
  @override
  String get reviewComment => 'yorum';
  @override
  String get reviewRequestChanges => 'değişiklik iste';
  @override
  String get reviewApprove => '✓ onayla';
  @override
  String get actionPatchDown => '↓ patch';
  @override
  String get actionPrReview => '✦ pr inceleme';
  @override
  String get actionOpenAsDesk => '⊞ desk olarak aç';
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
  String get deleteBranchAfter => 'sonrasında dalı sil';
  @override
  String checkDurationSec({required Object n}) => '${n}sn';
  @override
  String checkDurationMin({required Object m, required Object s}) =>
      '${m}dk ${s}sn';
  @override
  String assignedTo({required Object names}) => 'atanan: ${names}';
  @override
  String issueConvLine({required Object n, required Object time}) =>
      '${n} sohbet · ${time}';
  @override
  String get readingThread => 'ileti dizisi okunuyor…';
  @override
  String get addressedByHeading => 'ELE ALAN';
  @override
  String get descriptionHeading => 'AÇIKLAMA';
  @override
  String get threadHeading => 'İLETİ DİZİSİ';
  @override
  String get replyHint => 'yanıtla…';
  @override
  String get assignMe => 'beni ata';
  @override
  String get closeLower => 'kapat';
  @override
  String get postReply => '↩ gönder';
  @override
  String get remoteProviderUnavailable => 'Uzak sağlayıcı kullanılamıyor';
  @override
  String get noRecognisedRemoteHost =>
      'Bu repo için tanınan uzak ana bilgisayar yok.';
  @override
  String get corpseGone => 'gitti';
  @override
  String get corpseAbsorbed => 'soğuruldu';
  @override
  String get corpseSquashed => 'squash\'landı';
  @override
  String absorbedDeliveredIn({required Object hash}) =>
      '${hash} içinde teslim edildi';
  @override
  String get absorbedNoChanges => 'birleştirme değişiklik eklemiyor';
  @override
  String get corpseTagUpstreamGone => 'upstream gitti';
  @override
  String corpseTagAbsorbed({required Object receipt}) =>
      'soğuruldu, ${receipt}';
  @override
  String get corpseTagSquashed => 'squash\'lanıp birleştirildi';
  @override
  String semanticsCurrentBranch({required Object name}) =>
      '${name}, geçerli dal';
  @override
  String semanticsTracking({required Object name, required Object upstream}) =>
      '${name}, ${upstream} izleniyor';
  @override
  String semanticsLabelWithTag({required Object label, required Object tag}) =>
      '${label}, ${tag}';
  @override
  String semanticsWorktreeOpen({required Object label}) =>
      '${label}, çalışma ağacı açık';
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
  String get crossLinkPrDraft => 'PR · taslak';
  @override
  String issueChipCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} issue',
        other: '${n} issue',
      );
  @override
  String get headBadge => 'HEAD';
  @override
  String trackingLine({required Object upstream}) => '→ izleniyor: ${upstream}';
  @override
  String get checkoutButton => 'Checkout';
  @override
  String get createBranch => 'Dal oluştur';
  @override
  String get newBranchName => 'Yeni dal adı';
  @override
  String newBranchNameError({required Object error}) =>
      'Yeni dal adı — ${error}';
  @override
  String get forceDelete => 'Zorla?';
  @override
  String get annotated => 'açıklamalı';
  @override
  String get applyCheckFailed => 'apply --check başarısız';
  @override
  String get openPatchFrom => 'YAMAYI ŞURADAN AÇ';
  @override
  String get patchFromFile => 'dosyadan…';
  @override
  String get patchFromFileHint => '.patch / .diff';
  @override
  String get patchFromClipboard => 'panodan';
  @override
  String get patchFromClipboardHint => 'metin yapıştır';
  @override
  String get patchPreviewHeading => 'YAMA ÖNİZLEMESİ';
  @override
  String patchDiffSummary({
    required Object files,
    required Object adds,
    required Object dels,
  }) => '${files}  ·  +${adds}  −${dels}';
  @override
  String get stagedDone => 'hazırlandı.';
  @override
  String get appliedDone => 'uygulandı.';
  @override
  String get opening => 'açılıyor…';
  @override
  String get mergeEditor => '⇋ merge editörü';
  @override
  String get staging => 'hazırlanıyor…';
  @override
  String get applying => 'uygulanıyor…';
  @override
  String get stage => 'hazırla';
  @override
  String get apply => 'uygula';
  @override
  String get refineHint =>
      'iyileştir… (örn. "logger değişikliklerini de çıkar")';
  @override
  String get reverseArmedTooltip =>
      'hazır — sonraki uygulama yamayı GERİ ALIR (-R)';
  @override
  String get reverseDisarmedTooltip =>
      'tersine çevirmeyi hazırla (-R) — uygulamak yerine geri al';
  @override
  String get reverseArmedLabel => '⟲ tersine ✓';
  @override
  String get reverseLabel => '⟲ tersine';
  @override
  String get untouchedHeading => '⚠ DOKUNULMAMIŞ';
  @override
  String untouchedFiles({required num n, required Object count}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} dosyadan ${count} tanesi yamada değil',
        other: '${n} dosyadan ${count} tanesi yamada değil',
      );
  @override
  String get staysConflicted =>
      'bu dosyalar çakışmalı kalacak — uygulama onları hazırlamaz';
  @override
  String get orWith => 'YA DA ŞUNUNLA';
  @override
  String get noAiModelConfigured => 'AI modeli yapılandırılmadı';
  @override
  String applyWithPatchFrom({required Object label}) =>
      '${label} yamasıyla uygula';
  @override
  String applyWithPatchFromModel({
    required Object label,
    required Object model,
  }) => '${label} yamasıyla uygula  ·  ${model}';
  @override
  String get patching => 'yama uygulanıyor…';
  @override
  String applyWithPatchFromGlyph({required Object label}) =>
      '✦  ${label} yamasıyla uygula';
  @override
  String get orWithAnotherModel => 'ya da başka bir modelle';
  @override
  String get applyCheckPassed =>
      'git apply --check geçti — yama temiz uygulanacak';
  @override
  String get gitApplyCheckFailed => 'git apply --check başarısız';
  @override
  String get appliesClean => 'temiz uygulanır';
  @override
  String get willNotApply => 'uygulanmayacak';
  @override
  String get newLocalIssue => 'yeni yerel issue';
  @override
  String get filterHint => 'filtrele…';
  @override
  String get nothingToLink => 'Henüz bağlanacak bir şey yok.';
  @override
  String get nothingMatchesDot => 'Eşleşme yok.';
  @override
  String get relevantHeading => 'İLGİLİ';
  @override
  String get allHeading => 'TÜMÜ';
  @override
  String get doneLower => 'tamam';
  @override
  String get candidateRemote => 'R';
  @override
  String get candidateLocal => 'L';
  @override
  String get newLocalIssueTitle => 'Yeni yerel issue';
  @override
  String get titleHint => 'başlık';
  @override
  String get bodyHint => 'gövde (markdown)';
  @override
  String get cancelLower => 'iptal';
  @override
  String get createLower => 'oluştur';
  @override
  String get deleteFailed => 'silme başarısız';
  @override
  String reviewFailed({required Object error}) =>
      'İnceleme başarısız: ${error}';
  @override
  String get resolutionFailed => 'çözüm başarısız';
  @override
  String get patchBlocksNoCover =>
      'model, başarısız dosyaları kapsamayan yama blokları döndürdü';
  @override
  String get applyFailed => 'uygulama başarısız';
  @override
  String get emptyOrUnparseablePatch =>
      'model boş ya da ayrıştırılamayan bir yama döndürdü';
  @override
  String noModelConfiguredFor({required Object label}) =>
      '"${label}" için model yapılandırılmadı';
  @override
  String get checksHeading => 'KONTROLLER';
  @override
  String get peopleHeading => 'KİŞİLER';
  @override
  String get conversationHeading => 'KONUŞMA';
}

// Path: changes
class _Translations$changes$tr extends Translations$changes$en {
  _Translations$changes$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$usage$tr usage =
      _Translations$changes$usage$tr._(_root);
  @override
  late final _Translations$changes$tabs$tr tabs =
      _Translations$changes$tabs$tr._(_root);
  @override
  late final _Translations$changes$tabStrip$tr tabStrip =
      _Translations$changes$tabStrip$tr._(_root);
  @override
  late final _Translations$changes$select$tr select =
      _Translations$changes$select$tr._(_root);
  @override
  late final _Translations$changes$constellationToggle$tr constellationToggle =
      _Translations$changes$constellationToggle$tr._(_root);
  @override
  late final _Translations$changes$nudgeChip$tr nudgeChip =
      _Translations$changes$nudgeChip$tr._(_root);
  @override
  late final _Translations$changes$minimap$tr minimap =
      _Translations$changes$minimap$tr._(_root);
  @override
  late final _Translations$changes$tagInput$tr tagInput =
      _Translations$changes$tagInput$tr._(_root);
  @override
  late final _Translations$changes$composer$tr composer =
      _Translations$changes$composer$tr._(_root);
  @override
  late final _Translations$changes$commit$tr commit =
      _Translations$changes$commit$tr._(_root);
  @override
  late final _Translations$changes$rebase$tr rebase =
      _Translations$changes$rebase$tr._(_root);
  @override
  late final _Translations$changes$editor$tr editor =
      _Translations$changes$editor$tr._(_root);
  @override
  late final _Translations$changes$editorTitles$tr editorTitles =
      _Translations$changes$editorTitles$tr._(_root);
  @override
  late final _Translations$changes$askHint$tr askHint =
      _Translations$changes$askHint$tr._(_root);
  @override
  late final _Translations$changes$fileMenu$tr fileMenu =
      _Translations$changes$fileMenu$tr._(_root);
  @override
  late final _Translations$changes$multiFileMenu$tr multiFileMenu =
      _Translations$changes$multiFileMenu$tr._(_root);
  @override
  late final _Translations$changes$ignoreMenu$tr ignoreMenu =
      _Translations$changes$ignoreMenu$tr._(_root);
  @override
  late final _Translations$changes$discard$tr discard =
      _Translations$changes$discard$tr._(_root);
  @override
  late final _Translations$changes$snack$tr snack =
      _Translations$changes$snack$tr._(_root);
  @override
  late final _Translations$changes$trace$tr trace =
      _Translations$changes$trace$tr._(_root);
  @override
  late final _Translations$changes$cleanTree$tr cleanTree =
      _Translations$changes$cleanTree$tr._(_root);
  @override
  late final _Translations$changes$guardrail$tr guardrail =
      _Translations$changes$guardrail$tr._(_root);
  @override
  late final _Translations$changes$dropHint$tr dropHint =
      _Translations$changes$dropHint$tr._(_root);
  @override
  late final _Translations$changes$diffEmpty$tr diffEmpty =
      _Translations$changes$diffEmpty$tr._(_root);
  @override
  late final _Translations$changes$shelvePill$tr shelvePill =
      _Translations$changes$shelvePill$tr._(_root);
  @override
  late final _Translations$changes$stashAction$tr stashAction =
      _Translations$changes$stashAction$tr._(_root);
  @override
  late final _Translations$changes$stashContents$tr stashContents =
      _Translations$changes$stashContents$tr._(_root);
  @override
  late final _Translations$changes$stashFile$tr stashFile =
      _Translations$changes$stashFile$tr._(_root);
  @override
  late final _Translations$changes$fileRow$tr fileRow =
      _Translations$changes$fileRow$tr._(_root);
  @override
  late final _Translations$changes$resolveStrip$tr resolveStrip =
      _Translations$changes$resolveStrip$tr._(_root);
  @override
  late final _Translations$changes$badge$tr badge =
      _Translations$changes$badge$tr._(_root);
  @override
  late final _Translations$changes$review$tr review =
      _Translations$changes$review$tr._(_root);
  @override
  late final _Translations$changes$commitBtn$tr commitBtn =
      _Translations$changes$commitBtn$tr._(_root);
  @override
  late final _Translations$changes$shapeBtn$tr shapeBtn =
      _Translations$changes$shapeBtn$tr._(_root);
  @override
  late final _Translations$changes$dejaVu$tr dejaVu =
      _Translations$changes$dejaVu$tr._(_root);
  @override
  late final _Translations$changes$identity$tr identity =
      _Translations$changes$identity$tr._(_root);
  @override
  late final _Translations$changes$staleScope$tr staleScope =
      _Translations$changes$staleScope$tr._(_root);
  @override
  late final _Translations$changes$finding$tr finding =
      _Translations$changes$finding$tr._(_root);
  @override
  late final _Translations$changes$muse$tr muse =
      _Translations$changes$muse$tr._(_root);
  @override
  late final _Translations$changes$debug$tr debug =
      _Translations$changes$debug$tr._(_root);
  @override
  late final _Translations$changes$includeSummary$tr includeSummary =
      _Translations$changes$includeSummary$tr._(_root);
  @override
  late final _Translations$changes$status$tr status =
      _Translations$changes$status$tr._(_root);
  @override
  late final _Translations$changes$stash$tr stash =
      _Translations$changes$stash$tr._(_root);
  @override
  late final _Translations$changes$tooltips$tr tooltips =
      _Translations$changes$tooltips$tr._(_root);
  @override
  late final _Translations$changes$mergeEditor$tr mergeEditor =
      _Translations$changes$mergeEditor$tr._(_root);
  @override
  late final _Translations$changes$conflictResolution$tr conflictResolution =
      _Translations$changes$conflictResolution$tr._(_root);
  @override
  late final _Translations$changes$mergeFlow$tr mergeFlow =
      _Translations$changes$mergeFlow$tr._(_root);
  @override
  late final _Translations$changes$constellation$tr constellation =
      _Translations$changes$constellation$tr._(_root);
}

// Path: common
class _Translations$common$tr extends Translations$common$en {
  _Translations$common$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get listSeparator => ', ';
  @override
  String get cancel => 'İptal';
  @override
  String get close => 'Kapat';
  @override
  String get save => 'Kaydet';
  @override
  String get delete => 'Sil';
  @override
  String get retry => 'Yeniden dene';
  @override
  String get copy => 'Kopyala';
  @override
  String get copied => 'Kopyalandı';
  @override
  String get done => 'Tamam';
  @override
  String get loading => 'Yükleniyor…';
  @override
  String fileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} dosya',
        other: '${n} dosya',
      );
  @override
  String commitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} commit',
        other: '${n} commit',
      );
  @override
  String branchCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} dal',
        other: '${n} dal',
      );
  @override
  String localCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} yerel commit',
        other: '${n} yerel commit',
      );
  @override
  String remoteCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} uzak commit',
        other: '${n} uzak commit',
      );
  @override
  String conflictedFileCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} çakışan dosya',
        other: '${n} çakışan dosya',
      );
  @override
  late final _Translations$common$time$tr time = _Translations$common$time$tr._(
    _root,
  );
  @override
  late final _Translations$common$size$tr size = _Translations$common$size$tr._(
    _root,
  );
}

// Path: diff
class _Translations$diff$tr extends Translations$diff$en {
  _Translations$diff$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$diff$status$tr status =
      _Translations$diff$status$tr._(_root);
  @override
  late final _Translations$diff$toolbar$tr toolbar =
      _Translations$diff$toolbar$tr._(_root);
  @override
  late final _Translations$diff$hunkDropdown$tr hunkDropdown =
      _Translations$diff$hunkDropdown$tr._(_root);
  @override
  String stagingFailed({required Object error}) =>
      'Kısmi hazırlama başarısız: ${error}';
  @override
  late final _Translations$diff$trail$tr trail = _Translations$diff$trail$tr._(
    _root,
  );
  @override
  late final _Translations$diff$pinned$tr pinned =
      _Translations$diff$pinned$tr._(_root);
  @override
  late final _Translations$diff$hunkHint$tr hunkHint =
      _Translations$diff$hunkHint$tr._(_root);
  @override
  late final _Translations$diff$binary$tr binary =
      _Translations$diff$binary$tr._(_root);
  @override
  late final _Translations$diff$media$tr media = _Translations$diff$media$tr._(
    _root,
  );
}

// Path: filament
class _Translations$filament$tr extends Translations$filament$en {
  _Translations$filament$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get noRepositoryOpen => 'Açık depo yok.';
  @override
  String scanningProgress({required Object scanned, required Object total}) =>
      '${scanned} / ${total} dosya taranıyor…';
  @override
  String findingsAcrossFiles({required Object files, required Object count}) =>
      '${files} dosyada ${count} bulgu';
  @override
  String copiedFindings({required Object count}) => '${count} bulgu kopyalandı';
  @override
  String get copy => 'KOPYALA';
  @override
  String get noFindings => 'Yürütme akışı bulgusu yok.';
  @override
  late final _Translations$filament$severity$tr severity =
      _Translations$filament$severity$tr._(_root);
  @override
  late final _Translations$filament$kind$tr kind =
      _Translations$filament$kind$tr._(_root);
  @override
  String lineLabel({required Object line}) => 'S${line}';
  @override
  String findingSourceWithKind({
    required Object source,
    required Object kind,
  }) => '${source} — ${kind}';
}

// Path: history
class _Translations$history$tr extends Translations$history$en {
  _Translations$history$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$tr commitLede =
      _Translations$history$commitLede$tr._(_root);
  @override
  late final _Translations$history$seismograph$tr seismograph =
      _Translations$history$seismograph$tr._(_root);
  @override
  late final _Translations$history$worldline$tr worldline =
      _Translations$history$worldline$tr._(_root);
  @override
  late final _Translations$history$contextMenu$tr contextMenu =
      _Translations$history$contextMenu$tr._(_root);
  @override
  late final _Translations$history$cherryPick$tr cherryPick =
      _Translations$history$cherryPick$tr._(_root);
  @override
  late final _Translations$history$revert$tr revert =
      _Translations$history$revert$tr._(_root);
  @override
  late final _Translations$history$reflog$tr reflog =
      _Translations$history$reflog$tr._(_root);
  @override
  String revealCeilingExceeded({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: 'O commit, yüklenen ${n} commit\'ten daha derinde.',
        other: 'O commit, yüklenen ${n} commit\'ten daha derinde.',
      );
  @override
  String deleteTagFailed({required Object error}) =>
      'Etiket silinemedi: ${error}';
  @override
  String get loadingTitle => 'Geçmiş yükleniyor';
  @override
  String get loadingMessage => 'Son commit\'ler okunuyor.';
  @override
  String get unavailableTitle => 'Geçmiş kullanılamıyor';
  @override
  String get toggleWorldline => 'Dünya çizgisini aç/kapa';
  @override
  String get pageTitle => 'Geçmiş';
  @override
  String get viewingLast => 'Son';
  @override
  String get commitsUnit => 'commit görüntüleniyor';
  @override
  String get noCommitSelectedTitle => 'Commit seçilmedi';
  @override
  String get noCommitSelectedMessage =>
      'Değişikliklerini incelemek için bir commit seç.';
  @override
  String get loadingCommitTitle => 'Commit yükleniyor';
  @override
  String get loadingCommitMessage => 'Commit ayrıntıları okunuyor.';
  @override
  String get commitUnavailableTitle => 'Commit kullanılamıyor';
  @override
  String get couldNotLoadCommit => 'Commit yüklenemedi.';
  @override
  String get reflogDividerLabel => 'reflog';
  @override
  String get loadReflog => 'Reflog yükle';
  @override
  String get createTag => 'Etiket oluştur';
  @override
  String get newTagName => 'Yeni etiket adı';
  @override
  String newTagNameError({required Object error}) =>
      'Yeni etiket adı — ${error}';
  @override
  String allFilesHeader({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} dosya · tüm değişiklikler',
        other: '${n} dosya · tüm değişiklikler',
      );
  @override
  String get allChangesLabel => 'tüm değişiklikler';
  @override
  late final _Translations$history$rebase$tr rebase =
      _Translations$history$rebase$tr._(_root);
  @override
  late final _Translations$history$inFlight$tr inFlight =
      _Translations$history$inFlight$tr._(_root);
}

// Path: historySurgery
class _Translations$historySurgery$tr extends Translations$historySurgery$en {
  _Translations$historySurgery$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$historySurgery$chrome$tr chrome =
      _Translations$historySurgery$chrome$tr._(_root);
  @override
  late final _Translations$historySurgery$select$tr select =
      _Translations$historySurgery$select$tr._(_root);
  @override
  late final _Translations$historySurgery$understand$tr understand =
      _Translations$historySurgery$understand$tr._(_root);
  @override
  late final _Translations$historySurgery$confirm$tr confirm =
      _Translations$historySurgery$confirm$tr._(_root);
  @override
  late final _Translations$historySurgery$execute$tr execute =
      _Translations$historySurgery$execute$tr._(_root);
  @override
  late final _Translations$historySurgery$verify$tr verify =
      _Translations$historySurgery$verify$tr._(_root);
  @override
  late final _Translations$historySurgery$forcePush$tr forcePush =
      _Translations$historySurgery$forcePush$tr._(_root);
}

// Path: onboarding
class _Translations$onboarding$tr extends Translations$onboarding$en {
  _Translations$onboarding$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$nav$tr nav =
      _Translations$onboarding$nav$tr._(_root);
  @override
  late final _Translations$onboarding$naming$tr naming =
      _Translations$onboarding$naming$tr._(_root);
  @override
  late final _Translations$onboarding$theme$tr theme =
      _Translations$onboarding$theme$tr._(_root);
  @override
  late final _Translations$onboarding$repo$tr repo =
      _Translations$onboarding$repo$tr._(_root);
  @override
  late final _Translations$onboarding$preview$tr preview =
      _Translations$onboarding$preview$tr._(_root);
}

// Path: orrery
class _Translations$orrery$tr extends Translations$orrery$en {
  _Translations$orrery$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$orrery$header$tr header =
      _Translations$orrery$header$tr._(_root);
  @override
  late final _Translations$orrery$status$tr status =
      _Translations$orrery$status$tr._(_root);
  @override
  late final _Translations$orrery$legend$tr legend =
      _Translations$orrery$legend$tr._(_root);
  @override
  late final _Translations$orrery$node$tr node = _Translations$orrery$node$tr._(
    _root,
  );
  @override
  late final _Translations$orrery$milestone$tr milestone =
      _Translations$orrery$milestone$tr._(_root);
  @override
  late final _Translations$orrery$structure$tr structure =
      _Translations$orrery$structure$tr._(_root);
  @override
  late final _Translations$orrery$rail$tr rail = _Translations$orrery$rail$tr._(
    _root,
  );
  @override
  late final _Translations$orrery$selection$tr selection =
      _Translations$orrery$selection$tr._(_root);
  @override
  late final _Translations$orrery$findingKind$tr findingKind =
      _Translations$orrery$findingKind$tr._(_root);
  @override
  late final _Translations$orrery$findings$tr findings =
      _Translations$orrery$findings$tr._(_root);
  @override
  late final _Translations$orrery$anchor$tr anchor =
      _Translations$orrery$anchor$tr._(_root);
  @override
  late final _Translations$orrery$compare$tr compare =
      _Translations$orrery$compare$tr._(_root);
}

// Path: palette
class _Translations$palette$tr extends Translations$palette$en {
  _Translations$palette$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get active => 'etkin';
  @override
  late final _Translations$palette$prefixes$tr prefixes =
      _Translations$palette$prefixes$tr._(_root);
  @override
  late final _Translations$palette$chips$tr chips =
      _Translations$palette$chips$tr._(_root);
  @override
  late final _Translations$palette$predictive$tr predictive =
      _Translations$palette$predictive$tr._(_root);
  @override
  late final _Translations$palette$topTouched$tr topTouched =
      _Translations$palette$topTouched$tr._(_root);
  @override
  late final _Translations$palette$coherence$tr coherence =
      _Translations$palette$coherence$tr._(_root);
  @override
  late final _Translations$palette$keystone$tr keystone =
      _Translations$palette$keystone$tr._(_root);
  @override
  late final _Translations$palette$repoSub$tr repoSub =
      _Translations$palette$repoSub$tr._(_root);
  @override
  late final _Translations$palette$desks$tr desks =
      _Translations$palette$desks$tr._(_root);
  @override
  late final _Translations$palette$actions$tr actions =
      _Translations$palette$actions$tr._(_root);
  @override
  late final _Translations$palette$tools$tr tools =
      _Translations$palette$tools$tr._(_root);
  @override
  late final _Translations$palette$gitCommands$tr gitCommands =
      _Translations$palette$gitCommands$tr._(_root);
  @override
  late final _Translations$palette$pr$tr pr = _Translations$palette$pr$tr._(
    _root,
  );
  @override
  late final _Translations$palette$ai$tr ai = _Translations$palette$ai$tr._(
    _root,
  );
  @override
  late final _Translations$palette$undo$tr undo =
      _Translations$palette$undo$tr._(_root);
  @override
  late final _Translations$palette$navigation$tr navigation =
      _Translations$palette$navigation$tr._(_root);
  @override
  late final _Translations$palette$settings$tr settings =
      _Translations$palette$settings$tr._(_root);
  @override
  late final _Translations$palette$info$tr info =
      _Translations$palette$info$tr._(_root);
  @override
  late final _Translations$palette$debug$tr debug =
      _Translations$palette$debug$tr._(_root);
  @override
  late final _Translations$palette$dev$tr dev = _Translations$palette$dev$tr._(
    _root,
  );
  @override
  late final _Translations$palette$historySurgery$tr historySurgery =
      _Translations$palette$historySurgery$tr._(_root);
  @override
  late final _Translations$palette$orrery$tr orrery =
      _Translations$palette$orrery$tr._(_root);
  @override
  late final _Translations$palette$command$tr command =
      _Translations$palette$command$tr._(_root);
  @override
  late final _Translations$palette$search$tr search =
      _Translations$palette$search$tr._(_root);
  @override
  late final _Translations$palette$wick$tr wick =
      _Translations$palette$wick$tr._(_root);
  @override
  late final _Translations$palette$gitCache$tr gitCache =
      _Translations$palette$gitCache$tr._(_root);
}

// Path: releaseNotes
class _Translations$releaseNotes$tr extends Translations$releaseNotes$en {
  _Translations$releaseNotes$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get versionFallback => 'dev';
  @override
  late final _Translations$releaseNotes$about$tr about =
      _Translations$releaseNotes$about$tr._(_root);
  @override
  late final _Translations$releaseNotes$legal$tr legal =
      _Translations$releaseNotes$legal$tr._(_root);
}

// Path: repoSummary
class _Translations$repoSummary$tr extends Translations$repoSummary$en {
  _Translations$repoSummary$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$repoSummary$backbone$tr backbone =
      _Translations$repoSummary$backbone$tr._(_root);
  @override
  late final _Translations$repoSummary$glance$tr glance =
      _Translations$repoSummary$glance$tr._(_root);
  @override
  late final _Translations$repoSummary$heading$tr heading =
      _Translations$repoSummary$heading$tr._(_root);
  @override
  String get historyStarvedCaveat =>
      'Sıralama sınırlı: bağlaşım grafiğinde kenar yoktu (taze klon ya da çok az commit). Dosya sırası, yapısal merkeziyeti değil boyutu yansıtır.';
  @override
  late final _Translations$repoSummary$pitch$tr pitch =
      _Translations$repoSummary$pitch$tr._(_root);
  @override
  late final _Translations$repoSummary$region$tr region =
      _Translations$repoSummary$region$tr._(_root);
  @override
  late final _Translations$repoSummary$shape$tr shape =
      _Translations$repoSummary$shape$tr._(_root);
}

// Path: review
class _Translations$review$tr extends Translations$review$en {
  _Translations$review$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get unresolved => 'çözülmedi';
  @override
  String get done => 'tamam';
  @override
  String get ack => 'kabul';
  @override
  String get reply => 'yanıtla';
  @override
  String get pleaseFix => 'lütfen düzelt';
  @override
  String get draft => 'taslak';
  @override
  String get engine => 'motor';
  @override
  String get moved => 'taşındı';
  @override
  String get yourTurn => 'sıra sende';
  @override
  String get drafts => 'taslaklar';
  @override
  String get publish => 'yayımla';
  @override
  String get discard => 'vazgeç';
  @override
  String get saveDraft => 'taslağı kaydet';
  @override
  String get cancel => 'iptal';
  @override
  String get verdictApprove => 'onayla';
  @override
  String get verdictRequestChanges => 'değişiklik iste';
  @override
  String get verdictComment => 'yorum';
  @override
  String get caughtUp => 'güncel';
  @override
  String get sinceLastLook => 'son bakışından beri';
  @override
  String get fullDiff => 'tam diff';
  @override
  String get commentHint => 'yorum yaz';
  @override
  String outdatedLastSeen({required Object round}) =>
      'eskimiş · son görülme R${round}';
  @override
  String resolvedByFmt({required Object verb, required Object who}) =>
      '${verb} · ${who}';
  @override
  String waitingOnFmt({required Object who}) => '${who} bekleniyor';
  @override
  String roundChip({required Object round}) => 'R${round}';
  @override
  String filesSinceLastLook({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: 'son bakışından beri 1 dosya',
        other: 'son bakışından beri ${n} dosya',
      );
  @override
  String unresolvedCountFmt({required Object n}) => '${n} çözülmedi';
  @override
  String draftCountFmt({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '1 taslak',
        other: '${n} taslak',
      );
  @override
  String startReviewFailed({required Object error}) =>
      'İnceleme başlatılamadı: ${error}';
  @override
  String get anchorUnavailable =>
      'O satır sabitlenemiyor — dosya çok büyük veya kullanılamıyor.';
  @override
  String reviewActionFailed({required Object error}) =>
      'İnceleme işlemi başarısız oldu: ${error}';
  @override
  String get lensTooLarge =>
      'Bu karşılaştırma burada gösterilemeyecek kadar büyük — tam diff\'te kalıyoruz.';
  @override
  String get lensEmpty => 'Bu anlık görüntüler arasında hiçbir şey değişmedi.';
  @override
  String get reopen => 'yeniden aç';
  @override
  String get notBlocking => 'beni beklemeyin';
  @override
  String get markReviewed => 'okundu';
  @override
  String newComments({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '1 yeni yorum',
        other: '${n} yeni yorum',
      );
  @override
  String get handTo => 'devret';
  @override
  String get heading => 'İNCELEME';
  @override
  String get identityNeeded => 'İnceleme yapmak için bir git kimliği ayarlayın';
  @override
  String get fileUnreadable =>
      'Bu dosya burada okunamıyor — çok büyük ya da bu turda mevcut değil.';
  @override
  String get timeNow => 'şimdi';
  @override
  String timeMinutesFmt({required Object n}) => '${n} dk';
  @override
  String timeHoursFmt({required Object n}) => '${n} sa';
  @override
  String timeDaysFmt({required Object n}) => '${n} g';
  @override
  String get standingApproved => 'onaylandı';
  @override
  String get standingChangesRequested => 'değişiklik istendi';
  @override
  String get commentOnChange => 'Bu değişikliğe yorum yap';
  @override
  String get commentOnFile => 'Bu dosyaya yorum yap';
  @override
  String get imageNotLoaded => 'görsel yüklenmedi';
  @override
  String get nothingBlocking => 'bekleyen bir şey yok';
}

// Path: settings
class _Translations$settings$tr extends Translations$settings$en {
  _Translations$settings$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$language$tr language =
      _Translations$settings$language$tr._(_root);
  @override
  late final _Translations$settings$sectionLabels$tr sectionLabels =
      _Translations$settings$sectionLabels$tr._(_root);
  @override
  late final _Translations$settings$errors$tr errors =
      _Translations$settings$errors$tr._(_root);
  @override
  late final _Translations$settings$promptStatus$tr promptStatus =
      _Translations$settings$promptStatus$tr._(_root);
  @override
  late final _Translations$settings$clearData$tr clearData =
      _Translations$settings$clearData$tr._(_root);
  @override
  List<String> get guardrailStageLabels => [
    'Gevşek',
    'Dengeli',
    'Katı',
    'Paranoyak',
  ];
  @override
  late final _Translations$settings$guardrailMacro$tr guardrailMacro =
      _Translations$settings$guardrailMacro$tr._(_root);
  @override
  late final _Translations$settings$guardrails$tr guardrails =
      _Translations$settings$guardrails$tr._(_root);
  @override
  late final _Translations$settings$appearance$tr appearance =
      _Translations$settings$appearance$tr._(_root);
  @override
  late final _Translations$settings$retention$tr retention =
      _Translations$settings$retention$tr._(_root);
  @override
  late final _Translations$settings$navigation$tr navigation =
      _Translations$settings$navigation$tr._(_root);
  @override
  late final _Translations$settings$behaviour$tr behaviour =
      _Translations$settings$behaviour$tr._(_root);
  @override
  late final _Translations$settings$retentionClear$tr retentionClear =
      _Translations$settings$retentionClear$tr._(_root);
  @override
  late final _Translations$settings$channels$tr channels =
      _Translations$settings$channels$tr._(_root);
  @override
  late final _Translations$settings$pollResult$tr pollResult =
      _Translations$settings$pollResult$tr._(_root);
  @override
  late final _Translations$settings$keybindingProfile$tr keybindingProfile =
      _Translations$settings$keybindingProfile$tr._(_root);
  @override
  late final _Translations$settings$apiKeys$tr apiKeys =
      _Translations$settings$apiKeys$tr._(_root);
  @override
  late final _Translations$settings$shortcuts$tr shortcuts =
      _Translations$settings$shortcuts$tr._(_root);
  @override
  late final _Translations$settings$toggles$tr toggles =
      _Translations$settings$toggles$tr._(_root);
  @override
  late final _Translations$settings$diffDiffability$tr diffDiffability =
      _Translations$settings$diffDiffability$tr._(_root);
  @override
  late final _Translations$settings$modelSlots$tr modelSlots =
      _Translations$settings$modelSlots$tr._(_root);
  @override
  late final _Translations$settings$modelPicker$tr modelPicker =
      _Translations$settings$modelPicker$tr._(_root);
  @override
  late final _Translations$settings$aiFeatures$tr aiFeatures =
      _Translations$settings$aiFeatures$tr._(_root);
  @override
  late final _Translations$settings$commitEditor$tr commitEditor =
      _Translations$settings$commitEditor$tr._(_root);
  @override
  late final _Translations$settings$review$tr review =
      _Translations$settings$review$tr._(_root);
  @override
  late final _Translations$settings$museHint$tr museHint =
      _Translations$settings$museHint$tr._(_root);
  @override
  late final _Translations$settings$museEditor$tr museEditor =
      _Translations$settings$museEditor$tr._(_root);
  @override
  late final _Translations$settings$museStage$tr museStage =
      _Translations$settings$museStage$tr._(_root);
  @override
  late final _Translations$settings$lensAxis$tr lensAxis =
      _Translations$settings$lensAxis$tr._(_root);
  @override
  late final _Translations$settings$logosLens$tr logosLens =
      _Translations$settings$logosLens$tr._(_root);
  @override
  late final _Translations$settings$sortGuide$tr sortGuide =
      _Translations$settings$sortGuide$tr._(_root);
  @override
  late final _Translations$settings$piggyback$tr piggyback =
      _Translations$settings$piggyback$tr._(_root);
  @override
  late final _Translations$settings$diffStage$tr diffStage =
      _Translations$settings$diffStage$tr._(_root);
  @override
  late final _Translations$settings$undoScope$tr undoScope =
      _Translations$settings$undoScope$tr._(_root);
  @override
  late final _Translations$settings$undoWindow$tr undoWindow =
      _Translations$settings$undoWindow$tr._(_root);
  @override
  late final _Translations$settings$guardrailPhrase$tr guardrailPhrase =
      _Translations$settings$guardrailPhrase$tr._(_root);
  @override
  late final _Translations$settings$reviewGuideHint$tr reviewGuideHint =
      _Translations$settings$reviewGuideHint$tr._(_root);
  @override
  late final _Translations$settings$commitFormat$tr commitFormat =
      _Translations$settings$commitFormat$tr._(_root);
  @override
  late final _Translations$settings$commitPreview$tr commitPreview =
      _Translations$settings$commitPreview$tr._(_root);
  @override
  late final _Translations$settings$externalTools$tr externalTools =
      _Translations$settings$externalTools$tr._(_root);
  @override
  late final _Translations$settings$apiUsage$tr apiUsage =
      _Translations$settings$apiUsage$tr._(_root);
  @override
  late final _Translations$settings$gitea$tr gitea =
      _Translations$settings$gitea$tr._(_root);
  @override
  late final _Translations$settings$wick$tr wick =
      _Translations$settings$wick$tr._(_root);
  @override
  late final _Translations$settings$integrations$tr integrations =
      _Translations$settings$integrations$tr._(_root);
  @override
  late final _Translations$settings$reduceMotion$tr reduceMotion =
      _Translations$settings$reduceMotion$tr._(_root);
  @override
  late final _Translations$settings$resetQuit$tr resetQuit =
      _Translations$settings$resetQuit$tr._(_root);
  @override
  late final _Translations$settings$diagnostics$tr diagnostics =
      _Translations$settings$diagnostics$tr._(_root);
  @override
  late final _Translations$settings$telemetry$tr telemetry =
      _Translations$settings$telemetry$tr._(_root);
  @override
  late final _Translations$settings$flowEngine$tr flowEngine =
      _Translations$settings$flowEngine$tr._(_root);
  @override
  late final _Translations$settings$museStrands$tr museStrands =
      _Translations$settings$museStrands$tr._(_root);
  @override
  late final _Translations$settings$cliPiggyback$tr cliPiggyback =
      _Translations$settings$cliPiggyback$tr._(_root);
  @override
  late final _Translations$settings$header$tr header =
      _Translations$settings$header$tr._(_root);
  @override
  late final _Translations$settings$diagnosticsPanel$tr diagnosticsPanel =
      _Translations$settings$diagnosticsPanel$tr._(_root);
  @override
  late final _Translations$settings$release$tr release =
      _Translations$settings$release$tr._(_root);
  @override
  late final _Translations$settings$providerStatus$tr providerStatus =
      _Translations$settings$providerStatus$tr._(_root);
  @override
  late final _Translations$settings$meridiem$tr meridiem =
      _Translations$settings$meridiem$tr._(_root);
  @override
  late final _Translations$settings$offenders$tr offenders =
      _Translations$settings$offenders$tr._(_root);
}

// Path: sync
class _Translations$sync$tr extends Translations$sync$en {
  _Translations$sync$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$sync$actions$tr actions =
      _Translations$sync$actions$tr._(_root);
  @override
  late final _Translations$sync$panel$tr panel = _Translations$sync$panel$tr._(
    _root,
  );
  @override
  late final _Translations$sync$forcePush$tr forcePush =
      _Translations$sync$forcePush$tr._(_root);
}

// Path: xray
class _Translations$xray$tr extends Translations$xray$en {
  _Translations$xray$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$board$tr board = _Translations$xray$board$tr._(
    _root,
  );
  @override
  late final _Translations$xray$cadence$tr cadence =
      _Translations$xray$cadence$tr._(_root);
  @override
  late final _Translations$xray$cards$tr cards = _Translations$xray$cards$tr._(
    _root,
  );
  @override
  late final _Translations$xray$cardTitle$tr cardTitle =
      _Translations$xray$cardTitle$tr._(_root);
  @override
  late final _Translations$xray$grain$tr grain = _Translations$xray$grain$tr._(
    _root,
  );
  @override
  late final _Translations$xray$header$tr header =
      _Translations$xray$header$tr._(_root);
  @override
  late final _Translations$xray$hotspot$tr hotspot =
      _Translations$xray$hotspot$tr._(_root);
  @override
  late final _Translations$xray$inspector$tr inspector =
      _Translations$xray$inspector$tr._(_root);
  @override
  late final _Translations$xray$loadingCard$tr loadingCard =
      _Translations$xray$loadingCard$tr._(_root);
  @override
  late final _Translations$xray$metabolism$tr metabolism =
      _Translations$xray$metabolism$tr._(_root);
  @override
  late final _Translations$xray$multi$tr multi = _Translations$xray$multi$tr._(
    _root,
  );
  @override
  late final _Translations$xray$recency$tr recency =
      _Translations$xray$recency$tr._(_root);
  @override
  late final _Translations$xray$rings$tr rings = _Translations$xray$rings$tr._(
    _root,
  );
  @override
  late final _Translations$xray$stats$tr stats = _Translations$xray$stats$tr._(
    _root,
  );
  @override
  late final _Translations$xray$stratumLabel$tr stratumLabel =
      _Translations$xray$stratumLabel$tr._(_root);
  @override
  late final _Translations$xray$summary$tr summary =
      _Translations$xray$summary$tr._(_root);
  @override
  late final _Translations$xray$tabs$tr tabs = _Translations$xray$tabs$tr._(
    _root,
  );
  @override
  late final _Translations$xray$trajectory$tr trajectory =
      _Translations$xray$trajectory$tr._(_root);
  @override
  late final _Translations$xray$verdict$tr verdict =
      _Translations$xray$verdict$tr._(_root);
}

// Path: app.cheatsheet
class _Translations$app$cheatsheet$tr extends Translations$app$cheatsheet$en {
  _Translations$app$cheatsheet$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Klavye';
  @override
  String get sectionNavigate => 'gezin';
  @override
  String get sectionStaging => 'hazırlama';
  @override
  String get sectionBranchesPrs => 'dallar & PR\'lar';
  @override
  String get changes => 'Değişiklikler';
  @override
  String get history => 'Geçmiş';
  @override
  String get branches => 'Dallar';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Geçiş (her zaman)';
  @override
  String get commandPalette => 'Komut Paleti';
  @override
  String get elevatedPalette => 'Yükseltilmiş Palet';
  @override
  String get dismiss => 'Kapat';
  @override
  String get refresh => 'Yenile';
  @override
  String get nextPrevChange => 'Sonraki / önceki değişiklik';
  @override
  String get toggleLine => 'Satırı aç/kapa';
  @override
  String get toggleHunk => 'Hunk\'ı aç/kapa';
  @override
  String get toggleFile => 'Dosyayı aç/kapa';
  @override
  String get pinContext => 'Bağlamı sabitle';
  @override
  String get commit => 'Commit';
  @override
  String get acceptAiHint => 'AI ipucunu kabul et';
  @override
  String get undo => 'Geri al';
  @override
  String get navigate => 'Gezin';
  @override
  String get expand => 'Genişlet';
  @override
  String get checkoutPr => 'PR\'ı checkout et';
  @override
  String get approve => 'Onayla';
  @override
  String get requestChanges => 'Değişiklik iste';
  @override
  String profileSwitchHint({required Object profile}) =>
      '${profile} profili · Ayarlar\'da değiştir';
}

// Path: backend.ops
class _Translations$backend$ops$tr extends Translations$backend$ops$en {
  _Translations$backend$ops$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'Merge';
  @override
  String get pull => 'Pull';
  @override
  String get apply => 'Uygulama';
  @override
  String get switchOp => 'Geçiş';
  @override
  String get sync => 'Eşitleme';
}

// Path: backend.mergeOutcome
class _Translations$backend$mergeOutcome$tr
    extends Translations$backend$mergeOutcome$en {
  _Translations$backend$mergeOutcome$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String cancelled({required Object op}) => '${op} iptal edildi.';
  @override
  String complete({required Object op}) => '${op} tamamlandı.';
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} çakışma kaldı — Değişiklikler sayfasında çöz.',
        other: '${n} çakışma kaldı — Değişiklikler sayfasında çöz.',
      );
  @override
  String resolvedConflicts({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} çakışma çözüldü.',
        other: '${n} çakışma çözüldü.',
      );
  @override
  String uncommittedEdits({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
    n,
    one:
        '${n} dosyada commit edilmemiş değişiklik var — önce onları commit et.',
    other:
        '${n} dosyada commit edilmemiş değişiklik var — önce onları commit et.',
  );
}

// Path: changes.usage
class _Translations$changes$usage$tr extends Translations$changes$usage$en {
  _Translations$changes$usage$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String caption({required Object input, required Object output}) =>
      '${input} giriş · ${output} çıkış';
  @override
  String captionCached({
    required Object fresh,
    required Object cached,
    required Object out,
  }) => '${fresh} giriş · ${cached} önbellek · ${out} çıkış';
  @override
  String get inWord => 'giriş';
  @override
  String get cachedWord => 'önbellek';
  @override
  String get outWord => 'çıkış';
  @override
  String tipIn({required Object value}) => '${value}  giriş';
  @override
  String tipCacheRead({required Object value}) => '${value}  önbellek okuma';
  @override
  String tipCacheWrite({required Object value}) => '${value}  önbellek yazma';
  @override
  String tipOut({required Object value}) => '${value}  çıkış';
  @override
  String tipReasoning({required Object value}) => '${value}  akıl yürütme';
  @override
  String tipWallClock({required Object value}) => '${value}sn  duvar saati';
}

// Path: changes.tabs
class _Translations$changes$tabs$tr extends Translations$changes$tabs$en {
  _Translations$changes$tabs$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get defaultLabel => 'Değişiklikler';
  @override
  String get empty => 'Boş';
}

// Path: changes.tabStrip
class _Translations$changes$tabStrip$tr
    extends Translations$changes$tabStrip$en {
  _Translations$changes$tabStrip$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get newDiffTab => 'Yeni Diff Sekmesi';
}

// Path: changes.select
class _Translations$changes$select$tr extends Translations$changes$select$en {
  _Translations$changes$select$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get selectAll => 'Tümünü seç';
  @override
  String get deselectAll => 'Seçimi kaldır';
}

// Path: changes.constellationToggle
class _Translations$changes$constellationToggle$tr
    extends Translations$changes$constellationToggle$en {
  _Translations$changes$constellationToggle$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get backToList => 'listeye dön';
  @override
  String get atlas => 'atlas, commit adaylarını gör';
}

// Path: changes.nudgeChip
class _Translations$changes$nudgeChip$tr
    extends Translations$changes$nudgeChip$en {
  _Translations$changes$nudgeChip$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required Object path,
    required Object anchor,
    required Object pct,
    required Object receipts,
  }) => '${path}\n${anchor} ile bağlaşır · %${pct}${receipts}';
}

// Path: changes.minimap
class _Translations$changes$minimap$tr extends Translations$changes$minimap$en {
  _Translations$changes$minimap$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get roleNew => 'yeni';
  @override
  String get roleBridge => 'köprü';
  @override
  String get roleHub => 'hub';
  @override
  String get roleLeaf => 'yaprak';
  @override
  String get roleConnected => 'bağlı';
  @override
  String roleWithWell({required Object role, required Object well}) =>
      '${role} · ${well}';
  @override
  String changesWith({required Object name}) => '${name} ile değişir';
  @override
  String get newFile => 'yeni dosya';
  @override
  String nearOtherChanges({required Object dir, required Object count}) =>
      '${dir} içindeki ${count} diğer değişikliğe yakın';
  @override
  String usuallyChangesWithFile({required Object name}) =>
      '${name} genellikle bu dosyayla değişir';
}

// Path: changes.tagInput
class _Translations$changes$tagInput$tr
    extends Translations$changes$tagInput$en {
  _Translations$changes$tagInput$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get hint => 'etiket...';
}

// Path: changes.composer
class _Translations$changes$composer$tr
    extends Translations$changes$composer$en {
  _Translations$changes$composer$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get hintPlaceholder => 'commit mesajı...';
  @override
  String hintWithChar({required Object hint, required Object char}) =>
      '${hint}  ·  ${char}';
}

// Path: changes.commit
class _Translations$changes$commit$tr extends Translations$changes$commit$en {
  _Translations$changes$commit$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get primaryCommitChanges => 'Değişiklikleri commit et';
  @override
  String get primaryCommitChangesDetail =>
      'Detached HEAD: eşitlemeden yerel olarak commit et.';
  @override
  String get primaryPublish => 'Commit et & yayımla';
  @override
  String get primaryPublishDetail =>
      'Commit\'i oluştur ve bu dalı tek adımda yayımla.';
  @override
  String get primarySync => 'Commit et & eşitle';
  @override
  String get primarySyncDetail =>
      'Commit\'i oluştur, sonra dalı uzlaştır ve gönder.';
  @override
  String get primaryPush => 'Commit et & push';
  @override
  String get primaryPushDetail => 'Commit\'i oluştur ve hemen gönder.';
  @override
  String get amendLast => 'Son commit\'i düzelt';
  @override
  String amendAnd({required Object action}) => 'Düzelt & ${action}';
  @override
  String get chooseFile => 'Sonraki commit için en az bir dosya seç.';
  @override
  String get writeMessage => 'Önce bir commit mesajı yaz.';
  @override
  String get committing => 'Commit ediliyor';
  @override
  String get committingSync => 'Commit ediliyor ve eşitleniyor';
  @override
  String get committed => 'Commit edildi.';
  @override
  String get undoFailed => 'Geri alma başarısız.';
  @override
  String get working => 'Çalışıyor…';
  @override
  String get commitOnly => 'Yalnızca commit';
  @override
  String get noRuntimeModels =>
      'Commit mesajları için çalışma zamanında keşfedilen model yok.';
  @override
  String restoreFailedRetry({required Object err}) =>
      '${err}\nHariç tutulan dosyaların hazırlaması geri yüklenemedi; yeniden denemeden önce indeksi kontrol et.';
  @override
  String committedSummary({required Object summary, required Object hash}) =>
      '${summary} (${hash}) commit edildi.';
  @override
  String get restoreFailedSync =>
      'Hariç tutulan dosyaların seçimleri yeniden hazırlanamadı; eşitleme atlandı. Eşitlemeden önce indeksi kontrol et.';
  @override
  String get noModelLabel => 'Model yok';
  @override
  String get chooseBeforeGenerate => 'Üretmeden önce en az bir dosya seç.';
  @override
  String get aiUnavailable => 'Commit-mesajı AI\'ı henüz kullanılamıyor.';
  @override
  String get generateFailed => 'Üretme başarısız.';
  @override
  String get stageFailed => 'Dosyalar hazırlanamadı.';
  @override
  String get commitFailed => 'Commit başarısız.';
  @override
  String committedAndRan({
    required Object summary,
    required Object hash,
    required Object operation,
  }) => '${summary} (${hash}) commit edildi ve ${operation} çalıştırıldı.';
  @override
  String committedResolved({
    required num n,
    required Object summary,
    required Object hash,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
    n,
    one: '${summary} (${hash}) commit edildi; ${n} çakışma çözüldü.',
    other: '${summary} (${hash}) commit edildi; ${n} çakışma çözüldü.',
  );
  @override
  String conflictsLeft({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: 'Çözülecek ${n} çakışma kaldı.',
        other: 'Çözülecek ${n} çakışma kaldı.',
      );
  @override
  String syncBlocked({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
    n,
    one:
        'Commit başarılı oldu, ancak eşitleme ${n} commit edilmemiş dosya tarafından engellendi.',
    other:
        'Commit başarılı oldu, ancak eşitleme ${n} commit edilmemiş dosya tarafından engellendi.',
  );
  @override
  String syncStalled({required Object message}) =>
      'Commit başarılı oldu, ancak eşitleme takıldı: ${message}';
  @override
  String syncFailed({required Object message}) =>
      'Commit başarılı oldu, ancak eşitleme başarısız: ${message}';
}

// Path: changes.rebase
class _Translations$changes$rebase$tr extends Translations$changes$rebase$en {
  _Translations$changes$rebase$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get continueFailed => 'Rebase sürdürülemedi.';
}

// Path: changes.editor
class _Translations$changes$editor$tr extends Translations$changes$editor$en {
  _Translations$changes$editor$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get closeBarrier => 'Editörü kapat';
}

// Path: changes.editorTitles
class _Translations$changes$editorTitles$tr
    extends Translations$changes$editorTitles$en {
  _Translations$changes$editorTitles$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  List<String> get any => [
    'sevgili git-log',
    'beni bağış-git, çünkü günah işledim…',
    'bu ana bir ad ver',
    'döktür bakalım',
    'konuş!',
    'annen sarkan bir referanstı, baban da noktalı virgül kokuyordu',
  ];
  @override
  List<String> get short => [
    'öyle mi?',
    'merhaba:)',
    'bu arada:',
    'birkaç kelime',
    'kibar sürüm',
    'bir not bırak',
    'diyordun ki..?',
    'hadi, çıkar bakalım',
  ];
  @override
  List<String> get mid => [
    'kayıtlara geçsin',
    'gelecekteki sana anlat',
    'ama önce?',
    'nasıl gitti',
    'kendi kelimelerinle',
    'sen NE yaptın?',
    'not alındı',
    'dikkatimi çektin',
  ];
  @override
  List<String> get long => [
    'hayallerini duyayım',
    'güzel bir şey söyle',
    '... sonra dedim ki:',
    'gelecek nesiller bekliyor',
    'daha çok yazmak hatalarını yok eder',
    'vay canına',
    'kutsal metinler',
  ];
}

// Path: changes.askHint
class _Translations$changes$askHint$tr extends Translations$changes$askHint$en {
  _Translations$changes$askHint$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String round({required Object n}) =>
      'tur ${n} — iyileştir ya da bağlam ekle.';
  @override
  String get symptom => 'belirtiyi tarif et.';
  @override
  String get broken => 'ne bozuldu?';
  @override
  String get bug => 'hatayı tarif et.';
  @override
  String get error => 'hatayı yapıştır.';
}

// Path: changes.fileMenu
class _Translations$changes$fileMenu$tr
    extends Translations$changes$fileMenu$en {
  _Translations$changes$fileMenu$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get ripple => 'Dalga';
  @override
  String get includeCoChanges => 'Ortak değişimleri dahil et';
  @override
  String deleteFile({required Object name}) => '${name} sil…';
  @override
  String discardChangesTo({required Object name}) =>
      '${name} değişikliklerini iptal et…';
  @override
  String get ignore => 'Yoksay';
  @override
  String get diffTabFromSelection => 'Seçimden Diff Sekmesi';
  @override
  String addSelectedToTab({required Object name}) =>
      '${name} sekmesine seçileni ekle';
  @override
  String diffTabFromFile({required Object name}) =>
      '${name} dosyasından Diff Sekmesi';
  @override
  String addFileToTab({required Object file, required Object tab}) =>
      '${file}, ${tab} sekmesine ekle';
  @override
  String get copyFilePath => 'Dosya yolunu kopyala';
  @override
  String get showInExplorer => 'Gezgin\'de göster';
}

// Path: changes.multiFileMenu
class _Translations$changes$multiFileMenu$tr
    extends Translations$changes$multiFileMenu$en {
  _Translations$changes$multiFileMenu$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get cohesionTight => 'sıkı bağlı';
  @override
  String get cohesionLoose => 'gevşek ilişkili';
  @override
  String get cohesionScattered => 'yapısal olarak dağınık';
  @override
  String get clusterOne => 'hepsi tek kümede';
  @override
  String clusterSpansDetailed({required Object count, required Object parts}) =>
      '${count} kümeye yayılıyor (${parts} dosya)';
  @override
  String clusterSpans({required Object count}) => '${count} kümeye yayılıyor';
  @override
  String roleLine({required Object count, required Object cohesion}) =>
      '${count} dosya · ${cohesion}';
  @override
  String usuallyChangesWithGroup({required Object file}) =>
      '${file} genellikle bu grupla değişir';
  @override
  String get splitToNewTab => 'Yeni sekmeye böl';
  @override
  String copyPaths({required Object count}) => '${count} yolu kopyala';
}

// Path: changes.ignoreMenu
class _Translations$changes$ignoreMenu$tr
    extends Translations$changes$ignoreMenu$en {
  _Translations$changes$ignoreMenu$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String extension({required Object ext}) => '.${ext} uzantısı';
  @override
  String allSelected({required Object count}) => 'Seçili ${count} öğenin tümü';
  @override
  String couplesWith({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} dahil edilen dosyayla bağlaşır',
        other: '${n} dahil edilen dosyayla bağlaşır',
      );
  @override
  String get updateFailed => '.gitignore güncellenemedi.';
}

// Path: changes.discard
class _Translations$changes$discard$tr extends Translations$changes$discard$en {
  _Translations$changes$discard$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String deleteTitle({required Object name}) => '${name} silinsin mi?';
  @override
  String discardTitle({required Object name}) =>
      '${name} değişiklikleri iptal edilsin mi?';
  @override
  String deleteBody({required Object path}) =>
      '${path} diskten kaldırılacak. Bu, uygulama içinden geri alınamaz.';
  @override
  String discardBody({required Object path}) =>
      '${path} üzerindeki tüm değişiklikler HEAD\'deki durumuna geri döndürülecek. Bu geri alınamaz.';
  @override
  String get discard => 'İptal et';
  @override
  String deletingFile({required Object name}) => '${name} siliniyor';
  @override
  String discardingFile({required Object name}) =>
      '${name} değişiklikleri iptal ediliyor';
  @override
  String get discardFailed => 'Değişiklikler iptal edilemedi.';
  @override
  String discardManyTitle({required Object count}) =>
      '${count} dosyanın değişiklikleri iptal edilsin mi?';
  @override
  String get discardManyBody =>
      'İzlenen dosyalar HEAD\'deki durumuna döndürülecek; izlenmeyen dosyalar diskten kaldırılacak. Bu geri alınamaz.';
  @override
  String discardManyConfirm({required Object count}) => '${count} iptal et';
  @override
  String discardingManyFiles({required Object count}) =>
      '${count} dosya iptal ediliyor';
  @override
  String failedOpenExplorer({required Object error}) =>
      'Dosya gezgini açılamadı: ${error}';
  @override
  String get someFailed => 'Bazı iptaller başarısız oldu.';
}

// Path: changes.snack
class _Translations$changes$snack$tr extends Translations$changes$snack$en {
  _Translations$changes$snack$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get sameWorktree => 'Aynı çalışma ağacı — dökülecek bir şey yok.';
  @override
  String diffFailed({required Object error}) => 'Diff başarısız: ${error}';
  @override
  String get deskEmpty => 'Desk\'te önünde bir şey yok — boş döküm.';
  @override
  String sourceDesk({required Object label}) => '${label} desk\'i';
  @override
  String shelfReadFailed({required Object error}) =>
      'Raf okuması başarısız: ${error}';
  @override
  String get shelfEmpty => 'Boş raf — dökülecek bir şey yok.';
  @override
  String sourceShelf({required Object label}) => '${label} rafı';
  @override
  String noModelConfigured({required Object label}) =>
      '"${label}" için model yapılandırılmadı.';
  @override
  String fetchFailed({required Object error}) => 'Fetch başarısız: ${error}';
}

// Path: changes.trace
class _Translations$changes$trace$tr extends Translations$changes$trace$en {
  _Translations$changes$trace$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Doğrulama izi';
  @override
  String get draftReview => 'Taslak inceleme';
}

// Path: changes.cleanTree
class _Translations$changes$cleanTree$tr
    extends Translations$changes$cleanTree$en {
  _Translations$changes$cleanTree$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Çalışma ağacı temiz';
  @override
  String get subtitle =>
      'Hazırlanmış ya da hazırlanmamış değişiklik algılanmadı.';
  @override
  String get noUpstream => '  ·  upstream yok';
  @override
  String get ahead => ' ileride';
  @override
  String get behind => ' geride';
  @override
  String get refreshing => 'Yenileniyor...';
  @override
  String get refresh => 'Yenile';
  @override
  String get check => 'kontrol';
  @override
  String get checkTooltip => 'Fetch ve yerel yenileme.';
  @override
  String get sync => '& eşitle';
}

// Path: changes.guardrail
class _Translations$changes$guardrail$tr
    extends Translations$changes$guardrail$en {
  _Translations$changes$guardrail$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'Gevşek';
  @override
  String get balanced => 'Dengeli';
  @override
  String get strict => 'Katı';
  @override
  String get paranoid => 'Paranoyak';
}

// Path: changes.dropHint
class _Translations$changes$dropHint$tr
    extends Translations$changes$dropHint$en {
  _Translations$changes$dropHint$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get fromShelf =>
      'bu raftaki değişiklikleri buraya getirmek için bırak';
  @override
  String get fromDesk =>
      'bu desk\'teki değişiklikleri buraya getirmek için bırak';
}

// Path: changes.diffEmpty
class _Translations$changes$diffEmpty$tr
    extends Translations$changes$diffEmpty$en {
  _Translations$changes$diffEmpty$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Dosya seçilmedi';
  @override
  String get message => 'Diff\'ini incelemek için değiştirilmiş bir dosya seç.';
}

// Path: changes.shelvePill
class _Translations$changes$shelvePill$tr
    extends Translations$changes$shelvePill$en {
  _Translations$changes$shelvePill$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String shelveN({required Object count}) => '↓ ${count} rafa kaldır';
  @override
  String get shelve => '↓ rafa kaldır';
  @override
  String shelvedCount({required Object count, required Object glyph}) =>
      '${count} rafa kaldırıldı ${glyph}';
}

// Path: changes.stashAction
class _Translations$changes$stashAction$tr
    extends Translations$changes$stashAction$en {
  _Translations$changes$stashAction$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get pickUp => 'al';
  @override
  String get peek => 'göz at';
  @override
  String get toss => 'at';
}

// Path: changes.stashContents
class _Translations$changes$stashContents$tr
    extends Translations$changes$stashContents$en {
  _Translations$changes$stashContents$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get reading => 'raf okunuyor…';
  @override
  String get empty => 'boş raf';
}

// Path: changes.stashFile
class _Translations$changes$stashFile$tr
    extends Translations$changes$stashFile$en {
  _Translations$changes$stashFile$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get binary => 'bin';
}

// Path: changes.fileRow
class _Translations$changes$fileRow$tr extends Translations$changes$fileRow$en {
  _Translations$changes$fileRow$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get stagedLinesOnly => 'yalnızca hazırlanan satırları commit\'ler';
  @override
  String get doubleClickToggle => 'çift tıkla: tüm grubu aç/kapa';
  @override
  String get repoRoot => 'Depo kökü';
}

// Path: changes.resolveStrip
class _Translations$changes$resolveStrip$tr
    extends Translations$changes$resolveStrip$en {
  _Translations$changes$resolveStrip$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String reading({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} dosya okunuyor · çözüm hazırlanıyor…',
        other: '${n} dosya okunuyor · çözüm hazırlanıyor…',
      );
  @override
  String conflictsAcross({required num n, required Object files}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${files} genelinde ${n} çakışma',
        other: '${files} genelinde ${n} çakışma',
      );
  @override
  String get resolve => 'Çöz';
  @override
  String get orWith => 'YA DA ŞUNUNLA';
  @override
  String resolveWith({required Object label}) => '${label} ile çöz';
  @override
  String resolveWithModel({required Object label, required Object model}) =>
      '${label} ile çöz  ·  ${model}';
  @override
  String get resolving => 'çözülüyor…';
  @override
  String resolveWithGlyph({required Object label}) => '↵  ${label} ile çöz';
  @override
  String get orWithAnother => 'ya da başka bir modelle';
}

// Path: changes.badge
class _Translations$changes$badge$tr extends Translations$changes$badge$en {
  _Translations$changes$badge$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get stagedEdit => 'Hazırlanan düzenleme';
  @override
  String get edited => 'Düzenlendi';
  @override
  String get stagedAdd => 'Hazırlanan ekleme';
  @override
  String get added => 'Eklendi';
  @override
  String get stagedDelete => 'Hazırlanan silme';
  @override
  String get deleted => 'Silindi';
  @override
  String get stagedRename => 'Hazırlanan yeniden adlandırma';
  @override
  String get renamed => 'Yeniden adlandırıldı';
  @override
  String get stagedCopy => 'Hazırlanan kopya';
  @override
  String get copied => 'Kopyalandı';
  @override
  String get conflict => 'Çakışma';
  @override
  String get stagedTypeChange => 'Hazırlanan tür değişikliği';
  @override
  String get typeChanged => 'Tür değişti';
  @override
  String get untracked => 'İzlenmeyen';
}

// Path: changes.review
class _Translations$changes$review$tr extends Translations$changes$review$en {
  _Translations$changes$review$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Kod incelemesi';
  @override
  String includedFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} dahil edilen dosya',
        other: '${n} dahil edilen dosya',
      );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} hunk',
        other: '${n} hunk',
      );
  @override
  String guardrailModel({required Object guardrail, required Object model}) =>
      '${guardrail} | ${model}';
  @override
  String get unavailable => 'İnceleme kullanılamıyor';
  @override
  String get backToDiff => 'Diff\'e dön';
  @override
  String get verified => 'Doğrulandı';
  @override
  String get draftOnly => 'Yalnızca taslak';
  @override
  String get runAgain => 'Yeniden çalıştır';
  @override
  String draftShownBelow({required Object error}) =>
      '${error} Taslak inceleme aşağıda gösteriliyor.';
  @override
  String get hideTrace => 'İzi gizle';
  @override
  String get showTrace => 'İzi göster';
  @override
  String get showVerificationTrace => 'Doğrulama izini göster';
  @override
  String get whyLanded => 'Bu inceleme neden burada indi';
  @override
  String get noFindings => 'Bulgu yok';
  @override
  String get findings => 'Bulgular';
  @override
  String get noEvidenceIssues =>
      'Bu commit kapsamı için kanıta dayalı sorun ortaya çıkmadı.';
  @override
  String get observations => 'Gözlemler';
  @override
  String get chooseBeforeReview => 'İncelemeden önce en az bir dosya seç.';
  @override
  String get aiUnavailable => 'İnceleme AI\'ı henüz kullanılamıyor.';
  @override
  String get failed => 'İnceleme başarısız.';
  @override
  String get noRuntimeModels =>
      'Commit incelemesi için çalışma zamanında keşfedilen model yok.';
}

// Path: changes.commitBtn
class _Translations$changes$commitBtn$tr
    extends Translations$changes$commitBtn$en {
  _Translations$changes$commitBtn$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String switchTo({required Object label}) => 'Şuna geç: ${label}\n';
}

// Path: changes.shapeBtn
class _Translations$changes$shapeBtn$tr
    extends Translations$changes$shapeBtn$en {
  _Translations$changes$shapeBtn$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String askingWith({required Object cat}) => '${cat} ile soruluyor…';
  @override
  String askWith({required Object cat}) => '${cat} ile sor';
  @override
  String get noModel => 'AI modeli yapılandırılmadı';
  @override
  String nextTooltip({required Object cat}) =>
      'sonraki: ${cat}  ·  öncekiler için shift-tıkla';
  @override
  String get onlyOne => 'yalnızca bir AI kategorisi yapılandırıldı';
}

// Path: changes.dejaVu
class _Translations$changes$dejaVu$tr extends Translations$changes$dejaVu$en {
  _Translations$changes$dejaVu$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String tooltip({
    required num n,
    required Object pct,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
    n,
    one:
        '%${pct} déjà vu — atılan zaman çizgilerinden ${n} hayalet kenar bu diff\'e dokunuyor',
    other:
        '%${pct} déjà vu — atılan zaman çizgilerinden ${n} hayalet kenar bu diff\'e dokunuyor',
  );
  @override
  String get label => 'déjà vu';
}

// Path: changes.identity
class _Translations$changes$identity$tr
    extends Translations$changes$identity$en {
  _Translations$changes$identity$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'commit kimliği yapılandırılmadı';
  @override
  String asName({required Object name}) => '${name} olarak';
  @override
  String asNameEmail({required Object name, required Object email}) =>
      '${name} <${email}> olarak';
  @override
  String asNameSpace({required Object name}) => '${name} olarak ';
  @override
  String emailAngle({required Object email}) => '<${email}>';
  @override
  String get firstCommit => '\nbu repodaki ilk commit';
  @override
  String get newToRepo => '\nbu repoda yeni';
}

// Path: changes.staleScope
class _Translations$changes$staleScope$tr
    extends Translations$changes$staleScope$en {
  _Translations$changes$staleScope$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get message => 'bu çalıştığından beri seçim değişti';
  @override
  String get rerun => 'yeniden çalıştır';
}

// Path: changes.finding
class _Translations$changes$finding$tr extends Translations$changes$finding$en {
  _Translations$changes$finding$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get openDiff => 'Diff\'i aç';
  @override
  String get recorded => 'kaydedildi';
  @override
  String get dismiss => 'Kapat';
}

// Path: changes.muse
class _Translations$changes$muse$tr extends Translations$changes$muse$en {
  _Translations$changes$muse$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Muse';
  @override
  String get youPulledThis => 'bunu sen çektin';
  @override
  String fromIdea({required Object text}) => 'fikirden: "${text}"';
  @override
  String get foothold => 'dayanak — ';
  @override
  String get brainstormSpew => 'beyin fırtınası döküntüsü';
  @override
  String strandTooltip({required Object label, required Object count}) =>
      '${label} · ${count}';
  @override
  String copyN({required Object count}) => '${count} kopyala';
  @override
  String get clear => 'Temizle';
  @override
  String get chooseBeforeMuse => 'Muse\'u çağırmadan önce en az bir dosya seç.';
  @override
  String get aiUnavailable => 'Muse AI\'ı henüz kullanılamıyor.';
  @override
  String get failed => 'Muse başarısız.';
  @override
  String get noRuntimeModels =>
      'Muse için çalışma zamanında keşfedilen model yok.';
  @override
  String get needsModel => 'Muse en az bir yapılandırılmış model gerektirir.';
  @override
  String get dreaming => 'muse rüya görüyor...';
}

// Path: changes.debug
class _Translations$changes$debug$tr extends Translations$changes$debug$en {
  _Translations$changes$debug$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Hata Ayıklama';
  @override
  String round({required Object n}) => '· tur ${n}';
  @override
  String get clear => 'temizle';
  @override
  String get close => 'kapat';
  @override
  String get analyzing => 'belirti analiz ediliyor…';
  @override
  String get describeSymptom =>
      'bir belirti tarif et, sonra hata ayıkla\'ya bas.';
  @override
  String get evidenceFor => 'lehine';
  @override
  String get evidenceAgainst => 'ama';
  @override
  String get narrowDown => 'daraltmaya ne yardımcı olur:';
  @override
  String get failed => 'Hata ayıklama başarısız.';
  @override
  String get refinementFailed => 'Hata ayıklama iyileştirmesi başarısız.';
}

// Path: changes.includeSummary
class _Translations$changes$includeSummary$tr
    extends Translations$changes$includeSummary$en {
  _Translations$changes$includeSummary$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get none => 'Yok';
  @override
  String stagedSuffix({required Object count}) => ' · ${count} hazırlandı';
  @override
  String full({required num n, required Object staged}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: 'Tüm ${n} dosya${staged}',
        other: 'Tüm ${n} dosya${staged}',
      );
  @override
  String partial({
    required Object n,
    required Object count,
    required Object staged,
  }) => '${n} içinden ${count}${staged}';
  @override
  String shortAll({required Object n, required Object staged}) =>
      'Tümü ${n}${staged}';
}

// Path: changes.status
class _Translations$changes$status$tr extends Translations$changes$status$en {
  _Translations$changes$status$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get unavailableTitle => 'Depo durumu kullanılamıyor';
  @override
  String get loadingTitle => 'Depo durumu yükleniyor';
  @override
  String get loadingMessage => 'Çalışma ağacı okunuyor.';
}

// Path: changes.stash
class _Translations$changes$stash$tr extends Translations$changes$stash$en {
  _Translations$changes$stash$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get appliedWithConflicts =>
      'Zula çakışmalarla uygulandı — onları Değişiklikler sayfasında çöz (zula girdisi korundu).';
  @override
  String get couldNotPop => 'Zula pop edilemedi.';
  @override
  String get listChanged => 'Zula listesi değişti; silme atlandı. Tekrar dene.';
  @override
  String get droppingStash => 'Zula siliniyor';
}

// Path: changes.tooltips
class _Translations$changes$tooltips$tr
    extends Translations$changes$tooltips$en {
  _Translations$changes$tooltips$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get commitGenerating => 'commit mesajı üretiliyor...';
  @override
  String get commitPreparing => 'commit-mesajı hazırlanıyor...';
  @override
  String get commitSelectFile =>
      'commit mesajı üretmek için en az bir dosya seç.';
  @override
  String get commitConfigure =>
      'commit-mesajını Ayarlar > Davranışsal Dinamikler > Commit Mesajları\'nda yapılandır.';
  @override
  String get fastFallback => 'hızlı';
  @override
  String commitGenerateWith({required Object label}) =>
      '${label} modeliyle commit mesajı üret';
  @override
  String get museConsulting => 'muse\'a danışılıyor...';
  @override
  String get showMuse => 'muse\'u göster';
  @override
  String get museSelectFile => 'muse için en az bir dosya seç.';
  @override
  String get showMuseError => 'muse hatasını göster';
  @override
  String get museAsk => 'yön için muse\'a sor';
  @override
  String museAskWithModels({
    required Object brainstorm,
    required Object synthesis,
  }) => 'yön için muse\'a sor\n${brainstorm} → ${synthesis}';
  @override
  String get qualityFallback => 'kalite';
  @override
  String get reviewing => 'inceleniyor...';
  @override
  String get showReview => 'incelemeyi göster';
  @override
  String get reviewPreparing => 'commit incelemesi hazırlanıyor...';
  @override
  String get reviewSelectFile => 'incelemek için en az bir dosya seç.';
  @override
  String get reviewConfigure => 'inceleme AI\'ını ayarlarda yapılandır.';
  @override
  String get viewingReview => 'inceleme görüntüleniyor';
  @override
  String reviewWith({required Object label, required Object guardrail}) =>
      '${label} modeliyle ${guardrail} inceleme';
}

// Path: changes.mergeEditor
class _Translations$changes$mergeEditor$tr
    extends Translations$changes$mergeEditor$en {
  _Translations$changes$mergeEditor$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get resolutionYours => 'seninki';
  @override
  String get resolutionTheirs => 'onlarınki';
  @override
  String get resolutionCustom => 'özel';
  @override
  String get keepBoth => 'ikisini de tut';
  @override
  late final _Translations$changes$mergeEditor$trust$tr trust =
      _Translations$changes$mergeEditor$trust$tr._(_root);
  @override
  String get allResolved => 'tümü çözüldü';
  @override
  String get resolveEasy => 'kolay çakışmaları çöz';
  @override
  String get base => 'taban';
  @override
  String get cancel => 'iptal';
  @override
  String get save => 'kaydet';
  @override
  String get complete => 'tamamla';
  @override
  String get nextFile => 'sonraki dosya';
  @override
  String get edit => 'düzenle';
  @override
  String get auto => 'otomatik';
  @override
  String get undo => 'geri al';
  @override
  late final _Translations$changes$mergeEditor$keyHints$tr keyHints =
      _Translations$changes$mergeEditor$keyHints$tr._(_root);
  @override
  String get favoredTooltip =>
      'bağlaşım analizince yapısal olarak tercih edildi';
  @override
  String get newOnBothSides => '(her iki tarafta da yeni)';
  @override
  String writeFailed({required Object error}) =>
      'Çözülen dosyalar yazılamadı: ${error}';
  @override
  String neighborsCoChanged({required Object changed, required Object total}) =>
      '${changed}/${total} komşu ortak değişti';
  @override
  String integrity({required Object pct}) => 'bütünlük %${pct}';
  @override
  String reviewer({required Object name}) => 'inceleyici: ${name}';
}

// Path: changes.conflictResolution
class _Translations$changes$conflictResolution$tr
    extends Translations$changes$conflictResolution$en {
  _Translations$changes$conflictResolution$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String noModelConfigured({required Object category}) =>
      '"${category}" için model yapılandırılmadı. Ayarlar → AI\'da bir tane ayarla.';
  @override
  String sensitiveFilesSkipped({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} hassas dosya atlandı — elle çöz.',
        other: '${n} hassas dosya atlandı — elle çöz.',
      );
  @override
  String get couldNotReadFiles => 'Hiçbir çakışan dosya okunamadı.';
  @override
  String blockedSecret({required Object secret}) =>
      'Engellendi — çakışan bir dosya ${secret} içeriyor gibi görünüyor. Elle çöz.';
  @override
  String resolutionFailed({required Object error}) =>
      'Çözüm başarısız: ${error}';
  @override
  String mergeResolutionLabel({
    required Object resolved,
    required Object total,
    required Object category,
  }) => '◇ merge çözümü · ${resolved}/${total} dosya · ${category}';
  @override
  String conflictSummary({
    required Object op,
    required Object files,
    required Object conflicts,
  }) => '${op} · ${files} genelinde ${conflicts}';
  @override
  String conflictCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} çakışma',
        other: '${n} çakışma',
      );
  @override
  String get mergeEditorButton => '⇋ merge editörü';
  @override
  String get noAiModel => 'AI modeli yok';
  @override
  String get later => 'sonra';
  @override
  String get discard => 'iptal et';
  @override
  String get resolveWithAi => '◇ AI ile çöz';
  @override
  String get otherModel => 'başka model';
  @override
  String withModel({required Object model}) => '${model} ile';
}

// Path: changes.mergeFlow
class _Translations$changes$mergeFlow$tr
    extends Translations$changes$mergeFlow$en {
  _Translations$changes$mergeFlow$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$changes$mergeFlow$op$tr op =
      _Translations$changes$mergeFlow$op$tr._(_root);
  @override
  String get pushFailed => 'Gönderme başarısız';
  @override
  String get rebasedAndPushed => 'Rebase edildi ve gönderildi.';
  @override
  String switchedTo({required Object name}) => '${name} dalına geçildi.';
  @override
  String get switchFailed => 'Geçiş başarısız.';
  @override
  String switchedToCarried({required Object name}) =>
      '${name} dalına geçildi (değişiklikler taşındı).';
  @override
  String get alreadyUpToDate => 'Zaten güncel.';
  @override
  String merged({required Object upstream, required Object n}) =>
      '${upstream} birleştirildi (${n} dosya).';
  @override
  String get rebaseNotConverge => 'Rebase yakınsamadı — elle çöz.';
  @override
  String get rebased => 'Rebase edildi.';
  @override
  String rebasedResolved({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: 'Rebase edildi (${n} dosya çözüldü).',
        other: 'Rebase edildi (${n} dosya çözüldü).',
      );
  @override
  String get detachedHead =>
      'Eşitlenemiyor: detached HEAD durumu. Önce bir dala geç.';
  @override
  String get publishFailed => 'Yayımlama başarısız.';
  @override
  String get noRemote =>
      'Uzak yapılandırılmadı. Bu dalı yayımlamak için bir tane ekle.';
  @override
  String get failed => 'başarısız';
}

// Path: changes.constellation
class _Translations$changes$constellation$tr
    extends Translations$changes$constellation$en {
  _Translations$changes$constellation$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get axisStructure => 'YAPI';
  @override
  String get axisCoChange => 'ORTAK DEĞİŞİM';
  @override
  String get axisSpectralProfile => 'SPEKTRAL PROFİL';
  @override
  String get axisPathSiblings => 'YOL KARDEŞLERİ';
  @override
  String get axisDiffStructure => 'DIFF YAPISI';
  @override
  String get axisSpectral => 'SPEKTRAL';
  @override
  String get titleUnsorted => 'SIRALANMAMIŞ';
  @override
  String get titleSingleton => 'TEKİL';
  @override
  String get titleMixed => 'KARIŞIK';
  @override
  String get untie => 'ayır';
  @override
  String get bind => 'bağla';
  @override
  String get emptyClusters => 'henüz küme yok';
}

// Path: common.time
class _Translations$common$time$tr extends Translations$common$time$en {
  _Translations$common$time$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get now => 'şimdi';
  @override
  String get justNow => 'az önce';
  @override
  String get today => 'BUGÜN';
  @override
  String minutesAgo({required Object n}) => '${n}dk önce';
  @override
  String hoursAgo({required Object n}) => '${n}sa önce';
  @override
  String daysAgo({required Object n}) => '${n}g önce';
  @override
  String weeksAgo({required Object n}) => '${n}h önce';
  @override
  String monthsAgo({required Object n}) => '${n}ay önce';
  @override
  String yearsAgo({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n}y önce',
        other: '${n}y önce',
      );
  @override
  String minutesShort({required Object n}) => '${n}dk';
  @override
  String hoursShort({required Object n}) => '${n}sa';
  @override
  String daysShort({required Object n}) => '${n}g';
  @override
  String weeksShort({required Object n}) => '${n}h';
  @override
  String monthsShort({required Object n}) => '${n}ay';
  @override
  String yearsShort({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n}y',
        other: '${n}y',
      );
  @override
  String commitMonthsShort({required Object n}) => '${n}ay';
  @override
  String get idle => 'boşta';
  @override
  String idleDays({required Object n}) => '${n} gündür boşta';
  @override
  String idleYears({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} yıldır boşta',
        other: '${n} yıldır boşta',
      );
  @override
  List<String> get monthAbbrevs => [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];
}

// Path: common.size
class _Translations$common$size$tr extends Translations$common$size$en {
  _Translations$common$size$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

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
class _Translations$diff$status$tr extends Translations$diff$status$en {
  _Translations$diff$status$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Diff yükleniyor';
  @override
  String get loadingMessage => 'Dosya değişiklikleri okunuyor.';
  @override
  String get unavailableTitle => 'Diff kullanılamıyor';
  @override
  String get noChangesTitle => 'Değişiklik yok';
  @override
  String get noChangesMessage => 'Bu dosyada gösterilecek diff içeriği yok.';
}

// Path: diff.toolbar
class _Translations$diff$toolbar$tr extends Translations$diff$toolbar$en {
  _Translations$diff$toolbar$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get searchHint => 'diff\'te ara...';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} satır',
        other: '${n} satır',
      );
  @override
  String get blameLoading => 'blame...';
  @override
  String get blame => 'blame';
  @override
  String get wearMapOn => 'aşınma · açık';
  @override
  String get wearMapOnHint => 'aşınma haritası açık — gizlemek için tıkla';
  @override
  String get wearMapOffHint =>
      'aşınma haritasını göster (etkinlik ısı haritası)';
  @override
  String get trailBadge => '· iz';
}

// Path: diff.hunkDropdown
class _Translations$diff$hunkDropdown$tr
    extends Translations$diff$hunkDropdown$en {
  _Translations$diff$hunkDropdown$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get tooltip => 'Değişiklik bloğuna atla. Git bunlara hunk der.';
  @override
  String changeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} değişiklik',
        other: '${n} değişiklik',
      );
}

// Path: diff.trail
class _Translations$diff$trail$tr extends Translations$diff$trail$en {
  _Translations$diff$trail$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'iz yükleniyor...';
  @override
  String get noHistory => 'geçmiş bulunamadı';
  @override
  String get nowWorkingCopy => 'şimdi · çalışma kopyası';
  @override
  String stopLabel({
    required Object hash,
    required Object author,
    required Object time,
    required Object subject,
  }) => '${hash} · ${author} · ${time} · ${subject}';
}

// Path: diff.pinned
class _Translations$diff$pinned$tr extends Translations$diff$pinned$en {
  _Translations$diff$pinned$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get loadingContext => 'sabitlenmiş bağlam yükleniyor';
  @override
  String get pageManifold => 'Manifold';
  @override
  String get pageSignals => 'Sinyaller';
  @override
  String get echoesTitle => 'Yankılar';
  @override
  String get technicalLedger => 'Teknik Defter';
  @override
  String get noSecondaryCues => 'İkincil ipucu algılanmadı.';
  @override
  String get linkedPaths => 'Bağlı Yollar';
  @override
  String moreCount({required Object n}) => '+${n} daha';
  @override
  String get localSeam => 'Yerel dikiş';
  @override
  String get sharedOwnership => 'paylaşılan sahiplik';
  @override
  String get historyWarmingUp => 'Geçmiş ısınıyor';
  @override
  String echoesTotal({required Object n}) => '${n} TOPLAM';
  @override
  String get noEchoes => 'Bu diff\'te yankı yok.';
  @override
  String openRelatedFile({required Object name}) =>
      'İlgili dosyayı aç: ${name}';
  @override
  String inspectFile({required Object name}) => '${name} incele';
  @override
  String get jumpEcho => 'yankıya atla';
  @override
  String get copyLine => 'satırı kopyala';
  @override
  String get signalTempo => 'T';
  @override
  String get signalNovelty => 'N';
  @override
  String get signalReach => 'R';
  @override
  late final _Translations$diff$pinned$tempo$tr tempo =
      _Translations$diff$pinned$tempo$tr._(_root);
  @override
  late final _Translations$diff$pinned$tone$tr tone =
      _Translations$diff$pinned$tone$tr._(_root);
  @override
  late final _Translations$diff$pinned$summary$tr summary =
      _Translations$diff$pinned$summary$tr._(_root);
  @override
  late final _Translations$diff$pinned$tightness$tr tightness =
      _Translations$diff$pinned$tightness$tr._(_root);
  @override
  String conceptWithTightness({
    required Object concept,
    required Object tightness,
  }) => '${concept} (${tightness})';
  @override
  String get storyWhyThisMatters => 'Bu neden önemli';
  @override
  String get storyConfidence => 'Güven';
  @override
  String get storySecondarySignal => 'İkincil sinyal';
  @override
  String get storyNeighbourhood => 'Komşuluk';
  @override
  String neighbourhoodDetail({required Object name}) =>
      'Bu satır, mevcut kod tabanı alanında ${name} ile komşu.';
  @override
  String get propagationLane => 'Yayılma şeridi';
  @override
  String propagationLaneNamed({required Object lane}) =>
      'Yayılma şeridi: ${lane}';
  @override
  late final _Translations$diff$pinned$witness$tr witness =
      _Translations$diff$pinned$witness$tr._(_root);
  @override
  late final _Translations$diff$pinned$integrity$tr integrity =
      _Translations$diff$pinned$integrity$tr._(_root);
  @override
  late final _Translations$diff$pinned$related$tr related =
      _Translations$diff$pinned$related$tr._(_root);
  @override
  late final _Translations$diff$pinned$axis$tr axis =
      _Translations$diff$pinned$axis$tr._(_root);
}

// Path: diff.hunkHint
class _Translations$diff$hunkHint$tr extends Translations$diff$hunkHint$en {
  _Translations$diff$hunkHint$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String hiddenCount({required Object n}) => '${n} gizli';
  @override
  String get landing => 'iniş';
}

// Path: diff.binary
class _Translations$diff$binary$tr extends Translations$diff$binary$en {
  _Translations$diff$binary$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String tooLargeToPreview({required Object size}) =>
      '${size} MB (önizleme için çok büyük)';
  @override
  String get unableToLoadBlob => 'Blob yüklenemedi';
  @override
  String get omittedKindMedia => 'medya';
  @override
  String get omittedKindBinary => 'ikili';
  @override
  String omittedStub({required Object kind}) => '${kind} · gizli';
}

// Path: diff.media
class _Translations$diff$media$tr extends Translations$diff$media$en {
  _Translations$diff$media$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get unableToDecodeImage => 'Görüntü çözülemedi';
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
  String get stateAdded => 'eklendi';
  @override
  String get stateDeleted => 'silindi';
  @override
  String get stateModified => 'değiştirildi';
  @override
  String get fallbackFormatName => 'İkili';
}

// Path: filament.severity
class _Translations$filament$severity$tr
    extends Translations$filament$severity$en {
  _Translations$filament$severity$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get critical => 'kritik';
  @override
  String get warn => 'uyarı';
  @override
  String get info => 'bilgi';
  @override
  String get joint => 'eklem';
}

// Path: filament.kind
class _Translations$filament$kind$tr extends Translations$filament$kind$en {
  _Translations$filament$kind$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get staleValue => 'bayat değer';
  @override
  String get temporalShift => 'zamansal kayma';
  @override
  String get contextInversion => 'bağlam tersine dönüşü';
  @override
  String get contradictoryFlow => 'çelişkili akış';
}

// Path: history.commitLede
class _Translations$history$commitLede$tr
    extends Translations$history$commitLede$en {
  _Translations$history$commitLede$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$history$commitLede$semantics$tr semantics =
      _Translations$history$commitLede$semantics$tr._(_root);
}

// Path: history.seismograph
class _Translations$history$seismograph$tr
    extends Translations$history$seismograph$en {
  _Translations$history$seismograph$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get rootTrackLabel => '(kök)';
  @override
  String dirTrackLabel({required Object name}) => '(${name})';
  @override
  String moreLabel({required Object n}) => '+${n} daha';
  @override
  String filesInDir({required num n, required Object path}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${path}/ içinde ${n} dosya',
        other: '${path}/ içinde ${n} dosya',
      );
  @override
  String moreFilesCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} dosya daha',
        other: '${n} dosya daha',
      );
  @override
  String get breadcrumbAll => 'tümü';
  @override
  String breadcrumbCurrentFocus({required Object target}) =>
      'Geçerli odak: ${target}';
  @override
  String get breadcrumbViewAllChanges =>
      'Bu commit\'teki tüm değişiklikleri gör';
  @override
  String breadcrumbDrillUpTo({required Object target}) =>
      '${target} düzeyine çık';
  @override
  String trackStats({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
    n,
    one: '${n} dosya  +${adds}  -${dels}',
    other: '${n} dosya  +${adds}  -${dels}',
  );
  @override
  String subdirCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} alt dizin',
        other: '${n} alt dizin',
      );
  @override
  String segmentLeafSummary({
    required Object path,
    required Object adds,
    required Object dels,
  }) => '${path}, ${adds} eklendi, ${dels} silindi';
  @override
  String segmentContainerSummary({
    required num n,
    required Object adds,
    required Object dels,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
    n,
    one: '${n} dosya, ${adds} eklendi, ${dels} silindi',
    other: '${n} dosya, ${adds} eklendi, ${dels} silindi',
  );
  @override
  String hunkCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} hunk',
        other: '${n} hunk',
      );
  @override
  String get largestChangeInView => 'bu görünümdeki en büyük değişiklik';
  @override
  String get conflictedTag => 'çakışmalı';
  @override
  String get dirtyTag => 'kirli';
  @override
  String get drillInTag => 'içine dal';
  @override
  String get changeTypeRenamed => 'yeniden adlandırıldı';
  @override
  String get changeTypeCopied => 'kopyalandı';
  @override
  String get changeTypeTypechange => 'tür değişikliği';
  @override
  String get changeTypeConflict => 'çakışma';
  @override
  String get coreFile => 'çekirdek dosya';
  @override
  String get staleFile => 'bayat';
  @override
  String get filterPathHint => 'yol filtrele';
  @override
  String get escHint => 'esc';
}

// Path: history.worldline
class _Translations$history$worldline$tr
    extends Translations$history$worldline$en {
  _Translations$history$worldline$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get closeWorldline => 'Dünya çizgisini kapat';
  @override
  String get dragToOpenWorldline => 'Dünya çizgisini açmak için sürükle';
}

// Path: history.contextMenu
class _Translations$history$contextMenu$tr
    extends Translations$history$contextMenu$en {
  _Translations$history$contextMenu$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get currentBranchFallback => 'geçerli dal';
  @override
  String applyCommitOnto({required Object branch}) =>
      'Commit\'in değişikliklerini ${branch} üzerine uygula';
  @override
  String revertCommitOn({required Object branch}) =>
      'Commit\'in değişikliklerini ${branch} üzerinde revert et';
}

// Path: history.cherryPick
class _Translations$history$cherryPick$tr
    extends Translations$history$cherryPick$en {
  _Translations$history$cherryPick$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Cherry-pick duraklatıldı. Kalan çakışmaları Değişiklikler sayfasında tamamla.';
  @override
  String failed({required Object error}) => 'Cherry-pick başarısız: ${error}';
  @override
  String pickedResolved({required Object short}) =>
      '${short} cherry-pick edildi (çakışmalar çözüldü)';
  @override
  String picked({required Object short}) => '${short} cherry-pick edildi';
}

// Path: history.revert
class _Translations$history$revert$tr extends Translations$history$revert$en {
  _Translations$history$revert$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get paused =>
      'Revert duraklatıldı. Kalan çakışmaları Değişiklikler sayfasında tamamla.';
  @override
  String failed({required Object error}) => 'Revert başarısız: ${error}';
  @override
  String revertedResolved({required Object short}) =>
      '${short} revert edildi (çakışmalar çözüldü)';
  @override
  String reverted({required Object short}) => '${short} revert edildi';
}

// Path: history.reflog
class _Translations$history$reflog$tr extends Translations$history$reflog$en {
  _Translations$history$reflog$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get createBranchFromHere => 'Buradan dal oluştur…';
  @override
  String get copyCommitHash => 'Commit hash\'ini kopyala';
  @override
  String get createBranchDialogTitle => 'Reflog girdisinden dal oluştur';
  @override
  String anchorLine({required Object short, required Object summary}) =>
      'Çapa: ${short}  ·  ${summary}';
  @override
  String get branchNameHint => 'dal adı';
  @override
  String get createAction => 'Oluştur';
  @override
  String createBranchFailed({required Object error}) =>
      'Dal oluşturulamadı: ${error}';
  @override
  String branchCreatedAt({required Object name, required Object short}) =>
      '"${name}" dalı ${short} konumunda oluşturuldu.';
}

// Path: history.rebase
class _Translations$history$rebase$tr extends Translations$history$rebase$en {
  _Translations$history$rebase$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String firstCommitCannotBe({required Object action}) =>
      'İlk commit ${action} olamaz';
  @override
  String rebaseCommitCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} commit rebase et',
        other: '${n} commit rebase et',
      );
  @override
  String get resetLabel => 'sıfırla';
  @override
  String get dragToReorderHint =>
      'yeniden sıralamak için sürükle, her commit için eylem seç';
  @override
  String get newMessageHint => 'yeni mesaj';
  @override
  String get runningEllipsis => '…';
  @override
  String get startRebase => 'Rebase\'i Başlat';
}

// Path: history.inFlight
class _Translations$history$inFlight$tr
    extends Translations$history$inFlight$en {
  _Translations$history$inFlight$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'YOLDA';
  @override
  String get deskFallbackLabel => 'desk';
}

// Path: historySurgery.chrome
class _Translations$historySurgery$chrome$tr
    extends Translations$historySurgery$chrome$en {
  _Translations$historySurgery$chrome$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Geçmiş Cerrahisi';
  @override
  String get alphaBadge => 'alpha';
  @override
  String get dryRunBadge => 'PROVA';
}

// Path: historySurgery.select
class _Translations$historySurgery$select$tr
    extends Translations$historySurgery$select$en {
  _Translations$historySurgery$select$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get prompt => 'Geçmişten kaldırılacak dosyaları seç';
  @override
  String selectedCount({required Object n}) => '${n} seçili';
  @override
  String get searchHint => 'ara...';
  @override
  String get readingTree => 'ağaç okunuyor...';
  @override
  String get continueDisabled => 'devam için dosya seç';
  @override
  String get continueEnabled => 'devam →';
  @override
  String toPurgeCount({required Object n}) => '${n} temizlenecek';
  @override
  String get analyzing => 'analiz ediliyor...';
  @override
  String get riskLow => 'düşük risk';
  @override
  String get riskModerate => 'orta risk';
  @override
  String get riskHigh => 'yüksek risk';
  @override
  String get impactCommitsLabel => 'commit\'ler';
  @override
  String get impactBranchesLabel => 'dallar';
  @override
  String get impactWorktreesLabel => 'çalışma ağaçları';
  @override
  String get impactCouplingLabel => 'bağlaşım';
  @override
  String get impactCouplingIsland => 'ada';
  @override
  String impactCouplingNeighbors({required Object n}) => '${n} komşu';
  @override
  String renameArrow({required Object path}) => '← ${path}';
}

// Path: historySurgery.understand
class _Translations$historySurgery$understand$tr
    extends Translations$historySurgery$understand$en {
  _Translations$historySurgery$understand$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get heading => 'Bu nasıl çalışır';
  @override
  String get backupTitle => 'Yedek';
  @override
  String get backupBody =>
      'Herhangi bir şey değişmeden önce her dal ve etiket referansı bir yedek ad alanına kopyalanır. Bir şeyler ters giderse, tek tıkla özgün durum geri yüklenir.';
  @override
  String get rewriteTitle => 'Yeniden yaz';
  @override
  String get rewriteBody =>
      'Her commit kökten uca kadar gezilir. Hedef dosyaları içeren her commit için, bu dosyalar ağaçtan çıkarılmış yeni bir commit oluşturulur. Topolojiyi korumak için ebeveyn zincirleri yeniden eşlenir. ';
  @override
  String rewriteSummary({required Object total, required Object affected}) =>
      '${total} commit\'ten ${affected} tanesi yeniden yazılacak.';
  @override
  String get updateRefsTitle => 'Referansları güncelle';
  @override
  String get updateRefsBody =>
      'Dal ve etiket işaretçileri yeni commit SHA\'larına taşınır. Eski nesneler çöp toplama gerçekleşene kadar var olmaya devam eder. ';
  @override
  String worktreesNeedRecheckout({required Object n}) =>
      '${n} çalışma ağacın yeniden checkout edilmeli.';
  @override
  String get noWorktreesAffected => 'Hiçbir çalışma ağacı etkilenmiyor.';
  @override
  String get forcePushTitle => 'Force-push';
  @override
  String get forcePushBody =>
      'Temizliği doğruladıktan sonra, hangi dalların force-push edileceğini seçersin. --force-with-lease kullanır; böylece bu sırada başkası push ettiyse güvenli şekilde başarısız olur.';
  @override
  String get plumbingNote =>
      'filter-repo veya BFG\'nin aksine, bu tamamen git plumbing komutlarıyla çalışır (cat-file, mktree, commit-tree, update-ref). Harici bağımlılık yok. Yeniden adlandırma takibi dosya başına bir zinciri izler — bir dosya kopyalandıysa ve iki kopya bağımsız olarak yeniden adlandırıldıysa, yürütmeden sonra temizlik sonucunu doğrula.';
  @override
  String get back => '← Geri';
  @override
  String get continueLabel => 'Anladım, devam →';
}

// Path: historySurgery.confirm
class _Translations$historySurgery$confirm$tr
    extends Translations$historySurgery$confirm$en {
  _Translations$historySurgery$confirm$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String commitsRewritten({required Object n}) =>
      '${n} commit yeniden yazılacak';
  @override
  String get forcePushRequired => 'Uzak dallar için force-push gerekecek';
  @override
  String worktreesRecheckout({required Object n}) =>
      '${n} çalışma ağacı yeniden checkout edilmeli';
  @override
  String stashesInvalid({required Object n}) =>
      '${n} zula geçersiz hale gelebilir';
  @override
  String get heading => 'Bu işlem git geçmişini yeniden yazar';
  @override
  String get subheading => 'Force-push sonrası otomatik olarak geri alınamaz.';
  @override
  String typeHint({required Object word}) => '${word} yaz';
  @override
  String get goBack => 'Geri Dön';
  @override
  String get begin => 'Cerrahiye Başla';
}

// Path: historySurgery.execute
class _Translations$historySurgery$execute$tr
    extends Translations$historySurgery$execute$en {
  _Translations$historySurgery$execute$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get preparing => 'Hazırlanıyor...';
  @override
  String get backingUpRefs => 'Referanslar yedekleniyor...';
  @override
  String get rewritingCommits => 'Commit\'ler yeniden yazılıyor...';
  @override
  String get updatingRefs => 'Referanslar güncelleniyor...';
}

// Path: historySurgery.verify
class _Translations$historySurgery$verify$tr
    extends Translations$historySurgery$verify$en {
  _Translations$historySurgery$verify$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get complete => 'Cerrahi Tamamlandı';
  @override
  String get failed => 'Cerrahi Başarısız';
  @override
  String get commitsRewrittenLabel => 'Yeniden yazılan commit\'ler';
  @override
  String get refsUpdatedLabel => 'Güncellenen referanslar';
  @override
  String get oldHeadLabel => 'Eski HEAD';
  @override
  String get newHeadLabel => 'Yeni HEAD';
  @override
  String get purgeVerifiedLabel => 'Temizlik doğrulandı';
  @override
  String get purgeClean => 'temiz';
  @override
  String get purgeTracesRemain => 'İZLER KALDI';
  @override
  String get displacedWorktrees => 'Yeri Değişen Çalışma Ağaçları';
  @override
  String get undoSurgery => 'Cerrahiyi Geri Al';
  @override
  String get rolledBack => 'Yedek referanslara geri dönüldü.';
  @override
  String get done => 'Tamam';
}

// Path: historySurgery.forcePush
class _Translations$historySurgery$forcePush$tr
    extends Translations$historySurgery$forcePush$en {
  _Translations$historySurgery$forcePush$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get pushing => 'push ediliyor...';
  @override
  String get forcePushAll => 'Tümünü Force Push';
  @override
  String get confirmPush => 'push\'u onayla';
  @override
  String get cancel => 'iptal';
}

// Path: onboarding.nav
class _Translations$onboarding$nav$tr extends Translations$onboarding$nav$en {
  _Translations$onboarding$nav$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get back => 'Geri';
  @override
  String get continueLabel => 'Devam';
  @override
  String get letsGo => 'Hadi başlayalım';
}

// Path: onboarding.naming
class _Translations$onboarding$naming$tr
    extends Translations$onboarding$naming$en {
  _Translations$onboarding$naming$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'bu senin için ne?';
  @override
  String get questionEmphasis => 'bu';
  @override
  String get iAmPrefix => 'Ben ';
  @override
  String get iAmSuffix => ' , kişisel Git İstemcin.';
}

// Path: onboarding.theme
class _Translations$onboarding$theme$tr
    extends Translations$onboarding$theme$en {
  _Translations$onboarding$theme$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => '${name} giyinsin.';
  @override
  String get themesHeader => 'TEMALAR';
  @override
  String get keybindingsHeader => 'KISAYOL TUŞLARI';
  @override
  String get previewBadge => 'önizleme';
  @override
  String get useDefaults => 'varsayılanları kullan';
}

// Path: onboarding.repo
class _Translations$onboarding$repo$tr extends Translations$onboarding$repo$en {
  _Translations$onboarding$repo$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String title({required Object name}) => '${name} bir şeye baksın.';
  @override
  String get later => 'bunu sonra yaparım';
  @override
  late final _Translations$onboarding$repo$doors$tr doors =
      _Translations$onboarding$repo$doors$tr._(_root);
  @override
  late final _Translations$onboarding$repo$cloneForm$tr cloneForm =
      _Translations$onboarding$repo$cloneForm$tr._(_root);
  @override
  late final _Translations$onboarding$repo$pickers$tr pickers =
      _Translations$onboarding$repo$pickers$tr._(_root);
  @override
  late final _Translations$onboarding$repo$errors$tr errors =
      _Translations$onboarding$repo$errors$tr._(_root);
}

// Path: onboarding.preview
class _Translations$onboarding$preview$tr
    extends Translations$onboarding$preview$en {
  _Translations$onboarding$preview$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$preview$panels$tr panels =
      _Translations$onboarding$preview$panels$tr._(_root);
  @override
  late final _Translations$onboarding$preview$sidebar$tr sidebar =
      _Translations$onboarding$preview$sidebar$tr._(_root);
  @override
  late final _Translations$onboarding$preview$changes$tr changes =
      _Translations$onboarding$preview$changes$tr._(_root);
  @override
  late final _Translations$onboarding$preview$history$tr history =
      _Translations$onboarding$preview$history$tr._(_root);
  @override
  late final _Translations$onboarding$preview$branches$tr branches =
      _Translations$onboarding$preview$branches$tr._(_root);
  @override
  late final _Translations$onboarding$preview$diff$tr diff =
      _Translations$onboarding$preview$diff$tr._(_root);
}

// Path: orrery.header
class _Translations$orrery$header$tr extends Translations$orrery$header$en {
  _Translations$orrery$header$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Orrery';
  @override
  String get modeScrub => 'Tara';
  @override
  String get modeCompare => 'Karşılaştır';
  @override
  String get lodModules => 'Modüller';
  @override
  String get lodFiles => 'Dosyalar';
}

// Path: orrery.status
class _Translations$orrery$status$tr extends Translations$orrery$status$en {
  _Translations$orrery$status$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get loading => 'Manifold, geçmiş boyunca izleniyor…';
  @override
  String get loadError => 'Bu deponun geçmişi okunamadı.';
  @override
  String get notEnoughHistory =>
      'Bir yörünge çizmek için henüz yeterli geçmiş yok.';
  @override
  String get notEnoughHistoryDetail =>
      'Orrery\'nin haritalamak için birkaç commit\'e ihtiyacı var.';
}

// Path: orrery.legend
class _Translations$orrery$legend$tr extends Translations$orrery$legend$en {
  _Translations$orrery$legend$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get central => 'merkezi';
  @override
  String get peripheral => 'çevresel';
}

// Path: orrery.node
class _Translations$orrery$node$tr extends Translations$orrery$node$en {
  _Translations$orrery$node$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get module => 'modül';
  @override
  String moduleWithCount({required Object path, required Object n}) =>
      '${path} · ${n} dosya';
  @override
  String fileFallback({required Object id}) => 'dosya #${id}';
  @override
  String nodeFallback({required Object id}) => 'düğüm #${id}';
  @override
  String get rootModule => '(kök)';
}

// Path: orrery.milestone
class _Translations$orrery$milestone$tr
    extends Translations$orrery$milestone$en {
  _Translations$orrery$milestone$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get genesis => 'başlangıç';
  @override
  String get now => 'şimdi';
  @override
  String get reorganized => 'yeniden düzenlendi';
  @override
  String becameArchetype({required Object archetype}) => '${archetype} oldu';
  @override
  String get snapshot => 'anlık görüntü';
}

// Path: orrery.structure
class _Translations$orrery$structure$tr
    extends Translations$orrery$structure$en {
  _Translations$orrery$structure$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get forming => 'oluşuyor…';
  @override
  String get canonical => 'kanonik';
  @override
  String get connectivity => 'bağlantısallık';
  @override
  String get rigidity => 'katılık';
  @override
  String get entropy => 'entropi';
}

// Path: orrery.rail
class _Translations$orrery$rail$tr extends Translations$orrery$rail$en {
  _Translations$orrery$rail$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get structureLabel => 'YAPI';
  @override
  String get fieldLabel => 'ALAN';
  @override
  String get findingsLabel => 'BULGULAR';
  @override
  String get selectedLabel => 'SEÇİLİ';
  @override
  String get noFindings => 'Bu geçmişte yapısal olay algılanmadı.';
}

// Path: orrery.selection
class _Translations$orrery$selection$tr
    extends Translations$orrery$selection$en {
  _Translations$orrery$selection$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get notPresent => 'Geçmişin bu noktasında mevcut değil.';
  @override
  String get roleCentral =>
      'Bağlaşım-merkezli — buradaki değişiklikler tüm sisteme dalgalanır.';
  @override
  String get rolePeripheral =>
      'Çevresel — gevşek bağlı, çoğunlukla kendi başına değişir.';
  @override
  String get roleMid => 'Orta yapı — orta düzeyde bağlı.';
  @override
  String get driftOutward => ' Dışa doğru sürükleniyor — bağı çözülüyor.';
  @override
  String get driftInward => ' İçe doğru sürükleniyor — bütünleşiyor.';
  @override
  String get driftHolding => ' Konumunu koruyor.';
}

// Path: orrery.findingKind
class _Translations$orrery$findingKind$tr
    extends Translations$orrery$findingKind$en {
  _Translations$orrery$findingKind$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get hub => 'HUB';
  @override
  String get driftOut => 'DIŞA SÜRÜKLENİYOR';
  @override
  String get driftIn => 'İÇE SÜRÜKLENİYOR';
  @override
  String get tangle => 'DÜĞÜMLENİYOR';
  @override
  String get clarify => 'BERRAKLAŞIYOR';
  @override
  String get regime => 'REORG';
  @override
  String get thrash => 'ÇALKALANIYOR';
  @override
  String get reshuffle => 'YENİDEN KARMA';
  @override
  String get forecast => 'TAHMİN';
}

// Path: orrery.findings
class _Translations$orrery$findings$tr extends Translations$orrery$findings$en {
  _Translations$orrery$findings$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get forecastSplit =>
      'Bağlantısallık düşüyor ve en düşük noktasına yakın — bu böyle giderse, kod tabanı gevşek bağlı iki yarıya bölünmeye doğru ilerliyor. Bunun amaç olup olmadığına şimdi karar ver.';
  @override
  String get forecastConsolidate =>
      'Bağlantısallık zirvesine doğru tırmanıyor — bu böyle giderse, kod tabanı sıkı bağlı tek bir kütleye yoğunlaşıyor. Bir monolite katılaşmasına dikkat et.';
  @override
  String thrash({required Object name}) =>
      '${name} sürekli ileri geri yeniden düzenleniyor — çok yapısal çalkantı, az net hareket. Bağlaşımını yerine oturt ya da ona dokunmayı bırak.';
  @override
  String get reshuffle =>
      'Bu commit rutin görünüyordu ama hangi dosyaların merkezi olduğunu sessizce değiştirdi — genel biçim korunurken yapı altında yeniden karıldı. Onu dikkatle incele.';
  @override
  String hub({required Object name}) =>
      '${name} yapısal çekirdekte oturuyor — sistem onun etrafında yeniden düzenleniyor. Buradaki değişiklikleri yüksek patlama yarıçaplı olarak ele al.';
  @override
  String driftOut({required Object name}) =>
      '${name} çekirdekten kenara sürüklendi — sistemden bağı çözülüyor. Ya emekliye ayrılıyor ya da sessizce çürüyor.';
  @override
  String driftIn({required Object name}) =>
      '${name} çekirdeğe doğru göç etti — yük taşıyan hale geliyor. Ona daha fazlası bağlanmadan önce iyi test edildiğinden emin ol.';
  @override
  String get regime =>
      'Kod tabanı burada keskin şekilde yeniden düzenlendi — bağlantısallığı sıçradı. Neyin ayrıldığını veya birleştiğini incele.';
  @override
  String get tangleTrend =>
      'Geçmişi boyunca kod tabanı daha düğümlü bir yapıya eğilim gösterdi — bağlantısallığı yoğunlaşıyor ve daha az modüler hale geliyor.';
  @override
  String get clarifyTrend =>
      'Geçmişi boyunca kod tabanı daha temiz bir yapıya eğilim gösterdi — daha net modüllere ayrılıyor.';
}

// Path: orrery.anchor
class _Translations$orrery$anchor$tr extends Translations$orrery$anchor$en {
  _Translations$orrery$anchor$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get core => 'çekirdek';
  @override
  String get drift => 'sürüklenme';
  @override
  String get trend => 'eğilim';
  @override
  String get thrash => 'çalkantı';
}

// Path: orrery.compare
class _Translations$orrery$compare$tr extends Translations$orrery$compare$en {
  _Translations$orrery$compare$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'A → B';
  @override
  String get change => 'DEĞİŞİM';
  @override
  String get movers => 'HAREKET EDENLER';
  @override
  String get noMovers => 'Bu kareler arasında dosya hareket etmedi.';
  @override
  String get badgeA => 'A';
  @override
  String get badgeB => 'B';
  @override
  String get deltaFiles => 'dosyalar';
  @override
  String get deltaConnectivity => 'bağlantısallık';
  @override
  String get deltaRigidity => 'katılık';
  @override
  String get deltaEntropy => 'entropi';
  @override
  String get wayOutward => 'dışa';
  @override
  String get wayInward => 'içe';
  @override
  String get wayShifted => 'kaydı';
}

// Path: palette.prefixes
class _Translations$palette$prefixes$tr
    extends Translations$palette$prefixes$en {
  _Translations$palette$prefixes$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get askHint => 'sor: [soru]';
  @override
  String get nearHint => 'yakın: [dosya]';
  @override
  String get whoHint => 'kim: [dosya]';
  @override
  String get logHint => 'log: [mesaj]';
  @override
  String get runHint => 'çalıştır: [araç]';
  @override
  String askLabel({required Object name, required Object body}) =>
      'Sor (${name}): ${body}';
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
  }) => '${path} · ${count} inceleyici · ${touches} dokunma';
  @override
  String whoTouchesLabel({required Object name, required Object touches}) =>
      '${name} — ${touches} dokunma';
  @override
  String whoTouchesSubtitle({required Object path}) =>
      '${path} · inceleyici kaydı yok';
}

// Path: palette.chips
class _Translations$palette$chips$tr extends Translations$palette$chips$en {
  _Translations$palette$chips$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get ai => 'AI';
  @override
  String get near => 'YAKIN';
  @override
  String get who => 'KİM';
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
  String get hot => 'SICAK';
  @override
  String get key => 'KEY';
  @override
  String get web => 'WEB';
  @override
  String get sys => 'SYS';
  @override
  String get clip => 'PANO';
  @override
  String get sync => 'EŞİT';
  @override
  String get force => 'ZORLA';
  @override
  String get pr => 'PR';
  @override
  String get draft => 'TASLAK';
  @override
  String get undo => 'GERİ AL';
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
  String get gone => 'GİTTİ';
  @override
  String get remote => 'UZAK';
  @override
  String get local => 'YEREL';
  @override
  String get an => 'AN';
  @override
  String get lw => 'LW';
}

// Path: palette.predictive
class _Translations$palette$predictive$tr
    extends Translations$palette$predictive$en {
  _Translations$palette$predictive$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String momentumSuffix({required Object percent}) => '%${percent} momentum';
}

// Path: palette.topTouched
class _Translations$palette$topTouched$tr
    extends Translations$palette$topTouched$en {
  _Translations$palette$topTouched$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object count, required Object path}) =>
      '${count} dokunma · ${path}';
}

// Path: palette.coherence
class _Translations$palette$coherence$tr
    extends Translations$palette$coherence$en {
  _Translations$palette$coherence$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String label({required Object percent}) =>
      'Hazırlama tutarlılığı: %${percent}';
  @override
  String subtitle({required Object count}) => '${count} dosya';
}

// Path: palette.keystone
class _Translations$palette$keystone$tr
    extends Translations$palette$keystone$en {
  _Translations$palette$keystone$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String subtitle({required Object path, required Object score}) =>
      '${path} · kilit taşı ${score}';
}

// Path: palette.repoSub
class _Translations$palette$repoSub$tr extends Translations$palette$repoSub$en {
  _Translations$palette$repoSub$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String changes({required Object name}) => '${name} deposunda Değişiklikler';
  @override
  String history({required Object name}) => '${name} deposunda Geçmiş';
  @override
  String branches({required Object name}) => '${name} deposunda Dallar';
  @override
  String terminal({required Object name}) => '${name} deposunda Terminal';
  @override
  String generateCommit({required Object name}) => 'Commit Üret · ${name}';
  @override
  String reviewChanges({required Object name}) =>
      '${name} deposunda Değişiklikleri İncele';
  @override
  String muse({required Object name}) => '${name} deposunda Muse';
}

// Path: palette.desks
class _Translations$palette$desks$tr extends Translations$palette$desks$en {
  _Translations$palette$desks$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get mainWorktree => 'ana çalışma ağacı';
  @override
  String get detached => 'detached';
  @override
  String dirty({required Object count}) => '${count} kirli';
}

// Path: palette.actions
class _Translations$palette$actions$tr extends Translations$palette$actions$en {
  _Translations$palette$actions$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get openInBrowser => 'Tarayıcıda Aç';
  @override
  String get terminal => 'Terminal';
  @override
  String get revealInFiles => 'Dosya Yöneticisinde Göster';
  @override
  String get copyPath => 'Yolu Kopyala';
  @override
  String get copyBranch => 'Dalı Kopyala';
}

// Path: palette.tools
class _Translations$palette$tools$tr extends Translations$palette$tools$en {
  _Translations$palette$tools$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String launch({required Object label}) => '${label} başlat';
}

// Path: palette.gitCommands
class _Translations$palette$gitCommands$tr
    extends Translations$palette$gitCommands$en {
  _Translations$palette$gitCommands$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get fetch => 'Fetch';
  @override
  String get pull => 'Pull';
  @override
  String pullBehind({required Object count}) => '${count} geride';
  @override
  String pullBehindUpstream({
    required Object behind,
    required Object upstream,
  }) => '${behind} ${upstream}';
  @override
  String get push => 'Push';
  @override
  String pushCommits({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} commit',
        other: '${n} commit',
      );
  @override
  String pushCommitsUpstream({
    required Object commits,
    required Object upstream,
  }) => '${commits}, ${upstream} hedefine';
  @override
  String get forcePush => 'Force Push';
  @override
  String forcePushNoUpstream({required Object branch}) =>
      'Force-push yapılamıyor: ${branch} için upstream ayarlanmamış.';
  @override
  String get commit => 'Commit';
  @override
  String get stageAll => 'Tümünü Hazırla';
  @override
  String get unstageAll => 'Tümünü Hazırlıktan Çıkar';
  @override
  String get discardAll => 'Tümünü Sil';
  @override
  String get createBranch => 'Dal Oluştur';
  @override
  String get deleteBranch => 'Dal Sil';
  @override
  String get renameBranch => 'Dalı Yeniden Adlandır';
  @override
  String get stash => 'Stash';
  @override
  String get stashPop => 'Stash Pop';
  @override
  String get stashApply => 'Stash Apply';
  @override
  String get stashDrop => 'Stash Drop';
  @override
  String get createTag => 'Etiket Oluştur';
  @override
  String get cherryPick => 'Cherry-pick';
  @override
  String get revert => 'Revert';
  @override
  String get stashConflictMessage =>
      'Stash çakışmalarla uygulandı. Onları Değişiklikler sayfasında çöz.';
}

// Path: palette.pr
class _Translations$palette$pr$tr extends Translations$palette$pr$en {
  _Translations$palette$pr$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get create => 'PR Oluştur';
  @override
  String get merge => 'PR\'ı Merge Et';
  @override
  String get markReady => 'PR\'ı Hazır İşaretle';
}

// Path: palette.ai
class _Translations$palette$ai$tr extends Translations$palette$ai$en {
  _Translations$palette$ai$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get generateCommit => 'Commit Üret';
  @override
  String get reviewChanges => 'Değişiklikleri İncele';
  @override
  String get runMuse => 'Muse Çalıştır';
  @override
  String debugRepo({required Object name}) => 'Hata Ayıkla: ${name}';
  @override
  String get describeSymptom => 'bir belirti tarif et';
  @override
  String viewResult({required Object kind}) => '${kind} görüntüle';
  @override
  String get unseenResult => 'görülmemiş sonuç';
  @override
  String runningResult({required Object kind}) => 'AI: ${kind}…';
  @override
  String get running => 'çalışıyor';
  @override
  String get kindCommitMessage => 'Commit Mesajı';
  @override
  String get kindCodeReview => 'Kod İncelemesi';
  @override
  String get kindMuseResult => 'Muse Sonucu';
  @override
  String get kindPresentation => 'Sunum';
  @override
  String get kindDebugResult => 'Hata Ayıklama Sonucu';
}

// Path: palette.undo
class _Translations$palette$undo$tr extends Translations$palette$undo$en {
  _Translations$palette$undo$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String cancel({required Object label}) => 'İptal: ${label}';
}

// Path: palette.navigation
class _Translations$palette$navigation$tr
    extends Translations$palette$navigation$en {
  _Translations$palette$navigation$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get changes => 'Değişiklikler';
  @override
  String get history => 'Geçmiş';
  @override
  String get branches => 'Dallar';
  @override
  String get xray => 'X-Ray';
  @override
  String get settings => 'Ayarlar';
  @override
  String get refresh => 'Yenile';
}

// Path: palette.settings
class _Translations$palette$settings$tr
    extends Translations$palette$settings$en {
  _Translations$palette$settings$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get reduceMotion => 'Hareketi Azalt';
  @override
  String get animateLogoUnfocused => 'Logoyu Odak Dışıyken Canlandır';
  @override
  String get instantBlameHover => 'Anında Blame Vurgusu';
  @override
  String get autoSelectChanges => 'Değişiklikleri Otomatik Seç';
  @override
  String get fetchOnlineIssues => 'Çevrimiçi Issue\'ları Fetch Et';
  @override
  String get rememberWip => 'Devam Eden İşi Hatırla';
  @override
  String get hideAiFeatures => 'AI Özelliklerini Gizle';
  @override
  String get crashReporting => 'Çökme Raporlama';
  @override
  String get aiReadOnly => 'AI Salt Okunur';
  @override
  String get stashCabinetExpanded => 'Stash Dolabı Açık';
  @override
  String get fileSortInverted => 'Dosya Sıralaması Ters';
}

// Path: palette.info
class _Translations$palette$info$tr extends Translations$palette$info$en {
  _Translations$palette$info$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String version({required Object version}) => 'Manifold ${version}';
}

// Path: palette.debug
class _Translations$palette$debug$tr extends Translations$palette$debug$en {
  _Translations$palette$debug$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get engineStatus => 'Motor Durumu';
  @override
  String get engineStatusSubtitle => 'LogosGit spektral motor tanılaması';
  @override
  String get fileCoupling => 'Dosya Bağlaşımı';
  @override
  String get fileCouplingSubtitle =>
      'Hazırlanan dosyalar için en yakın ortak-değişim komşuları';
  @override
  String get themeSpecimen => 'Tema Örneği';
  @override
  String get themeSpecimenSubtitle =>
      'Tüm renkler, simgeler, metin katmanları ve geometri';
}

// Path: palette.dev
class _Translations$palette$dev$tr extends Translations$palette$dev$en {
  _Translations$palette$dev$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get testMergeEditor => 'Merge Editörünü Test Et';
  @override
  String get testHistorySurgery => 'Geçmiş Cerrahisini Test Et';
  @override
  String get back => 'geri';
  @override
  String get cancel => 'iptal';
  @override
  String get buildingConflicts => 'geçmişten test çakışmaları oluşturuluyor…';
}

// Path: palette.historySurgery
class _Translations$palette$historySurgery$tr
    extends Translations$palette$historySurgery$en {
  _Translations$palette$historySurgery$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Geçmiş Cerrahisi';
  @override
  String get subtitle =>
      'Dosyaları kalıcı olarak kaldırmak için geçmişi yeniden yaz';
}

// Path: palette.orrery
class _Translations$palette$orrery$tr extends Translations$palette$orrery$en {
  _Translations$palette$orrery$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Orrery';
  @override
  String get subtitle => 'Deponun yapısal geçmişini manifold boyunca tara';
}

// Path: palette.command
class _Translations$palette$command$tr extends Translations$palette$command$en {
  _Translations$palette$command$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String complete({required Object label}) => '${label} tamamlandı';
  @override
  String failed({required Object label, required Object message}) =>
      '${label} başarısız: ${message}';
  @override
  String get copy => 'Kopyala';
}

// Path: palette.search
class _Translations$palette$search$tr extends Translations$palette$search$en {
  _Translations$palette$search$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get hintDefault => 'her şeyde ara...';
  @override
  String get hintElevated => 'yükseltilmiş — tüm eylemler';
  @override
  String get emptyTypeToSearch => 'aramak için yaz';
  @override
  String get emptyNoResults => 'sonuç yok';
}

// Path: palette.wick
class _Translations$palette$wick$tr extends Translations$palette$wick$en {
  _Translations$palette$wick$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'wick';
  @override
  String get coupledFallback => 'bağlı';
}

// Path: palette.gitCache
class _Translations$palette$gitCache$tr
    extends Translations$palette$gitCache$en {
  _Translations$palette$gitCache$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'güncel';
  @override
  String get staged => 'hazırlanmış';
  @override
  String get modified => 'değiştirilmiş';
}

// Path: releaseNotes.about
class _Translations$releaseNotes$about$tr
    extends Translations$releaseNotes$about$en {
  _Translations$releaseNotes$about$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$releaseNotes$about$whyFlutter$tr whyFlutter =
      _Translations$releaseNotes$about$whyFlutter$tr._(_root);
  @override
  late final _Translations$releaseNotes$about$spectralEngine$tr spectralEngine =
      _Translations$releaseNotes$about$spectralEngine$tr._(_root);
  @override
  late final _Translations$releaseNotes$about$whereGoing$tr whereGoing =
      _Translations$releaseNotes$about$whereGoing$tr._(_root);
}

// Path: releaseNotes.legal
class _Translations$releaseNotes$legal$tr
    extends Translations$releaseNotes$legal$en {
  _Translations$releaseNotes$legal$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get copyright => '© 2026 Woflo Labs';
  @override
  String get license =>
      'GPL-3.0-or-later · WLCSL topluluk kaynaklı araştırma çekirdeği · garanti yok';
}

// Path: repoSummary.backbone
class _Translations$repoSummary$backbone$tr
    extends Translations$repoSummary$backbone$en {
  _Translations$repoSummary$backbone$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String entry({
    required Object path,
    required Object lines,
    required Object region,
  }) => '`${path}` (${lines}) — ${region}';
  @override
  String lineCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} satır',
        other: '${n} satır',
      );
  @override
  String purposeSuffix({required Object purpose}) => ' · ${purpose}';
}

// Path: repoSummary.glance
class _Translations$repoSummary$glance$tr
    extends Translations$repoSummary$glance$en {
  _Translations$repoSummary$glance$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String files({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} dosya.',
        other: '${n} dosya.',
      );
  @override
  String lines({required num n, required Object bytes}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} satır (${bytes}).',
        other: '${n} satır (${bytes}).',
      );
  @override
  String roles({required Object parts}) => 'Roller — ${parts}.';
  @override
  String showingNofM({required Object total, required Object active}) =>
      '${total} dosyadan ${active} tanesi gösteriliyor, yapısal merkeziyete göre sıralı.';
}

// Path: repoSummary.heading
class _Translations$repoSummary$heading$tr
    extends Translations$repoSummary$heading$en {
  _Translations$repoSummary$heading$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get atAGlance => 'Bir bakışta';
  @override
  String get core => 'Çekirdek';
  @override
  String get gettingStarted => 'Başlarken';
  @override
  String get regions => 'Bölgeler';
  @override
  String get shape => 'Biçim';
}

// Path: repoSummary.pitch
class _Translations$repoSummary$pitch$tr
    extends Translations$repoSummary$pitch$en {
  _Translations$repoSummary$pitch$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String empty({required Object detail}) =>
      'Okunabilir metin dosyası olmayan bir depo${detail}.';
  @override
  String emptyBinary({required Object n}) => '${n} ikili';
  @override
  String emptyUnreadable({required Object n}) => '${n} okunamaz';
  @override
  String noRegions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} etkin dosyalı bir depo.',
        other: '${n} etkin dosyalı bir depo.',
      );
  @override
  String withRegions({required num n, required Object regions}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} etkin dosyalı bir depo — ${regions}.',
        other: '${n} etkin dosyalı bir depo — ${regions}.',
      );
}

// Path: repoSummary.region
class _Translations$repoSummary$region$tr
    extends Translations$repoSummary$region$en {
  _Translations$repoSummary$region$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String bodyCommonDir({required Object dir}) => 'Tümü `${dir}` altında.';
  @override
  String get bodyCommonDirSeparator => ' ';
  @override
  String bodyCore({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '1 çekirdek',
        other: '${n} çekirdek',
      );
  @override
  String get bodyCoreSeparator => ', ';
  @override
  String bodyFiles({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: 'Bir dosya',
        other: '${n} dosya',
      );
  @override
  String connectsTo({required Object linked}) => 'Şuna bağlanır: ${linked}.';
  @override
  String get filesLabel => 'Dosyalar:';
}

// Path: repoSummary.shape
class _Translations$repoSummary$shape$tr
    extends Translations$repoSummary$shape$en {
  _Translations$repoSummary$shape$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get bulk =>
      'Yoğun bağlı kod tabanı: çoğu dosya, paylaşılan değişimin tek büyük bir komşuluğuna katılır.';
  @override
  String get crystalline =>
      'Kafes biçimli kod tabanı: dosyalar arasında öngörülebilir yerel yapıyla düzenli, tekdüze bağlaşım.';
  @override
  String get goe =>
      'Zengin bağlı kod tabanı: bağlaşımlar baskın bir omurga olmadan dosyalara yayılır.';
  @override
  String get modular =>
      'Modüler kod tabanı: sınırlı çapraz bağlaşımlı birkaç uyumlu bölge. Bir bölgedeki çalışma nadiren bir diğerini rahatsız eder.';
  @override
  String get poisson =>
      'Gevşek bağlı kod tabanı: dosyalar çoğunlukla kendi başına gelişir, ara sıra paylaşılan değişimle.';
  @override
  String get tree =>
      'Ağaç biçimli kod tabanı: bağımlı dallara sahip tek baskın omurga. Değişim genellikle çekirdekten dışarı yayılır.';
}

// Path: settings.language
class _Translations$settings$language$tr
    extends Translations$settings$language$en {
  _Translations$settings$language$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Dil';
  @override
  String get summary =>
      'Bu uygulama için arayüz dili. Git çıktısı, günlükler ve tanılamalar İngilizce kalır, böylece hata raporları aranabilir kalır.';
  @override
  String get label => 'GÖRÜNÜM DİLİ';
  @override
  String get systemDefault => 'Sistem varsayılanı';
  @override
  String systemDefaultDetail({required Object resolved}) =>
      'İşletim sistemi dilini takip eder (${resolved})';
  @override
  String get disclosureSource =>
      'Kaynak dil, geliştiriciler tarafından yazıldı.';
  @override
  String disclosureAi({required Object model}) =>
      '${model} tarafından makine çevirisi, henüz insan tarafından incelenmedi. Düzeltmeler memnuniyetle karşılanır.';
  @override
  String disclosureAiReviewed({
    required Object model,
    required Object percent,
  }) =>
      '${model} tarafından makine çevirisi. %${percent} insan tarafından incelendi.';
  @override
  String get disclosureHuman =>
      'İnsan çevirisi, topluluk tarafından sürdürülüyor.';
  @override
  String reviewedBy({required Object names}) =>
      '${names} tarafından incelendi.';
}

// Path: settings.sectionLabels
class _Translations$settings$sectionLabels$tr
    extends Translations$settings$sectionLabels$en {
  _Translations$settings$sectionLabels$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get preferences => 'Tercihler';
  @override
  String get shortcuts => 'Kısayollar';
  @override
  String get behaviour => 'Davranış';
  @override
  String get aiProviders => 'AI Sağlayıcıları';
  @override
  String get modelSlots => 'Model Yuvaları';
  @override
  String get tools => 'Araçlar';
  @override
  String get diagnostics => 'Tanılama';
  @override
  String get offenders => 'İhlaller';
  @override
  String get release => 'Sürüm';
}

// Path: settings.errors
class _Translations$settings$errors$tr extends Translations$settings$errors$en {
  _Translations$settings$errors$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get saveGuardrailProfile => 'Koruma profili kaydedilemedi.';
  @override
  String get saveRetentionPolicy => 'Saklama politikası kaydedilemedi.';
  @override
  String get saveUpdateChannel => 'Güncelleme kanalı kaydedilemedi.';
  @override
  String get saveModelSelection => 'AI model seçimi kaydedilemedi.';
  @override
  String get saveModelAlias => 'Model takma adı kaydedilemedi.';
  @override
  String get saveCommitMessageModelSlot =>
      'Commit mesajı model yuvası kaydedilemedi.';
  @override
  String get saveReviewModelSlot => 'İnceleme model yuvası kaydedilemedi.';
  @override
  String get saveCommitMessageCustomPrompt =>
      'Commit mesajı özel istemi kaydedilemedi.';
  @override
  String get saveReviewGuide => 'İnceleme kılavuzu kaydedilemedi.';
  @override
  String get saveMuseNotes => 'Muse notları kaydedilemedi.';
  @override
  String get saveReviewDoubleCheck =>
      'İnceleme çift kontrol modu kaydedilemedi.';
  @override
  String get saveApiPiggybackCli => 'API sırtlama CLI\'ı kaydedilemedi.';
  @override
  String get saveCliTimeout => 'CLI zaman aşımı kaydedilemedi.';
  @override
  String get stopAllCli => 'Çalışan CLI oturumları durdurulamadı.';
  @override
  String clearLocalData({required Object error}) =>
      'Yerel veri temizlenemedi: ${error}';
}

// Path: settings.promptStatus
class _Translations$settings$promptStatus$tr
    extends Translations$settings$promptStatus$en {
  _Translations$settings$promptStatus$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get editing => 'Düzenleniyor';
  @override
  String get saving => 'Kaydediliyor';
  @override
  String get saveFailed => 'Kaydetme başarısız';
}

// Path: settings.clearData
class _Translations$settings$clearData$tr
    extends Translations$settings$clearData$en {
  _Translations$settings$clearData$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get dialogTitle => 'Yerel veriyi temizle';
  @override
  String get clear => 'Temizle';
  @override
  String get confirmDiagnostics =>
      'Yerel tanılama örnekleri ve performans zamanlamaları temizlensin mi?';
  @override
  String get confirmAudit =>
      'Yerel AI denetim meta veri kayıtları temizlensin mi?';
  @override
  String get confirmAll =>
      'Tüm yerel tanılama örnekleri ve AI denetim meta veri kayıtları temizlensin mi?';
  @override
  String get confirmWipeAll =>
      'Son depolar listesi dahil tüm yerel uygulama verisi silinip çıkılsın mı? Diskteki gerçek git depolarına dokunulmaz.';
  @override
  String get confirmReset =>
      'Yerel uygulama verisi sıfırlanıp çıkılsın mı?\n\nAyarlar, tema, ilk kullanım, AI tercihleri, telemetri ve engram önbellekleri temizlenir. Son depolar listesi korunur.';
}

// Path: settings.guardrailMacro
class _Translations$settings$guardrailMacro$tr
    extends Translations$settings$guardrailMacro$en {
  _Translations$settings$guardrailMacro$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get loose => 'gevşek';
  @override
  String get balanced => 'dengeli';
  @override
  String get strict => 'katı';
  @override
  String get paranoid => 'paranoyak';
}

// Path: settings.guardrails
class _Translations$settings$guardrails$tr
    extends Translations$settings$guardrails$en {
  _Translations$settings$guardrails$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Koruma Önlemleri';
  @override
  String get summary =>
      'Tüm deneyim boyunca otomasyonun ne kadar dikkatli olduğu.';
}

// Path: settings.appearance
class _Translations$settings$appearance$tr
    extends Translations$settings$appearance$en {
  _Translations$settings$appearance$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Görünüm';
  @override
  String get summary => 'Küresel arayüz havası ve atmosferi.';
}

// Path: settings.retention
class _Translations$settings$retention$tr
    extends Translations$settings$retention$en {
  _Translations$settings$retention$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Yerel Veri Saklama';
  @override
  String get summaryDiagnostics => 'Tanılama saklama politikası.';
  @override
  String get summaryWithAudit => 'Tanılama ve AI denetim saklama politikası.';
  @override
  String get unitDays => 'gün';
  @override
  String get unitMb => 'MB';
  @override
  String get includesNote =>
      'Tanılamayı, performans zamanlamalarını ve meta veriyi içerir.';
}

// Path: settings.navigation
class _Translations$settings$navigation$tr
    extends Translations$settings$navigation$en {
  _Translations$settings$navigation$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Gezinme ve Dinamikler';
  @override
  String get summaryShortcuts => 'Kısayollar ve arayüz davranışı.';
  @override
  String get summaryWithAi => 'Kısayollar, arayüz davranışı ve AI yönlendirme.';
}

// Path: settings.behaviour
class _Translations$settings$behaviour$tr
    extends Translations$settings$behaviour$en {
  _Translations$settings$behaviour$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Davranışsal Dinamikler';
}

// Path: settings.retentionClear
class _Translations$settings$retentionClear$tr
    extends Translations$settings$retentionClear$en {
  _Translations$settings$retentionClear$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get diag => 'Tanı';
  @override
  String get audit => 'Denetim';
  @override
  String get all => 'Tümü';
  @override
  String get clearsHint => '<-- temizler';
}

// Path: settings.channels
class _Translations$settings$channels$tr
    extends Translations$settings$channels$en {
  _Translations$settings$channels$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get stable => 'KARARLI';
  @override
  String get beta => 'BETA';
  @override
  String get dev => 'DEV';
}

// Path: settings.pollResult
class _Translations$settings$pollResult$tr
    extends Translations$settings$pollResult$en {
  _Translations$settings$pollResult$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get upToDate => 'güncel';
  @override
  String updateAvailable({required Object version}) => '${version} mevcut';
  @override
  String get notConfigured => 'güncelleme sunucusu yok';
  @override
  String notFound({required Object channel}) => '${channel} sürümü yok';
  @override
  String get unreachable => 'erişilemez';
  @override
  String get badManifest => 'bozuk manifest';
}

// Path: settings.keybindingProfile
class _Translations$settings$keybindingProfile$tr
    extends Translations$settings$keybindingProfile$en {
  _Translations$settings$keybindingProfile$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Tuş atama profili';
  @override
  String get porcelain => 'Porcelain';
  @override
  String get numeric => 'Sayısal';
  @override
  String get porcelainDescription => 'Akorlu kısayollar (G sonra C, H, B…).';
  @override
  String get numericDescription => 'Tek tuşlu sayısal kısayollar (1, 2, 3…).';
}

// Path: settings.apiKeys
class _Translations$settings$apiKeys$tr
    extends Translations$settings$apiKeys$en {
  _Translations$settings$apiKeys$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get keyHintDefault => 'api anahtarı';
  @override
  String get endpointHint => 'uç nokta';
  @override
  String get test => 'Test';
  @override
  String get hide => 'Gizle';
  @override
  String get show => 'Göster';
}

// Path: settings.shortcuts
class _Translations$settings$shortcuts$tr
    extends Translations$settings$shortcuts$en {
  _Translations$settings$shortcuts$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get navigate => 'gezin';
  @override
  String get staging => 'hazırlama';
  @override
  String get branchesPrs => 'dallar & PR\'lar';
  @override
  String get modifiers => 'değiştiriciler';
  @override
  String get changes => 'Değişiklikler';
  @override
  String get history => 'Geçmiş';
  @override
  String get branches => 'Dallar';
  @override
  String get xray => 'X-Ray';
  @override
  String get switchAlways => 'Geçiş (her zaman)';
  @override
  String get search => 'Ara';
  @override
  String get dismiss => 'Kapat';
  @override
  String get refresh => 'Yenile';
  @override
  String get shortcuts => 'Kısayollar';
  @override
  String get nextChange => 'Sonraki değişiklik';
  @override
  String get prevChange => 'Önceki değişiklik';
  @override
  String get toggleLine => 'Satırı aç/kapa';
  @override
  String get toggleHunk => 'Hunk\'ı aç/kapa';
  @override
  String get toggleFile => 'Dosyayı aç/kapa';
  @override
  String get pinContext => 'Bağlamı sabitle';
  @override
  String get commit => 'Commit';
  @override
  String get acceptHint => 'İpucunu kabul et';
  @override
  String get undo => 'Geri al';
  @override
  String get navigateRow => 'Gezin';
  @override
  String get expand => 'Genişlet';
  @override
  String get checkout => 'Checkout';
  @override
  String get approve => 'Onayla';
  @override
  String get requestChanges => 'Değişiklik iste';
  @override
  String get selectRange => 'Aralık seç';
  @override
  String get extendedMenu => 'Genişletilmiş menü';
}

// Path: settings.toggles
class _Translations$settings$toggles$tr
    extends Translations$settings$toggles$en {
  _Translations$settings$toggles$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get aiReadOnlyLabel => 'AI salt okunur modu';
  @override
  String get aiReadOnlyDescription =>
      'AI\'ın otomatik olarak değişiklik yazmasını ya da hazırlamasını engeller.';
  @override
  String get logoMotionLabel => 'Sekme dışındayken logo canlanır';
  @override
  String get logoMotionDescriptionEnabled =>
      'Verimli olacak şekilde tasarlandı, kalbini kırma';
  @override
  String get logoMotionDescriptionDisabled => ':(';
  @override
  String get rememberWipLabel => 'Devam eden işi hatırla';
  @override
  String get rememberWipDescription =>
      'Commit taslaklarını ve dosya seçimini oturumlar arasında koru.';
  @override
  String get stashCabinetLabel => 'Stash dolabı açık başlar';
  @override
  String get stashCabinetDescription =>
      'Bir deponun rafları olduğunda dosya dolabı çekmecesini varsayılan olarak açık göster.';
  @override
  String get instantBlameLabel => 'Anında blame vurgusu';
  @override
  String get instantBlameDescription =>
      'Bir diff satırında blame bilgisi belirmeden önceki 180ms gecikmeyi atla.';
  @override
  String get autoSelectLabel => 'Yeni değişiklikleri otomatik seç';
  @override
  String get autoSelectDescription =>
      'Yeni izlenen ya da değişen dosyalar otomatik olarak commit seçimine eklenir.';
  @override
  String get changeIdLabel => 'change-id üstbilgilerini yaz';
  @override
  String get changeIdDescription =>
      'Yeni commit\'lere change-id kimlik üstbilgisi ekler (Jujutsu, GitButler ve Gerrit standardı). Her commit oluşturulduktan hemen sonra bir kez yeniden yazılır.';
  @override
  String get fetchIssuesLabel =>
      'Dal yüklenirken çevrimiçi issue\'ları fetch et';
  @override
  String get fetchIssuesDescription =>
      'Dallar sayfası açıldığında PR ve issue ayrıntılarını git sağlayıcından arka planda çek.';
  @override
  String get hateAiLabel => 'AI\'dan nefret ediyorum';
  @override
  String get hateAiDescription =>
      'Tüm LLM destekli özellikleri kov. Logos çalışmaya devam eder çünkü o sadece spektral matematik.';
}

// Path: settings.diffDiffability
class _Translations$settings$diffDiffability$tr
    extends Translations$settings$diffDiffability$en {
  _Translations$settings$diffDiffability$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'diff diff-lenebilirliği';
}

// Path: settings.modelSlots
class _Translations$settings$modelSlots$tr
    extends Translations$settings$modelSlots$en {
  _Translations$settings$modelSlots$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get loadingProviders => 'Sağlayıcılar yükleniyor...';
  @override
  String get refreshingProviders => 'Sağlayıcı tanılaması yenileniyor...';
  @override
  String get routeDescription =>
      'Yapılandırmaları algılanan herhangi bir sağlayıcı modeline yeniden adlandır ve yönlendir.';
  @override
  String get loadingCategories => 'Model kategorileri yükleniyor...';
  @override
  String get noOptions =>
      'Henüz model seçeneği yok. Önce uyumlu bir yerel AI CLI\'ı algıla.';
  @override
  String get slotsAppearWhenAvailable =>
      'Sağlayıcı modelleri hazır olduğunda model yuvası ayarları burada görünecek.';
  @override
  String get effortDefault => 'varsayılan';
  @override
  String get noModelsForSlot => 'Bu yuva için model algılanmadı.';
  @override
  String viaProvider({required Object provider}) => '${provider} üzerinden';
  @override
  String get customModelId => 'özel model kimliği';
}

// Path: settings.modelPicker
class _Translations$settings$modelPicker$tr
    extends Translations$settings$modelPicker$en {
  _Translations$settings$modelPicker$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String noMatch({required Object query}) => '"${query}" ile eşleşen model yok';
  @override
  String get noModels => 'kullanılabilir model yok';
  @override
  String get filterHint => 'modelleri filtrele...';
  @override
  String get warming => 'ısınıyor…';
  @override
  String get detailsUnavailable => 'ayrıntılar kullanılamıyor';
  @override
  String get free => 'ücretsiz';
}

// Path: settings.aiFeatures
class _Translations$settings$aiFeatures$tr
    extends Translations$settings$aiFeatures$en {
  _Translations$settings$aiFeatures$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get commitDescription =>
      'Yapını, sesini ve kapsam tercihlerini kullanarak hazırlanan değişikliklerden commit mesajları taslağı oluştur.';
  @override
  String get reviewDescription =>
      'Commit\'lemeden önce mevcut commit kapsamını incele.';
  @override
  String get museDescription =>
      'Beyin fırtınası yapıp sonra diff için ileri bir yön sentezleyen üç aşamalı kâhin.';
}

// Path: settings.commitEditor
class _Translations$settings$commitEditor$tr
    extends Translations$settings$commitEditor$en {
  _Translations$settings$commitEditor$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get styleGuide => 'Stil Kılavuzu';
  @override
  String get styleGuideHint =>
      'İsteğe bağlı. Ses / ton / yasaklar. Yukarıdaki biçim iskeleti halleder.';
}

// Path: settings.review
class _Translations$settings$review$tr extends Translations$settings$review$en {
  _Translations$settings$review$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'İncelemede kullanılacak ek notlar';
  @override
  String get doubleCheckLabel => 'İncelemeyi çift kontrol et';
  @override
  String get doubleCheckDescription =>
      'Nihai raporu göstermeden önce ikinci bir doğrulama turu çalıştır.';
}

// Path: settings.museHint
class _Translations$settings$museHint$tr
    extends Translations$settings$museHint$en {
  _Translations$settings$museHint$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get loose =>
      'nazikçe yönlendirilecek bir şey var mı? bugün ruh hali iyi.';
  @override
  String get balanced =>
      'neye odaklanılacak, ne atlanacak. dürüst, ama sert değil.';
  @override
  String get strict => 'standartlar. yasaklar. muse\'un geçmeyeceği şeyler.';
  @override
  String get paranoid =>
      'merceği ayarla. manifold hangi frekanslarda uğuldamalı?';
}

// Path: settings.museEditor
class _Translations$settings$museEditor$tr
    extends Translations$settings$museEditor$en {
  _Translations$settings$museEditor$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get additionalNotes => 'Muse için ek notlar';
}

// Path: settings.museStage
class _Translations$settings$museStage$tr
    extends Translations$settings$museStage$en {
  _Translations$settings$museStage$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get brainstorm => 'BEYİN FIRTINASI';
  @override
  String get synthesize => 'SENTEZLE';
  @override
  String get slot => 'yuva';
  @override
  String get ideaCountLoose => '~12 fikir';
  @override
  String get ideaCountBalanced => '~16 fikir';
  @override
  String get ideaCountStrict => '~20 fikir';
  @override
  String get ideaCountParanoid => '~24 fikir';
  @override
  String guardrailHint({required Object ideas, required Object macro}) =>
      '${ideas}  ·  koruma: ${macro}';
}

// Path: settings.lensAxis
class _Translations$settings$lensAxis$tr
    extends Translations$settings$lensAxis$en {
  _Translations$settings$lensAxis$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get folder => 'KLASÖR';
  @override
  String get history => 'GEÇMİŞ';
  @override
  String get far => 'UZAK';
  @override
  String get near => 'YAKIN';
}

// Path: settings.logosLens
class _Translations$settings$logosLens$tr
    extends Translations$settings$logosLens$en {
  _Translations$settings$logosLens$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get moduleMap => 'modül haritası';
  @override
  String get repoCenters => 'repo merkezleri';
  @override
  String get neighbors => 'komşular';
  @override
  String get toTouch => 'sırada neye dokunmalı';
  @override
  String get relevanceEngine => 'ilgililik motoru';
  @override
  String get description =>
      'dosyaların yapı, geçmiş ve ritim boyunca nasıl birlikte hareket ettiğini okur, böylece Manifold neyin değiştiğini değil, neyin önemli olduğunu bilir.';
  @override
  String get withinReach => 'erişilebilir';
  @override
  String get gate => 'kapı';
  @override
  String get nearest => 'en yakın';
  @override
  String get warming => 'ısınıyor';
  @override
  String get emptyOpenRepo => 'merceği canlı görmek için\nbir repo aç';
  @override
  String get emptyNoFiles => 'erişimde dosya yok\n— GEÇMİŞ\'e doğru\nsürükle';
}

// Path: settings.sortGuide
class _Translations$settings$sortGuide$tr
    extends Translations$settings$sortGuide$en {
  _Translations$settings$sortGuide$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Değişiklik sıralama kılavuzu';
  @override
  String get related =>
      'Birlikte değişen dosyalar birlikte kümelenir. Önce mesele gelir; bağlam onu izler.';
  @override
  String get relatedInverted =>
      'İzole değişiklikler önce gelir. Sıkı bağlı kümeler dibe iner.';
  @override
  String get alphabetical =>
      'Yola göre düz A → Z. Büyük/küçük harf duyarsız, sayılar doğal sıralı.';
  @override
  String get alphabeticalInverted =>
      'Yola göre düz Z → A. Büyük/küçük harf duyarsız, sayılar doğal sıralı.';
  @override
  String get impact =>
      'En ağır değişiklikler önce çıkar. Çalkantı ağırlıklandırılır; ikili ve yeni dosyalar öne çıkarılır.';
  @override
  String get impactInverted =>
      'En hafif değişiklikler önce çıkar. Hızlı kazançlar üstte; ağır işler bekler.';
  @override
  String get nearRelated => 'yakın ilişkili';
  @override
  String get alphabeticalShort => 'alfabetik';
  @override
  String get byImpact => 'etkiye göre';
  @override
  String get flipped => 'ters çevrildi';
  @override
  String get peek => 'göz at';
}

// Path: settings.piggyback
class _Translations$settings$piggyback$tr
    extends Translations$settings$piggyback$en {
  _Translations$settings$piggyback$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get apiModelsUse => 'API modelleri şunu kullanır';
  @override
  String get codexNotDetected => 'codex algılanmadı';
  @override
  String get dormant => 'UYKUDA';
}

// Path: settings.diffStage
class _Translations$settings$diffStage$tr
    extends Translations$settings$diffStage$en {
  _Translations$settings$diffStage$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get viewer => 'görüntüleyici';
  @override
  String get media => 'medya';
  @override
  String get binary => 'ikili';
  @override
  String get hidden => 'gizli';
}

// Path: settings.undoScope
class _Translations$settings$undoScope$tr
    extends Translations$settings$undoScope$en {
  _Translations$settings$undoScope$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get destructiveActions => 'yıkıcı eylemler';
  @override
  String get discards => 'iptaller';
  @override
  String get commits => 'commit\'ler';
  @override
  String get commitPush => 'commit + push';
  @override
  String get all => 'tümü';
}

// Path: settings.undoWindow
class _Translations$settings$undoWindow$tr
    extends Translations$settings$undoWindow$en {
  _Translations$settings$undoWindow$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Geri alma penceresi';
  @override
  String get off => 'Kapalı';
  @override
  String descriptionInstant({required Object scope}) =>
      '${scope} anında kesinleşir.';
  @override
  String descriptionDelayed({required Object scope, required Object seconds}) =>
      '${scope} kesinleşmeden önce ${seconds}sn.';
  @override
  String get cycleScopeTooltip =>
      'Kapsamı döngülemek için tıkla · kaydırıcıda yukarı/aşağı da sürükle';
  @override
  String get resetTooltip =>
      'Her eylemi varsayılan pencereyi kullanacak şekilde sıfırla';
}

// Path: settings.guardrailPhrase
class _Translations$settings$guardrailPhrase$tr
    extends Translations$settings$guardrailPhrase$en {
  _Translations$settings$guardrailPhrase$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get probablyFine => 'Muhtemelen iyi demek, iyi demek';
  @override
  String get proper => 'Düzgün bir okuma, mantık, entegrasyon, desenler';
  @override
  String get lookAgain => 'Tekrar bak. Bir şey saklanıyor olabilir';
  @override
  String get assumeWrong => 'Bir şeyin yanlış olduğunu varsay. Onu bul';
}

// Path: settings.reviewGuideHint
class _Translations$settings$reviewGuideHint$tr
    extends Translations$settings$reviewGuideHint$en {
  _Translations$settings$reviewGuideHint$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get focusHigh =>
      'örn. Üst düzey mantığa ve büyük hatalara odaklan. Kısa ve hoşgörülü ol.';
  @override
  String get surfaceBugs =>
      'örn. Olası hataları, mimari tutarsızlıkları ve uç durum arızalarını ortaya çıkar.';
  @override
  String get scrutinize =>
      'örn. Optimizasyon, güvenlik ve desen uyumu için her satırı didikle.';
  @override
  String get trustNothing =>
      'örn. Hiçbir şeye güvenme. Her yan etkiyi sorgula. Her satırı olası bir arıza olarak ele al.';
  @override
  String get optional =>
      'İncelemenin neyi önemsemesi gerektiğine dair isteğe bağlı yönlendirme.';
}

// Path: settings.commitFormat
class _Translations$settings$commitFormat$tr
    extends Translations$settings$commitFormat$en {
  _Translations$settings$commitFormat$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Biçim';
  @override
  String get peek => 'göz at';
  @override
  String get structure => 'Yapı';
  @override
  String get voice => 'Ses';
  @override
  String get coverage => 'Kapsam';
  @override
  String get structureTitleBody => 'başlık + gövde';
  @override
  String get structureTitleOnly => 'yalnızca başlık';
  @override
  String get structureFreeform => 'serbest biçim';
  @override
  String get voiceVerbLed => 'eylem odaklı';
  @override
  String get voiceDescriptive => 'betimleyici';
  @override
  String get voiceNarrative => 'anlatısal';
  @override
  String get coverageEssentials => 'temeller';
  @override
  String get coverageBalanced => 'dengeli';
  @override
  String get coverageEverything => 'her şey';
}

// Path: settings.commitPreview
class _Translations$settings$commitPreview$tr
    extends Translations$settings$commitPreview$en {
  _Translations$settings$commitPreview$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$tr title =
      _Translations$settings$commitPreview$title$tr._(_root);
  @override
  late final _Translations$settings$commitPreview$base$tr base =
      _Translations$settings$commitPreview$base$tr._(_root);
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$tr
  balancedSuffix = _Translations$settings$commitPreview$balancedSuffix$tr._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$tr
  everythingSuffix = _Translations$settings$commitPreview$everythingSuffix$tr._(
    _root,
  );
}

// Path: settings.externalTools
class _Translations$settings$externalTools$tr
    extends Translations$settings$externalTools$en {
  _Translations$settings$externalTools$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Harici Araçlar';
  @override
  String get summary =>
      'Bunlardan biriyle açmak için kenar çubuğundaki bir projeye sağ tıkla. Argümanlar proje klasörü için {path} kullanır.';
  @override
  String get detecting => 'Kurulu araçlar algılanıyor…';
  @override
  String get allPresetsAdded =>
      'Bilinen tüm hazır ayarlar zaten eklendi. Daha fazlası için “+ Özel” kullan.';
  @override
  String get noToolsConfigured =>
      'Henüz araç yapılandırılmadı. Yukarıdan bir tane ekle.';
  @override
  String get categoryAi => 'ai';
  @override
  String get categoryEditors => 'editörler';
  @override
  String get categoryExplore => 'keşfet';
  @override
  String get categoryOps => 'ops';
  @override
  String get categoryGitOps => 'git ops';
  @override
  String get nameHint => 'Ad';
  @override
  String get commandHint => 'komut';
  @override
  String get test => 'test';
  @override
  String get removeTool => 'Aracı kaldır';
  @override
  String get modeTerminal => 'terminal';
  @override
  String get modeDetached => 'ayrık';
}

// Path: settings.apiUsage
class _Translations$settings$apiUsage$tr
    extends Translations$settings$apiUsage$en {
  _Translations$settings$apiUsage$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String thisMonth({required Object used, required Object limit}) =>
      'bu ay ${used}${limit}';
}

// Path: settings.gitea
class _Translations$settings$gitea$tr extends Translations$settings$gitea$en {
  _Translations$settings$gitea$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Gitea token\'ları';
  @override
  String get hostHint => 'ana bilgisayar';
  @override
  String get tokenHint => 'token';
  @override
  String get save => 'kaydet';
}

// Path: settings.wick
class _Translations$settings$wick$tr extends Translations$settings$wick$en {
  _Translations$settings$wick$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get selectExecutable => 'wick yürütülebilir dosyasını seç';
  @override
  String get connected => 'wick · bağlı';
  @override
  String get pathToExecutable => 'wick · yürütülebilir dosya yolu';
  @override
  String get off => 'kapalı';
  @override
  String get disableHint => 'wick entegrasyonunu kapat';
  @override
  String get enableHint => 'wick entegrasyonunu aç';
}

// Path: settings.integrations
class _Translations$settings$integrations$tr
    extends Translations$settings$integrations$en {
  _Translations$settings$integrations$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => '& Entegrasyonlar';
  @override
  String get alpha => 'alpha';
  @override
  String get planned => 'planlandı';
  @override
  String get lspComingSoon => 'lsp · yakında';
  @override
  String get alphaMathConnected => 'alpha-math · bağlı';
  @override
  String get alphaMathComingSoon => 'alpha-math · yakında';
}

// Path: settings.reduceMotion
class _Translations$settings$reduceMotion$tr
    extends Translations$settings$reduceMotion$en {
  _Translations$settings$reduceMotion$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get label => 'Hareketi azalt';
  @override
  String get subtitleStill => 'Buz gibi… durgun mu?';
  @override
  String get subtitleFlow => 'Su gibi ak.';
}

// Path: settings.resetQuit
class _Translations$settings$resetQuit$tr
    extends Translations$settings$resetQuit$en {
  _Translations$settings$resetQuit$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get resetAndQuit => 'SIFIRLA & ÇIK';
  @override
  String get keepRepos => 'DEPOLARI KORU';
  @override
  String get wipeAll => 'TÜMÜNÜ SİL';
}

// Path: settings.diagnostics
class _Translations$settings$diagnostics$tr
    extends Translations$settings$diagnostics$en {
  _Translations$settings$diagnostics$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get commandDiagnostics => 'Komut Tanılaması';
  @override
  String get networkFlowTelemetry => 'Ağ Akışı Telemetrisi';
  @override
  String get clearSamples => 'Örnekleri Temizle';
  @override
  String get clearMetrics => 'Metrikleri Temizle';
  @override
  String get clearTimings => 'Zamanlamaları Temizle';
  @override
  String get recalibrate => 'YENİDEN AYARLA';
  @override
  String get ok => 'tamam';
  @override
  String get noCommandTimings =>
      'Henüz komut zamanlaması yakalanmadı. Tanılamayı doldurmak için normal eylemler çalıştır.';
  @override
  String get noBackendSamples =>
      'Henüz arka uç komut örneği yakalanmadı. Bu günlüğü doldurmak için git ve ayar eylemleri çalıştır.';
  @override
  String get noDiffSessions =>
      'Henüz diff oluşturma oturumu yakalanmadı. Bu paneli doldurmak için dosya diff\'lerini aç ve kaydır.';
  @override
  String get noUiSessions =>
      'Henüz UI zamanlama oturumu yakalanmadı. Bu paneli doldurmak için panelleri aç ve rotalarda gez.';
  @override
  String get recentOperations => 'Son İşlemler';
  @override
  String get recentBackendOperations => 'Son Arka Uç İşlemleri';
  @override
  String get recentDiffSessions => 'Son Diff Oturumları';
  @override
  String get recentUiTimings => 'Son UI Zamanlamaları';
  @override
  String uniqueCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} benzersiz komut',
        other: '${n} benzersiz komut',
      );
  @override
  String scopedCommands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} kapsamlı komut',
        other: '${n} kapsamlı komut',
      );
  @override
  String instrumentedEvents({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} enstrümanlı olay',
        other: '${n} enstrümanlı olay',
      );
  @override
  String summaryCommand({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryBackend({required Object samples, required Object commands}) =>
      '${samples} | ${commands}';
  @override
  String summaryDiff({required Object sessions, required Object jank}) =>
      '${sessions} | takılma %${jank}';
  @override
  String summaryUi({required Object samples, required Object events}) =>
      '${samples} | ${events}';
  @override
  List<String> get headersCommand => ['komut', 'p50', 'güvenilirlik', 'aralık'];
  @override
  List<String> get headersBackend => ['kapsam', 'p50', 'p95', 'hatalar'];
  @override
  List<String> get headersDiff => [
    'oluşturucu',
    'ilk çizim',
    'kare p95',
    'raster p95',
    'takılma',
  ];
  @override
  List<String> get headersUi => ['olay', 'p50', 'hatalar', 'aralık'];
}

// Path: settings.telemetry
class _Translations$settings$telemetry$tr
    extends Translations$settings$telemetry$en {
  _Translations$settings$telemetry$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String samples({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} örnek',
        other: '${n} örnek',
      );
  @override
  String commands({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} komut',
        other: '${n} komut',
      );
  @override
  String sessions({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} oturum',
        other: '${n} oturum',
      );
  @override
  String events({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} olay',
        other: '${n} olay',
      );
  @override
  String stability({required Object pct}) => '%${pct} kararlılık';
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
class _Translations$settings$flowEngine$tr
    extends Translations$settings$flowEngine$en {
  _Translations$settings$flowEngine$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get executionFlow => 'yürütme-akışı';
  @override
  String get description =>
      'kod üzerinde osilatörler simüle eder. hataya dönüşmeden önce kırılgan yürütme yollarını ortaya çıkarır.';
  @override
  String get idle => 'boşta';
  @override
  String get emptyOpenRepo => 'akış analizini görmek için\nbir repo aç';
  @override
  String get scanning => 'taranıyor';
  @override
  String get analysing => 'mercekteki dosyalar\nanaliz ediliyor…';
  @override
  String get fragility => 'kırılganlık';
  @override
  String get findings => 'bulgular';
  @override
  String get gap => 'boşluk';
  @override
  String get clean => 'temiz';
  @override
  String get severity => 'önem';
  @override
  String get critical => 'kritik';
  @override
  String get warn => 'uyarı';
  @override
  String get info => 'bilgi';
}

// Path: settings.museStrands
class _Translations$settings$museStrands$tr
    extends Translations$settings$museStrands$en {
  _Translations$settings$museStrands$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get spark => 'ilham kıvılcımı · hemen sonraki adım';
  @override
  String get current => 'sudaki akıntı · şimdiki zaman uzantıları';
  @override
  String get horizon => 'ufkun ötesine bak · uzanan yönler';
  @override
  String get fever => 'ateşli bir rüyadan uyan · kışkırtmalar';
  @override
  String get echo => 'kanyondaki bir yankı · başka yerlerdeki benzerler';
  @override
  String get vertigo => 'uçurum kenarında baş dönmesi · komşu riskler';
  @override
  String get ghost => 'olanın hayaleti · tarihsel bağlam';
  @override
  String get mirror => 'durgun sudaki bir ayna · tersine çevirmeler';
}

// Path: settings.cliPiggyback
class _Translations$settings$cliPiggyback$tr
    extends Translations$settings$cliPiggyback$en {
  _Translations$settings$cliPiggyback$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'CLI Sırtlama';
  @override
  String get clearCacheLabel => 'Önbelleği temizle';
  @override
  String get clearCacheTooltip =>
      'Önbelleğe alınmış modelleri sil ve yeniden sonda gönder. Bir sağlayıcının bıraktıklarını temizler.';
  @override
  String get refreshLabel => 'Sağlayıcıları yenile';
  @override
  String get refreshTooltip => 'Her sağlayıcıyı şimdi yeniden sonda gönder.';
  @override
  String get body =>
      'Arayüz mesajlarını doğrudan yerel sağlayıcı ikili dosyalarına aktar.';
  @override
  String get cliTimeoutLabel => 'Çalıştırma başına zaman aşımı';
  @override
  String get cliTimeoutUnitMinutes => 'dakika';
  @override
  String get cliTimeoutUnitMinute => 'dakika';
  @override
  String get forceStopLabel => 'Tüm oturumları durdur';
  @override
  String get forceStopTooltip =>
      'Devam eden her CLI çalıştırmasını zorla kapat.';
  @override
  String get forceStopConfirmTitle => 'Çalışan CLI oturumları durdurulsun mu?';
  @override
  String forceStopConfirmBody({required Object count}) =>
      'Bu, devam eden ${count} CLI çalıştırmasını zorla kapatır. Çıktıları kaybolur.';
  @override
  String get forceStopConfirmAction => 'Tümünü durdur';
  @override
  String get forceStopNoneRunning => 'Çalışan CLI oturumu yok';
  @override
  String get forceStopRecordError =>
      'Durduruldu — CLI oturumları zorla kapatıldı.';
}

// Path: settings.header
class _Translations$settings$header$tr extends Translations$settings$header$en {
  _Translations$settings$header$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Çalışma Alanı Tercihleri';
  @override
  String get subtitle =>
      'Tüm çalışma alanı için küresel estetiği, arayüz dinamiklerini ve temel operasyonel güvenceleri yapılandır.';
  @override
  String get releaseNotesTooltip => 'Sürüm notları';
  @override
  String get replayOnboardingTooltip => 'İlk kullanımı tekrar oynat';
}

// Path: settings.diagnosticsPanel
class _Translations$settings$diagnosticsPanel$tr
    extends Translations$settings$diagnosticsPanel$en {
  _Translations$settings$diagnosticsPanel$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Performans Tanılaması';
  @override
  String get copyTrace => 'İzi Kopyala';
  @override
  String get offenderRanking => 'İhlal Sıralaması';
  @override
  String get offenderRankingSubtitle => 'Akışlar genelinde gecikme kaynakları.';
  @override
  String get noOffenders =>
      'Henüz ihlal sıralaması yok. Bu listeyi doldurmak için tanılama etkinliği yakala.';
}

// Path: settings.release
class _Translations$settings$release$tr
    extends Translations$settings$release$en {
  _Translations$settings$release$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Sürüm Dağıtımı';
  @override
  String get summary => 'Güncellemeyle ilgili ayarlar.';
  @override
  String get deploymentChannel => 'DAĞITIM KANALI';
  @override
  String get captureCrashDiagnostics => 'Çökme tanılamalarını yakala';
  @override
  String get comingSoon => 'Yakında.';
  @override
  String get checking => 'KONTROL EDİLİYOR…';
  @override
  String get pollForUpdates => 'GÜNCELLEMELERİ YOKLA';
}

// Path: settings.providerStatus
class _Translations$settings$providerStatus$tr
    extends Translations$settings$providerStatus$en {
  _Translations$settings$providerStatus$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get detecting => 'Algılanıyor...';
  @override
  String get ready => 'Hazır';
  @override
  String get notDetected => 'Algılanmadı';
  @override
  String configured({required Object count}) => '${count} yapılandırıldı';
  @override
  String get notConfigured => 'Yapılandırılmadı';
  @override
  String get cliManaged => 'CLI-yönetimli';
  @override
  String get connected => 'Bağlı';
  @override
  String modelCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} model',
        other: '${n} model',
      );
  @override
  String providerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} sağlayıcı',
        other: '${n} sağlayıcı',
      );
}

// Path: settings.meridiem
class _Translations$settings$meridiem$tr
    extends Translations$settings$meridiem$en {
  _Translations$settings$meridiem$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get am => 'AM';
  @override
  String get pm => 'PM';
}

// Path: settings.offenders
class _Translations$settings$offenders$tr
    extends Translations$settings$offenders$en {
  _Translations$settings$offenders$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get commandStream => 'Komut';
  @override
  String get diffStream => 'Diff Oluşturma';
  @override
  String get uiStream => 'UI Zamanlama';
  @override
  String rendererName({required Object mode}) => '${mode} oluşturucu';
  @override
  String latencyFailMetric({required Object p95, required Object fail}) =>
      '${p95}ms p95 | %${fail} hata';
  @override
  String jankFrameMetric({required Object jank, required Object frame}) =>
      '%${jank} takılma | ${frame}ms kare p95';
  @override
  String inStream({required Object stream}) => '${stream} içinde';
}

// Path: sync.actions
class _Translations$sync$actions$tr extends Translations$sync$actions$en {
  _Translations$sync$actions$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get syncLabel => 'Eşitle';
  @override
  String get syncOpenRepoDetail =>
      'Push ve pull işlemlerini yönetmek için bir depo aç.';
  @override
  String get detachedHeadLabel => 'Detached HEAD';
  @override
  String get detachedHeadDetail => 'Push veya pull yapmadan önce bir dala geç.';
  @override
  String get publishBranchLabel => 'Dalı yayımla';
  @override
  String publishBranchDetail({required Object branch}) =>
      '${branch} dalını push et ve upstream izleme dalını ayarla.';
  @override
  String get publishButtonLabel => 'Yayımla';
  @override
  String get syncBranchLabel => 'Dalı eşitle';
  @override
  String syncBranchDetail({
    required Object behindCount,
    required Object aheadCount,
  }) => '${behindCount} rebase ile pull et, sonra ${aheadCount} push et.';
  @override
  String get syncBranchButtonLabel => 'Pull (rebase), sonra push';
  @override
  String get pushBranchLabel => 'Dalı push et';
  @override
  String pushBranchDetail({required Object count, required Object upstream}) =>
      '${count}, ${upstream} hedefine push edilecek.';
  @override
  String get pushBranchButtonLabel => 'Commit\'leri push et';
  @override
  String get pullUpdatesLabel => 'Güncellemeleri pull et';
  @override
  String pullUpdatesDetail({required Object count, required Object upstream}) =>
      '${count}, ${upstream} kaynağından pull edilecek.';
  @override
  String syncUpToDateDetail({required Object upstream}) =>
      '${upstream} kaynağından fetch et ve upstream durumunu yenile.';
}

// Path: sync.panel
class _Translations$sync$panel$tr extends Translations$sync$panel$en {
  _Translations$sync$panel$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get loadingTitle => 'Uzak durum yükleniyor';
  @override
  String get loadingMessage => 'Dal izleme bilgisi kontrol ediliyor.';
  @override
  String get remoteStatusUnavailable => 'Uzak durum kullanılamıyor';
  @override
  String get noUpstream => 'upstream yok';
  @override
  String get aheadLabel => 'İleride';
  @override
  String get behindLabel => 'Geride';
  @override
  String get treeLabel => 'Ağaç';
  @override
  String get runningSync => 'Eşitleme çalışıyor…';
  @override
  String get fetching => 'Fetch ediliyor…';
  @override
  String get fetchOnly => 'Yalnızca fetch';
  @override
  String get syncFailed => 'Eşitleme başarısız';
  @override
  String get forcePushRecoveryLabel => 'Force push (lease ile)';
  @override
  String get conflictsToResolveTitle => 'Çözülecek çakışmalar';
  @override
  String conflictsToResolveBody({
    required Object count,
    required Object list,
  }) => '${count} çözülmeli: ${list}';
  @override
  String get resolveConflicts => 'Çakışmaları çöz';
  @override
  String get workingEllipsis => 'Çalışıyor…';
  @override
  String lastActivity({required Object operation}) =>
      'Son etkinlik: ${operation}';
  @override
  String get noOutput => 'Çıktı yok.';
  @override
  String resolvedConflicts({required Object count}) => '${count} çözüldü.';
  @override
  String get cancelledUnchanged => 'İptal edildi, çalışma ağacı değişmedi.';
  @override
  String uncommittedEditsBlocked({
    required Object count,
    required Object list,
  }) =>
      '${count} dosyada commit edilmemiş değişiklik var, rebase-eşitleme için önce onları commit et (${list}).';
  @override
  String noUpstreamForForcePush({required Object branch}) =>
      'Force-push yapılamıyor: "${branch}" için upstream yapılandırılmamış.';
}

// Path: sync.forcePush
class _Translations$sync$forcePush$tr extends Translations$sync$forcePush$en {
  _Translations$sync$forcePush$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get confirmTitle => 'Force push (lease ile)?';
  @override
  String target({required Object remote, required Object branch}) =>
      'Hedef: ${remote}/${branch}';
  @override
  String get warning =>
      'Bu, uzak dalı yerel geçmişinle üzerine yazar. Lease ile, son fetch\'inden sonra biri uzağa push ettiyse iptal eder, ancak zaten fetch edilmiş değişiklikler yine de üzerine yazılır. Yalnızca dalı ayrıştıran bir rebase veya amend amaçladığında kullan.';
  @override
  String get confirmButton => 'Force push';
}

// Path: xray.board
class _Translations$xray$board$tr extends Translations$xray$board$en {
  _Translations$xray$board$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get movesWithModule => 'başka bir modülle hareket ediyor';
  @override
  String reviewerCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} inceleyici',
        other: '${n} inceleyici',
      );
  @override
  String get territory => 'Bölge';
  @override
  String get unreviewed => 'incelenmemiş';
}

// Path: xray.cadence
class _Translations$xray$cadence$tr extends Translations$xray$cadence$en {
  _Translations$xray$cadence$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String burstTooltipMulti({
    required Object sum,
    required Object days,
    required Object lines,
  }) => '${sum} commit · ${days} gün\n${lines}';
  @override
  String burstTooltipSingle({required Object label, required Object n}) =>
      '${label} tarihinde ${n} commit';
  @override
  String gapTooltip({required Object n, required Object label}) =>
      '${n} günlük boşluk · ${label}';
  @override
  String reflogTooltip({required Object label, required Object n}) =>
      '${label} tarihinde ${n} reflog olayı';
}

// Path: xray.cards
class _Translations$xray$cards$tr extends Translations$xray$cards$en {
  _Translations$xray$cards$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$xray$cards$branchModel$tr branchModel =
      _Translations$xray$cards$branchModel$tr._(_root);
  @override
  late final _Translations$xray$cards$bursty$tr bursty =
      _Translations$xray$cards$bursty$tr._(_root);
  @override
  late final _Translations$xray$cards$hiddenRefs$tr hiddenRefs =
      _Translations$xray$cards$hiddenRefs$tr._(_root);
  @override
  late final _Translations$xray$cards$keystone$tr keystone =
      _Translations$xray$cards$keystone$tr._(_root);
  @override
  late final _Translations$xray$cards$machineHistory$tr machineHistory =
      _Translations$xray$cards$machineHistory$tr._(_root);
  @override
  late final _Translations$xray$cards$migration$tr migration =
      _Translations$xray$cards$migration$tr._(_root);
  @override
  late final _Translations$xray$cards$narrowHotspot$tr narrowHotspot =
      _Translations$xray$cards$narrowHotspot$tr._(_root);
  @override
  late final _Translations$xray$cards$noTags$tr noTags =
      _Translations$xray$cards$noTags$tr._(_root);
  @override
  late final _Translations$xray$cards$reflog$tr reflog =
      _Translations$xray$cards$reflog$tr._(_root);
  @override
  late final _Translations$xray$cards$singleOwner$tr singleOwner =
      _Translations$xray$cards$singleOwner$tr._(_root);
}

// Path: xray.cardTitle
class _Translations$xray$cardTitle$tr extends Translations$xray$cardTitle$en {
  _Translations$xray$cardTitle$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get branches => 'dallar';
  @override
  String get bursty => 'patlamalı';
  @override
  String get hiddenRefs => 'gizli referanslar';
  @override
  String get machineHeavy => 'makine-ağırlıklı';
  @override
  String get migration => 'geçiş';
  @override
  String get narrowHotspot => 'dar hotspot';
  @override
  String get noTags => 'etiket yok';
  @override
  String get reflog => 'reflog';
  @override
  String get singleOwner => 'tek-sahip';
}

// Path: xray.grain
class _Translations$xray$grain$tr extends Translations$xray$grain$en {
  _Translations$xray$grain$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get coarsest => 'en kaba — üst düzey modüller';
  @override
  String get finest => 'en ince tane';
  @override
  String get mid => 'orta tane';
  @override
  String get oneCharacteristic => 'tek karakteristik ölçek';
}

// Path: xray.header
class _Translations$xray$header$tr extends Translations$xray$header$en {
  _Translations$xray$header$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get dirtyBadge => 'kirli';
  @override
  String get machineChip => 'makine';
  @override
  String get refresh => 'Yenile';
  @override
  String get refreshing => 'Yenileniyor...';
  @override
  String get title => 'Repo X-Ray';
}

// Path: xray.hotspot
class _Translations$xray$hotspot$tr extends Translations$xray$hotspot$en {
  _Translations$xray$hotspot$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get clusterPeers => 'küme komşuları';
  @override
  String get coChangers => 'ortak değişenler';
  @override
  String get keystone => 'kilit taşı';
  @override
  String keystoneScore({required Object score}) => 'kilit taşı  φ=${score}';
}

// Path: xray.inspector
class _Translations$xray$inspector$tr extends Translations$xray$inspector$en {
  _Translations$xray$inspector$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get branchLabel => 'dal';
  @override
  String commitsHumanMachine({required Object n}) => 'insan · ${n} makine';
  @override
  String get commitsLabel => 'commit\'ler';
  @override
  String get confidenceLabel => 'güven';
  @override
  String get curlLabel => 'curl';
  @override
  String get engineSection => 'motor';
  @override
  String get gradientLabel => 'gradyan';
  @override
  String get harmonicLabel => 'harmonik';
  @override
  String get headLabel => 'head';
  @override
  String get hiddenRefsLabel => 'gizli referanslar';
  @override
  String mergeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} merge',
        other: '${n} merge',
      );
  @override
  String get noTags => 'etiket yok';
  @override
  String get notesLabel => 'notes';
  @override
  String get openCommit => 'Commit\'i aç';
  @override
  String get pathLabel => 'yol';
  @override
  String remoteCount({required Object n}) => '${n} uzak';
  @override
  String get renamesLabel => 'yeniden adlandırmalar';
  @override
  String scannedAt({required Object time}) => '${time} tarandı';
  @override
  String selectedCount({required Object n}) => '${n} seçili';
  @override
  String get shapeLinear => 'doğrusal';
  @override
  String get shapeMergeHeavy => 'merge-ağırlıklı';
  @override
  String get shapeMostlyLinear => 'çoğunlukla doğrusal';
  @override
  String stashCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} zula',
        other: '${n} zula',
      );
  @override
  String get stressLabel => 'gerilim';
  @override
  String tagCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} etiket',
        other: '${n} etiket',
      );
  @override
  String worktreeCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} çalışma ağacı',
        other: '${n} çalışma ağacı',
      );
}

// Path: xray.loadingCard
class _Translations$xray$loadingCard$tr
    extends Translations$xray$loadingCard$en {
  _Translations$xray$loadingCard$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get buildingMessage =>
      'Git geçmişi, referanslar, tempo ve hotspot\'lar sondalanıyor.';
  @override
  String get buildingTitle => 'Repo X-Ray oluşturuluyor';
  @override
  String get idleMessage => 'Mevcut depoyu sondalamak için paneli tekrar aç.';
  @override
  String get idleTitle => 'Repo X-Ray';
  @override
  String get unavailableTitle => 'Repo X-Ray kullanılamıyor';
}

// Path: xray.metabolism
class _Translations$xray$metabolism$tr extends Translations$xray$metabolism$en {
  _Translations$xray$metabolism$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String halfLife({required Object n}) => '${n}g yarı ömür';
}

// Path: xray.multi
class _Translations$xray$multi$tr extends Translations$xray$multi$en {
  _Translations$xray$multi$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String clusterCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} küme',
        other: '${n} küme',
      );
  @override
  String clusterSingle({required Object id}) => 'küme ${id}';
  @override
  String couplingSuffix({required Object parts}) => '${parts} bağlaşım';
  @override
  String externalCount({required Object n}) => '${n} dış';
  @override
  String mutualCount({required Object n}) => '${n} karşılıklı';
}

// Path: xray.recency
class _Translations$xray$recency$tr extends Translations$xray$recency$en {
  _Translations$xray$recency$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String days({required Object n}) => '${n}g';
  @override
  String months({required Object n}) => '${n}ay';
  @override
  String get today => 'bugün';
  @override
  String weeks({required Object n}) => '${n}h';
  @override
  String years({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n}y',
        other: '${n}y',
      );
}

// Path: xray.rings
class _Translations$xray$rings$tr extends Translations$xray$rings$en {
  _Translations$xray$rings$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get hintOneBlended => 'tek harmanlanmış yapı';
  @override
  String get hintSelfSimilar => 'öz-benzer';
  @override
  String get oneBlendedBody =>
      'Tek harmanlanmış yapı — henüz ayrılabilir modül ölçeği çözülmüyor.';
  @override
  String get overHistory => 'Geçmiş boyunca';
  @override
  String get parts => 'parçalar';
  @override
  String get readingHint => 'yapı okunuyor…';
  @override
  String scaleCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} ölçek',
        other: '${n} ölçek',
      );
  @override
  String get scaleDissolved => 'yapısal bir ölçek çözüldü';
  @override
  String get scaleEmerged => 'yapısal bir ölçek ortaya çıktı';
  @override
  String get scaleSpectrum => 'ölçek spektrumu';
  @override
  String get selfSimilarBody =>
      'Öz-benzer — yapı, tek bir karakteristik düzey olmadan ölçekler boyunca tekrar eder.';
  @override
  String shiftInHistory({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: 'geçmişte ${n} kayma',
        other: 'geçmişte ${n} kayma',
      );
  @override
  String structuralShiftCount({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} yapısal kayma',
        other: '${n} yapısal kayma',
      );
  @override
  String get title => 'Büyüme halkaları';
  @override
  String get unavailable => 'kullanılamıyor';
}

// Path: xray.stats
class _Translations$xray$stats$tr extends Translations$xray$stats$en {
  _Translations$xray$stats$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get alive => 'canlı';
  @override
  String get files => 'dosyalar';
  @override
  String get lastTouched => 'son dokunulan';
  @override
  String owner({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: 'sahip',
        other: 'sahipler',
      );
  @override
  String get touches => 'dokunmalar';
}

// Path: xray.stratumLabel
class _Translations$xray$stratumLabel$tr
    extends Translations$xray$stratumLabel$en {
  _Translations$xray$stratumLabel$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get current => 'güncel';
  @override
  String get legacy => 'eski';
  @override
  String get zone => 'repo bölgesi';
}

// Path: xray.summary
class _Translations$xray$summary$tr extends Translations$xray$summary$en {
  _Translations$xray$summary$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String analysisFailed({required Object error}) =>
      'Analiz başarısız: ${error}';
  @override
  String get analyze => 'Analiz et';
  @override
  String get copied => 'Özet panoya kopyalandı.';
  @override
  String get directionHint => 'yön';
  @override
  String get download => 'İndir';
  @override
  String get emptyState =>
      'Bu deponun yapısını ve bölgelerini haritalamak için Logos analizini çalıştır.\n(tw: şu an baya döküntü)';
  @override
  String get exit => 'Çık';
  @override
  String get generating => 'Repo okunuyor ve özellikler kümeleniyor…';
  @override
  String get noModel => 'AI modeli yapılandırılmadı.';
  @override
  String get noModelConfigured => 'AI modeli yapılandırılmadı';
  @override
  String presentWith({required Object label}) => '${label} ile sun';
  @override
  String presentingWith({required Object label}) => '${label} ile sunuluyor…';
  @override
  String get reanalyze => 'Yeniden analiz et';
  @override
  String get saveDialogTitle => 'Depo özetini kaydet';
  @override
  String saveFailed({required Object error}) => 'Kaydetme başarısız: ${error}';
  @override
  String get savePresentationDialogTitle => 'Sunumu kaydet';
  @override
  String savedTo({required Object path}) => '${path} konumuna kaydedildi';
}

// Path: xray.tabs
class _Translations$xray$tabs$tr extends Translations$xray$tabs$en {
  _Translations$xray$tabs$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get map => 'Harita';
  @override
  String get signals => 'Sinyaller';
  @override
  String get summary => 'Özet';
  @override
  String get time => 'Zaman';
}

// Path: xray.trajectory
class _Translations$xray$trajectory$tr extends Translations$xray$trajectory$en {
  _Translations$xray$trajectory$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get connectivity => 'bağlantısallık';
  @override
  String events({required Object n}) => '${n} olay';
  @override
  String get openInOrrery => 'Orrery\'de aç';
  @override
  String get readingHint => 'geçmiş okunuyor…';
  @override
  String snapshots({required Object n}) => '${n} anlık görüntü';
  @override
  String get steady => 'Sabit — bu pencerede yapısal olay yok.';
  @override
  String get title => 'Yapısal yörünge';
}

// Path: xray.verdict
class _Translations$xray$verdict$tr extends Translations$xray$verdict$en {
  _Translations$xray$verdict$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String canonical({required Object pct}) => '%${pct} kanonik';
  @override
  String tooltip({
    required Object archetype,
    required Object canonical,
    required Object decisive,
  }) => '${archetype} · %${canonical} kanonik · %${decisive} belirleyici';
}

// Path: changes.mergeEditor.trust
class _Translations$changes$mergeEditor$trust$tr
    extends Translations$changes$mergeEditor$trust$en {
  _Translations$changes$mergeEditor$trust$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get manual => 'manuel';
  @override
  String get safe => 'güvenli';
  @override
  String get guided => 'yönlendirmeli';
  @override
  String get assisted => 'yardımlı';
  @override
  String get full => 'tam';
  @override
  String label({required Object label}) => 'güven: ${label}';
}

// Path: changes.mergeEditor.keyHints
class _Translations$changes$mergeEditor$keyHints$tr
    extends Translations$changes$mergeEditor$keyHints$en {
  _Translations$changes$mergeEditor$keyHints$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get accept => 'kabul et';
  @override
  String get other => 'diğer';
  @override
  String get both => 'ikisi';
  @override
  String get navigate => 'gez';
  @override
  String get jumpNext => 'sonrakine atla';
}

// Path: changes.mergeFlow.op
class _Translations$changes$mergeFlow$op$tr
    extends Translations$changes$mergeFlow$op$en {
  _Translations$changes$mergeFlow$op$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get merge => 'merge';
  @override
  String get cherryPick => 'cherry-pick';
  @override
  String get revert => 'revert';
  @override
  String get resolve => 'çöz';
  @override
  String get switchOp => 'geç';
  @override
  String get pull => 'pull';
  @override
  String get rebase => 'rebase';
  @override
  String rebaseOnto({required Object branch, required Object base}) =>
      '${branch}, ${base} üzerine rebase et';
}

// Path: diff.pinned.tempo
class _Translations$diff$pinned$tempo$tr
    extends Translations$diff$pinned$tempo$en {
  _Translations$diff$pinned$tempo$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get hotOwnerLane =>
      'Yakında güçlü bir sahiple birlikte yakın zamanlı hareket.';
  @override
  String get activeSeam => 'Yakında birden çok elden yakın zamanlı hareket.';
  @override
  String get stableOwnerLane => 'Tek baskın sahibi olan uzun ömürlü şerit.';
  @override
  String get sharedLongLivedSeam => 'Zamanla birikmiş paylaşılan dikiş.';
  @override
  String get sharedLane => 'Tek baskın sahibi olmayan paylaşılan şerit.';
  @override
  String get resolving => 'Geçmiş bu satırın etrafında hâlâ çözülüyor.';
}

// Path: diff.pinned.tone
class _Translations$diff$pinned$tone$tr
    extends Translations$diff$pinned$tone$en {
  _Translations$diff$pinned$tone$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get hot => 'Sıcak';
  @override
  String get novel => 'Yeni';
  @override
  String get contested => 'Çekişmeli';
  @override
  String get spreading => 'Yayılıyor';
  @override
  String get stable => 'Kararlı';
}

// Path: diff.pinned.summary
class _Translations$diff$pinned$summary$tr
    extends Translations$diff$pinned$summary$en {
  _Translations$diff$pinned$summary$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String livesIn({required Object concept}) => '${concept} içinde yaşıyor';
  @override
  String get sitsInLocalSeam => 'Yerel bir dikişte oturuyor';
  @override
  String workedMostlyBy({required Object owner}) =>
      'çoğunlukla yakındaki ${owner} tarafından işlendi';
  @override
  String echoesInSpots({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} başka noktada yankılanıyor',
        other: '${n} başka noktada yankılanıyor',
      );
  @override
  String inspectNext({required Object path, required Object detail}) =>
      'sırada ${path} incele${detail}';
  @override
  String inspectDetail({required Object reason}) => ' (${reason})';
}

// Path: diff.pinned.tightness
class _Translations$diff$pinned$tightness$tr
    extends Translations$diff$pinned$tightness$en {
  _Translations$diff$pinned$tightness$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get tight => 'sıkı oturuş';
  @override
  String get close => 'yakın oturuş';
  @override
  String get loose => 'gevşek oturuş';
}

// Path: diff.pinned.witness
class _Translations$diff$pinned$witness$tr
    extends Translations$diff$pinned$witness$en {
  _Translations$diff$pinned$witness$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String nearbySupport({required Object label}) => 'Yakın destek · ${label}';
  @override
  String localizedMove({required Object label}) =>
      'Yerelleşmiş hareket · ${label}';
  @override
  String surprisingMove({required Object label}) =>
      'Şaşırtıcı hareket · ${label}';
}

// Path: diff.pinned.integrity
class _Translations$diff$pinned$integrity$tr
    extends Translations$diff$pinned$integrity$en {
  _Translations$diff$pinned$integrity$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get stableStructure => 'Kararlı yapı';
  @override
  String get conflictingSignals => 'Çelişen sinyaller';
  @override
  String get novelShape => 'Yeni biçim';
}

// Path: diff.pinned.related
class _Translations$diff$pinned$related$tr
    extends Translations$diff$pinned$related$en {
  _Translations$diff$pinned$related$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get testMirror => 'Test aynası';
  @override
  String get semanticHistorySibling => 'Anlamsal + geçmiş kardeşi';
  @override
  String get recentCoChange => 'Yakın zamanlı ortak değişim';
  @override
  String get semanticSibling => 'Anlamsal kardeş';
  @override
  String get relatedStructure => 'İlgili yapı';
  @override
  String get tightlyBound => 'sıkı bağlı';
  @override
  String get orbiting => 'yörüngede';
  @override
  String get weaklyCoupled => 'zayıf bağlı';
  @override
  String baseWithTier({required Object base, required Object tier}) =>
      '${base} · ${tier}';
}

// Path: diff.pinned.axis
class _Translations$diff$pinned$axis$tr
    extends Translations$diff$pinned$axis$en {
  _Translations$diff$pinned$axis$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get historyTrail => 'geçmiş izi';
  @override
  String get testMirrorLane => 'test aynası şeridi';
  @override
  String get structuralLane => 'yapısal şerit';
  @override
  String get semanticNeighbourhood => 'anlamsal komşuluk';
}

// Path: history.commitLede.semantics
class _Translations$history$commitLede$semantics$tr
    extends Translations$history$commitLede$semantics$en {
  _Translations$history$commitLede$semantics$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get importanceHigh => 'yüksek önem';
  @override
  String get importanceModerate => 'orta önem';
  @override
  String get mostlyAdditions => 'çoğunlukla eklemeler';
  @override
  String get mostlyDeletions => 'çoğunlukla silmeler';
  @override
  String get tightlyCoupled => 'sıkı bağlı dosyalar';
  @override
  String get overlapsWorkingTree => 'çalışma ağacınla örtüşüyor';
}

// Path: onboarding.repo.doors
class _Translations$onboarding$repo$doors$tr
    extends Translations$onboarding$repo$doors$en {
  _Translations$onboarding$repo$doors$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$onboarding$repo$doors$open$tr open =
      _Translations$onboarding$repo$doors$open$tr._(_root);
  @override
  late final _Translations$onboarding$repo$doors$clone$tr clone =
      _Translations$onboarding$repo$doors$clone$tr._(_root);
  @override
  late final _Translations$onboarding$repo$doors$create$tr create =
      _Translations$onboarding$repo$doors$create$tr._(_root);
}

// Path: onboarding.repo.cloneForm
class _Translations$onboarding$repo$cloneForm$tr
    extends Translations$onboarding$repo$cloneForm$en {
  _Translations$onboarding$repo$cloneForm$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'URL\'den klonla';
  @override
  String get urlLabel => 'Depo URL\'si';
  @override
  String get targetLabel => 'Hedef klasör';
  @override
  String get browse => 'Gözat…';
  @override
  String get clone => 'Klonla';
  @override
  String get cloning => 'Klonlanıyor…';
}

// Path: onboarding.repo.pickers
class _Translations$onboarding$repo$pickers$tr
    extends Translations$onboarding$repo$pickers$en {
  _Translations$onboarding$repo$pickers$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get openRepository => 'Depo Aç';
  @override
  String get createRepository => 'Depo Oluştur';
  @override
  String get cloneTarget => 'Klon Hedefi';
}

// Path: onboarding.repo.errors
class _Translations$onboarding$repo$errors$tr
    extends Translations$onboarding$repo$errors$en {
  _Translations$onboarding$repo$errors$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get urlAndTargetRequired => 'URL ve hedef yol gerekli.';
  @override
  String get createFailed => 'Depo oluşturulamadı.';
  @override
  String get cloneFailed => 'Depo klonlanamadı.';
}

// Path: onboarding.preview.panels
class _Translations$onboarding$preview$panels$tr
    extends Translations$onboarding$preview$panels$en {
  _Translations$onboarding$preview$panels$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get xray => 'repo x-ray';
  @override
  String get settings => 'ayarlar';
}

// Path: onboarding.preview.sidebar
class _Translations$onboarding$preview$sidebar$tr
    extends Translations$onboarding$preview$sidebar$en {
  _Translations$onboarding$preview$sidebar$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get projectsHeader => 'Projeler';
}

// Path: onboarding.preview.changes
class _Translations$onboarding$preview$changes$tr
    extends Translations$onboarding$preview$changes$en {
  _Translations$onboarding$preview$changes$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String filesStagedCount({required Object total, required Object staged}) =>
      '${total} dosyadan ${staged} tanesi';
  @override
  String stagedCount({required Object n}) => '${n} hazırlandı';
  @override
  String get commitMessageHint => 'Commit mesajı…';
  @override
  String get commitAndPush => 'Commit & push';
}

// Path: onboarding.preview.history
class _Translations$onboarding$preview$history$tr
    extends Translations$onboarding$preview$history$en {
  _Translations$onboarding$preview$history$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get header => 'Geçmiş';
  @override
  String get viewingLast => 'son 20 commit görüntüleniyor';
  @override
  String get inFlight => 'YOLDA';
  @override
  String get you => 'sen';
  @override
  String get commit1 => 'tilkiye yutmadan önce koklamayı öğret';
  @override
  String get commit2 => 'amber: kokuyu gece boyu tut';
  @override
  String get commit3 => 'lahanayı bırak, yerine amber + diken';
  @override
  String get commit4 => 'diken kapıyı korur';
}

// Path: onboarding.preview.branches
class _Translations$onboarding$preview$branches$tr
    extends Translations$onboarding$preview$branches$en {
  _Translations$onboarding$preview$branches$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get lensBranches => 'DALLAR';
  @override
  String get lensPRs => 'PR\'lar';
  @override
  String get absorbed => 'soğuruldu';
  @override
  String get desk => 'desk';
  @override
  String get head => 'HEAD';
  @override
  String tracking({required Object ref}) => '→ izleniyor: ${ref}';
}

// Path: onboarding.preview.diff
class _Translations$onboarding$preview$diff$tr
    extends Translations$onboarding$preview$diff$en {
  _Translations$onboarding$preview$diff$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get readmeTagline => 'Kişisel Git istemcin.';
}

// Path: releaseNotes.about.whyFlutter
class _Translations$releaseNotes$about$whyFlutter$tr
    extends Translations$releaseNotes$about$whyFlutter$en {
  _Translations$releaseNotes$about$whyFlutter$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'NEDEN FLUTTER?';
  @override
  String get body =>
      'Bunun ilk sürümü bir Tauri uygulamasıydı (Rust + TypeScript). Yavaş hissettirdiğini zaten biliyordum. Sonra normalde izlemediğim bir yayında bir yayıncının aynı şeyi söylediğini yakaladım, ve nihayet geçiş yapmam için gereken dürtü bu oldu. Flutter\'ı önermedi; tam tersine. Dart\'ı kendim buldum, alelacele bir prototip kurdum, ve başlangıç süresi yaklaşık 15 saniyeden bir saniyenin altına indi. Gece ile gündüz gibi. Elveda Tauri dönemi.\n\nFlutter\'ın render hattı bir DOM\'dan çok bir oyun motoruna yakın, ve UI\'nin ürünün kendisi olduğu bir masaüstü uygulaması için bu her şey demek. Dart da gerçekten iyi bir dil çıktı. Spektral motorun arkasındaki matematik önce Rust\'ta prototiplenmişti, bu yüzden o iş sorunsuz taşındı.\n\nFlutter varsayılan olarak çapraz platform, ki bu harika, ama doğası gereği Google\'vari, bu yüzden birkaç tuhaflığı var.';
}

// Path: releaseNotes.about.spectralEngine
class _Translations$releaseNotes$about$spectralEngine$tr
    extends Translations$releaseNotes$about$spectralEngine$en {
  _Translations$releaseNotes$about$spectralEngine$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'SPEKTRAL MOTOR NEDİR?';
  @override
  String get body =>
      'Her commit yaptığında, birlikte değiştirdiğin dosyalar zaman içinde desenler oluşturur. Spektral motor commit grafiğini okur ve bu ortak değişim desenlerini sinyallere ayrıştırır: hangi dosyalar bağlı, ne kadar sıkı ve depoda hangi yapısal rolü oynuyorlar. Temelde geliştirme geçmişin üzerinde spektral analiz. Bir git istemcisinde. Bilerek.\n\nMatematik yeni, bu yüzden ona oyun hissi gibi davranıyorum: ayarla, test et, düzelt ve sinyaller doğru hissettirene kadar devam et.\n\nBu sinyaller her şeyi besler. Geçmişteki sismograf, commit başlıklarının altındaki boyalı çubuklar, inceleme sistemi, Muse, dosya takımyıldızı. Tüm uygulama bu katmandan aşağıya doğru akıl yürütür, tersi yönde değil.';
}

// Path: releaseNotes.about.whereGoing
class _Translations$releaseNotes$about$whereGoing$tr
    extends Translations$releaseNotes$about$whereGoing$en {
  _Translations$releaseNotes$about$whereGoing$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get question => 'BU NEREYE GİDİYOR?';
  @override
  String get body =>
      'İlk kilometre taşı GitHub Desktop, SourceTree ve GitKraken ile tam denklik. Hızlı hissettiren ve temelleri her şeyden daha iyi ele alan çapraz platform bir git istemcisi. Bu büyük ölçüde tamam. Spektral motor, diğer istemcilerin sana manuel olarak düşündürdüğü işlemler için bize şimdiden bir avantaj sağlıyor.\n\nBunun ötesinde amaç, diğer her git istemcisini hız, erişilebilirlik, zekâ ve genel UX açısından geçmek. Burada duyurulandan daha fazlası hazırlıkta.';
}

// Path: settings.commitPreview.title
class _Translations$settings$commitPreview$title$tr
    extends Translations$settings$commitPreview$title$en {
  _Translations$settings$commitPreview$title$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$title$verbLed$tr verbLed =
      _Translations$settings$commitPreview$title$verbLed$tr._(_root);
  @override
  late final _Translations$settings$commitPreview$title$descriptive$tr
  descriptive = _Translations$settings$commitPreview$title$descriptive$tr._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$title$narrative$tr narrative =
      _Translations$settings$commitPreview$title$narrative$tr._(_root);
}

// Path: settings.commitPreview.base
class _Translations$settings$commitPreview$base$tr
    extends Translations$settings$commitPreview$base$en {
  _Translations$settings$commitPreview$base$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$base$verbLed$tr verbLed =
      _Translations$settings$commitPreview$base$verbLed$tr._(_root);
  @override
  late final _Translations$settings$commitPreview$base$descriptive$tr
  descriptive = _Translations$settings$commitPreview$base$descriptive$tr._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$base$narrative$tr narrative =
      _Translations$settings$commitPreview$base$narrative$tr._(_root);
}

// Path: settings.commitPreview.balancedSuffix
class _Translations$settings$commitPreview$balancedSuffix$tr
    extends Translations$settings$commitPreview$balancedSuffix$en {
  _Translations$settings$commitPreview$balancedSuffix$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$verbLed$tr
  verbLed = _Translations$settings$commitPreview$balancedSuffix$verbLed$tr._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$descriptive$tr
  descriptive =
      _Translations$settings$commitPreview$balancedSuffix$descriptive$tr._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$balancedSuffix$narrative$tr
  narrative =
      _Translations$settings$commitPreview$balancedSuffix$narrative$tr._(_root);
}

// Path: settings.commitPreview.everythingSuffix
class _Translations$settings$commitPreview$everythingSuffix$tr
    extends Translations$settings$commitPreview$everythingSuffix$en {
  _Translations$settings$commitPreview$everythingSuffix$tr._(
    TranslationsTr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$verbLed$tr
  verbLed = _Translations$settings$commitPreview$everythingSuffix$verbLed$tr._(
    _root,
  );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$descriptive$tr
  descriptive =
      _Translations$settings$commitPreview$everythingSuffix$descriptive$tr._(
        _root,
      );
  @override
  late final _Translations$settings$commitPreview$everythingSuffix$narrative$tr
  narrative =
      _Translations$settings$commitPreview$everythingSuffix$narrative$tr._(
        _root,
      );
}

// Path: xray.cards.branchModel
class _Translations$xray$cards$branchModel$tr
    extends Translations$xray$cards$branchModel$en {
  _Translations$xray$cards$branchModel$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get broadClaim =>
      'Depoda, dal-farkında gezinmeyi ödüllendirecek kadar dal yüzeyi var.';
  @override
  String get broadTitle => 'Dal modelinin yüzey alanı var';
  @override
  String localBranchesDetail({required Object count}) => '${count} yerel dal.';
  @override
  String get localBranchesLabel => 'Yerel dallar';
  @override
  String remoteBranchesDetail({required Object count}) => '${count} uzak dal.';
  @override
  String get remoteBranchesLabel => 'Uzak dallar';
  @override
  String get simpleClaim => 'Görünür dal modeli dar.';
  @override
  String get simpleTitle => 'Basit dal modeli';
}

// Path: xray.cards.bursty
class _Translations$xray$cards$bursty$tr
    extends Translations$xray$cards$bursty$en {
  _Translations$xray$cards$bursty$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'İş, düz bir günlük ritim yerine yoğunlaşmış patlamalarda iniyor.';
  @override
  String get title => 'Patlamalı geliştirme temposu';
}

// Path: xray.cards.hiddenRefs
class _Translations$xray$cards$hiddenRefs$tr
    extends Translations$xray$cards$hiddenRefs$en {
  _Translations$xray$cards$hiddenRefs$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object count}) =>
      '${count} referans normal dal/etiket alanının dışında yaşıyor.';
  @override
  String evidenceDetail({required Object count}) =>
      'heads/remotes/tags dışında ${count} referans.';
  @override
  String get evidenceLabel => 'Gizli referanslar';
  @override
  String get namespacesLabel => 'Ad alanları';
  @override
  String get title => 'Gizli Git ad alanları';
}

// Path: xray.cards.keystone
class _Translations$xray$cards$keystone$tr
    extends Translations$xray$cards$keystone$en {
  _Translations$xray$cards$keystone$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String claim({
    required num n,
  }) => (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
    n,
    one:
        'Bir dosya, dokunma sayısına oranla orantısız ortak değişim ağırlığı taşıyor.',
    other:
        'Küçük bir dosya kümesi, dokunma sayılarına oranla orantısız ortak değişim ağırlığı taşıyor.',
  );
  @override
  String evidenceDetail({required num n, required Object score}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: '${n} dokunma · çekim φ=${score}',
        other: '${n} dokunma · çekim φ=${score}',
      );
  @override
  String title({required num n}) =>
      (_root.$meta.cardinalResolver ?? PluralResolvers.cardinal('tr'))(
        n,
        one: 'Kilit taşı köprü-dosya',
        other: '${n} kilit taşı köprü-dosya',
      );
}

// Path: xray.cards.machineHistory
class _Translations$xray$cards$machineHistory$tr
    extends Translations$xray$cards$machineHistory$en {
  _Translations$xray$cards$machineHistory$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Checkpoint tarzı commit\'ler naif geçmiş metriklerini önemli ölçüde çarpıtıyor.';
  @override
  String machineCommitsDetail({required Object count}) =>
      '${count} commit, makine/oturum desenlerine uydu.';
  @override
  String get machineCommitsLabel => 'Makine commit\'leri';
  @override
  String rawVsFilteredDetail({required Object raw, required Object filtered}) =>
      '${raw} ham commit vs ${filtered} filtrelenmiş commit.';
  @override
  String get rawVsFilteredLabel => 'Ham vs filtrelenmiş';
  @override
  String get title => 'Makine geçmişi ham metriklere hâkim';
}

// Path: xray.cards.migration
class _Translations$xray$cards$migration$tr
    extends Translations$xray$cards$migration$en {
  _Translations$xray$cards$migration$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object older, required Object newer}) =>
      'Geçmiş `${older}` katmanından `${newer}` katmanına kayıyor, bir yığın veya yüzey geçişine işaret ediyor.';
  @override
  String stratumDetail({required Object touches, required Object lastActive}) =>
      '${touches} dokunma, son etkinlik ${lastActive}.';
  @override
  String get title => 'Mimari geçiş görünür';
}

// Path: xray.cards.narrowHotspot
class _Translations$xray$cards$narrowHotspot$tr
    extends Translations$xray$cards$narrowHotspot$en {
  _Translations$xray$cards$narrowHotspot$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Küçük bir dosya ve dizin kümesi, değişikliklerin orantısız bir payını soğuruyor.';
  @override
  String get title => 'Hotspot yoğunluğu dar';
  @override
  String topHotspotDetail({required Object path, required Object pct}) =>
      '${path}, görünür hotspot kümesinin %${pct} payına sahip.';
  @override
  String get topHotspotLabel => 'En üst hotspot';
  @override
  String visibleAuthorsDetail({required Object count}) =>
      'Bu geçmiş diliminde ${count} yazar.';
  @override
  String get visibleAuthorsLabel => 'Görünür yazarlar';
}

// Path: xray.cards.noTags
class _Translations$xray$cards$noTags$tr
    extends Translations$xray$cards$noTags$en {
  _Translations$xray$cards$noTags$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Git etiketleri görünür bir sürüm veya kilometre taşı katmanı olarak kullanılmıyor.';
  @override
  String remoteEndpointsDetail({required Object count}) =>
      '${count} uzak uç nokta yapılandırıldı.';
  @override
  String get remoteEndpointsLabel => 'Uzak uç noktalar';
  @override
  String get tagCountDetail => '0 etiket bulundu.';
  @override
  String get tagCountLabel => 'Etiket sayısı';
  @override
  String get title => 'Biçimsel sürüm/etiket izi yok';
}

// Path: xray.cards.reflog
class _Translations$xray$cards$reflog$tr
    extends Translations$xray$cards$reflog$en {
  _Translations$xray$cards$reflog$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get claim =>
      'Reflog hacmi, yayımlanan commit\'lerin ötesinde yoğun yerel yineleme olduğunu gösteriyor.';
  @override
  String get peakReflogDayLabel => 'Zirve reflog günü';
  @override
  String get title => 'Yoğun yerel düzenleme oturumları';
}

// Path: xray.cards.singleOwner
class _Translations$xray$cards$singleOwner$tr
    extends Translations$xray$cards$singleOwner$en {
  _Translations$xray$cards$singleOwner$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String claim({required Object path, required Object kind}) =>
      '`${path}`, tek belirgin görünür yazarı olan, yoğun şekilde dokunulmuş bir ${kind}.';
  @override
  String ownerCountDetail({required Object count}) =>
      '${count} belirgin yazar.';
  @override
  String get ownerCountLabel => 'Sahip sayısı';
  @override
  String get title => 'Tek sahipli hotspot';
  @override
  String get touchCountLabel => 'Dokunma sayısı';
  @override
  String touchDetailFiltered({required Object count}) =>
      'Filtrelenmiş geçmişte ${count} dokunma.';
  @override
  String touchDetailRaw({required Object count}) =>
      'Ham geçmişte ${count} dokunma.';
}

// Path: onboarding.repo.doors.open
class _Translations$onboarding$repo$doors$open$tr
    extends Translations$onboarding$repo$doors$open$en {
  _Translations$onboarding$repo$doors$open$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Aç';
  @override
  String get subtitle => 'mevcut';
  @override
  String get hint => 'zaten sahip olduğun biri';
}

// Path: onboarding.repo.doors.clone
class _Translations$onboarding$repo$doors$clone$tr
    extends Translations$onboarding$repo$doors$clone$en {
  _Translations$onboarding$repo$doors$clone$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Klonla';
  @override
  String get subtitle => 'URL\'den';
  @override
  String get hint => 'bir uzak URL yapıştır';
}

// Path: onboarding.repo.doors.create
class _Translations$onboarding$repo$doors$create$tr
    extends Translations$onboarding$repo$doors$create$en {
  _Translations$onboarding$repo$doors$create$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get title => 'Oluştur';
  @override
  String get subtitle => 'yeni';
  @override
  String get hint => 'sıfırdan bir şey başlat';
}

// Path: settings.commitPreview.title.verbLed
class _Translations$settings$commitPreview$title$verbLed$tr
    extends Translations$settings$commitPreview$title$verbLed$en {
  _Translations$settings$commitPreview$title$verbLed$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Tilkinin kötü kokan kurabiyeleri atlamasına izin ver';
  @override
  String get s2 =>
      'Tilkiye yutmadan önce kurcalanmış kurabiyeleri reddetmeyi öğret';
  @override
  String get s3 => 'Tilkiyi kapıda her kurabiyeyi adli olarak incelemeye zorla';
  @override
  String get def => 'Tilkiye kötü kurabiyeleri reddetmeyi öğret';
}

// Path: settings.commitPreview.title.descriptive
class _Translations$settings$commitPreview$title$descriptive$tr
    extends Translations$settings$commitPreview$title$descriptive$en {
  _Translations$settings$commitPreview$title$descriptive$tr._(
    TranslationsTr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'tilki artık kurabiyeleri seçiyor';
  @override
  String get s2 => 'Kurabiye-inceleme rutini, tilkiye tembihlendi';
  @override
  String get s3 =>
      'Kurabiye-doğrulama adli incelemesi, tekrarla tilkiye işlendi';
  @override
  String get def => 'Kurabiye-koklama protokolü, tilkiye kuruldu';
}

// Path: settings.commitPreview.title.narrative
class _Translations$settings$commitPreview$title$narrative$tr
    extends Translations$settings$commitPreview$title$narrative$en {
  _Translations$settings$commitPreview$title$narrative$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'tilki yanlış kokan kurabiyeleri atlamaya başladı';
  @override
  String get s2 =>
      'Tilkiyle oturup hangi kurabiyelerin reddedileceğini adım adım çalıştık';
  @override
  String get s3 =>
      'Öğleden sonranın büyük kısmını tilkiyi, sunulan her kurabiyenin iyi niyetle bir kurabiye olmadığına ikna etmekle geçirdim';
  @override
  String get def => 'Tilkiden kurabiyeleri yemeden önce koklamasını istedim';
}

// Path: settings.commitPreview.base.verbLed
class _Translations$settings$commitPreview$base$verbLed$tr
    extends Translations$settings$commitPreview$base$verbLed$en {
  _Translations$settings$commitPreview$base$verbLed$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Tilki şöyle bir bakar. Ters olan ne varsa bırakılır.';
  @override
  String get s2 =>
      'Tilki her token\'ı inceler, kokusu ters olan her şeyi reddeder ve reddi verandaya not eder.';
  @override
  String get s3 =>
      'Tilki her token\'ın etrafında döner, havayı üç açıdan koklar, yanlış okuduğu her token\'ı reddeder ve reddin oturması için bir an bekler.';
  @override
  String get def =>
      'Tilki artık her token\'ı koklar ve şüphelileri kibarca reddeder.';
}

// Path: settings.commitPreview.base.descriptive
class _Translations$settings$commitPreview$base$descriptive$tr
    extends Translations$settings$commitPreview$base$descriptive$en {
  _Translations$settings$commitPreview$base$descriptive$tr._(
    TranslationsTr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Garip olanlara yumuşak bir geçiş, çoğunlukla.';
  @override
  String get s2 =>
      'Kokusu ters her token\'a, verandadan verilip not edilen belgeli bir ret.';
  @override
  String get s3 =>
      'Kokusu ters her token için, biri havada biri sabit bir pençeyle verandadan verilen noter onaylı bir ret.';
  @override
  String get def => 'Şüpheli token\'lara verandadan verilen kibar bir ret.';
}

// Path: settings.commitPreview.base.narrative
class _Translations$settings$commitPreview$base$narrative$tr
    extends Translations$settings$commitPreview$base$narrative$en {
  _Translations$settings$commitPreview$base$narrative$tr._(TranslationsTr root)
    : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => 'Tilki garip olanları yemeyi öylece bıraktı. Kolay.';
  @override
  String get s2 =>
      'Eskiden her token pek düşünülmeden yutulurdu; şimdi bir duraklama, düzgün bir bakış ve içine sinmeyenler için bir ret var.';
  @override
  String get s3 =>
      'Eskiden her token düşünülmeden yutulurdu. Şimdi: bir duraklama. Hava, içe çekilir. Hava, tutulur. Tilki, bir şey ters gittiğinde bazen olan o küçük seğirme için veranda tahtalarını izler ve karar ancak o zaman verilir.';
  @override
  String get def =>
      'Eskiden her token merasimsiz yutulurdu; şimdi önce bir koklama var.';
}

// Path: settings.commitPreview.balancedSuffix.verbLed
class _Translations$settings$commitPreview$balancedSuffix$verbLed$tr
    extends Translations$settings$commitPreview$balancedSuffix$verbLed$en {
  _Translations$settings$commitPreview$balancedSuffix$verbLed$tr._(
    TranslationsTr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Veranda iyi. Arka bahçe her neyse.';
  @override
  String get s2 =>
      ' Her retten sonra veranda süpürülür; arka bahçe çamuruna ilan edilen saatler içinde izin verilir.';
  @override
  String get s3 =>
      ' Veranda süpürülür ve yeniden süpürülür; arka bahçe çamuru pençe iziyle ve havaya göre kataloglanır, ve tilki eşikte eskisinden daha uzun oyalanır.';
  @override
  String get def => ' Veranda temiz kalır; arka bahçe çamur haklarını korur.';
}

// Path: settings.commitPreview.balancedSuffix.descriptive
class _Translations$settings$commitPreview$balancedSuffix$descriptive$tr
    extends Translations$settings$commitPreview$balancedSuffix$descriptive$en {
  _Translations$settings$commitPreview$balancedSuffix$descriptive$tr._(
    TranslationsTr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Veranda tamam. Arka bahçe arka bahçelik işler yapar.';
  @override
  String get s2 =>
      ' Veranda kanıt-temizliğinde bir bölge; arka bahçe belirlenmiş çamur bölgesi, saatler ilan edilmiş.';
  @override
  String get s3 =>
      ' Veranda kanıt-kalitesinde temiz oda; arka bahçe kataloglanmış çamur arşivi; eşik ise tilkinin durup fazla uzun düşündüğü bir yer.';
  @override
  String get def => ' Temiz veranda; çamur hakları arka bahçede korunur.';
}

// Path: settings.commitPreview.balancedSuffix.narrative
class _Translations$settings$commitPreview$balancedSuffix$narrative$tr
    extends Translations$settings$commitPreview$balancedSuffix$narrative$en {
  _Translations$settings$commitPreview$balancedSuffix$narrative$tr._(
    TranslationsTr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Veranda iyiydi. Arka bahçe, kim bilir.';
  @override
  String get s2 =>
      ' Veranda sonrasında temiz tutuldu; tilki, düşünmenin gerçekleştiği yer olan arka bahçeye çekildi.';
  @override
  String get s3 =>
      ' O akşam veranda iki kez fırçalandı. Tilki arka bahçede yavaşça yürüdü, hep aynı çit direğinde durdu ve verandaya, sanki veranda ona bir şey borçluymuş gibi baktı.';
  @override
  String get def =>
      ' Veranda temiz kalır, gerçi onur meselesinde arka bahçe hâlâ kazanır.';
}

// Path: settings.commitPreview.everythingSuffix.verbLed
class _Translations$settings$commitPreview$everythingSuffix$verbLed$tr
    extends Translations$settings$commitPreview$everythingSuffix$verbLed$en {
  _Translations$settings$commitPreview$everythingSuffix$verbLed$tr._(
    TranslationsTr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Amber orada. Drift sürüklenir. Diken, gerekirse batar. Çoğunlukla hiçbir şey.';
  @override
  String get s2 =>
      ' Amber her kokuyu inceleme için tutar. Drift günün havasını kapı dikenine taşır, o da her reddi akşam sayımı için işaretler.';
  @override
  String get s3 =>
      ' Amber her kokuyu tutar ve saate göre farklı bir ağırlık verir. Drift, önemsiz olması gereken ama olan açılarda verandanın içinden geçer. Kapı dikeni retler için bir kez, tilkinin neredeyse kaçırdıkları için iki kez batar, ve başka kimse bilmese bile tilki farkı bilir.';
  @override
  String get def =>
      ' Amber kokuyu tutar. Drift onu taşır. Kapı dikeni geçmemesi gerekeni yakalar.';
}

// Path: settings.commitPreview.everythingSuffix.descriptive
class _Translations$settings$commitPreview$everythingSuffix$descriptive$tr
    extends
        Translations$settings$commitPreview$everythingSuffix$descriptive$en {
  _Translations$settings$commitPreview$everythingSuffix$descriptive$tr._(
    TranslationsTr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 => ' Amber direkte. Drift havada. Diken kapıda. İyi.';
  @override
  String get s2 =>
      ' Amber belirlenmiş koku-tanığı; drift kayıtlı bir ortam; diken-işaretleri günün ret kaydı, alaca karanlıkta uzlaştırılır.';
  @override
  String get s3 =>
      ' Amber, sessizliği başlı başına bir okuma olan bir koku-tanığı; drift, bir şey ters olduğu günlerde yanlış hareket eden desenli bir ortam; diken kapının sayım tutucusu, işaretlerini tilki yatmadan önce ve şafaktan önce yeniden kontrol eder.';
  @override
  String get def =>
      ' Amber koku-tanığı; drift ortam bağlamı; diken kapının sessiz ret-işareti.';
}

// Path: settings.commitPreview.everythingSuffix.narrative
class _Translations$settings$commitPreview$everythingSuffix$narrative$tr
    extends Translations$settings$commitPreview$everythingSuffix$narrative$en {
  _Translations$settings$commitPreview$everythingSuffix$narrative$tr._(
    TranslationsTr root,
  ) : this._root = root,
      super.internal(root);

  final TranslationsTr _root; // ignore: unused_field

  // Translations
  @override
  String get s0 =>
      ' Amber etraftaydı. Drift gelip gitti. Diken sessiz işini yaptı. Neyse, rahattı.';
  @override
  String get s2 =>
      ' Amber günün koku-kaydını tuttu, drift yön ve saate göre not edildi, ve dikenin işaretleri sayılıp veranda tarafından karşı-imzalandı.';
  @override
  String get s3 =>
      ' Amber koku-kaydını tuttu, ama tilki belirli sabahlar daha ağır bastığına yemin ediyor. Drift verandanın içinden hep yaptığı gibi geçti, yani önemli olan günlerde yanlış. Kapı dikeni her reddi işaretledi; tilki ilk ışıkta onları saymaya çıktı, tıpkı zaten saydığın basamakları saydığın gibi.';
  @override
  String get def =>
      ' Amber koku-kaydını tuttu, drift havayı taşıdı, ve kapı dikeni yakalanması gerekeni yakaladı.';
}
