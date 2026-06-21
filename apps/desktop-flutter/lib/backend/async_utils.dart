import 'dart:async';

import 'package:flutter/foundation.dart';

void fireAndLog(Future<void> future, String tag) {
  unawaited(future.catchError((Object e) => debugPrint('$tag failed: $e')));
}
