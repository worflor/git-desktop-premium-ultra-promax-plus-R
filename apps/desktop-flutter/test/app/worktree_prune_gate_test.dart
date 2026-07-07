// Unit test for the once-per-repo worktree-prune gate. `git worktree
// prune` should fire the first time a repo path is listed and never
// again that session, so the gate is a pure Set membership claim.
// The claim is only KEPT on a successful prune: refreshFor releases it
// (Set.remove) when the prune fails, so a transient fault retries on
// the next refresh instead of ghost worktrees persisting all session.

import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/app/worktree_state.dart';

void main() {
  group('WorktreeState.claimPrune', () {
    test('claims a path exactly once', () {
      final pruned = <String>{};
      expect(WorktreeState.claimPrune(pruned, 'c:/repo'), isTrue);
      expect(WorktreeState.claimPrune(pruned, 'c:/repo'), isFalse);
      expect(WorktreeState.claimPrune(pruned, 'c:/repo'), isFalse);
    });

    test('distinct repos each get their first-time claim', () {
      final pruned = <String>{};
      expect(WorktreeState.claimPrune(pruned, 'c:/a'), isTrue);
      expect(WorktreeState.claimPrune(pruned, 'c:/b'), isTrue);
      expect(WorktreeState.claimPrune(pruned, 'c:/a'), isFalse);
      expect(WorktreeState.claimPrune(pruned, 'c:/b'), isFalse);
      expect(pruned, {'c:/a', 'c:/b'});
    });

    test('a released claim (failed prune) can be re-claimed', () {
      final pruned = <String>{};
      expect(WorktreeState.claimPrune(pruned, 'c:/repo'), isTrue);
      // refreshFor releases the claim when the prune fails…
      pruned.remove('c:/repo');
      // …so the next refresh gets a fresh first-time claim and retries.
      expect(WorktreeState.claimPrune(pruned, 'c:/repo'), isTrue);
      expect(WorktreeState.claimPrune(pruned, 'c:/repo'), isFalse);
    });
  });
}
