"""
RAQA on a REAL REPO — this one. Right here.
=============================================
Parse git log into a file co-change graph.
Compute eigenspace. Find wormholes. Measure everything.
"""

import numpy as np
import subprocess
import sys
from collections import defaultdict

np.set_printoptions(precision=6, linewidth=140, suppress=True)

def run_git(args):
    r = subprocess.run(
        ["git"] + args,
        capture_output=True, text=True, encoding="utf-8", errors="replace",
        cwd=r"C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R"
    )
    return r.stdout

def laplacian(adj):
    d = adj.sum(axis=1)
    d_inv_sqrt = np.where(d > 0, 1.0 / np.sqrt(d), 0.0)
    D = np.diag(d_inv_sqrt)
    return np.eye(len(adj)) - D @ adj @ D

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


def parse_git_log():
    """Parse git log into file co-change counts."""
    # Get commits with changed files (no path filter — filter in Python)
    log = run_git([
        "log", "--no-merges", "--name-only",
        "--format=COMMIT_SEP%H", "-n", "200",
    ])

    commits = []
    current_files = []

    for line in log.split("\n"):
        line = line.strip()
        if line.startswith("COMMIT_SEP"):
            if current_files:
                commits.append(current_files)
            current_files = []
        elif line:
            if line.startswith("apps/desktop-flutter/lib/"):
                # Shorten path for readability
                short = line.replace("apps/desktop-flutter/lib/", "")
                current_files.append(short)

    if current_files:
        commits.append(current_files)

    return commits


def build_coupling_matrix(commits, min_cochanges=2):
    """Build co-change adjacency matrix from commits."""
    # Count pairwise co-changes
    pair_counts = defaultdict(int)
    file_set = set()

    for files in commits:
        files = list(set(files))  # dedupe within commit
        file_set.update(files)
        for i in range(len(files)):
            for j in range(i + 1, len(files)):
                pair = tuple(sorted([files[i], files[j]]))
                pair_counts[pair] += 1

    # Filter to files that appear in enough co-changes
    files = sorted(file_set)

    # Build adjacency matrix
    file_idx = {f: i for i, f in enumerate(files)}
    n = len(files)
    A = np.zeros((n, n))

    for (f1, f2), count in pair_counts.items():
        if count >= min_cochanges:
            i, j = file_idx[f1], file_idx[f2]
            A[i, j] = count
            A[j, i] = count

    # Remove isolated nodes
    connected = A.sum(axis=1) > 0
    A = A[np.ix_(connected, connected)]
    files = [f for f, c in zip(files, connected) if c]

    return A, files


def main():
    print()
    print("  +---------------------------------------------------------+")
    print("  |        R A Q A   R E A L   R E P O   L A B              |")
    print("  |    eigenspace of the codebase you're sitting in          |")
    print("  +---------------------------------------------------------+")
    print()

    # === PARSE GIT HISTORY ===
    print("  Parsing git log...")
    commits = parse_git_log()
    print(f"  Found {len(commits)} commits touching desktop-flutter/lib/")

    A_raw, files = build_coupling_matrix(commits, min_cochanges=2)
    n = len(files)
    print(f"  {n} files with >= 2 co-changes")
    print(f"  {int(A_raw.sum() / 2)} weighted edges")

    if n < 5:
        print("  Not enough connected files. Try min_cochanges=1.")
        A_raw, files = build_coupling_matrix(commits, min_cochanges=1)
        n = len(files)
        print(f"  Retrying: {n} files with >= 1 co-change")

    if n < 5:
        print("  Still too few files. Aborting.")
        return

    # Binarize for Laplacian (edges exist or don't, weight stored separately)
    A_bin = (A_raw > 0).astype(float)
    weights = A_raw.copy()

    # === EIGENSPACE ===
    print(f"\n{'='*70}")
    print("  EIGENSPACE OF THIS REPO")
    print(f"{'='*70}")

    L = laplacian(A_bin)
    eigs, vecs = np.linalg.eigh(L)

    nz_mask = eigs > 1e-8
    nz_eigs = eigs[nz_mask]
    nz_vecs = vecs[:, nz_mask]

    # Effective dimension
    if len(nz_eigs) > 0:
        p = nz_eigs / nz_eigs.sum()
        d_eff = 1.0 / np.sum(p**2)
        cumsum = np.cumsum(nz_eigs) / nz_eigs.sum()
        d_90 = np.searchsorted(cumsum, 0.90) + 1
    else:
        d_eff = 0
        d_90 = 0

    components = np.sum(eigs < 1e-8)
    gap = nz_eigs[0] if len(nz_eigs) > 0 else 0

    print(f"\n  Files: {n}")
    print(f"  Connected components: {components}")
    print(f"  Spectral gap: {gap:.6f}")
    print(f"  Effective dimension: {d_eff:.1f} / {n}")
    print(f"  Dimensions for 90% mass: {d_90}")
    print(f"  Compression ratio: {d_eff/n:.1%}")

    # === TOP FILES BY EIGENSPACE CENTRALITY ===
    # Eigenvector centrality: importance in the Fiedler vector (2nd eigenvector)
    if len(nz_eigs) > 0:
        fiedler = nz_vecs[:, 0]  # First non-zero eigenvector
        fiedler_rank = sorted(range(n), key=lambda i: abs(fiedler[i]), reverse=True)

        print(f"\n  Top files by Fiedler centrality (spectral importance):")
        for rank, idx in enumerate(fiedler_rank[:15]):
            deg = int(A_bin[idx].sum())
            weight_sum = int(weights[idx].sum())
            # Shorten filename
            fname = files[idx]
            if len(fname) > 50:
                fname = "..." + fname[-47:]
            print(f"    {rank+1:2d}. {fname:<50s}  deg={deg:2d}  "
                  f"co-ch={weight_sum:3d}  fiedler={fiedler[idx]:+.4f}")

    # === EIGENSPACE COORDINATES ===
    if nz_vecs.shape[1] >= 3:
        eigen_weights = 1.0 / np.sqrt(nz_eigs[:min(len(nz_eigs), n)])
        coords = nz_vecs[:, :len(eigen_weights)] * eigen_weights[np.newaxis, :]
    else:
        coords = nz_vecs

    # Spectral distance matrix
    sd = np.zeros((n, n))
    for i in range(n):
        for j in range(i+1, n):
            d = np.linalg.norm(coords[i] - coords[j])
            sd[i,j] = sd[j,i] = d

    # Graph distance matrix
    gd = np.zeros((n, n))
    for i in range(n):
        gd[i] = bfs_dist(A_bin, i)

    # === WORMHOLES IN THIS REPO ===
    print(f"\n{'='*70}")
    print("  WORMHOLES IN THIS CODEBASE")
    print(f"{'='*70}")

    wormholes = []
    for i in range(n):
        for j in range(i+1, n):
            if gd[i,j] <= 0:
                continue
            gd_z = (gd[i,j] - gd[gd > 0].mean()) / (gd[gd > 0].std() + 1e-12)
            sd_z = (sd[i,j] - sd[sd > 0].mean()) / (sd[sd > 0].std() + 1e-12)
            score = gd_z - sd_z
            wormholes.append((i, j, gd[i,j], sd[i,j], score))

    wormholes.sort(key=lambda x: -x[4])

    if wormholes:
        print(f"\n  Top spectral wormholes (far in co-change graph, close in eigenspace):")
        print(f"  These files rarely change together but play structurally identical roles.\n")

        for rank, (i, j, gd_val, sd_val, score) in enumerate(wormholes[:12]):
            fi = files[i][-45:] if len(files[i]) > 45 else files[i]
            fj = files[j][-45:] if len(files[j]) > 45 else files[j]
            print(f"    {rank+1:2d}. {fi}")
            print(f"        <-> {fj}")
            print(f"        graph_d={gd_val:.0f}  eigen_d={sd_val:.3f}  score={score:.3f}")
            print()

    # === BRIDGE FRAGILITY ===
    print(f"{'='*70}")
    print("  BRIDGE FRAGILITY: which edges hold eigenspace together?")
    print(f"{'='*70}")

    edge_fragility = []
    edges = [(i,j) for i in range(n) for j in range(i+1,n) if A_bin[i,j] > 0]

    for i, j in edges:
        A_mod = A_bin.copy()
        A_mod[i,j] = A_mod[j,i] = 0

        L_mod = laplacian(A_mod)
        eigs_mod = np.linalg.eigvalsh(L_mod)

        min_len = min(len(eigs), len(eigs_mod))
        eig_shift = np.sum(np.abs(eigs[:min_len] - eigs_mod[:min_len]))
        modes_hit = np.sum(np.abs(eigs[:min_len] - eigs_mod[:min_len]) > 0.001)

        deg_i = int(A_bin[i].sum())
        deg_j = int(A_bin[j].sum())
        cochange_weight = int(weights[i, j])

        edge_fragility.append((i, j, eig_shift, modes_hit, deg_i, deg_j, cochange_weight))

    edge_fragility.sort(key=lambda x: -x[2])

    print(f"\n  Most fragile edges (removing these reshapes eigenspace the most):\n")
    for rank, (i, j, shift, modes, di, dj, w) in enumerate(edge_fragility[:10]):
        fi = files[i][-40:] if len(files[i]) > 40 else files[i]
        fj = files[j][-40:] if len(files[j]) > 40 else files[j]
        print(f"    {rank+1:2d}. {fi} (deg={di})")
        print(f"        <-> {fj} (deg={dj})")
        print(f"        co-changes={w}  spectral_shift={shift:.4f}  modes_hit={modes}")
        print()

    # Verify bridge fragility law
    degs = np.array([e[4] + e[5] for e in edge_fragility], dtype=float)
    shifts = np.array([e[2] for e in edge_fragility])
    modes = np.array([e[3] for e in edge_fragility], dtype=float)
    cochanges = np.array([e[6] for e in edge_fragility], dtype=float)

    print(f"  Correlations on this real codebase:")
    print(f"    degree_sum vs spectral_shift: {np.corrcoef(degs, shifts)[0,1]:+.3f}")
    print(f"    degree_sum vs modes_hit:      {np.corrcoef(degs, modes)[0,1]:+.3f}")
    print(f"    co_change_weight vs shift:    {np.corrcoef(cochanges, shifts)[0,1]:+.3f}")

    # === INFORMATION PARADOX ON REAL FILES ===
    print(f"\n{'='*70}")
    print("  INFORMATION PARADOX: can eigenspace identify deleted files?")
    print(f"{'='*70}")

    # Spectral fingerprint per node
    bins = np.linspace(0, 2.2, 50)
    hist_orig, _ = np.histogram(eigs, bins=bins, density=True)

    fingerprints = {}
    for node in range(n):
        A_red = np.delete(np.delete(A_bin, node, 0), node, 1)
        if A_red.shape[0] < 2:
            continue
        L_red = laplacian(A_red)
        eigs_red = np.linalg.eigvalsh(L_red)
        hist_red, _ = np.histogram(eigs_red, bins=bins, density=True)
        fingerprints[node] = hist_orig - hist_red

    # Test reconstruction
    rng = np.random.RandomState(42)
    test_nodes = rng.choice(list(fingerprints.keys()), min(15, len(fingerprints)), replace=False)
    correct = 0

    print(f"\n  Removing files one at a time, identifying from spectral shift:\n")
    for test_node in test_nodes:
        A_red = np.delete(np.delete(A_bin, test_node, 0), test_node, 1)
        L_red = laplacian(A_red)
        eigs_red = np.linalg.eigvalsh(L_red)
        hist_red, _ = np.histogram(eigs_red, bins=bins, density=True)
        observed = hist_orig - hist_red

        best_match = -1
        best_corr = -1
        for cand, fp in fingerprints.items():
            c = np.corrcoef(observed, fp)[0,1]
            if c > best_corr:
                best_corr = c
                best_match = cand

        hit = best_match == test_node
        if hit:
            correct += 1
        fname = files[test_node][-50:] if len(files[test_node]) > 50 else files[test_node]
        status = "HIT" if hit else f"miss -> {files[best_match][-30:]}"
        print(f"    {fname:<50s}  corr={best_corr:.4f}  {status}")

    acc = correct / len(test_nodes)
    chance = 1.0 / len(fingerprints)
    print(f"\n  Accuracy: {acc:.0%} ({correct}/{len(test_nodes)})")
    print(f"  Random chance: {chance:.1%}")

    if acc > 0.5:
        print(f"  The eigenspace of this codebase remembers deleted files.")
    print()

    # === ANDERSON LOCALIZATION CHECK ===
    print(f"{'='*70}")
    print("  LOCALIZATION: are any files spectrally isolated?")
    print(f"{'='*70}")

    # IPR of each eigenvector
    iprs = np.sum(vecs**4, axis=0)
    loc_threshold = 5.0 / n

    print(f"\n  Eigenvectors with IPR > {loc_threshold:.4f} (localized):")
    loc_count = 0
    for mode_idx in range(len(iprs)):
        if iprs[mode_idx] > loc_threshold:
            loc_count += 1
            # Which file(s) does this mode localize on?
            mode_vec = np.abs(vecs[:, mode_idx])
            top_file = np.argmax(mode_vec)
            weight = mode_vec[top_file]
            fname = files[top_file][-50:] if len(files[top_file]) > 50 else files[top_file]
            if loc_count <= 10:
                print(f"    mode {mode_idx:3d}: IPR={iprs[mode_idx]:.4f}  "
                      f"eigenval={eigs[mode_idx]:.4f}  "
                      f"localized on: {fname} ({weight:.2f})")

    print(f"\n  {loc_count} of {len(iprs)} modes are localized ({loc_count/len(iprs):.0%})")
    if loc_count > 0:
        print(f"  These files are spectrally isolated -- Anderson localization.")
        print(f"  In repo terms: they change with few partners, forming spectral islands.")
    print()


if __name__ == "__main__":
    main()
