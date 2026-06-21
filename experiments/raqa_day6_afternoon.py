"""
RAQA Day 6 Afternoon — chasing the fractal down
=================================================
1. Spectral rank as the complexity measure (not graph size)
2. The Fiedler tree: build the full recursive bisection tree, measure
   whether spectral properties SCALE across levels (power law?)
3. Cluster genetics: do clusters in DIFFERENT repos resemble each other?
   (is there a universal cluster archetype?)
4. The spectral skeleton: strip a repo to its minimum spanning tree in
   eigenspace. What's the backbone? What's decoration?
5. Eigenvalue harmonics: are eigenvalue RATIOS (not values) conserved
   across repos? Like overtones in music.
"""

import numpy as np
import subprocess
import os
import tempfile
from collections import defaultdict

np.set_printoptions(precision=4, linewidth=140, suppress=True)

WORK_DIR = os.path.join(tempfile.gettempdir(), "raqa_repos")
LOCAL = r"C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R"
SRC_EXTS = ['.py','.js','.ts','.dart','.rs','.go','.java','.c','.cpp','.h','.rb','.vue','.jsx','.tsx']

def laplacian(adj):
    d = adj.sum(axis=1)
    d_inv_sqrt = np.where(d > 0, 1.0 / np.sqrt(d), 0.0)
    D = np.diag(d_inv_sqrt)
    return np.eye(len(adj)) - D @ adj @ D

def parse_repo(path, n_commits=200, min_co=1):
    try:
        r = subprocess.run(["git","log","--no-merges","--name-only",
                            "--format=COMMIT_SEP%H","-n",str(n_commits)],
                           capture_output=True,text=True,encoding="utf-8",
                           errors="replace",cwd=path,timeout=60)
    except: return None, None
    commits=[]; cur=[]
    for ln in r.stdout.split("\n"):
        ln=ln.strip()
        if ln.startswith("COMMIT_SEP"):
            if cur:
                s=[f for f in cur if any(f.endswith(e) for e in SRC_EXTS)]
                if 1<len(s)<=50: commits.append(s)
            cur=[]
        elif ln: cur.append(ln)
    pairs=defaultdict(int); fset=set()
    for fs in commits:
        fs=list(set(fs)); fset.update(fs)
        for i in range(len(fs)):
            for j in range(i+1,len(fs)):
                pairs[tuple(sorted([fs[i],fs[j]]))]+= 1
    fl=sorted(fset); idx={f:i for i,f in enumerate(fl)}; n=len(fl)
    A=np.zeros((n,n))
    for (a,b),c in pairs.items():
        if c>=min_co: A[idx[a],idx[b]]=c; A[idx[b],idx[a]]=c
    conn=A.sum(axis=1)>0; A=A[np.ix_(conn,conn)]
    fl=[f for f,c in zip(fl,conn) if c]
    return A, fl

def get_repos():
    repos={"pretext":LOCAL}
    for name in ["flask","django","pytorch","rust-lang","vue","fastapi","express"]:
        p=os.path.join(WORK_DIR,name)
        if os.path.exists(p): repos[name]=p
    return repos


# === EXPERIMENT 1: SPECTRAL RANK AS THE COMPLEXITY MEASURE ===========
# Count distinct eigenvalues (within tolerance). This is the spectral
# rank — the TRUE complexity of the graph. Compare to n.

def experiment_spectral_rank():
    print("=" * 80)
    print("  SPECTRAL RANK: how many DISTINCT eigenvalues does each repo have?")
    print("  Spectral rank = true complexity. n = apparent complexity.")
    print("=" * 80)

    print(f"\n  {'repo':>12}  {'n':>5}  {'rank':>5}  {'rank/n':>7}  {'rank_type':>12}  distinct eigenvalues")
    print(f"  {'---':>12}  {'---':>5}  {'---':>5}  {'---':>7}  {'---':>12}")

    for rname, rpath in get_repos().items():
        A, files = parse_repo(rpath, 200, 1)
        if A is None or len(files) < 10: continue
        A_bin = (A > 0).astype(float)
        n = len(files)
        L = laplacian(A_bin)
        eigs = np.linalg.eigvalsh(L)

        # Count distinct eigenvalues (tolerance = 1e-4)
        unique = np.unique(np.round(eigs, 4))
        rank = len(unique)
        ratio = rank / n

        if ratio > 0.9:
            rank_type = "full rank"
        elif ratio > 0.5:
            rank_type = "high rank"
        elif ratio > 0.2:
            rank_type = "low rank"
        else:
            rank_type = "DEGENERATE"

        # Show first few distinct eigenvalues
        preview = unique[:6]
        preview_str = " ".join(f"{v:.3f}" for v in preview)
        if len(unique) > 6:
            preview_str += " ..."

        print(f"  {rname:>12}  {n:5d}  {rank:5d}  {ratio:7.2f}  {rank_type:>12}  {preview_str}")

    print()


# === EXPERIMENT 2: THE FIEDLER TREE — POWER LAW SCALING? =============
# Build the full recursive Fiedler bisection tree.
# At each level, measure: gap, size, localization, density.
# If these scale as power laws with depth, eigenspace is self-similar
# in a quantifiable way.

def experiment_fiedler_tree():
    print("=" * 80)
    print("  THE FIEDLER TREE: does spectral structure scale with depth?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        A, files = parse_repo(rpath, 200, 1)
        if A is None or len(files) < 30: continue
        A_bin = (A > 0).astype(float)
        n = len(files)

        # Collect measurements at each level of the bisection tree
        level_data = defaultdict(list)  # level -> [(size, gap, density, loc)]

        def bisect(adj, depth=0, max_depth=5):
            m = len(adj)
            if m < 4 or depth > max_depth: return

            L = laplacian(adj)
            eigs, vecs = np.linalg.eigh(L)
            nz = eigs > 1e-8
            nz_eigs = eigs[nz]
            if len(nz_eigs) == 0: return

            gap = nz_eigs[0]
            density = adj.sum() / (m * (m-1)) if m > 1 else 0
            iprs = np.sum(vecs**4, axis=0)
            loc = np.mean(iprs > 5.0/m)

            level_data[depth].append((m, gap, density, loc))

            # Fiedler bisection
            nz_vecs = vecs[:, nz]
            fiedler = nz_vecs[:, 0]
            a = np.where(fiedler >= 0)[0]
            b = np.where(fiedler < 0)[0]
            if len(a) >= 4: bisect(adj[np.ix_(a,a)], depth+1, max_depth)
            if len(b) >= 4: bisect(adj[np.ix_(b,b)], depth+1, max_depth)

        bisect(A_bin)

        if not level_data: continue

        print(f"\n  {rname}: {n} files")
        print(f"  {'depth':>5}  {'n_clusters':>10}  {'avg_size':>9}  {'avg_gap':>8}  "
              f"{'avg_density':>11}  {'avg_loc':>8}")
        print(f"  {'---':>5}  {'---':>10}  {'---':>9}  {'---':>8}  {'---':>11}  {'---':>8}")

        depths = sorted(level_data.keys())
        sizes = []
        gaps = []

        for d in depths:
            data = level_data[d]
            avg_size = np.mean([x[0] for x in data])
            avg_gap = np.mean([x[1] for x in data])
            avg_density = np.mean([x[2] for x in data])
            avg_loc = np.mean([x[3] for x in data])
            sizes.append(avg_size)
            gaps.append(avg_gap)

            print(f"  {d:5d}  {len(data):10d}  {avg_size:9.1f}  {avg_gap:8.4f}  "
                  f"{avg_density:11.3f}  {avg_loc:7.0%}")

        # Check for power law: does gap scale as size^alpha?
        if len(sizes) >= 3:
            log_sizes = np.log(sizes)
            log_gaps = np.log(np.array(gaps) + 1e-10)
            valid = np.isfinite(log_sizes) & np.isfinite(log_gaps)
            if valid.sum() >= 3:
                slope, _ = np.polyfit(log_sizes[valid], log_gaps[valid], 1)
                print(f"  Gap ~ size^{slope:.2f}", end="")
                if abs(slope) < 0.3:
                    print("  (gap is SIZE-INDEPENDENT — true self-similarity)")
                elif slope < 0:
                    print("  (gap GROWS as clusters shrink — sub-clusters are tighter)")
                else:
                    print("  (gap SHRINKS as clusters shrink — sub-clusters are looser)")

    print()


# === EXPERIMENT 3: CLUSTER GENETICS ==================================
# Extract the spectral signature of each cluster (eigenvalue histogram).
# Compare clusters ACROSS repos. Do clusters in flask resemble clusters
# in pytorch? Is there a universal cluster archetype?

def experiment_cluster_genetics():
    print("=" * 80)
    print("  CLUSTER GENETICS: do clusters look the same across repos?")
    print("=" * 80)

    bins = np.linspace(0, 2.2, 30)
    all_cluster_signatures = []

    for rname, rpath in get_repos().items():
        A, files = parse_repo(rpath, 200, 1)
        if A is None or len(files) < 20: continue
        A_bin = (A > 0).astype(float)
        n = len(files)

        L = laplacian(A_bin)
        eigs, vecs = np.linalg.eigh(L)
        nz = eigs > 1e-8
        nz_eigs = eigs[nz]
        nz_vecs = vecs[:, nz]

        k = min(5, len(nz_eigs))
        if k < 2: continue
        w = 1.0 / np.sqrt(nz_eigs[:k])
        coords = nz_vecs[:, :k] * w[np.newaxis, :]

        # K-means
        n_cl = min(4, n // 6)
        rng = np.random.RandomState(42)
        centers = coords[rng.choice(n, n_cl, replace=False)]
        labels = np.zeros(n, dtype=int)
        for _ in range(30):
            for i in range(n): labels[i] = np.argmin([np.linalg.norm(coords[i]-c) for c in centers])
            for j in range(n_cl):
                m = coords[labels==j]
                if len(m) > 0: centers[j] = m.mean(axis=0)

        for cl in range(n_cl):
            members = np.where(labels == cl)[0]
            if len(members) < 4: continue
            A_sub = A_bin[np.ix_(members, members)]
            L_sub = laplacian(A_sub)
            eigs_sub = np.linalg.eigvalsh(L_sub)
            hist, _ = np.histogram(eigs_sub, bins=bins, density=True)

            n_int = int(A_sub.sum() // 2)
            n_ext = sum(1 for m in members for j in range(n) if A_bin[m,j]>0 and labels[j]!=cl)
            mod = n_int / (n_int + n_ext + 1e-6)

            all_cluster_signatures.append({
                "repo": rname,
                "cluster": cl,
                "size": len(members),
                "hist": hist,
                "modularity": mod,
            })

    if len(all_cluster_signatures) < 4:
        print("  Not enough clusters."); return

    # Pairwise JSD between ALL clusters across ALL repos
    n_cl = len(all_cluster_signatures)
    D = np.zeros((n_cl, n_cl))
    for i in range(n_cl):
        for j in range(i+1, n_cl):
            p = all_cluster_signatures[i]["hist"]
            q = all_cluster_signatures[j]["hist"]
            p = p / (p.sum() + 1e-12) + 1e-12
            q = q / (q.sum() + 1e-12) + 1e-12
            m = (p + q) / 2
            jsd = 0.5 * np.sum(p * np.log(p/m)) + 0.5 * np.sum(q * np.log(q/m))
            D[i,j] = D[j,i] = jsd

    # Find closest CROSS-REPO cluster pairs (different repos, similar spectrum)
    cross_pairs = []
    for i in range(n_cl):
        for j in range(i+1, n_cl):
            if all_cluster_signatures[i]["repo"] != all_cluster_signatures[j]["repo"]:
                cross_pairs.append((i, j, D[i,j]))

    cross_pairs.sort(key=lambda x: x[2])

    print(f"\n  {n_cl} clusters across {len(get_repos())} repos")
    print(f"\n  Most similar CROSS-REPO cluster pairs:")
    print(f"  {'repo_A':>12}  {'cl':>3}  {'sz':>4}  {'mod':>5}   {'repo_B':>12}  {'cl':>3}  {'sz':>4}  {'mod':>5}   {'JSD':>7}")
    print(f"  {'---':>12}  {'---':>3}  {'---':>4}  {'---':>5}   {'---':>12}  {'---':>3}  {'---':>4}  {'---':>5}   {'---':>7}")

    for i, j, jsd in cross_pairs[:12]:
        a = all_cluster_signatures[i]
        b = all_cluster_signatures[j]
        print(f"  {a['repo']:>12}  {a['cluster']:3d}  {a['size']:4d}  {a['modularity']:.2f}   "
              f"{b['repo']:>12}  {b['cluster']:3d}  {b['size']:4d}  {b['modularity']:.2f}   {jsd:7.4f}")

    # Are SAME-TYPE clusters more similar across repos than DIFFERENT-TYPE?
    # Type = island (mod > 0.7) vs bridge (mod < 0.4)
    island_islands = []
    bridge_bridges = []
    island_bridges = []

    for i, j, jsd in cross_pairs:
        a_mod = all_cluster_signatures[i]["modularity"]
        b_mod = all_cluster_signatures[j]["modularity"]
        a_island = a_mod > 0.6
        b_island = b_mod > 0.6

        if a_island and b_island: island_islands.append(jsd)
        elif not a_island and not b_island: bridge_bridges.append(jsd)
        else: island_bridges.append(jsd)

    print(f"\n  Cross-repo cluster similarity by type:")
    if island_islands:
        print(f"    Island↔Island:   mean JSD = {np.mean(island_islands):.4f} (n={len(island_islands)})")
    if bridge_bridges:
        print(f"    Bridge↔Bridge:   mean JSD = {np.mean(bridge_bridges):.4f} (n={len(bridge_bridges)})")
    if island_bridges:
        print(f"    Island↔Bridge:   mean JSD = {np.mean(island_bridges):.4f} (n={len(island_bridges)})")

    if island_islands and bridge_bridges and island_bridges:
        same = (np.mean(island_islands) + np.mean(bridge_bridges)) / 2
        diff = np.mean(island_bridges)
        if same < diff * 0.8:
            print(f"\n  SAME-TYPE clusters are more similar across repos than DIFFERENT-TYPE.")
            print(f"  There IS a universal cluster archetype. Islands look alike everywhere.")
        else:
            print(f"\n  No clear type-based pattern. Cluster similarity doesn't depend on type.")

    print()


# === EXPERIMENT 4: THE SPECTRAL SKELETON ============================
# Minimum spanning tree in eigenspace. The BACKBONE of the codebase.
# Every file is connected, but by the shortest eigenspace path.
# What survives? What's decoration?

def experiment_skeleton():
    print("=" * 80)
    print("  THE SPECTRAL SKELETON")
    print("  Strip the repo to its minimum eigenspace spanning tree.")
    print("  What's backbone? What's decoration?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        A, files = parse_repo(rpath, 200, 2)
        if A is None or len(files) < 15:
            A, files = parse_repo(rpath, 200, 1)
        if A is None or len(files) < 15: continue
        if len(files) > 120: continue

        n = len(files)
        A_bin = (A > 0).astype(float)
        L = laplacian(A_bin)
        eigs, vecs = np.linalg.eigh(L)

        nz = eigs > 1e-8
        nz_eigs = eigs[nz]
        nz_vecs = vecs[:, nz]
        k = min(len(nz_eigs), n)
        if k < 2: continue
        w = 1.0 / np.sqrt(nz_eigs[:k])
        coords = nz_vecs[:, :k] * w[np.newaxis, :]

        # Spectral distance matrix
        sd = np.zeros((n, n))
        for i in range(n):
            for j in range(i+1, n):
                d = np.linalg.norm(coords[i] - coords[j])
                sd[i,j] = sd[j,i] = d

        # Prim's MST on spectral distances
        in_tree = np.zeros(n, dtype=bool)
        in_tree[0] = True
        mst_edges = []
        mst_weight = 0

        for _ in range(n - 1):
            best_i, best_j, best_d = -1, -1, float('inf')
            for i in range(n):
                if not in_tree[i]: continue
                for j in range(n):
                    if in_tree[j]: continue
                    if sd[i,j] < best_d:
                        best_i, best_j, best_d = i, j, sd[i,j]
            if best_j < 0: break
            in_tree[best_j] = True
            mst_edges.append((best_i, best_j, best_d))
            mst_weight += best_d

        # Which edges in the MST are also in the original graph?
        orig_edges = set()
        for i in range(n):
            for j in range(i+1, n):
                if A_bin[i,j] > 0: orig_edges.add((min(i,j), max(i,j)))

        mst_in_orig = 0
        mst_not_in_orig = 0
        for i, j, d in mst_edges:
            key = (min(i,j), max(i,j))
            if key in orig_edges:
                mst_in_orig += 1
            else:
                mst_not_in_orig += 1

        n_orig = len(orig_edges)
        skeleton_frac = mst_in_orig / (n - 1) if n > 1 else 0

        # Degree distribution of MST
        mst_deg = np.zeros(n)
        for i, j, d in mst_edges:
            mst_deg[i] += 1
            mst_deg[j] += 1

        # MST hubs (degree > 3)
        hubs = [(i, int(mst_deg[i])) for i in range(n) if mst_deg[i] >= 3]
        hubs.sort(key=lambda x: -x[1])

        # MST leaves (degree 1)
        leaves = [i for i in range(n) if mst_deg[i] == 1]

        print(f"\n  {rname}: {n} files, {n_orig} co-change edges, {n-1} MST edges")
        print(f"    MST edges in original graph: {mst_in_orig}/{n-1} ({skeleton_frac:.0%})")
        print(f"    MST edges NOT in original:   {mst_not_in_orig} (spectral shortcuts)")
        print(f"    Total MST weight: {mst_weight:.2f}")
        print(f"    Leaves: {len(leaves)}  Hubs (deg>=3): {len(hubs)}")

        if hubs:
            print(f"    Skeleton hubs:")
            for idx, deg in hubs[:5]:
                fname = files[idx][-45:] if len(files[idx]) > 45 else files[idx]
                orig_deg = int(A_bin[idx].sum())
                print(f"      {fname}  mst_deg={deg}  orig_deg={orig_deg}")

        if leaves:
            print(f"    Skeleton leaves (decoration):")
            for idx in leaves[:5]:
                fname = files[idx][-45:] if len(files[idx]) > 45 else files[idx]
                orig_deg = int(A_bin[idx].sum())
                print(f"      {fname}  orig_deg={orig_deg}")

    print()


# === EXPERIMENT 5: EIGENVALUE HARMONICS ==============================
# In music, the overtone series is f, 2f, 3f, 4f...
# Do eigenvalue RATIOS follow a pattern across repos?
# If lambda_2/lambda_1 ≈ constant across repos, it's a harmonic law.

def experiment_harmonics():
    print("=" * 80)
    print("  EIGENVALUE HARMONICS: are overtone ratios universal?")
    print("=" * 80)

    ratios_by_mode = defaultdict(list)

    for rname, rpath in get_repos().items():
        A, files = parse_repo(rpath, 200, 1)
        if A is None or len(files) < 15: continue
        A_bin = (A > 0).astype(float)
        L = laplacian(A_bin)
        eigs = np.linalg.eigvalsh(L)
        nz = eigs[eigs > 1e-8]
        if len(nz) < 8: continue

        fundamental = nz[0]
        print(f"\n  {rname}: fundamental = {fundamental:.4f}")
        print(f"    {'mode':>4}  {'lambda':>8}  {'ratio':>7}  {'harmonic':>9}  {'nearest':>8}")
        print(f"    {'---':>4}  {'---':>8}  {'---':>7}  {'---':>9}  {'---':>8}")

        for k in range(min(12, len(nz))):
            ratio = nz[k] / fundamental
            nearest_harmonic = round(ratio)
            deviation = abs(ratio - nearest_harmonic) / nearest_harmonic if nearest_harmonic > 0 else 0

            ratios_by_mode[k].append(ratio)

            print(f"    {k:4d}  {nz[k]:8.4f}  {ratio:7.3f}  {nearest_harmonic:9d}  "
                  f"{'EXACT' if deviation < 0.05 else f'{deviation:.2f}'}")

    # Cross-repo consistency of ratios
    print(f"\n  Cross-repo ratio consistency:")
    print(f"  {'mode':>4}  {'mean_ratio':>10}  {'std':>7}  {'cv':>7}  {'universal?':>10}")
    print(f"  {'---':>4}  {'---':>10}  {'---':>7}  {'---':>7}  {'---':>10}")

    for k in sorted(ratios_by_mode.keys()):
        if len(ratios_by_mode[k]) < 3: continue
        ratios = np.array(ratios_by_mode[k])
        mean_r = ratios.mean()
        std_r = ratios.std()
        cv = std_r / mean_r if mean_r > 0 else 0

        universal = "YES" if cv < 0.15 else ("weak" if cv < 0.30 else "no")
        print(f"  {k:4d}  {mean_r:10.3f}  {std_r:7.3f}  {cv:7.3f}  {universal:>10}")

    print()


# === RUN ==============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |      R A Q A   D A Y  6   A F T E R N O O N            |")
    print("  |   chasing the fractal down                               |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_spectral_rank()
    experiment_fiedler_tree()
    experiment_cluster_genetics()
    experiment_skeleton()
    experiment_harmonics()

    print("=" * 80)
    print("  eigenspace has a skeleton, a genetic code, and a harmonic series.")
    print("  it's not a metaphor. it's an organism.")
    print("=" * 80)
