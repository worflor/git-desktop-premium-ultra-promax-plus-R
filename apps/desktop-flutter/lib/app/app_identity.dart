import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../backend/settings_store.dart';
import 'build_info.dart';

const Object _tagSentinel = Object();

@immutable
class AppIdentity {
  final String shortName;
  final String fullName;
  final String description;
  final String? tag;

  const AppIdentity({
    required this.shortName,
    required this.fullName,
    required this.description,
    this.tag,
  });

  bool get hasTag => tag != null && tag!.trim().isNotEmpty;

  AppIdentity copyWith({
    String? shortName,
    String? fullName,
    String? description,
    Object? tag = _tagSentinel,
  }) {
    return AppIdentity(
      shortName: shortName ?? this.shortName,
      fullName: fullName ?? this.fullName,
      description: description ?? this.description,
      tag: identical(tag, _tagSentinel) ? this.tag : tag as String?,
    );
  }
}

/// Branding template. The build-channel tag (DEV / BETA / null) is
/// resolved from [BuildInfo] at access time so a single binary is
/// honest about what it is — a beta release no longer wears the DEV
/// badge baked in at compile time of this file.
AppIdentity get defaultAppIdentity => AppIdentity(
      shortName: 'Manifold',
      fullName: 'Manifold Git Client',
      description: 'Your Personal Git Client',
      tag: BuildInfo.tag,
    );

class AppIdentityState extends ChangeNotifier {
  AppIdentityState([AppIdentity? identity])
      : _identity = identity ?? defaultAppIdentity;

  AppIdentity _identity;

  AppIdentity get identity => _identity;

  void setIdentity(AppIdentity next) {
    if (_identity == next) {
      return;
    }
    _identity = next;
    notifyListeners();
  }

  /// Rehydrates the identity's user-customizable fields from the settings
  /// snapshot. Only [AppIdentity.shortName] is persisted; the rest is
  /// derived so code and marketing copy stay the source of truth.
  void loadFromSettings(AppSettingsSnapshot settings) {
    final name = settings.appShortName.trim().isEmpty
        ? defaultAppIdentity.shortName
        : settings.appShortName.trim();
    setIdentity(_identity.copyWith(shortName: name));
  }

  /// Updates the short name in memory (instant UI update) and persists
  /// asynchronously. Callers that need the writeback to complete can await.
  Future<void> setShortName(String value) async {
    final trimmed = value.trim();
    final normalized = trimmed.isEmpty ? defaultAppIdentity.shortName : trimmed;
    if (normalized != _identity.shortName) {
      setIdentity(_identity.copyWith(shortName: normalized));
    }
    final settings = await SettingsStore.load();
    if (settings.appShortName == normalized) return;
    await SettingsStore.persist(
      settings.copyWith(appShortName: normalized),
    );
  }
}

extension BuildContextAppIdentity on BuildContext {
  AppIdentity get appIdentity => watch<AppIdentityState>().identity;
  AppIdentityState get appIdentityState => read<AppIdentityState>();
}
