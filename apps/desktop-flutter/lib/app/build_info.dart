import 'package:flutter/foundation.dart';

/// Which build of Manifold this binary is. Distinct from the user's
/// chosen update-feed preference (`PreferencesState.updateChannel`):
/// the channel here is baked in at compile time, the preference is
/// what feed they want to track for new versions. They can differ —
/// e.g. a beta-build user pinned to stable.
enum BuildChannel { dev, beta, stable }

extension BuildChannelX on BuildChannel {
  /// Stable on-disk identifier. Matches the strings the settings store
  /// already persists ('dev' / 'beta' / 'stable').
  String get id => name;

  /// All-caps tag shown in the titlebar's BrandLockup. `null` for
  /// stable, since shipping releases shouldn't shout.
  String? get badge {
    switch (this) {
      case BuildChannel.dev:
        return 'DEV';
      case BuildChannel.beta:
        return 'BETA';
      case BuildChannel.stable:
        return null;
    }
  }
}

BuildChannel? _channelFromId(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'dev':
    case 'development':
      return BuildChannel.dev;
    case 'beta':
      return BuildChannel.beta;
    case 'stable':
    case 'release':
    case 'production':
      return BuildChannel.stable;
    default:
      return null;
  }
}

/// Compile-time build identity. All values come from `--dart-define`s
/// the release script passes; in unit tests / `flutter run` they fall
/// back to the dev profile.
abstract final class BuildInfo {
  static const String _channelDefine =
      String.fromEnvironment('MANIFOLD_CHANNEL', defaultValue: '');
  static const String _versionDefine =
      String.fromEnvironment('MANIFOLD_VERSION', defaultValue: '');
  static const String _shaDefine =
      String.fromEnvironment('MANIFOLD_GIT_SHA', defaultValue: '');
  static const String _updateBaseDefine =
      String.fromEnvironment('MANIFOLD_UPDATE_BASE_URL', defaultValue: '');
  static const String _cohortDefine =
      String.fromEnvironment('BUILD_COHORT', defaultValue: 'the-best-offense');

  /// Resolved channel for this binary. Falls back to dev in debug
  /// builds and stable in release builds when the define is absent —
  /// so `flutter run` always feels like a dev session and an
  /// un-tagged `flutter build --release` doesn't masquerade as beta.
  static BuildChannel get channel {
    final parsed = _channelFromId(_channelDefine);
    if (parsed != null) return parsed;
    return kDebugMode ? BuildChannel.dev : BuildChannel.stable;
  }

  /// Semver of this build, e.g. `0.2.0-beta.1`. Empty when running
  /// `flutter test` / `flutter run` without the define — the UI
  /// renders this as `dev` in that case.
  static String get version => _versionDefine;

  /// Short git sha (7 chars) when the release script passed it.
  static String? get gitSha => _shaDefine.isEmpty ? null : _shaDefine;

  /// Base URL of the manifest server. Per-channel manifests live at
  /// `${updateBaseUrl}/${channel}.json`. Empty means "no update
  /// server configured" — POLL FOR UPDATES surfaces that explicitly
  /// instead of silently failing.
  static String get updateBaseUrl => _updateBaseDefine;

  static String? get cohort =>
      _cohortDefine.isEmpty ? null : _cohortDefine;

  /// Human display: "0.2.0-beta.1 (a1b2c3d)" when both available, or
  /// just the version, or "dev" when the build wasn't tagged.
  static String get versionDisplay {
    final v = version.isEmpty ? 'dev' : version;
    final sha = gitSha;
    if (sha == null || sha.isEmpty) return v;
    return '$v ($sha)';
  }

  /// Tag shown in the titlebar lockup. Mirrors [BuildChannel.badge].
  static String? get tag => channel.badge;

  /// Canonicalises a persisted update-channel id ('dev' / 'beta' / 'stable').
  ///
  /// Two invariants are enforced here so callers don't have to re-derive
  /// them every time they touch the value:
  ///
  ///   1. The `dev` channel is only valid on dev builds. A beta or stable
  ///      binary asking to track the dev feed has no meaningful path —
  ///      there's no dev manifest a release binary would actually fetch
  ///      — so we snap it back to the build's own channel.
  ///   2. Anything unrecognised (legacy values, typos, future channels
  ///      we don't ship yet) falls back to the build's own channel,
  ///      i.e. "track the binary you installed."
  ///
  /// This is the single source of truth for channel coercion. Both
  /// [SettingsStore] (deserialisation path) and [PreferencesState]
  /// (in-memory write path) delegate here.
  static String normalizeChannelId(String value) =>
      normalizeChannelIdFor(value, channel);
}

/// Pure variant of [BuildInfo.normalizeChannelId], parametric over the
/// build channel so tests can exercise the cross-binary migration paths
/// without rebuilding with different `--dart-define`s. Production code
/// should prefer [BuildInfo.normalizeChannelId].
String normalizeChannelIdFor(String value, BuildChannel buildChannel) {
  final v = value.trim().toLowerCase();
  if (v == 'dev') {
    return buildChannel == BuildChannel.dev ? 'dev' : buildChannel.id;
  }
  if (v == 'beta' || v == 'stable') return v;
  return buildChannel.id;
}
