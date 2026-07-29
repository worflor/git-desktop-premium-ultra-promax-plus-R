// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// ai_model_selection_retention_test.dart — a choice outlives a bad
// discovery pass.
//
// Model discovery is a LIVE probe: it spawns each CLI and asks each API
// provider what it can serve. So the catalog shrinks whenever a provider
// is logged out, offline, rate-limited, or merely slower than the pass
// that collects it. The sync used to treat "not in this pass" as "not a
// valid choice", replace the selection with whatever model sorted first,
// and PERSIST that — turning a provider hiccup into permanent loss of
// the model behind reviews and commit messages. Observed exactly that
// way: an expired `codex login` silently moved the reviewer, and it
// stayed moved after the login was repaired.
//
//  A1  a selection the current catalog cannot see is kept.
//  A2  it is kept across the sync that follows, so nothing persists the
//      substitute behind the user's back.
//  A3  when the provider returns, the original choice is still in force
//      — the point of A1, stated as the user would state it.
//  A4  an empty slot still seeds from the catalog, so a fresh install
//      arrives configured rather than blank.
//  A5  an explicit change still wins, including one made while the
//      chosen model is not on offer.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/ai_settings_state.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:shared_preferences/shared_preferences.dart';

AiModelOptionData _model(String provider, String id) => AiModelOptionData(
      value: '$provider:$id',
      modelId: id,
      providerId: provider,
      providerLabel: provider,
      label: id,
      description: '',
      supportsReasoning: false,
      hasFastTier: false,
    );

AiModelCategoryData _quality(List<AiModelOptionData> models) =>
    AiModelCategoryData(id: 'quality', label: 'Quality', models: models);

/// The catalog with every provider answering.
final _full = _quality([
  _model('opencode', 'luna'),
  _model('claude', 'claude-sonnet-5'),
]);

/// The same catalog during an outage of the provider serving the pick.
final _degraded = _quality([_model('opencode', 'luna')]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AiSettingsState state;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    state = AiSettingsState();
    await state.load();
    await state.syncModelCategories([_full]);
    await state.setModelSelection('quality', 'claude:claude-sonnet-5');
    expect(state.modelSelections['quality'], 'claude:claude-sonnet-5');
  });

  test('A1: a selection the catalog cannot see is kept', () async {
    await state.syncModelCategories([_degraded]);
    expect(state.modelSelections['quality'], 'claude:claude-sonnet-5',
        reason: 'the provider is missing, not the decision');
  });

  test('A2: and stays kept across further syncs', () async {
    await state.syncModelCategories([_degraded]);
    await state.syncModelCategories([_degraded]);
    expect(state.modelSelections['quality'], 'claude:claude-sonnet-5',
        reason: 'no pass may quietly persist a substitute');
  });

  test('A3: when the provider returns, so does the choice', () async {
    await state.syncModelCategories([_degraded]);
    await state.syncModelCategories([_full]);
    expect(state.modelSelections['quality'], 'claude:claude-sonnet-5',
        reason: 'this is the whole complaint: the reviewer came back as '
            'the substitute instead of the model that was picked');
  });

  test('A4: an empty slot still seeds from the catalog', () async {
    // A category nobody has ever chosen for. Retention must not mean
    // "leave it blank" — a slot with no decision behind it takes the
    // catalog's first offer, which is what makes a first run arrive
    // configured rather than empty.
    final fast = AiModelCategoryData(
      id: 'fast',
      label: 'Fast',
      models: [_model('opencode', 'luna')],
    );
    await state.syncModelCategories([_full, fast]);
    expect(state.modelSelections['fast'], 'opencode:luna');
    expect(state.modelSelections['quality'], 'claude:claude-sonnet-5',
        reason: 'seeding one slot must not disturb another');
  });

  test('A5: an explicit change still wins', () async {
    await state.syncModelCategories([_degraded]);
    await state.setModelSelection('quality', 'opencode:luna');
    expect(state.modelSelections['quality'], 'opencode:luna');

    await state.syncModelCategories([_full]);
    expect(state.modelSelections['quality'], 'opencode:luna',
        reason: 'retention protects the last DECISION, not the last '
            'value that happened to be available');
  });
}
