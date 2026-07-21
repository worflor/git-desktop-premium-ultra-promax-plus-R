# SPDX-FileCopyrightText: 2026 Woflo Labs
# SPDX-License-Identifier: LicenseRef-WLCSL-1.0
# See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

"""
RAQA DEEP VERIFICATION — stress-testing the surprising results
===============================================================
1. Bridge fragility law: does it hold across ALL graph types?
2. Perturbation non-locality: is it universal or graph-dependent?
3. Information paradox: how far can we push it? (multi-node deletion)
4. Wormhole transitivity: if A~B and B~C, does A~C?
5. Spectral prediction: can eigenspace predict FUTURE edges?
"""

import numpy as np
import time

np.set_printoptions(precision=6, linewidth=120, suppress=True)

def laplacian(adj):
    d = adj.sum(axis=1)
    d_inv_sqrt = np.where(d > 0, 1.0 / np.sqrt(d), 0.0)
    D = np.diag(d_inv_sqrt)
    return np.eye(len(adj)) - D @ adj @ D

def random_graph(n, p=0.3, seed=42):
    rng = np.random.RandomState(seed)
    A = (rng.rand(n, n) < p).astype(float)
    A = np.triu(A, 1); A = A + A.T
    return A

def path_graph(n):
    A = np.zeros((n, n))
    for i in range(n-1): A[i,i+1] = A[i+1,i] = 1
    return A

def grid_2d(rows, cols):
    n = rows * cols
    A = np.zeros((n, n))
    for r in range(rows):
        for c in range(cols):
            i = r * cols + c
            if c + 1 < cols: j = r * cols + c + 1; A[i,j] = A[j,i] = 1
            if r + 1 < rows: j = (r+1) * cols + c; A[i,j] = A[j,i] = 1
    return A

def barbell_graph(n):
    h = n // 2
    A = np.zeros((n, n))
    for i in range(h):
        for j in range(i+1, h):
            A[i,j] = A[j,i] = 1
    for i in range(h, n):
        for j in range(i+1, n):
            A[i,j] = A[j,i] = 1
    A[h-1, h] = A[h, h-1] = 1
    return A

def scale_free_graph(n, m=2, seed=42):
    """Barabasi-Albert preferential attachment."""
    rng = np.random.RandomState(seed)
    A = np.zeros((n, n))
    # Start with a small clique
    for i in range(m+1):
        for j in range(i+1, m+1):
            A[i,j] = A[j,i] = 1
    for new in range(m+1, n):
        degrees = A[:new].sum(axis=1)
        probs = degrees / degrees.sum() if degrees.sum() > 0 else np.ones(new)/new
        targets = rng.choice(new, size=m, replace=False, p=probs)
        for t in targets:
            A[new, t] = A[t, new] = 1
    return A

def bfs_dist(adj, src):
    n = len(adj)
    dist = np.full(n, -1)
    dist[src] = 0
    queue = [src]
    while queue:
        node = queue.pop(0)
        for nb in range(n):
            if adj[node, nb] > 0 and dist[nb] == -1:
                dist[nb] = dist[node] + 1
                queue.append(nb)
    return dist


# === TEST 1: BRIDGE FRAGILITY ACROSS GRAPH TYPES ====================

def test_bridge_fragility():
    print("=" * 70)
    print("TEST 1: BRIDGE FRAGILITY LAW — universal or not?")
    print("Does low degree -> high spectral importance hold everywhere?")
    print("=" * 70)

    configs = [
        ("random(100,0.08)", lambda: random_graph(100, 0.08, seed=42)),
        ("random(100,0.15)", lambda: random_graph(100, 0.15, seed=42)),
        ("random(100,0.25)", lambda: random_graph(100, 0.25, seed=42)),
        ("grid(10x10)", lambda: grid_2d(10, 10)),
        ("path(100)", lambda: path_graph(100)),
        ("barbell(100)", lambda: barbell_graph(100)),
        ("scale-free(100)", lambda: scale_free_graph(100, m=2, seed=42)),
    ]

    print(f"\n  {'graph':>22}  {'edges':>6}  {'r(deg,shift)':>12}  "
          f"{'r(deg,modes)':>12}  {'verdict':>15}")
    print(f"  {'---':>22}  {'---':>6}  {'---':>12}  {'---':>12}  {'---':>15}")

    for name, make_graph in configs:
        A = make_graph()
        n = len(A)
        L = laplacian(A)
        eigs = np.linalg.eigvalsh(L)

        edges = [(i,j) for i in range(n) for j in range(i+1,n) if A[i,j] > 0]
        n_edges = len(edges)

        # Sample edges if too many
        rng = np.random.RandomState(42)
        sample = edges if len(edges) <= 60 else [edges[k] for k in rng.choice(len(edges), 60, replace=False)]

        degs = []
        shifts = []
        modes_list = []

        for i, j in sample:
            A_mod = A.copy()
            A_mod[i,j] = A_mod[j,i] = 0
            L_mod = laplacian(A_mod)
            eigs_mod = np.linalg.eigvalsh(L_mod)

            min_len = min(len(eigs), len(eigs_mod))
            shift = np.sum(np.abs(eigs[:min_len] - eigs_mod[:min_len]))
            modes_hit = np.sum(np.abs(eigs[:min_len] - eigs_mod[:min_len]) > 0.001)

            degs.append(A[i].sum() + A[j].sum())
            shifts.append(shift)
            modes_list.append(modes_hit)

        degs = np.array(degs)
        shifts = np.array(shifts)
        modes_arr = np.array(modes_list, dtype=float)

        r_shift = np.corrcoef(degs, shifts)[0,1] if shifts.std() > 0 else 0
        r_modes = np.corrcoef(degs, modes_arr)[0,1] if modes_arr.std() > 0 else 0

        if r_shift < -0.3 and r_modes < -0.3:
            verdict = "CONFIRMED"
        elif r_shift < -0.1 or r_modes < -0.1:
            verdict = "weak signal"
        elif r_shift > 0.3:
            verdict = "REVERSED!"
        else:
            verdict = "no signal"

        print(f"  {name:>22}  {n_edges:6d}  {r_shift:>+12.3f}  {r_modes:>+12.3f}  {verdict:>15}")

    print()


# === TEST 2: PERTURBATION NON-LOCALITY ===============================

def test_perturbation_locality():
    print("=" * 70)
    print("TEST 2: PERTURBATION NON-LOCALITY — universal?")
    print("When you remove one edge, does the eigenspace displacement")
    print("decay with graph distance, or is it felt everywhere equally?")
    print("=" * 70)

    configs = [
        ("random(80,0.10)", random_graph(80, 0.10, seed=42)),
        ("random(80,0.20)", random_graph(80, 0.20, seed=42)),
        ("grid(9x9)", grid_2d(9, 9)),
        ("path(80)", path_graph(80)),
        ("scale-free(80)", scale_free_graph(80, m=2, seed=42)),
    ]

    for name, A in configs:
        n = len(A)
        L = laplacian(A)
        eigs, vecs = np.linalg.eigh(L)

        # Eigenspace coordinates
        nz = eigs > 1e-8
        nz_eigs = eigs[nz]
        nz_vecs = vecs[:, nz]
        if len(nz_eigs) == 0:
            continue
        w = 1.0 / np.sqrt(nz_eigs)
        coords = nz_vecs * w[np.newaxis, :]

        # Pick 10 random edges and average their displacement profiles
        edges = [(i,j) for i in range(n) for j in range(i+1,n) if A[i,j] > 0]
        rng = np.random.RandomState(42)
        sample = [edges[k] for k in rng.choice(len(edges), min(10, len(edges)), replace=False)]

        # Graph distance matrix
        gd_matrix = np.zeros((n, n))
        for i in range(n):
            gd_matrix[i] = bfs_dist(A, i)

        max_dist = int(gd_matrix[gd_matrix > 0].max()) if np.any(gd_matrix > 0) else 1
        max_dist = min(max_dist, 8)

        # Average displacement at each distance from the removed edge
        avg_disp_by_dist = np.zeros(max_dist + 1)
        counts_by_dist = np.zeros(max_dist + 1)

        for ei, ej in sample:
            A_mod = A.copy()
            A_mod[ei, ej] = A_mod[ej, ei] = 0
            L_mod = laplacian(A_mod)
            eigs_mod, vecs_mod = np.linalg.eigh(L_mod)

            nz_mod = eigs_mod > 1e-8
            nz_eigs_mod = eigs_mod[nz_mod]
            nz_vecs_mod = vecs_mod[:, nz_mod]
            min_dim = min(len(nz_eigs), len(nz_eigs_mod))
            if min_dim == 0:
                continue

            w_mod = 1.0 / np.sqrt(nz_eigs_mod[:min_dim])
            coords_mod = nz_vecs_mod[:, :min_dim] * w_mod[np.newaxis, :]
            coords_orig = nz_vecs[:, :min_dim] * w[:min_dim][np.newaxis, :]

            displacements = np.array([np.linalg.norm(coords_orig[k] - coords_mod[k]) for k in range(n)])

            dist_from_edge = np.minimum(gd_matrix[ei], gd_matrix[ej])
            for node in range(n):
                d = int(dist_from_edge[node])
                if 0 <= d <= max_dist:
                    avg_disp_by_dist[d] += displacements[node]
                    counts_by_dist[d] += 1

        # Normalize
        mask = counts_by_dist > 0
        avg_disp_by_dist[mask] /= counts_by_dist[mask]

        # Normalize to max=1 for comparison
        peak = avg_disp_by_dist.max()
        if peak > 0:
            normed = avg_disp_by_dist / peak
        else:
            normed = avg_disp_by_dist

        # Decay ratio: displacement at max distance / displacement at distance 0
        d0 = avg_disp_by_dist[0] if counts_by_dist[0] > 0 else 0
        d_far = 0
        for d in range(max_dist, 0, -1):
            if counts_by_dist[d] > 0:
                d_far = avg_disp_by_dist[d]
                break

        decay_ratio = d_far / d0 if d0 > 0 else 0

        # Print profile
        print(f"\n  {name}:")
        print(f"    Displacement vs distance from removed edge (avg over {len(sample)} removals):")
        print(f"    decay_ratio (far/near) = {decay_ratio:.3f}", end="")
        if decay_ratio > 0.8:
            print("  -- NON-LOCAL (felt everywhere)")
        elif decay_ratio > 0.5:
            print("  -- partially local")
        else:
            print("  -- LOCAL (decays with distance)")

        for d in range(max_dist + 1):
            if counts_by_dist[d] > 0:
                bar_len = int(normed[d] * 40)
                bar = "#" * bar_len
                print(f"      d={d}: {avg_disp_by_dist[d]:8.4f}  |{bar:<40s}|  ({normed[d]:.2f})")
    print()


# === TEST 3: MULTI-NODE INFORMATION PARADOX ==========================

def test_multi_deletion():
    print("=" * 70)
    print("TEST 3: MULTI-NODE INFORMATION PARADOX")
    print("Delete 2, 3, 4, 5 nodes at once. Can we still reconstruct ALL of them?")
    print("=" * 70)

    n = 60
    A = random_graph(n, p=0.15, seed=42)
    L = laplacian(A)
    eigs_orig = np.linalg.eigvalsh(L)
    bins = np.linspace(0, 2.2, 50)
    hist_orig, _ = np.histogram(eigs_orig, bins=bins, density=True)

    # Single-node fingerprints for matching
    fingerprints = {}
    for node in range(n):
        A_red = np.delete(np.delete(A, node, 0), node, 1)
        L_red = laplacian(A_red)
        eigs_red = np.linalg.eigvalsh(L_red)
        hist_red, _ = np.histogram(eigs_red, bins=bins, density=True)
        fingerprints[node] = hist_orig - hist_red

    rng = np.random.RandomState(42)

    for k in [1, 2, 3, 4, 5, 8, 10]:
        trials = 20
        total_correct = 0
        total_nodes = 0

        for trial in range(trials):
            # Delete k nodes
            deleted = list(rng.choice(n, k, replace=False))
            remaining = sorted(set(range(n)) - set(deleted))

            A_red = A[np.ix_(remaining, remaining)]
            L_red = laplacian(A_red)
            eigs_red = np.linalg.eigvalsh(L_red)
            hist_red, _ = np.histogram(eigs_red, bins=bins, density=True)

            # Composite shift
            observed = hist_orig - hist_red

            # Try to identify each deleted node by matching against fingerprints
            # Greedy matching: find best match, remove it, repeat
            unmatched = set(deleted)
            candidates = list(range(n))

            correct = 0
            for _ in range(k):
                best_node = -1
                best_corr = -1
                for cand in candidates:
                    c = np.corrcoef(observed, fingerprints[cand])[0,1]
                    if not np.isnan(c) and c > best_corr:
                        best_corr = c
                        best_node = cand

                if best_node in unmatched:
                    correct += 1
                    unmatched.discard(best_node)
                candidates.remove(best_node) if best_node in candidates else None
                # Subtract matched fingerprint from observation
                observed = observed - fingerprints.get(best_node, 0)

            total_correct += correct
            total_nodes += k

        acc = total_correct / total_nodes
        chance = k / n
        print(f"  k={k:2d} deleted:  accuracy={acc:.1%}  "
              f"(random chance={chance:.1%})  "
              f"lift={acc/chance:.1f}x over random")

    print()


# === TEST 4: WORMHOLE TRANSITIVITY ==================================

def test_wormhole_transitivity():
    print("=" * 70)
    print("TEST 4: WORMHOLE TRANSITIVITY")
    print("If A wormholes to B and B wormholes to C, does A wormhole to C?")
    print("=" * 70)

    n = 100
    A = random_graph(n, p=0.12, seed=42)
    L = laplacian(A)
    eigs, vecs = np.linalg.eigh(L)

    nz = eigs > 1e-8
    w = 1.0 / np.sqrt(eigs[nz])
    coords = vecs[:, nz] * w[np.newaxis, :]

    sd = np.zeros((n, n))
    for i in range(n):
        for j in range(i+1, n):
            d = np.linalg.norm(coords[i] - coords[j])
            sd[i,j] = sd[j,i] = d

    gd = np.zeros((n, n))
    for i in range(n):
        gd[i] = bfs_dist(A, i)

    # Define wormhole: graph_dist >= 3 AND spectral_dist < 30th percentile
    sd_flat = sd[np.triu_indices(n, 1)]
    gd_flat = gd[np.triu_indices(n, 1)]
    valid = gd_flat > 0
    sd_threshold = np.percentile(sd_flat[valid], 30)

    is_wormhole = np.zeros((n, n), dtype=bool)
    for i in range(n):
        for j in range(i+1, n):
            if gd[i,j] >= 3 and sd[i,j] < sd_threshold:
                is_wormhole[i,j] = is_wormhole[j,i] = True

    n_wormholes = is_wormhole.sum() // 2
    print(f"\n  Graph: random({n}, p=0.12)")
    print(f"  Wormhole criterion: graph_dist >= 3 AND spectral_dist < 30th percentile")
    print(f"  Found {n_wormholes} wormhole pairs")

    # Find transitive triples: A~B and B~C
    transitive_triples = 0
    transitive_and_wormhole = 0
    transitive_but_not = 0

    for b in range(n):
        wh_neighbors = [j for j in range(n) if is_wormhole[b, j]]
        for idx_a in range(len(wh_neighbors)):
            for idx_c in range(idx_a + 1, len(wh_neighbors)):
                a = wh_neighbors[idx_a]
                c = wh_neighbors[idx_c]
                transitive_triples += 1
                if is_wormhole[a, c]:
                    transitive_and_wormhole += 1
                else:
                    transitive_but_not += 1

    if transitive_triples > 0:
        transitivity = transitive_and_wormhole / transitive_triples
        # Compare to baseline: what fraction of ALL pairs are wormholes?
        total_pairs = n * (n-1) // 2
        baseline = n_wormholes / total_pairs

        print(f"\n  Transitive triples (A~B, B~C): {transitive_triples}")
        print(f"  Where A~C also holds: {transitive_and_wormhole} ({transitivity:.1%})")
        print(f"  Baseline (random pair is wormhole): {baseline:.1%}")
        print(f"  Transitivity lift: {transitivity / baseline:.1f}x over random")

        if transitivity > baseline * 2:
            print(f"\n  WORMHOLES ARE TRANSITIVE.")
            print(f"  If A connects to B through eigenspace, and B connects to C,")
            print(f"  then A is {transitivity/baseline:.1f}x more likely to connect to C")
            print(f"  than a random pair. Wormholes form COMMUNITIES, not random shortcuts.")
        elif transitivity > baseline * 1.3:
            print(f"\n  Weak transitivity. Wormholes cluster but not strongly.")
        else:
            print(f"\n  Wormholes are NOT transitive. They're random tunnels.")
    else:
        print("  No transitive triples found.")
    print()


# === TEST 5: SPECTRAL EDGE PREDICTION ===============================

def test_edge_prediction():
    print("=" * 70)
    print("TEST 5: SPECTRAL EDGE PREDICTION")
    print("Can eigenspace proximity predict which edges will form?")
    print("Train on partial graph, predict held-out edges.")
    print("=" * 70)

    n = 80
    A_full = random_graph(n, p=0.15, seed=42)
    edges_all = [(i,j) for i in range(n) for j in range(i+1,n) if A_full[i,j] > 0]
    non_edges = [(i,j) for i in range(n) for j in range(i+1,n) if A_full[i,j] == 0]

    rng = np.random.RandomState(42)

    holdout_fracs = [0.05, 0.10, 0.20, 0.30]

    print(f"\n  Graph: random({n}, p=0.15), {len(edges_all)} edges")
    print(f"  Hold out some edges, compute eigenspace on remainder,")
    print(f"  predict held-out edges from spectral proximity.\n")

    print(f"  {'holdout%':>8}  {'train_edges':>11}  {'AUC':>6}  "
          f"{'precision@k':>12}  {'verdict':>10}")
    print(f"  {'---':>8}  {'---':>11}  {'---':>6}  {'---':>12}  {'---':>10}")

    for frac in holdout_fracs:
        k = max(1, int(len(edges_all) * frac))
        holdout_idx = rng.choice(len(edges_all), k, replace=False)
        holdout = set(holdout_idx)

        # Build training graph
        A_train = A_full.copy()
        for idx in holdout_idx:
            i, j = edges_all[idx]
            A_train[i,j] = A_train[j,i] = 0

        # Eigenspace of training graph
        L = laplacian(A_train)
        eigs, vecs = np.linalg.eigh(L)
        nz = eigs > 1e-8
        if not np.any(nz):
            continue
        w = 1.0 / np.sqrt(eigs[nz])
        coords = vecs[:, nz] * w[np.newaxis, :]

        # Score ALL non-training-edges by spectral proximity
        # (held-out true edges + non-edges)
        candidates = []
        held_out_edges = [edges_all[idx] for idx in holdout_idx]

        # Mix held-out edges with equal number of non-edges
        neg_sample = [non_edges[k] for k in rng.choice(len(non_edges), min(len(held_out_edges) * 5, len(non_edges)), replace=False)]

        all_candidates = [(i, j, True) for i, j in held_out_edges] + [(i, j, False) for i, j in neg_sample]

        scores = []
        labels = []
        for i, j, is_true in all_candidates:
            spec_dist = np.linalg.norm(coords[i] - coords[j])
            scores.append(-spec_dist)  # negative distance = high score = more likely edge
            labels.append(1 if is_true else 0)

        scores = np.array(scores)
        labels = np.array(labels)

        # AUC (manual, no sklearn)
        pos_scores = scores[labels == 1]
        neg_scores = scores[labels == 0]
        auc = 0
        for ps in pos_scores:
            auc += np.sum(neg_scores < ps) + 0.5 * np.sum(neg_scores == ps)
        auc /= (len(pos_scores) * len(neg_scores)) if len(pos_scores) * len(neg_scores) > 0 else 1

        # Precision@k (top k predictions, how many are true edges?)
        top_k = min(k, len(scores))
        top_indices = np.argsort(-scores)[:top_k]
        prec_at_k = np.mean(labels[top_indices])

        verdict = "STRONG" if auc > 0.7 else ("decent" if auc > 0.6 else "weak")

        print(f"  {frac:>7.0%}  {len(edges_all)-k:>11d}  {auc:6.3f}  "
              f"{prec_at_k:>11.1%}  {verdict:>10}")

    print(f"\n  AUC > 0.5 = better than random. AUC > 0.7 = the eigenspace")
    print(f"  genuinely predicts which edges exist from structure alone.")
    print(f"  Precision@k = fraction of top predictions that are real edges.\n")


# === RUN ============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |       R A Q A   D E E P   V E R I F I C A T I O N       |")
    print("  |     stress-testing every surprising result                |")
    print("  +---------------------------------------------------------+")
    print()

    test_bridge_fragility()
    test_perturbation_locality()
    test_multi_deletion()
    test_wormhole_transitivity()
    test_edge_prediction()

    print("=" * 70)
    print("Verification complete. What survived?")
    print("=" * 70)
