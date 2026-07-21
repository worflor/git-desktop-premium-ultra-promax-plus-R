// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:async';

import 'package:flutter/foundation.dart';

void fireAndLog(Future<void> future, String tag) {
  unawaited(future.catchError((Object e) => debugPrint('$tag failed: $e')));
}
