import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../app/build_info.dart';

/// Shape of a single release manifest, served at
/// `${updateBaseUrl}/${channel}.json`.
///
/// Example:
/// ```json
/// {
///   "version": "0.2.0-beta.2",
///   "channel": "beta",
///   "downloadUrl": "https://releases.manifold.dev/0.2.0-beta.2/manifold.zip",
///   "notes": "Faster diff renderer; fixes engram cold-start.",
///   "publishedAt": "2026-04-30T12:00:00Z"
/// }
/// ```
class ReleaseManifest {
  final String version;
  final String channel;
  final String? downloadUrl;
  final String? notes;
  final DateTime? publishedAt;

  const ReleaseManifest({
    required this.version,
    required this.channel,
    this.downloadUrl,
    this.notes,
    this.publishedAt,
  });

  factory ReleaseManifest.fromJson(Map<String, dynamic> json) {
    final version = (json['version'] as String?)?.trim();
    final channel = (json['channel'] as String?)?.trim();
    if (version == null || version.isEmpty) {
      throw const FormatException('release manifest missing "version"');
    }
    if (channel == null || channel.isEmpty) {
      throw const FormatException('release manifest missing "channel"');
    }
    DateTime? published;
    final publishedRaw = json['publishedAt'];
    if (publishedRaw is String && publishedRaw.isNotEmpty) {
      published = DateTime.tryParse(publishedRaw);
    }
    final rawDownload = (json['downloadUrl'] as String?)?.trim();
    return ReleaseManifest(
      version: version,
      channel: channel,
      // Drop a downloadUrl that isn't plain http(s). The OPEN DOWNLOAD
      // button hands this string to the system browser, so a hostile
      // manifest could otherwise smuggle in `file://`, UNC paths,
      // `ms-appinstaller:`, `javascript:`, etc. — all of which Windows
      // would happily dispatch through their registered protocol
      // handler. Treating the field as missing here keeps OPEN DOWNLOAD
      // disabled rather than launching an attacker-supplied target;
      // openInSystemBrowser also rejects the same set as defense-in-
      // depth at the call site.
      downloadUrl: _sanitizedDownloadUrl(rawDownload),
      notes: (json['notes'] as String?)?.trim(),
      publishedAt: published,
    );
  }
}

String? _sanitizedDownloadUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final parsed = Uri.tryParse(raw);
  if (parsed == null) return null;
  if (!parsed.hasAuthority) return null;
  if (!(parsed.isScheme('https') || parsed.isScheme('http'))) return null;
  return raw;
}

enum ReleaseCheckStatus {
  /// Local build is at or ahead of the manifest's version.
  upToDate,

  /// Manifest version is newer than the local build.
  updateAvailable,

  /// No update server URL configured for this binary.
  /// Common in dev builds; surfaced explicitly so the user knows
  /// the button isn't broken — there's just nothing to check.
  notConfigured,

  /// Server returned 404 for this channel — no releases published yet.
  /// Distinct from [networkError] so the UI can say "no releases on
  /// the BETA channel yet" rather than "request failed".
  notFound,

  /// Connection / timeout / non-2xx-non-404 response.
  networkError,

  /// Manifest decoded but didn't match our schema.
  parseError,
}

class ReleaseCheckResult {
  final ReleaseCheckStatus status;
  final String currentVersion;
  final String channel;
  final ReleaseManifest? manifest;
  final String? errorDetail;

  const ReleaseCheckResult({
    required this.status,
    required this.currentVersion,
    required this.channel,
    this.manifest,
    this.errorDetail,
  });

  bool get hasUpdate => status == ReleaseCheckStatus.updateAvailable;
}

abstract final class ReleaseChecker {
  /// Looks up the manifest for [channel] and compares its version
  /// against [currentVersion] (defaults to [BuildInfo.version]).
  ///
  /// All failure modes are encoded in [ReleaseCheckResult.status]; the
  /// returned future never rejects. Pass an [httpClient] to inject a
  /// fake in tests; pass [overrideBaseUrl] to force a URL when the
  /// build wasn't tagged with one.
  static Future<ReleaseCheckResult> check({
    required String channel,
    String? currentVersion,
    String? overrideBaseUrl,
    HttpClient? httpClient,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final base = (overrideBaseUrl ?? BuildInfo.updateBaseUrl).trim();
    final version = currentVersion ?? BuildInfo.version;
    if (base.isEmpty) {
      return ReleaseCheckResult(
        status: ReleaseCheckStatus.notConfigured,
        currentVersion: version,
        channel: channel,
      );
    }

    final normalisedBase = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    final Uri url;
    try {
      url = Uri.parse('$normalisedBase/$channel.json');
    } on FormatException catch (e) {
      return ReleaseCheckResult(
        status: ReleaseCheckStatus.networkError,
        currentVersion: version,
        channel: channel,
        errorDetail: 'invalid manifest URL: ${e.message}',
      );
    }

    // HTTPS-only at the fetch layer. The manifest body controls the
    // string the user clicks for "open download," so an HTTP base URL
    // exposes the channel to MITM rewrites that could substitute a
    // hostile downloadUrl. Reject up front rather than relying on the
    // downstream parsers to catch every shape — a misconfigured
    // deployment should fail loudly, not silently downgrade trust.
    if (!url.isScheme('https')) {
      return ReleaseCheckResult(
        status: ReleaseCheckStatus.notConfigured,
        currentVersion: version,
        channel: channel,
        errorDetail: 'update base URL must use https',
      );
    }

    final ownClient = httpClient == null;
    final client = httpClient ?? HttpClient();
    client.connectionTimeout = timeout;
    try {
      final request = await client.getUrl(url).timeout(timeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode == 404) {
        await response.drain<void>();
        return ReleaseCheckResult(
          status: ReleaseCheckStatus.notFound,
          currentVersion: version,
          channel: channel,
        );
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        return ReleaseCheckResult(
          status: ReleaseCheckStatus.networkError,
          currentVersion: version,
          channel: channel,
          errorDetail: 'HTTP ${response.statusCode}',
        );
      }
      final body = await response.transform(utf8.decoder).join().timeout(timeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        return ReleaseCheckResult(
          status: ReleaseCheckStatus.parseError,
          currentVersion: version,
          channel: channel,
          errorDetail: 'manifest root is not a JSON object',
        );
      }
      final manifest = ReleaseManifest.fromJson(decoded);
      final cmp = compareSemver(manifest.version, version);
      return ReleaseCheckResult(
        status: cmp > 0
            ? ReleaseCheckStatus.updateAvailable
            : ReleaseCheckStatus.upToDate,
        currentVersion: version,
        channel: channel,
        manifest: manifest,
      );
    } on TimeoutException {
      return ReleaseCheckResult(
        status: ReleaseCheckStatus.networkError,
        currentVersion: version,
        channel: channel,
        errorDetail: 'request timed out',
      );
    } on FormatException catch (e) {
      return ReleaseCheckResult(
        status: ReleaseCheckStatus.parseError,
        currentVersion: version,
        channel: channel,
        errorDetail: e.message,
      );
    } on SocketException catch (e) {
      return ReleaseCheckResult(
        status: ReleaseCheckStatus.networkError,
        currentVersion: version,
        channel: channel,
        errorDetail: e.message,
      );
    } on HttpException catch (e) {
      return ReleaseCheckResult(
        status: ReleaseCheckStatus.networkError,
        currentVersion: version,
        channel: channel,
        errorDetail: e.message,
      );
    } finally {
      if (ownClient) client.close(force: true);
    }
  }
}

/// Returns positive if [a] > [b], negative if [a] < [b], 0 if equal.
///
/// Implements semver-2.0.0 ordering well enough for our manifests:
/// `major.minor.patch[-prerelease][+build]`. Build metadata is
/// ignored. Prerelease handling: a build with a prerelease label
/// (e.g. `0.2.0-beta.1`) is older than the same base without one
/// (`0.2.0`); within prereleases, dot-separated identifiers are
/// compared field-by-field — numeric < numeric numerically, alpha
/// vs alpha lexicographically, numeric < alpha.
///
/// Empty / missing strings sort as oldest, so an un-tagged dev build
/// reliably treats any published manifest as newer.
int compareSemver(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return -1;
  if (b.isEmpty) return 1;

  final pa = _parseSemver(a);
  final pb = _parseSemver(b);
  for (var i = 0; i < 3; i++) {
    final cmp = pa.base[i].compareTo(pb.base[i]);
    if (cmp != 0) return cmp;
  }
  // Equal base — prerelease tags decide.
  if (pa.prerelease.isEmpty && pb.prerelease.isEmpty) return 0;
  if (pa.prerelease.isEmpty) return 1; // 1.0.0 > 1.0.0-beta
  if (pb.prerelease.isEmpty) return -1;
  return _comparePrerelease(pa.prerelease, pb.prerelease);
}

class _ParsedSemver {
  final List<int> base;
  final List<String> prerelease;
  const _ParsedSemver(this.base, this.prerelease);
}

_ParsedSemver _parseSemver(String v) {
  // Strip build metadata (everything after '+').
  final plus = v.indexOf('+');
  final core = plus < 0 ? v : v.substring(0, plus);
  final dash = core.indexOf('-');
  final basePart = dash < 0 ? core : core.substring(0, dash);
  final pre = dash < 0 ? '' : core.substring(dash + 1);
  final segments = basePart.split('.');
  final base = <int>[
    for (var i = 0; i < 3; i++)
      i < segments.length ? (int.tryParse(segments[i]) ?? 0) : 0,
  ];
  final prerelease = pre.isEmpty ? const <String>[] : pre.split('.');
  return _ParsedSemver(base, prerelease);
}

int _comparePrerelease(List<String> a, List<String> b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final ai = a[i];
    final bi = b[i];
    final an = int.tryParse(ai);
    final bn = int.tryParse(bi);
    if (an != null && bn != null) {
      final cmp = an.compareTo(bn);
      if (cmp != 0) return cmp;
    } else if (an != null) {
      return -1; // numeric identifiers sort before alphanumerics
    } else if (bn != null) {
      return 1;
    } else {
      final cmp = ai.compareTo(bi);
      if (cmp != 0) return cmp;
    }
  }
  return a.length.compareTo(b.length); // shorter prerelease wins
}
