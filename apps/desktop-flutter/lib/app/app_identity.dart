import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

// Branch/build tag policy lives here:
// development = 'DEV', beta = 'BETA', release = null.
const defaultAppIdentity = AppIdentity(
  shortName: 'Manifold',
  fullName: 'Manifold Git Client',
  description: 'Your Personal Git Client',
  tag: 'DEV',
);

class AppIdentityState extends ChangeNotifier {
  AppIdentityState([AppIdentity identity = defaultAppIdentity])
      : _identity = identity;

  AppIdentity _identity;

  AppIdentity get identity => _identity;

  void setIdentity(AppIdentity next) {
    if (_identity == next) {
      return;
    }
    _identity = next;
    notifyListeners();
  }
}

extension BuildContextAppIdentity on BuildContext {
  AppIdentity get appIdentity => watch<AppIdentityState>().identity;
  AppIdentityState get appIdentityState => read<AppIdentityState>();
}
