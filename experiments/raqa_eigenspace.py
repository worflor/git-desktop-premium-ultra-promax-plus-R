"""
RAQA EIGENSPACE — the geometry behind the geometry
====================================================
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

def graph_dist_matrix(adj):
    n = len(adj)
    D = np.zeros((n, n))
    for i in range(n):
        D[i] = bfs_dist(adj, i)
    return D

def eigenspace_coords(adj, n_dims=None):
    """Project nodes into eigenspace. Returns (coords, eigs, vecs)."""
    L = laplacian(adj)
    eigs, vecs = np.linalg.eigh(L)
    # Skip zero mode(s), use next n_dims eigenvectors
    nz_mask = eigs > 1e-8
    nz_eigs = eigs[nz_mask]
    nz_vecs = vecs[:, nz_mask]
    if n_dims is None:
        n_dims = len(nz_eigs)
    n_dims = min(n_dims, len(nz_eigs))
    # Weight by 1/sqrt(lambda) so low modes dominate (global structure)
    weights = 1.0 / np.sqrt(nz_eigs[:n_dims])
    coords = nz_vecs[:, :n_dims] * weights[np.newaxis, :]
    return coords, eigs, vecs

def spectral_dist_matrix(coords):
    """Pairwise distances in eigenspace."""
    n = len(coords)
    D = np.zeros((n, n))
    for i in range(n):
        for j in range(i+1, n):
            d = np.linalg.norm(coords[i] - coords[j])
            D[i,j] = D[j,i] = d
    return D


# === EXPERIMENT 1: EIGENSPACE CARTOGRAPHY ===========================
# Map the eigenspace. What does it look like? Where do nodes cluster?
# Which nodes are eigenspace-neighbors vs graph-neighbors?

def experiment_cartography():
    print("=" * 70)
    print("EXPERIMENT 1: EIGENSPACE CARTOGRAPHY")
    print("What does the inside of a graph look like?")
    print("=" * 70)

    n = 60
    A = random_graph(n, p=0.12, seed=42)
    coords, eigs, vecs = eigenspace_coords(A)

    gd = graph_dist_matrix(A)
    sd = spectral_dist_matrix(coords)

    # Use first 3 eigenspace dimensions for visualization
    c3 = coords[:, :3] if coords.shape[1] >= 3 else coords

    # Find eigenspace clusters via simple distance-based grouping
    # k-means by hand (no scipy needed)
    k = 5
    rng = np.random.RandomState(0)
    centers = c3[rng.choice(n, k, replace=False)]

    for _ in range(30):
        # assign
        labels = np.array([np.argmin([np.linalg.norm(c3[i] - c) for c in centers]) for i in range(n)])
        # update
        for j in range(k):
            members = c3[labels == j]
            if len(members) > 0:
                centers[j] = members.mean(axis=0)

    # Print cluster membership and properties
    print(f"\n  Graph: random({n}, p=0.12)")
    print(f"  Projected into 3D eigenspace, clustered into {k} groups\n")

    for cl in range(k):
        members = np.where(labels == cl)[0]
        if len(members) == 0:
            continue

        # Avg degree of cluster members
        avg_deg = np.mean([A[m].sum() for m in members])

        # Cluster tightness in eigenspace
        cl_coords = c3[members]
        cl_center = cl_coords.mean(axis=0)
        tightness = np.mean([np.linalg.norm(c - cl_center) for c in cl_coords])

        # Avg graph distance WITHIN cluster
        internal_d = []
        for i in members:
            for j in members:
                if i < j and gd[i,j] > 0:
                    internal_d.append(gd[i,j])
        avg_internal_d = np.mean(internal_d) if internal_d else 0

        # Avg graph distance TO OTHER clusters
        external_d = []
        for i in members:
            for j in range(n):
                if labels[j] != cl and gd[i,j] > 0:
                    external_d.append(gd[i,j])
        avg_external_d = np.mean(external_d) if external_d else 0

        print(f"  Cluster {cl}: {len(members):2d} nodes  "
              f"avg_deg={avg_deg:4.1f}  tightness={tightness:.3f}  "
              f"internal_d={avg_internal_d:.2f}  external_d={avg_external_d:.2f}")

        # ASCII scatter of this cluster in first 2 dims
        # (we'll do a big combined one later)

    # === ASCII SCATTER PLOT of eigenspace ===
    print(f"\n  Eigenspace map (first 2 dimensions):")
    print(f"  Each character = a node. Digit = cluster ID.\n")

    x = c3[:, 0]
    y = c3[:, 1]

    # Normalize to grid
    W, H = 72, 30
    x_min, x_max = x.min(), x.max()
    y_min, y_max = y.min(), y.max()
    x_range = x_max - x_min if x_max > x_min else 1
    y_range = y_max - y_min if y_max > y_min else 1

    grid = [[' ' for _ in range(W)] for _ in range(H)]

    for i in range(n):
        gx = int((x[i] - x_min) / x_range * (W - 1))
        gy = int((y[i] - y_min) / y_range * (H - 1))
        gx = max(0, min(W-1, gx))
        gy = max(0, min(H-1, gy))
        ch = str(labels[i])
        if grid[gy][gx] == ' ':
            grid[gy][gx] = ch
        else:
            grid[gy][gx] = '*'  # overlap

    for row in reversed(grid):  # y increases upward
        print(f"  |{''.join(row)}|")
    print(f"  +{'-' * W}+")

    # === WORMHOLE MAP overlaid ===
    # Find top wormholes and draw them
    print(f"\n  Top 10 wormholes overlaid on eigenspace:")
    print(f"  (far in graph, close in eigenspace)\n")

    wormholes = []
    for i in range(n):
        for j in range(i+1, n):
            if gd[i,j] <= 0:
                continue
            gd_norm = (gd[i,j] - gd.mean()) / (gd.std() + 1e-12)
            sd_norm = (sd[i,j] - sd.mean()) / (sd.std() + 1e-12)
            score = gd_norm - sd_norm
            wormholes.append((i, j, gd[i,j], sd[i,j], score))

    wormholes.sort(key=lambda x: -x[4])

    print(f"  {'i':>4} (cl{'':<1}) {'j':>4} (cl{'':<1})  {'graph_d':>7}  "
          f"{'eigen_d':>7}  {'score':>7}  eigenspace position")
    print(f"  {'---':>4}       {'---':>4}        {'---':>7}  {'---':>7}  {'---':>7}")

    for i, j, gd_val, sd_val, score in wormholes[:10]:
        # Show their eigenspace coordinates
        ci = c3[i]
        cj = c3[j]
        midpoint = (ci + cj) / 2
        print(f"  {i:4d} (c{labels[i]})  {j:4d} (c{labels[j]})  "
              f"{gd_val:7.0f}  {sd_val:7.3f}  {score:7.3f}  "
              f"({ci[0]:+.2f},{ci[1]:+.2f}) -- ({cj[0]:+.2f},{cj[1]:+.2f})")

    # Do wormholes connect BETWEEN clusters or WITHIN?
    between = sum(1 for i,j,_,_,_ in wormholes[:20] if labels[i] != labels[j])
    within = 20 - between
    print(f"\n  Of top 20 wormholes: {between} cross clusters, {within} stay within.")

    if within > between:
        print(f"  Wormholes mostly connect nodes within the same eigenspace cluster.")
        print(f"  They're not bridges between worlds -- they're INTERNAL shortcuts.")
    else:
        print(f"  Wormholes mostly BRIDGE eigenspace clusters.")
        print(f"  They tunnel between different structural communities.")
    print()


# === EXPERIMENT 2: THE WORMHOLE GRAPH ===============================
# Build a graph from ONLY the wormhole connections.
# Compute ITS spectrum. Does the wormhole network have structure?
# Do the wormholes have wormholes?

def experiment_wormhole_graph():
    print("=" * 70)
    print("EXPERIMENT 2: THE WORMHOLE GRAPH")
    print("Build a graph from only the wormhole connections.")
    print("Then compute ITS eigenspace. Wormholes of wormholes.")
    print("=" * 70)

    n = 80
    A = random_graph(n, p=0.10, seed=7)
    coords, eigs, vecs = eigenspace_coords(A)

    gd = graph_dist_matrix(A)
    sd = spectral_dist_matrix(coords)

    # Identify wormholes: graph_dist >= 3 AND spectral_dist < median
    median_sd = np.median(sd[sd > 0])

    W = np.zeros((n, n))  # wormhole adjacency
    n_wormholes = 0

    for i in range(n):
        for j in range(i+1, n):
            if gd[i,j] >= 3 and sd[i,j] < median_sd * 0.8:
                W[i,j] = W[j,i] = 1
                n_wormholes += 1

    print(f"\n  Original graph: random({n}, p=0.10)")
    print(f"  Wormhole criterion: graph_dist >= 3 AND spectral_dist < 0.8 * median")
    print(f"  Found {n_wormholes} wormhole edges")

    # How many nodes participate in wormholes?
    wh_degree = W.sum(axis=1)
    active_nodes = np.sum(wh_degree > 0)
    print(f"  {active_nodes} of {n} nodes have at least one wormhole")

    if n_wormholes < 3:
        print(f"  Not enough wormholes to analyze. Try denser graph.")
        print()
        return

    # Properties of the wormhole graph
    L_wh = laplacian(W)
    eigs_wh = np.linalg.eigvalsh(L_wh)

    # Original graph properties
    eigs_orig = eigs

    # Zero modes = connected components of wormhole graph
    wh_components = np.sum(eigs_wh < 1e-8)
    orig_components = np.sum(eigs_orig < 1e-8)

    wh_gap = eigs_wh[eigs_wh > 1e-8][0] if np.any(eigs_wh > 1e-8) else 0
    orig_gap = eigs_orig[eigs_orig > 1e-8][0] if np.any(eigs_orig > 1e-8) else 0

    print(f"\n  Comparison:")
    print(f"  {'':>20}  {'Original':>10}  {'Wormhole':>10}")
    print(f"  {'edges':>20}  {int(A.sum()//2):>10}  {n_wormholes:>10}")
    print(f"  {'components':>20}  {orig_components:>10}  {wh_components:>10}")
    print(f"  {'spectral gap':>20}  {orig_gap:>10.4f}  {wh_gap:>10.4f}")
    print(f"  {'max eigenvalue':>20}  {eigs_orig[-1]:>10.4f}  {eigs_wh[-1]:>10.4f}")

    # Level spacing statistics of the wormhole graph
    nz_wh = eigs_wh[eigs_wh > 1e-8]
    if len(nz_wh) > 5:
        spacings = np.diff(nz_wh)
        mean_s = spacings.mean()
        if mean_s > 0:
            spacings_norm = spacings / mean_s
            r_vals = np.minimum(spacings_norm[:-1], spacings_norm[1:]) / \
                     np.maximum(spacings_norm[:-1], spacings_norm[1:])
            r_mean = r_vals.mean()

            if r_mean > 0.48:
                stat_type = "GOE (quantum chaotic)"
            elif r_mean < 0.42:
                stat_type = "Poisson (integrable)"
            else:
                stat_type = "intermediate"

            print(f"  {'<r> ratio':>20}  {'':>10}  {r_mean:>10.4f}  ({stat_type})")

    # THE BIG QUESTION: eigenspace of the wormhole graph
    if active_nodes > 5:
        coords_wh, _, _ = eigenspace_coords(W)
        sd_wh = spectral_dist_matrix(coords_wh)

        # Wormhole graph's own graph distances
        gd_wh = graph_dist_matrix(W)

        # Find wormholes-of-wormholes
        meta_wormholes = 0
        meta_pairs = []
        for i in range(n):
            for j in range(i+1, n):
                if gd_wh[i,j] >= 3 and gd_wh[i,j] > 0 and sd_wh[i,j] < np.median(sd_wh[sd_wh > 0]) * 0.8:
                    meta_wormholes += 1
                    meta_pairs.append((i, j, gd_wh[i,j], sd_wh[i,j]))

        print(f"\n  RECURSION:")
        print(f"  Wormhole graph has {meta_wormholes} meta-wormholes")
        print(f"  (wormholes between nodes that are far apart in the wormhole graph")
        print(f"   but close in the wormhole graph's eigenspace)")

        if meta_wormholes > 0:
            print(f"\n  Top meta-wormholes:")
            meta_pairs.sort(key=lambda x: x[3])
            for i, j, gd_val, sd_val in meta_pairs[:5]:
                # What's the original graph distance?
                orig_d = gd[i,j]
                print(f"    nodes {i:3d}-{j:3d}:  "
                      f"orig_d={orig_d:.0f}  wormhole_d={gd_val:.0f}  "
                      f"meta_eigen_d={sd_val:.3f}")

            print(f"\n  It goes deeper. The wormhole network has its own shortcuts.")
            print(f"  Eigenspace all the way down.")
        else:
            print(f"  No meta-wormholes found. The wormhole graph may be too sparse")
            print(f"  or too well-connected for secondary shortcuts to emerge.")

    # Eigenvalue distribution comparison (ASCII histogram)
    print(f"\n  Eigenvalue distributions:")
    print(f"  (original vs wormhole graph)\n")

    bins = np.linspace(0, 2.2, 30)

    hist_o, _ = np.histogram(eigs_orig, bins=bins)
    hist_w, _ = np.histogram(eigs_wh, bins=bins)

    max_h = max(hist_o.max(), hist_w.max(), 1)

    print(f"  Original:  ", end="")
    for h in hist_o:
        c = int(h / max_h * 8)
        chars = " .:-=+#@"
        print(chars[min(c, 7)], end="")
    print()

    print(f"  Wormhole:  ", end="")
    for h in hist_w:
        c = int(h / max_h * 8)
        chars = " .:-=+#@"
        print(chars[min(c, 7)], end="")
    print()

    print(f"             {'0':.<15}{'1':.<14}{'2'}")
    print()


# === EXPERIMENT 3: EIGENSPACE DIMENSION =============================
# How many dimensions does eigenspace ACTUALLY have?
# Not all eigenvalues matter equally. The effective dimension
# tells you the true complexity of the graph's structure.
# And then: does the wormhole graph live in fewer dimensions?

def experiment_dimension():
    print("=" * 70)
    print("EXPERIMENT 3: HOW MANY DIMENSIONS DOES EIGENSPACE HAVE?")
    print("The effective dimension = the true complexity of the graph.")
    print("=" * 70)

    graphs = {
        "path(80)":          (lambda: np.diag(np.ones(79), 1) + np.diag(np.ones(79), -1)),
        "grid(9x9)":         (lambda: grid_2d(9, 9)),
        "random(80,0.08)":   (lambda: random_graph(80, 0.08, seed=42)),
        "random(80,0.15)":   (lambda: random_graph(80, 0.15, seed=42)),
        "random(80,0.30)":   (lambda: random_graph(80, 0.30, seed=42)),
        "barbell(80)":       (lambda: barbell_graph(80)),
    }

    print(f"\n  {'graph':>20}  {'n':>4}  {'d_eff':>6}  {'d_90%':>6}  {'d_99%':>6}  "
          f"{'gap':>8}  spectrum shape")
    print(f"  {'---':>20}  {'---':>4}  {'---':>6}  {'---':>6}  {'---':>6}  {'---':>8}")

    for name, make_graph in graphs.items():
        A = make_graph()
        n = len(A)
        L = laplacian(A)
        eigs = np.linalg.eigvalsh(L)
        nz = eigs[eigs > 1e-8]

        if len(nz) == 0:
            continue

        # Effective dimension via participation ratio of eigenvalue distribution
        # Normalize eigenvalues to a distribution
        p = nz / nz.sum()

        # Participation ratio: 1/sum(p^2). Ranges from 1 (one dominant mode) to n.
        d_eff = 1.0 / np.sum(p**2)

        # Cumulative energy: how many modes for 90% / 99% of total eigenvalue mass?
        cumsum = np.cumsum(nz) / nz.sum()
        d_90 = np.searchsorted(cumsum, 0.90) + 1
        d_99 = np.searchsorted(cumsum, 0.99) + 1

        gap = nz[0]

        # ASCII sparkline of eigenvalue distribution
        nbins = 30
        hist, _ = np.histogram(nz, bins=nbins)
        max_h = max(hist.max(), 1)
        spark = ""
        for h in hist:
            level = int(h / max_h * 7)
            spark += " .:-=+#@"[level]

        print(f"  {name:>20}  {n:4d}  {d_eff:6.1f}  {d_90:6d}  {d_99:6d}  "
              f"{gap:8.4f}  {spark}")

    print(f"\n  d_eff = participation ratio (effective number of modes)")
    print(f"  d_90% = modes needed for 90% of spectral mass")
    print(f"  d_99% = modes needed for 99% of spectral mass")
    print(f"\n  Low d_eff = the graph is secretly low-dimensional.")
    print(f"  It may have 80 nodes but its eigenspace is a thin manifold.")
    print(f"  That's compressibility. That's why Logos works.\n")


# === EXPERIMENT 4: EIGENSPACE TRAVEL ================================
# Start at a node. Take steps in eigenspace (not graph space).
# Where do you end up? How does eigenspace travel differ from
# graph traversal?

def experiment_travel():
    print("=" * 70)
    print("EXPERIMENT 4: EIGENSPACE TRAVEL")
    print("Walk through eigenspace instead of the graph.")
    print("Where does the geometry take you?")
    print("=" * 70)

    n = 60
    A = random_graph(n, p=0.12, seed=42)
    coords, eigs, vecs = eigenspace_coords(A)
    gd = graph_dist_matrix(A)
    sd = spectral_dist_matrix(coords)

    # Pick a starting node (highest degree for interesting walks)
    degrees = A.sum(axis=1)
    start = int(np.argmax(degrees))

    print(f"\n  Graph: random({n}, p=0.12)")
    print(f"  Starting at node {start} (degree={int(degrees[start])})")

    # WALK 1: Greedy graph walk (always go to unvisited neighbor)
    print(f"\n  Walk 1: GRAPH walk (follow edges)")
    visited_g = {start}
    path_g = [start]
    current = start
    for step in range(15):
        neighbors = [j for j in range(n) if A[current, j] > 0 and j not in visited_g]
        if not neighbors:
            break
        # Pick neighbor with highest degree (greedy)
        nxt = max(neighbors, key=lambda j: degrees[j])
        visited_g.add(nxt)
        path_g.append(nxt)
        current = nxt

    # WALK 2: Greedy eigenspace walk (always go to nearest in eigenspace)
    print(f"  Walk 2: EIGENSPACE walk (nearest in eigenspace, ignoring edges)")
    visited_e = {start}
    path_e = [start]
    current = start
    for step in range(15):
        # Find nearest unvisited node in eigenspace (not necessarily a neighbor!)
        best_j = -1
        best_d = float('inf')
        for j in range(n):
            if j not in visited_e and sd[current, j] < best_d:
                best_d = sd[current, j]
                best_j = j
        if best_j < 0:
            break
        visited_e.add(best_j)
        path_e.append(best_j)
        current = best_j

    # WALK 3: Wormhole walk (maximize graph_dist / spectral_dist ratio)
    print(f"  Walk 3: WORMHOLE walk (maximize topological surprise)")
    visited_w = {start}
    path_w = [start]
    current = start
    for step in range(15):
        best_j = -1
        best_score = -float('inf')
        for j in range(n):
            if j not in visited_w and gd[current, j] > 0 and sd[current, j] > 1e-6:
                score = gd[current, j] / sd[current, j]
                if score > best_score:
                    best_score = score
                    best_j = j
        if best_j < 0:
            break
        visited_w.add(best_j)
        path_w.append(best_j)
        current = best_j

    # Print walks side by side
    max_len = max(len(path_g), len(path_e), len(path_w))

    print(f"\n  {'step':>4}  {'GRAPH':>20}  {'EIGENSPACE':>20}  {'WORMHOLE':>20}")
    print(f"  {'---':>4}  {'---':>20}  {'---':>20}  {'---':>20}")

    for step in range(max_len):
        g_str = e_str = w_str = ""
        if step < len(path_g):
            nd = path_g[step]
            g_str = f"n{nd}(d={int(degrees[nd])})"
            if step > 0:
                g_str += f" gd={int(gd[path_g[step-1], nd])}"
        if step < len(path_e):
            nd = path_e[step]
            e_str = f"n{nd}(d={int(degrees[nd])})"
            if step > 0:
                e_str += f" sd={sd[path_e[step-1], nd]:.2f}"
        if step < len(path_w):
            nd = path_w[step]
            w_str = f"n{nd}(d={int(degrees[nd])})"
            if step > 0:
                prev = path_w[step-1]
                w_str += f" g/s={gd[prev, nd]/max(sd[prev,nd],1e-6):.1f}"

        print(f"  {step:4d}  {g_str:>20}  {e_str:>20}  {w_str:>20}")

    # Coverage analysis
    print(f"\n  Coverage after 15 steps:")

    for walk_name, path in [("graph", path_g), ("eigenspace", path_e), ("wormhole", path_w)]:
        visited = set(path)
        # How much of the graph's spectral mass do these nodes cover?
        nz_eigs = eigs[eigs > 1e-8]
        nz_vecs = vecs[:, eigs > 1e-8]

        # Spectral coverage: sum of |psi_k(visited)|^2 across all modes
        coverage_per_mode = np.sum(nz_vecs[list(visited), :]**2, axis=0)
        total_coverage = coverage_per_mode.mean()  # avg fraction of each mode captured

        # Unique graph neighborhoods reached
        neighborhoods = set()
        for nd in visited:
            for nb in range(n):
                if A[nd, nb] > 0:
                    neighborhoods.add(nb)

        # Average pairwise graph distance within the walk
        walk_nodes = list(visited)
        if len(walk_nodes) > 1:
            dists = [gd[i,j] for i in walk_nodes for j in walk_nodes if i < j and gd[i,j] > 0]
            avg_spread = np.mean(dists) if dists else 0
        else:
            avg_spread = 0

        print(f"    {walk_name:>10}: {len(visited):2d} nodes, "
              f"spectral_coverage={total_coverage:.1%}, "
              f"neighborhoods={len(neighborhoods)}, "
              f"avg_spread={avg_spread:.1f}")

    print()


# === EXPERIMENT 5: EIGENSPACE ECHOES ================================
# Perturb the graph (add/remove one edge). Measure how the
# perturbation PROPAGATES through eigenspace. Does it ripple?
# Decay? Resonate?

def experiment_echoes():
    print("=" * 70)
    print("EXPERIMENT 5: EIGENSPACE ECHOES")
    print("Perturb one edge. Watch the ripple through eigenspace.")
    print("=" * 70)

    n = 80
    A = random_graph(n, p=0.10, seed=42)
    L = laplacian(A)
    eigs_orig, vecs_orig = np.linalg.eigh(L)

    coords_orig, _, _ = eigenspace_coords(A)

    # Pick an edge to remove
    edges = [(i,j) for i in range(n) for j in range(i+1,n) if A[i,j] > 0]
    rng = np.random.RandomState(42)

    print(f"\n  Graph: random({n}, p=0.10), {len(edges)} edges")
    print(f"  Removing one edge at a time. Measuring eigenspace displacement.\n")

    print(f"  {'edge':>10}  {'deg_i':>5}  {'deg_j':>5}  {'max_shift':>10}  "
          f"{'mean_shift':>10}  {'modes_hit':>10}  ripple")
    print(f"  {'---':>10}  {'---':>5}  {'---':>5}  {'---':>10}  "
          f"{'---':>10}  {'---':>10}")

    edge_effects = []

    sample = rng.choice(len(edges), min(25, len(edges)), replace=False)

    for idx in sorted(sample):
        i, j = edges[idx]

        # Remove the edge
        A_mod = A.copy()
        A_mod[i,j] = A_mod[j,i] = 0

        L_mod = laplacian(A_mod)
        eigs_mod = np.linalg.eigvalsh(L_mod)

        coords_mod, _, _ = eigenspace_coords(A_mod)

        # How much did each NODE move in eigenspace?
        min_dim = min(coords_orig.shape[1], coords_mod.shape[1])
        displacements = np.array([
            np.linalg.norm(coords_orig[k, :min_dim] - coords_mod[k, :min_dim])
            for k in range(n)
        ])

        # How much did the eigenvalues shift?
        min_eig = min(len(eigs_orig), len(eigs_mod))
        eig_shifts = np.abs(eigs_orig[:min_eig] - eigs_mod[:min_eig])

        max_shift = displacements.max()
        mean_shift = displacements.mean()
        modes_hit = np.sum(eig_shifts > 0.001)

        deg_i = int(A[i].sum())
        deg_j = int(A[j].sum())

        # Ripple visualization: how far from the edge does the effect reach?
        gd_full = graph_dist_matrix(A)
        dist_from_edge = np.minimum(gd_full[i], gd_full[j])

        # Displacement vs distance from edge
        ripple = ""
        for d in range(6):
            mask = dist_from_edge == d
            if mask.sum() > 0:
                avg_disp = displacements[mask].mean()
                level = min(7, int(avg_disp / (max_shift + 1e-12) * 8))
                ripple += " .:-=+#@"[level]
            else:
                ripple += " "

        edge_effects.append((i, j, deg_i, deg_j, max_shift, mean_shift, modes_hit))

        print(f"  ({i:3d},{j:3d})  {deg_i:5d}  {deg_j:5d}  {max_shift:10.4f}  "
              f"{mean_shift:10.4f}  {modes_hit:10d}  |{ripple}|")

    # Correlations
    degs = np.array([(e[2] + e[3]) for e in edge_effects], dtype=float)
    shifts = np.array([e[4] for e in edge_effects])
    modes = np.array([e[6] for e in edge_effects], dtype=float)

    if len(degs) > 3:
        print(f"\n  Correlations:")
        print(f"    degree_sum vs max_shift:  {np.corrcoef(degs, shifts)[0,1]:+.3f}")
        print(f"    degree_sum vs modes_hit:  {np.corrcoef(degs, modes)[0,1]:+.3f}")
        print(f"    max_shift vs modes_hit:   {np.corrcoef(shifts, modes)[0,1]:+.3f}")

    print(f"\n  Ripple column: displacement at graph distance 0,1,2,3,4,5 from the edge.")
    print(f"  '@' = maximum displacement, ' ' = no effect.")
    print(f"  If the ripple decays with distance: perturbations are LOCAL in eigenspace.")
    print(f"  If it doesn't: one edge can reshape the entire eigenspace.\n")


# === RUN ============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |         R A Q A   E I G E N S P A C E   L A B           |")
    print("  |        the geometry behind the geometry                   |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_cartography()
    experiment_wormhole_graph()
    experiment_dimension()
    experiment_travel()
    experiment_echoes()

    print("=" * 70)
    print("Eigenspace is not a metaphor. It's the room you're standing in.")
    print("You just can't see it without the right eyes.")
    print("=" * 70)
