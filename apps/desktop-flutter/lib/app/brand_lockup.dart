import 'package:flutter/material.dart';
import 'app_identity.dart';
import '../components/hypercube_logo.dart';
import '../ui/tokens.dart';

class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final identity = context.appIdentity;
    return Row(
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
              border: Border.all(color: t.chromeAccent.withValues(alpha: 0.30)),
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
    );
  }
}
