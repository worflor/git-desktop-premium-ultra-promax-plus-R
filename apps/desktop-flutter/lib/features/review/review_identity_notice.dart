// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_identity_notice.dart — the review section with no one to sign it.
//
// Review writes are SIGNED: a comment attributed to nobody is not a
// degraded comment, it is a corrupt one, and it would sync to every peer
// that way. So when git has no configured identity the pane refuses to
// exist and this stands in its place.
//
// Two lines and no more. This is not explanatory microcopy — it is a
// blocked action and its single remedy, and the remedy is short enough
// to state exactly rather than describe. The command is selectable
// because the only useful thing to do with it is copy it.

import 'package:flutter/material.dart';

import '../../ui/design_primitives.dart';
import '../../ui/tokens.dart';
import 'review_chrome.dart';
import 'review_view_model.dart';

class ReviewIdentityNotice extends StatelessWidget {
  final ReviewStrings strings;

  /// The shell command that fixes it, shown verbatim so the string the
  /// user copies is the string the resolver reads back.
  final String command;

  const ReviewIdentityNotice({
    super.key,
    required this.strings,
    required this.command,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          strings.identityNeeded,
          style: TextStyle(color: t.textMuted, fontSize: ReviewType.body),
        ),
        const SizedBox(height: AppSpacing.sm6),
        SelectableText(
          command,
          style: TextStyle(
            color: t.textStrong,
            fontSize: ReviewType.meta,
            fontFamily: AppFonts.mono,
            fontFamilyFallback: AppFonts.monoFallback,
          ),
        ),
      ],
    );
  }
}
