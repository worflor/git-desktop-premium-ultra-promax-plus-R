import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_identity.dart';
import 'preferences_state.dart';
import 'window_activity.dart';
import '../components/hypercube_logo.dart';
import '../ui/tokens.dart';

class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final identity = context.appIdentity;
    // Escape hatch from the root TickerMode mute when the user has the
    // "Logo animates when tabbed out" preference ON. The root gate is
    // a blanket GPU saver for decorative animations; the hypercube is
    // the one animation a user can explicitly opt to keep running while
    // blurred. Nested TickerMode takes precedence for its subtree, so
    // this flips the logo's ticker back on even if the outer mute is
    // off. When the window is focused, both are on and this is a no-op.
    final animateUnfocused = context.select<PreferencesState, bool>(
      (p) => p.logoAnimatesWhenUnfocused,
    );
    // Re-read awake only to decide whether we need the override at all.
    // context.watch on WindowActivity would be ideal, but it's a
    // ChangeNotifier singleton outside Provider; the root mute already
    // subscribes and rebuilds its subtree, so our build runs when awake
    // flips.
    final awake = WindowActivity.instance.awake;
    return TickerMode(
      enabled: awake || animateUnfocused,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const HypercubeLogo(size: 24),
          const SizedBox(width: 8),
          Text(
            identity.shortName,
            style: TextStyle(
              color: t.textStrong,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (identity.hasTag) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: t.chromeAccent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(4),
                border:
                    Border.all(color: t.chromeAccent.withValues(alpha: 0.30)),
              ),
              child: Text(
                identity.tag!,
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  height: 1,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
