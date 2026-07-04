import 'package:flutter/material.dart';

import '../../ui/design_primitives.dart';
import '../../ui/tokens.dart';

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
        'Force push (with lease)?',
        style: TextStyle(color: t.textStrong, fontSize: 14),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Target: $remote/$branch',
            style: TextStyle(
              color: t.textStrong,
              fontSize: 11.5,
              fontFamily: AppFonts.mono,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This rewrites the remote branch with your local history. '
            'With lease aborts if someone pushed to the remote after your '
            'last fetch, but already-fetched changes will still be '
            'overwritten. Use only when you intended a rebase or amend that '
            'diverged the branch.',
            style: TextStyle(color: t.textNormal, fontSize: 12, height: 1.45),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Force push'),
        ),
      ],
    ),
  );
  return res == true;
}
