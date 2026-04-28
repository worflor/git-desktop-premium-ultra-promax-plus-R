import 'package:flutter/foundation.dart';

/// Sections of the settings page that other surfaces may deep-link
/// into. The set is small on purpose — every value here implies a
/// section header in `settings_page.dart` with a `GlobalKey` attached
/// so `Scrollable.ensureVisible` can find it.
///
/// Keep entries ordered by their visual order in the settings page
/// so the enum doubles as a navigation index for future "next/prev
/// section" affordances if those appear.
enum SettingsSection {
  externalTools,
}

/// App-level pipe for cross-tree navigation requests into the settings
/// page. The sidebar's project context menu lives in a different
/// subtree from the workspace shell that owns the settings panel
/// state; rather than thread a callback through every intermediate
/// widget, we publish navigation intents through this notifier and
/// the workspace shell consumes them.
///
/// Consumers (workspace_shell) listen, react to a non-null
/// [pendingFocus] by opening the panel and rendering the settings
/// page with the requested focus, then call [consume] to clear the
/// intent so a re-open from elsewhere doesn't re-trigger.
///
/// Producers (the sidebar context menu, future deep-links from muse /
/// review etc.) call [requestFocus]. Idempotent — repeatedly
/// requesting the same section is harmless; only the most-recent
/// request is held.
class SettingsNavigationState extends ChangeNotifier {
  SettingsSection? _pendingFocus;

  /// Most-recent unconsumed focus request, or null if there is no
  /// pending intent. Workspace shell reads this when its listener
  /// fires.
  SettingsSection? get pendingFocus => _pendingFocus;

  /// Publish a new focus intent. The notifier fires even if [section]
  /// matches the current pending value — the consumer might have
  /// cleared the panel between requests, and it should re-open.
  void requestFocus(SettingsSection section) {
    _pendingFocus = section;
    notifyListeners();
  }

  /// Returns the pending focus and clears it. Workspace shell calls
  /// this after rendering so subsequent panel toggles don't re-focus.
  /// Returns null when there is no pending request.
  SettingsSection? consume() {
    final out = _pendingFocus;
    _pendingFocus = null;
    return out;
  }
}
