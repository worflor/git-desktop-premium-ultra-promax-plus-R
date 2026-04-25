import 'package:flutter/material.dart';

import 'tokens.dart';

enum AppStatusTone { neutral, error }

const noRepositoryTitle = 'No repository open';
const noRepositoryMessage =
    'Open or add a repository from Projects to use this view.';

class AppStatusView extends StatelessWidget {
  final String title;
  final String message;
  final bool busy;
  final AppStatusTone tone;
  final bool compact;

  const AppStatusView({
    super.key,
    required this.title,
    required this.message,
    this.busy = false,
    this.tone = AppStatusTone.neutral,
    this.compact = false,
  });

  const AppStatusView.noRepository({super.key, this.compact = false})
      : title = noRepositoryTitle,
        message = noRepositoryMessage,
        busy = false,
        tone = AppStatusTone.neutral;

  const AppStatusView.loading({
    super.key,
    required this.title,
    required this.message,
    this.compact = false,
  })  : busy = true,
        tone = AppStatusTone.neutral;

  const AppStatusView.error({
    super.key,
    required this.title,
    required this.message,
    this.compact = false,
  })  : busy = false,
        tone = AppStatusTone.error;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent =
        tone == AppStatusTone.error ? t.stateConflicted : t.accentBright;
    final width = compact ? 280.0 : 420.0;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Padding(
          padding: EdgeInsets.all(compact ? 14 : 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (busy) ...[
                TopProgressLine(color: accent),
                SizedBox(height: compact ? 10 : 14),
              ],
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: tone == AppStatusTone.error ? accent : t.textStrong,
                  fontSize: compact ? 13 : 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              // Skip the secondary line entirely when there's no copy.
              // Lets callers render title-only without an empty Text
              // reserving 1.4× line-height of vertical space below.
              if (message.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: compact ? 11 : 13,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class TopProgressLine extends StatelessWidget {
  final Color color;
  final double height;

  const TopProgressLine({
    super.key,
    required this.color,
    this.height = 2,
  });

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      minHeight: height,
      color: color.withValues(alpha: 0.75),
      backgroundColor: Colors.transparent,
    );
  }
}
