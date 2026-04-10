import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../ui/tokens.dart';
import 'app_identity.dart';
import 'repository_state.dart';

// ── TitlebarStrip ─────────────────────────────────────────────────────────────
// 40px tall custom titlebar.
// Left: repo name (textNormal 13px) or the app name (textMuted).
// Right: 6px status dot.
// Drag region: pan → startDragging, double-tap → toggle maximize.

class TitlebarStrip extends StatelessWidget {
  const TitlebarStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final repo = context.watch<RepositoryState>();
    final identity = context.appIdentity;

    final repoName = repo.activeRepoName;
    final hasRepo = repoName != null;

    // border-bottom: 1px solid secondaryBtnBorder
    final borderColor = t.secondaryBtnBorder;

    // box-shadow: inset 0 0.5px 0 rgba(255,255,255,0.1)
    const insetHighlight = BoxShadow(
      color: Color(0x1AFFFFFF),
      offset: Offset(0, 0.5),
      blurRadius: 0,
      blurStyle: BlurStyle.inner,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          await windowManager.restore();
        } else {
          await windowManager.maximize();
        }
      },
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: t.surface0,
          border: Border(
            bottom: BorderSide(color: borderColor, width: 1),
          ),
          boxShadow: const [insetHighlight],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // workspace-identity
            Expanded(
              child: Text(
                hasRepo ? repoName : identity.shortName,
                style: TextStyle(
                  color: hasRepo ? t.textNormal : t.textMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // titlebar-status: 6px circle
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: t.chromeBorder.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
