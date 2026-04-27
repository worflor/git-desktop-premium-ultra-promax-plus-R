import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../app/hyper_reactivity.dart';
import '../../app/repository_state.dart';
import '../../backend/dtos.dart';
import '../../backend/git.dart';
import '../../ui/control_chrome.dart';
import '../../ui/design_primitives.dart';
import '../../ui/form_controls.dart';
import '../../ui/status_view.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';

String _detectScope(String query) {
  final trimmed = query.trim();
  if (trimmed.startsWith('S:')) return 'code';
  if (trimmed.contains('/') || RegExp(r'\.\w{1,6}$').hasMatch(trimmed)) {
    return 'files';
  }
  return 'messages';
}

String _scopeLabel(String scope) {
  switch (scope) {
    case 'code':
      return 'searching code changes (pickaxe)';
    case 'files':
      return 'searching file history';
    default:
      return 'searching commit messages';
  }
}

class SearchPanel extends StatefulWidget {
  final VoidCallback onClose;
  final void Function(String hash) onCommitSelected;

  const SearchPanel({
    super.key,
    required this.onClose,
    required this.onCommitSelected,
  });

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  final _controller = TextEditingController();
  List<CommitSearchResultData> _results = [];
  bool _loading = false;
  bool _searched = false;
  String _scope = 'messages';
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {
      _query = value;
      _scope = _detectScope(value);
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || _query != value) return;
      _search(value);
    });
  }

  Future<void> _search(String query) async {
    final repo = context.read<RepositoryState>().activePath;
    final trimmed = query.trim();
    if (repo == null || trimmed.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }

    final effectiveQuery = _scope == 'code'
        ? trimmed.replaceFirst(RegExp(r'^S:'), '').trim()
        : trimmed;

    setState(() {
      _loading = true;
      _searched = true;
    });

    final result = await searchCommits(repo, effectiveQuery, scope: _scope);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _results = result.ok ? result.data! : [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      children: [
        _SearchHeader(onClose: widget.onClose),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SearchInput(
                  controller: _controller,
                  onChanged: _onChanged,
                  onClose: widget.onClose,
                ),
                if (_query.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _scopeLabel(_scope),
                    style: TextStyle(
                      color: t.textMuted.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Expanded(
                    child: _ResultsBody(
                  loading: _loading,
                  searched: _searched,
                  results: _results,
                  tokens: t,
                  onCommitSelected: (hash) {
                    widget.onClose();
                    widget.onCommitSelected(hash);
                  },
                )),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchHeader extends StatelessWidget {
  final VoidCallback onClose;

  const _SearchHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.18)),
        ),
      ),
      child: Row(
        children: [
          Text(
            'Search',
            style: TextStyle(
              color: t.textMuted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          _CloseButton(onClose: onClose),
        ],
      ),
    );
  }
}

class _SearchInput extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  const _SearchInput({
    required this.controller,
    required this.onChanged,
    required this.onClose,
  });

  @override
  State<_SearchInput> createState() => _SearchInputState();
}

class _SearchInputState extends State<_SearchInput> {
  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: widget.controller,
      autofocus: true,
      fontSize: 13,
      hintText: 'search commits...',
      onChanged: widget.onChanged,
      onSubmitted: widget.onChanged,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
    );
  }
}

class _ResultsBody extends StatelessWidget {
  final bool loading;
  final bool searched;
  final List<CommitSearchResultData> results;
  final AppTokens tokens;
  final ValueChanged<String> onCommitSelected;

  const _ResultsBody({
    required this.loading,
    required this.searched,
    required this.results,
    required this.tokens,
    required this.onCommitSelected,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    if (loading && results.isEmpty) {
      // The progress bar already says "looking" — title is enough.
      return const AppStatusView.loading(
        title: 'Searching',
        message: '',
        compact: true,
      );
    }
    if (searched && results.isEmpty) {
      return const AppStatusView(
        title: 'No results',
        message: 'message · path · S: pickaxe',
        compact: true,
      );
    }
    if (!searched && results.isEmpty) {
      return const AppStatusView(
        title: 'Search',
        message: 'message · path · S: pickaxe',
        compact: true,
      );
    }
    return Stack(
      children: [
        ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 2),
          itemBuilder: (context, index) => _ResultRow(
            result: results[index],
            tokens: t,
            onTap: () => onCommitSelected(results[index].commitHash),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            opacity: loading ? 1 : 0,
            duration: context.motion(const Duration(milliseconds: 80)),
            child: TopProgressLine(color: t.accentBright),
          ),
        ),
      ],
    );
  }
}

class _ResultRow extends StatefulWidget {
  final CommitSearchResultData result;
  final AppTokens tokens;
  final VoidCallback onTap;

  const _ResultRow({
    required this.result,
    required this.tokens,
    required this.onTap,
  });

  @override
  State<_ResultRow> createState() => _ResultRowState();
}

class _ResultRowState extends State<_ResultRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final result = widget.result;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 100)),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            // Use the canonical itemHoverBg / itemActiveBg tokens so
            // search rows share the hover language with branches and
            // history rows. Previously this drew a chromeBorder wash
            // that didn't match either neighbor.
            color: _hovered ? t.itemHoverBg : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    result.shortHash,
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 10,
                      fontFamily: AppFonts.mono,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(result.authoredAt),
                    style: TextStyle(
                      color: t.textMuted.withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                result.subject,
                style: TextStyle(color: t.textNormal, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 3),
              Text(
                result.authorName,
                style: TextStyle(
                  color: t.textMuted.withValues(alpha: 0.7),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.length > 10 ? iso.substring(0, 10) : iso;
    }
  }
}

class _CloseButton extends StatefulWidget {
  final VoidCallback onClose;

  const _CloseButton({required this.onClose});

  @override
  State<_CloseButton> createState() => _CloseButtonState();
}

class _CloseButtonState extends State<_CloseButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chrome = ghostButtonChrome(
      t,
      hovered: _hovered,
      pressed: _pressed,
      enabled: true,
      baseBorderColor: t.secondaryBtnBorder,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onClose,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: HyperReactive(
          borderRadius: 6,
          child: AnimatedScale(
            duration: context.motion(const Duration(milliseconds: 80)),
            scale: chrome.scale,
            child: AnimatedContainer(
              duration: context.motion(const Duration(milliseconds: 80)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: chrome.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: chrome.borderColor,
                ),
                boxShadow: chrome.shadows,
              ),
              child: Transform.translate(
                offset: chrome.offset,
                child: Text(
                  'Close',
                  style: TextStyle(color: t.textNormal, fontSize: 11),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
