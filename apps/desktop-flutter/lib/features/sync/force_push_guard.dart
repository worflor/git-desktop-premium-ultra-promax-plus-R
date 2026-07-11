import 'package:flutter/material.dart';

import '../../ui/design_primitives.dart';
import '../../ui/tokens.dart';
import '../../i18n/gen/strings.g.dart' as i18n;

/// The one confirm every force-push in the app funnels through. Force-with-
/// lease is safe relative to bare `--force` (it won't overwrite commits the
/// user hasn't fetched), but it still rewrites remote history — worth a
/// deliberate confirm. Surfaces the resolved remote + branch ref so the user
/// can verify the destination before authorising; this is the only place the
/// actual push target is shown.
///
/// Returns true when the user chose to proceed. Shared contract: every force-
/// push path routes through here, and it is always lease, never bare force.
Future<bool> confirmForcePush(
  BuildContext context, {
  required String remote,
  required String branch,
}) async {
  final t = context.tokens;
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        i18n.t.sync.forcePush.confirmTitle,
        style: TextStyle(color: t.textStrong, fontSize: 14),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.t.sync.forcePush.target(remote: remote, branch: branch),
            style: TextStyle(
              color: t.textStrong,
              fontSize: 11.5,
              fontFamily: AppFonts.mono,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            i18n.t.sync.forcePush.warning,
            style: TextStyle(color: t.textNormal, fontSize: 12, height: 1.45),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(i18n.t.common.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(i18n.t.sync.forcePush.confirmButton),
        ),
      ],
    ),
  );
  return res == true;
}
