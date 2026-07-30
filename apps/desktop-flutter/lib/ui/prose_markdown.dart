// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// prose_markdown.dart — the ONLY way this app renders someone else's
// markdown.
//
// Every markdown body in Manifold is untrusted by construction. Review
// comments arrive over `refs/manifold/review/<id>/state`, written by
// whoever else is on the remote; PR comments arrive from any account on
// GitHub or GitLab. Both are rendered the moment a pane opens, with no
// click and no confirmation.
//
// flutter_markdown's DEFAULT image handling fetches. `kDefaultImageBuilder`
// hands http/https straight to `Image.network`, and everything else to
// `Image.file`. So a plain `MarkdownBody(data: theirComment)` means:
//
//   * `![](https://x/p.png)` — every reader's client GETs an
//     attacker-chosen URL on render. In a review tool that is a read
//     receipt: who opened the review, when, from which IP, how often.
//     It works on a private repo, and it needs no reply from the reader.
//   * `![](file:///C:/Users/me/.ssh/id_rsa)` — a local read attempt fed
//     into an image decoder, i.e. a file-existence probe plus a parser
//     reached from remote text.
//
// Neither needs a bug in our code; it is what the widget does when asked
// nicely. So this file asks differently: images become inert text that
// SAYS what was suppressed, and no request leaves the machine. Showing
// the URL as prose is deliberate — a reviewer should be able to see that
// someone tried, which a silently-dropped node would hide.
//
// One factory rather than a careful call site, because there were two
// call sites and both were wrong in the same way. `test/laws` forbids
// constructing `MarkdownBody` anywhere else.

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'tokens.dart';

/// Render untrusted [data] as markdown. Never fetches anything.
///
/// [selectable] is the only knob, because it is the only thing the two
/// surfaces disagree about: prose a reader quotes from wants selection,
/// a dense thread card does not. Everything else is fixed so there is
/// one rendering of somebody else's text, not two that drift.
Widget proseMarkdown({
  required String data,
  required MarkdownStyleSheet styleSheet,
  required AppTokens tokens,

  /// What a suppressed image says it is. Injected because it is prose a
  /// screen reader will speak, and a hardcoded English constant here
  /// would be the one untranslated sentence on a localized surface.
  required String imageNotLoadedLabel,
  bool selectable = false,
}) =>
    MarkdownBody(
      data: data,
      selectable: selectable,
      shrinkWrap: true,
      fitContent: true,
      styleSheet: styleSheet,
      sizedImageBuilder: (config) =>
          _suppressedImage(config, tokens, imageNotLoadedLabel),
    );

/// What an image renders as instead of a request: its alt text, and the
/// URL it wanted, as plain unclickable prose.
Widget _suppressedImage(
    MarkdownImageConfig config, AppTokens tokens, String notLoaded) {
  final alt = (config.alt ?? '').trim();
  final label = alt.isEmpty ? config.uri.toString() : '$alt — ${config.uri}';
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      '[$notLoaded] $label',
      style: TextStyle(
        color: tokens.textMuted,
        fontSize: 10.5,
        fontStyle: FontStyle.italic,
      ),
    ),
  );
}
