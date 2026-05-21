import 'dart:async';

import 'package:flutter/foundation.dart';

void fireAndLog(Future<void> future, String tag) {
  unawaited(future.catchError((e) => debugPrint('$tag failed: $e')));
}
