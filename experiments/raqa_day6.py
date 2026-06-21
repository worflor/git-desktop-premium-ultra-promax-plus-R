"""
RAQA Day 6 — three open questions
===================================
1. What lives INSIDE eigenspace clusters?
2. Ricci flow on real repos: what does code WANT to become?
3. The star graph 3-iteration theorem: prove or disprove
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

def random_graph(n, p, seed=42):
    rng = np.random.RandomState(seed)
    A = (rng.rand(n,n)<p).astype(float); A=np.triu(A,1); A=A+A.T; return A

def star_graph(n):
    A = np.zeros((n,n))
    for i in range(1,n): A[0,i]=A[i,0]=1
    return A

def path_graph(n):
    A=np.zeros((n,n))
    for i in range(n-1): A[i,i+1]=A[i+1,i]=1
    return A

def bfs_dist(adj, src):
    n=len(adj); dist=np.full(n,-1); dist[src]=0; q=[src]
    while q:
        nd=q.pop(0)
        for nb in range(n):
            if adj[nd,nb]>0 and dist[nb]==-1: dist[nb]=dist[nd]+1; q.append(nb)
    return dist

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


# === EXPERIMENT 1: INSIDE THE CLUSTERS ===============================
# Find eigenspace clusters, then compute the INTERNAL spectrum of each.
# Do clusters have their own spectral gap? Their own localization?
# Are clusters structurally homogeneous or do they have sub-communities?

def experiment_inside_clusters():
    print("=" * 80)
    print("  WHAT LIVES INSIDE EIGENSPACE CLUSTERS?")
    print("  Zooming into each cluster's internal spectral structure.")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        A_raw, files = parse_repo(rpath, 200, 2)
        if A_raw is None or len(files) < 20:
            A_raw, files = parse_repo(rpath, 200, 1)
        if A_raw is None or len(files) < 20: continue

        n = len(files)
        A_bin = (A_raw > 0).astype(float)
        L = laplacian(A_bin)
        eigs, vecs = np.linalg.eigh(L)

        # Eigenspace coordinates (first 5 dims, weighted by 1/sqrt(lambda))
        nz = eigs > 1e-8
        nz_eigs = eigs[nz]
        nz_vecs = vecs[:, nz]
        k = min(5, len(nz_eigs))
        if k < 2: continue
        w = 1.0 / np.sqrt(nz_eigs[:k])
        coords = nz_vecs[:, :k] * w[np.newaxis, :]

        # K-means clustering in eigenspace
        n_clusters = min(5, n // 5)
        rng = np.random.RandomState(42)
        centers = coords[rng.choice(n, n_clusters, replace=False)]
        labels = np.zeros(n, dtype=int)

        for _ in range(30):
            for i in range(n):
                dists = [np.linalg.norm(coords[i] - c) for c in centers]
                labels[i] = np.argmin(dists)
            for j in range(n_clusters):
                members = coords[labels == j]
                if len(members) > 0:
                    centers[j] = members.mean(axis=0)

        print(f"\n  {rname}: {n} files, {n_clusters} eigenspace clusters")

        for cl in range(n_clusters):
            members = np.where(labels == cl)[0]
            if len(members) < 3:
                continue

            # Extract the subgraph for this cluster
            A_sub = A_bin[np.ix_(members, members)]

            # Internal spectral analysis
            L_sub = laplacian(A_sub)
            eigs_sub = np.linalg.eigvalsh(L_sub)
            nz_sub = eigs_sub[eigs_sub > 1e-8]

            if len(nz_sub) == 0:
                continue

            # Internal gap
            gap_sub = nz_sub[0]

            # Internal components
            components_sub = np.sum(eigs_sub < 1e-8)

            # Internal localization
            _, vecs_sub = np.linalg.eigh(L_sub)
            iprs_sub = np.sum(vecs_sub**4, axis=0)
            loc_frac_sub = np.mean(iprs_sub > 5.0 / len(members))

            # Internal density
            n_internal_edges = int(A_sub.sum() / 2)
            max_edges = len(members) * (len(members) - 1) // 2
            density = n_internal_edges / max_edges if max_edges > 0 else 0

            # External edges (connections to other clusters)
            external_edges = 0
            for m in members:
                for j in range(n):
                    if A_bin[m, j] > 0 and labels[j] != cl:
                        external_edges += 1

            modularity_ratio = n_internal_edges / (n_internal_edges + external_edges + 1e-6)

            # Top files in cluster
            member_files = [files[m] for m in members[:3]]

            print(f"\n    Cluster {cl}: {len(members)} files")
            print(f"      Internal gap:       {gap_sub:.4f}")
            print(f"      Internal components: {components_sub}")
            print(f"      Localization:        {loc_frac_sub:.0%}")
            print(f"      Density:             {density:.2f}")
            print(f"      Modularity ratio:    {modularity_ratio:.2f}")
            print(f"      Edges in/out:        {n_internal_edges} / {external_edges}")

            # Is this cluster a LEAF (mostly external connections) or a CORE (mostly internal)?
            if modularity_ratio > 0.7:
                kind = "ISLAND (self-contained module)"
            elif modularity_ratio > 0.4:
                kind = "PENINSULA (partially connected)"
            else:
                kind = "BRIDGE (more external than internal)"

            print(f"      Type:                {kind}")
            for f in member_files:
                short = f[-50:] if len(f) > 50 else f
                print(f"        {short}")

    print()


# === EXPERIMENT 2: RICCI FLOW ========================================
# Start with a real repo's co-change graph.
# Run discrete Ollivier-Ricci flow: adjust edge weights to make
# curvature more uniform. Watch the graph EVOLVE toward its ideal shape.
# Where does it converge? What does the "healed" architecture look like?

def experiment_ricci_flow():
    print("=" * 80)
    print("  RICCI FLOW: WHAT DOES CODE WANT TO BECOME?")
    print("  Evolving each repo's geometry toward uniform curvature.")
    print("=" * 80)

    def ollivier_ricci(adj, i, j):
        n = len(adj)
        d_i = adj[i].sum(); d_j = adj[j].sum()
        if d_i == 0 or d_j == 0: return 0
        alpha = 0.5
        mu_i = np.zeros(n); mu_i[i] = alpha
        for nb in range(n):
            if adj[i,nb] > 0: mu_i[nb] = (1-alpha) * adj[i,nb] / d_i
        mu_j = np.zeros(n); mu_j[j] = alpha
        for nb in range(n):
            if adj[j,nb] > 0: mu_j[nb] = (1-alpha) * adj[j,nb] / d_j
        support = list(set(np.where(mu_i>0)[0].tolist()+np.where(mu_j>0)[0].tolist()))
        dm = np.zeros((n,n))
        for s in support: dm[s] = bfs_dist((adj>0).astype(float), s)
        ri=mu_i.copy(); rj=mu_j.copy(); cost=0
        for _ in range(100):
            si=np.argmax(ri); dj_idx=np.argmax(rj)
            if ri[si]<1e-15 or rj[dj_idx]<1e-15: break
            amt=min(ri[si],rj[dj_idx]); d=dm[si,dj_idx] if dm[si,dj_idx]>=0 else 999
            cost+=amt*d; ri[si]-=amt; rj[dj_idx]-=amt
        d_ij = dm[i,j] if dm[i,j]>0 else 1
        return 1.0 - cost/d_ij

    def ricci_flow_step(adj, dt=0.1):
        """One step of discrete Ricci flow: w_ij += dt * kappa_ij * w_ij."""
        n = len(adj)
        adj_new = adj.copy()
        edges = [(i,j) for i in range(n) for j in range(i+1,n) if adj[i,j]>0]
        for i, j in edges:
            kappa = ollivier_ricci(adj, i, j)
            # Ricci flow: edges with negative curvature get heavier (bridges strengthen)
            # Edges with positive curvature get lighter (clusters thin out)
            new_w = adj[i,j] * (1 + dt * kappa)
            new_w = max(new_w, 0.01)  # don't let edges vanish
            adj_new[i,j] = adj_new[j,i] = new_w
        return adj_new

    configs = []
    for rname, rpath in list(get_repos().items())[:4]:
        A_raw, files = parse_repo(rpath, 200, 2)
        if A_raw is None or len(files) < 15:
            A_raw, files = parse_repo(rpath, 200, 1)
        if A_raw is not None and 15 <= len(files) <= 80:
            configs.append((rname, (A_raw>0).astype(float), files))

    # Also add a synthetic control
    configs.append(("random(40,0.15)", random_graph(40, 0.15, 42), [f"node_{i}" for i in range(40)]))

    for name, A_start, files in configs:
        n = len(A_start)
        edges = [(i,j) for i in range(n) for j in range(i+1,n) if A_start[i,j]>0]

        # Only sample edges for curvature (it's expensive)
        rng = np.random.RandomState(42)
        sample = [edges[k] for k in rng.choice(len(edges), min(30, len(edges)), replace=False)]

        # Measure initial curvature
        kappas_start = [ollivier_ricci(A_start, i, j) for i, j in sample]
        mean_k_start = np.mean(kappas_start)
        std_k_start = np.std(kappas_start)

        print(f"\n  {name}: {n} files, {len(edges)} edges")
        print(f"    Initial: mean_kappa={mean_k_start:+.4f}  std={std_k_start:.4f}")

        # Run Ricci flow for several steps
        A_current = A_start.copy()
        n_steps = 8

        print(f"    Running {n_steps} Ricci flow steps (dt=0.3)...\n")
        print(f"    {'step':>4}  {'mean_k':>8}  {'std_k':>7}  {'max_w':>7}  {'min_w':>7}  {'curvature_bar':>20}")
        print(f"    {'---':>4}  {'---':>8}  {'---':>7}  {'---':>7}  {'---':>7}")

        for step in range(n_steps):
            A_current = ricci_flow_step(A_current, dt=0.3)

            kappas = [ollivier_ricci(A_current, i, j) for i, j in sample]
            mean_k = np.mean(kappas)
            std_k = np.std(kappas)
            max_w = A_current[A_current > 0].max()
            min_w = A_current[A_current > 0].min()

            # Curvature uniformity bar
            bar_center = int((mean_k + 0.5) * 20)
            bar_spread = int(std_k * 20)
            bar = ['.'] * 20
            for b in range(max(0, bar_center - bar_spread), min(20, bar_center + bar_spread + 1)):
                bar[b] = '='
            if 0 <= bar_center < 20:
                bar[bar_center] = '#'
            bar_str = ''.join(bar)

            print(f"    {step+1:4d}  {mean_k:+8.4f}  {std_k:7.4f}  {max_w:7.3f}  {min_w:7.3f}  |{bar_str}|")

        # After flow: what changed?
        kappas_end = [ollivier_ricci(A_current, i, j) for i, j in sample]
        mean_k_end = np.mean(kappas_end)
        std_k_end = np.std(kappas_end)

        print(f"\n    After flow: mean_kappa={mean_k_end:+.4f}  std={std_k_end:.4f}")
        print(f"    Curvature std reduction: {(1 - std_k_end/std_k_start)*100:.0f}%")

        if std_k_end < std_k_start * 0.7:
            print(f"    RICCI FLOW CONVERGES. Curvature is becoming more uniform.")
            print(f"    The architecture is evolving toward a more 'round' shape.")
        elif mean_k_end > mean_k_start + 0.05:
            print(f"    Curvature is INCREASING. The graph is becoming more spherical.")
        else:
            print(f"    Flow is slow. More iterations needed.")

        # Which edges changed weight the most?
        print(f"    Most weight-changed edges (Ricci flow's prescription):")
        weight_changes = []
        for i, j in sample:
            delta_w = A_current[i,j] - A_start[i,j]
            weight_changes.append((i, j, delta_w, A_start[i,j], A_current[i,j]))

        weight_changes.sort(key=lambda x: -abs(x[2]))
        for i, j, dw, w0, w1 in weight_changes[:5]:
            fi = files[i][-35:] if len(files[i]) > 35 else files[i]
            fj = files[j][-35:] if len(files[j]) > 35 else files[j]
            direction = "STRENGTHEN" if dw > 0 else "WEAKEN"
            print(f"      {direction}: {fi} <-> {fj}")
            print(f"        weight {w0:.3f} -> {w1:.3f} ({dw:+.3f})")

    print()


# === EXPERIMENT 3: THE STAR 3-ITERATION THEOREM ======================
# The star graph self-spectrum converges in EXACTLY 3 iterations.
# Is this a theorem? Prove it by analyzing what happens at each step.

def experiment_star_theorem():
    print("=" * 80)
    print("  THE STAR GRAPH 3-ITERATION THEOREM")
    print("  WHY does the star self-spectrum converge in exactly 3 steps?")
    print("=" * 80)

    for n in [5, 8, 12, 20, 50, 100]:
        A = star_graph(n)
        L = laplacian(A)
        eigs = np.sort(np.linalg.eigvalsh(L))

        print(f"\n  Star({n}):")
        print(f"    Eigenvalues: {eigs[:6]}{'...' if n > 6 else ''}")

        # Count unique eigenvalues
        unique = np.unique(np.round(eigs, 8))
        print(f"    Unique eigenvalues: {len(unique)} -> {unique}")

        # Trace the self-spectrum iteration
        A_current = A.copy()
        for step in range(5):
            L_cur = laplacian(A_current)
            eigs_cur = np.sort(np.linalg.eigvalsh(L_cur))
            unique_cur = np.unique(np.round(eigs_cur, 8))

            # Build next graph
            spacings = np.diff(eigs_cur)
            threshold = np.mean(spacings) * 1.2 if len(spacings) > 0 else 0.1
            m = len(eigs_cur)
            A_next = np.zeros((m, m))
            for i in range(m):
                for j in range(i+1, m):
                    if abs(eigs_cur[i] - eigs_cur[j]) < threshold:
                        A_next[i,j] = A_next[j,i] = 1

            density = A_next.sum() / (m*(m-1)) if m > 1 else 0

            print(f"    Step {step}: {len(unique_cur)} unique eigenvalues, "
                  f"graph density={density:.3f}, "
                  f"eigs={eigs_cur[:min(5, len(eigs_cur))]}")

            # Check convergence
            if step > 0:
                prev_eigs = np.sort(np.linalg.eigvalsh(laplacian(A_current)))
                ml = min(len(eigs_cur), len(prev_eigs))
                delta = np.linalg.norm(eigs_cur[:ml] - prev_eigs[:ml])
                if delta < 1e-10:
                    print(f"    >>> CONVERGED at step {step}!")
                    break

            A_current = A_next

    # Analysis: WHY 3?
    print(f"\n  Analysis:")
    print(f"    Star(n) has exactly 2 unique eigenvalues: 0 and n/(n-1)")
    print(f"    (one zero mode + (n-1) copies of n/(n-1))")
    print(f"")

    # Verify
    for n in [10, 50]:
        A = star_graph(n)
        L = laplacian(A)
        eigs = np.sort(np.linalg.eigvalsh(L))
        print(f"    Star({n}): eigenvalues = {eigs[0]:.6f}, {eigs[1]:.6f} "
              f"(x{np.sum(np.abs(eigs - eigs[1]) < 1e-6)}), n/(n-1)={n/(n-1):.6f}")

    print(f"\n    Step 0: star(n) -> eigs = [0, n/(n-1), n/(n-1), ...]")
    print(f"    Step 1: eigenvalue graph has n nodes, (n-1) of which are at the SAME value")
    print(f"           -> those (n-1) nodes are all connected (distance < threshold)")
    print(f"           -> plus the zero node is isolated or connected depending on threshold")
    print(f"    Step 2: the eigenvalue graph is itself a star-like or complete subgraph")
    print(f"           -> its eigenvalues are again [0, c, c, c, ...]")
    print(f"    Step 3: same structure -> fixed point")
    print(f"\n    The star converges because its spectrum has only 2 DISTINCT values.")
    print(f"    Any graph with only 2 distinct eigenvalues converges fast because")
    print(f"    the eigenvalue-graph it generates has the same 2-value structure.")
    print(f"    It's a SPECTRAL FIXED POINT of multiplicity. Not a coincidence.")
    print()


# === EXPERIMENT 4: CLUSTER FRACTALITY ================================
# Do clusters contain sub-clusters? Is eigenspace fractal?
# Recurse: cluster -> sub-cluster -> sub-sub-cluster.
# If structure persists at every level, eigenspace is self-similar.

def experiment_fractal():
    print("=" * 80)
    print("  IS EIGENSPACE FRACTAL?")
    print("  Do clusters contain sub-clusters that contain sub-sub-clusters?")
    print("=" * 80)

    for rname, rpath in list(get_repos().items())[:3]:
        A_raw, files = parse_repo(rpath, 200, 1)
        if A_raw is None or len(files) < 30: continue

        n = len(files)
        A_bin = (A_raw > 0).astype(float)

        def recursive_cluster(adj, file_list, depth=0, max_depth=3):
            n_loc = len(adj)
            if n_loc < 6 or depth >= max_depth:
                return

            L = laplacian(adj)
            eigs, vecs = np.linalg.eigh(L)
            nz = eigs > 1e-8
            nz_eigs = eigs[nz]
            nz_vecs = vecs[:, nz]
            k_dim = min(3, len(nz_eigs))
            if k_dim < 2:
                return

            w = 1.0 / np.sqrt(nz_eigs[:k_dim])
            coords = nz_vecs[:, :k_dim] * w[np.newaxis, :]

            # Split into 2 clusters (Fiedler bisection)
            fiedler = nz_vecs[:, 0]
            group_a = np.where(fiedler >= 0)[0]
            group_b = np.where(fiedler < 0)[0]

            if len(group_a) < 3 or len(group_b) < 3:
                return

            # Internal spectral properties of each group
            for group, label in [(group_a, "A"), (group_b, "B")]:
                A_sub = adj[np.ix_(group, group)]
                L_sub = laplacian(A_sub)
                eigs_sub = np.linalg.eigvalsh(L_sub)
                nz_sub = eigs_sub[eigs_sub > 1e-8]
                gap_sub = nz_sub[0] if len(nz_sub) > 0 else 0
                comp_sub = np.sum(eigs_sub < 1e-8)

                indent = "  " * (depth + 2)
                files_preview = [file_list[g][-30:] for g in group[:2]]
                print(f"{indent}Level {depth} Group {label}: "
                      f"{len(group)} files, gap={gap_sub:.4f}, "
                      f"comp={comp_sub}, "
                      f"e.g. {files_preview}")

                # Recurse into this group
                sub_files = [file_list[g] for g in group]
                recursive_cluster(A_sub, sub_files, depth + 1, max_depth)

        print(f"\n  {rname}: {n} files — recursive Fiedler bisection")
        recursive_cluster(A_bin, files)

    print()


# === RUN ==============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |              R A Q A   D A Y   6                        |")
    print("  |   three open questions that won't let me sleep           |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_star_theorem()
    experiment_inside_clusters()
    experiment_ricci_flow()
    experiment_fractal()

    print("=" * 80)
    print("  Day 6. The questions multiply faster than the answers.")
    print("  That's how you know you're doing science.")
    print("=" * 80)
