import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/sidebar_org_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists and reloads grouped sidebar organization', () async {
    final state = SidebarOrgState();
    state.anchorRepo('/repo/app');
    state.nestUnder('/repo/tools', '/repo/app');

    final group = state.roots.single as SidebarGroup;
    state.setGroupLabel(group.id, 'Work');
    state.setGroupColor(group.id, 2);
    state.toggleCollapsed(group.id);
    await state.flushPendingSaveForTesting();

    final loaded = SidebarOrgState();
    await loaded.load();

    final loadedGroup = loaded.roots.single as SidebarGroup;
    expect(loadedGroup.label, 'Work');
    expect(loadedGroup.headRepoPath, '/repo/app');
    expect(loadedGroup.colorSlot, 2);
    expect(loadedGroup.collapsed, isTrue);
    expect((loadedGroup.children.single as SidebarRepo).path, '/repo/tools');
    expect(loaded.inheritedColor('/repo/app'), 2);
    expect(loaded.inheritedColor('/repo/tools'), 2);
  });

  test('moving an organized repo keeps paths deduplicated', () async {
    final state = SidebarOrgState();
    state.anchorRepo('/repo/app');
    state.nestUnder('/repo/tools', '/repo/app');
    state.moveToTopLevel('/repo/tools');
    await state.flushPendingSaveForTesting();

    expect(state.organizedPaths, {'/repo/app', '/repo/tools'});
    expect(state.roots, hasLength(2));
    expect(state.roots.whereType<SidebarRepo>().map((r) => r.path), [
      '/repo/app',
      '/repo/tools',
    ]);
  });

  test('corrupt persisted json falls back to an empty organization', () async {
    SharedPreferences.setMockInitialValues({'sidebar_org': '{not json'});

    final state = SidebarOrgState();
    await state.load();

    expect(state.isEmpty, isTrue);
    expect(state.organizedPaths, isEmpty);
  });

  test('remove group drops its children while dissolve preserves them',
      () async {
    final state = SidebarOrgState();
    state.createEmptyGroup(label: 'Scratch');
    final scratch = state.roots.single as SidebarGroup;
    state.addToGroup('/repo/tmp', scratch.id);
    state.removeGroup(scratch.id);

    expect(state.organizedPaths, isEmpty);

    state.nestUnder('/repo/tools', '/repo/app');
    final group = state.roots.single as SidebarGroup;
    state.dissolveGroup(group.id);
    await state.flushPendingSaveForTesting();

    expect(state.roots.whereType<SidebarRepo>().map((r) => r.path), [
      '/repo/app',
      '/repo/tools',
    ]);
  });
}
