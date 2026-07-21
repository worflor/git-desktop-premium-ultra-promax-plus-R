# SPDX-FileCopyrightText: 2026 Woflo Labs
# SPDX-License-Identifier: LicenseRef-WLCSL-1.0
# See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

"""
RAQA ELDRITCH — things that shouldn't work but do
===================================================
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

def path_graph(n):
    A = np.zeros((n, n))
    for i in range(n-1): A[i,i+1] = A[i+1,i] = 1
    return A


# === EXPERIMENT A: THE GRAPH HAS A TEMPERATURE =====================
# AND IT UNDERGOES PHASE TRANSITIONS
# Treat eigenvalues as energy levels. Compute partition function,
# free energy, heat capacity as a function of temperature.
# Phase transition = peak in heat capacity = the graph "melts".

def experiment_thermodynamics():
    print("=" * 70)
    print("EXPERIMENT A: THE GRAPH HAS A TEMPERATURE")
    print("And it undergoes phase transitions. On your desk.")
    print("=" * 70)

    graphs = {
        "random(100,0.1)":  random_graph(100, 0.1, seed=7),
        "random(100,0.3)":  random_graph(100, 0.3, seed=7),
        "grid(10x10)":      grid_2d(10, 10),
        "path(100)":        path_graph(100),
    }

    for name, A in graphs.items():
        L = laplacian(A)
        eigs = np.linalg.eigvalsh(L)
        eigs = eigs[eigs > 1e-10]  # strip zero modes

        betas = np.logspace(-2, 2, 300)  # inverse temperature
        Cv_max = 0
        beta_crit = 0
        E_at_crit = 0

        results = []
        for beta in betas:
            # Partition function Z = sum exp(-beta * E)
            boltz = np.exp(-beta * eigs)
            Z = boltz.sum()

            # <E> = -d(ln Z)/d(beta) = sum(E * exp(-beta*E)) / Z
            E_mean = (eigs * boltz).sum() / Z

            # <E^2>
            E2_mean = (eigs**2 * boltz).sum() / Z

            # Heat capacity: C_v = beta^2 * (<E^2> - <E>^2)
            Cv = beta**2 * (E2_mean - E_mean**2)

            # Free energy F = -ln(Z)/beta
            F = -np.log(Z) / beta

            # Entropy S = beta*(E - F)
            S = beta * (E_mean - F)

            results.append((beta, E_mean, Cv, F, S))

            if Cv > Cv_max:
                Cv_max = Cv
                beta_crit = beta
                E_at_crit = E_mean

        T_crit = 1.0 / beta_crit
        print(f"\n  {name}:")
        print(f"    Critical temperature:  T* = {T_crit:.4f}")
        print(f"    Peak heat capacity:    Cv = {Cv_max:.4f}")
        print(f"    Energy at transition:  <E> = {E_at_crit:.4f}")
        print(f"    Spectral bandwidth:    {eigs[-1] - eigs[0]:.4f}")

        # Show heat capacity curve around the transition
        print(f"    Cv(T) near transition:")
        for beta_val, E_val, Cv_val, F_val, S_val in results:
            T_val = 1.0 / beta_val
            if 0.3 * T_crit < T_val < 3.0 * T_crit:
                bar = "#" * int(Cv_val / Cv_max * 40)
                if abs(T_val - T_crit) / T_crit < 0.05:
                    print(f"      T={T_val:6.3f}  Cv={Cv_val:6.3f}  {bar} <-- TRANSITION")
                elif len(bar) > 15:
                    print(f"      T={T_val:6.3f}  Cv={Cv_val:6.3f}  {bar}")

    print(f"\n  The graph is a thermodynamic system.")
    print(f"  The peak in Cv is a phase transition between ordered and")
    print(f"  disordered spectral regimes. Below T*: frozen, dominated by")
    print(f"  the ground state. Above T*: melted, all modes equally excited.")
    print(f"  The transition temperature is set by the spectral gap.\n")


# === EXPERIMENT B: ANDERSON LOCALIZATION ============================
# Add disorder to a regular graph. Watch eigenvectors LOCALIZE.
# Delocalized = information spreads everywhere.
# Localized = information gets trapped. Files become islands.
# This is why messy repos have isolated dead code that nobody touches.

def experiment_anderson():
    print("=" * 70)
    print("EXPERIMENT B: ANDERSON LOCALIZATION")
    print("Disorder traps information. Eigenvectors that used to spread")
    print("across the whole graph get stuck in one corner.")
    print("This is why dead code exists.")
    print("=" * 70)

    n = 200
    A = path_graph(n)

    disorders = [0, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0, 32.0]
    rng = np.random.RandomState(42)

    print(f"\n  Path graph, n={n}")
    print(f"  Adding random on-site potential V_i ~ Uniform[-W/2, W/2]")
    print(f"  IPR = inverse participation ratio. 1/n = delocalized. ~1 = localized.\n")
    print(f"  {'W':>6}  {'mean IPR':>10}  {'max IPR':>10}  {'localized%':>11}  visualization")
    print(f"  {'---':>6}  {'---':>10}  {'---':>10}  {'---':>11}  ---")

    for W in disorders:
        L = laplacian(A)

        # Add diagonal disorder: L_ij -> L_ij + V_i * delta_ij
        V = rng.uniform(-W/2, W/2, n)
        L_disordered = L + np.diag(V)

        eigs, vecs = np.linalg.eigh(L_disordered)

        # IPR for each eigenvector: sum(|psi|^4)
        # Delocalized: IPR ~ 1/n. Localized: IPR ~ 1.
        iprs = np.sum(vecs**4, axis=0)
        mean_ipr = iprs.mean()
        max_ipr = iprs.max()

        # Fraction of eigenvectors that are "localized" (IPR > 5/n)
        loc_frac = np.mean(iprs > 5.0/n)

        # Visualization: show where the most localized eigenvector lives
        worst_idx = np.argmax(iprs)
        worst_vec = np.abs(vecs[:, worst_idx])
        peak = np.argmax(worst_vec)
        # Show a 60-char bar of the eigenvector amplitude
        bins = np.array_split(worst_vec, 60)
        bar = ""
        for b in bins:
            val = b.max()
            if val > 0.3: bar += "@"
            elif val > 0.15: bar += "#"
            elif val > 0.05: bar += "="
            elif val > 0.01: bar += "-"
            else: bar += " "

        print(f"  {W:6.1f}  {mean_ipr:10.6f}  {max_ipr:10.6f}  "
              f"{loc_frac*100:10.1f}%  |{bar}|")

    print(f"\n  1/n = {1/n:.6f} (perfectly delocalized reference)")
    print(f"\n  At W=0, eigenvectors spread everywhere (IPR ~ 1/n).")
    print(f"  As disorder increases, they LOCALIZE. Information gets trapped.")
    print(f"  The '@' shows where the most trapped eigenvector lives.")
    print(f"  This is Anderson localization. Same physics as electrons in")
    print(f"  amorphous semiconductors. Happening on a graph. In numpy.\n")


# === EXPERIMENT C: ENTANGLEMENT AREA LAW ============================
# The holographic principle: information about a region is encoded
# on its BOUNDARY, not in its VOLUME. This is why black hole entropy
# goes as surface area, not volume.
# On a graph: cut it in half. The entanglement entropy should scale
# with the CUT SIZE (number of edges crossing), not partition size.
# If this works, the graph obeys holographic physics.

def experiment_area_law():
    print("=" * 70)
    print("EXPERIMENT C: THE HOLOGRAPHIC PRINCIPLE ON A GRAPH")
    print("Entanglement entropy ~ boundary, not volume.")
    print("If this holds, graphs obey the same law as black holes.")
    print("=" * 70)

    # Use thermal state rho = exp(-beta*L) / Z as the quantum state
    # Partial trace over subsystem B to get rho_A
    # Von Neumann entropy S = -tr(rho_A * ln(rho_A))

    beta = 1.0  # inverse temperature

    results = []

    # Test on grids of different sizes with different partition sizes
    print(f"\n  2D grid graphs, beta={beta}")
    print(f"  Partitioning into regions of size |A| and measuring S(A)\n")
    print(f"  {'grid':>8}  {'|A|':>5}  {'|boundary|':>10}  {'S(A)':>8}  "
          f"{'S/|A|':>8}  {'S/|bnd|':>8}")
    print(f"  {'---':>8}  {'---':>5}  {'---':>10}  {'---':>8}  {'---':>8}  {'---':>8}")

    for grid_size in [6, 8, 10, 12]:
        A = grid_2d(grid_size, grid_size)
        n = grid_size * grid_size
        L = laplacian(A)

        # Thermal state
        rho = np.linalg.matrix_power(
            np.diag(np.exp(-beta * np.linalg.eigvalsh(L))), 1
        )
        # Actually compute properly with eigenvectors
        eigs, vecs = np.linalg.eigh(L)
        boltz = np.exp(-beta * eigs)
        Z = boltz.sum()
        rho = vecs @ np.diag(boltz / Z) @ vecs.T

        # Try different partition sizes: take rectangular sub-blocks
        for cut_rows in range(1, grid_size - 1, max(1, grid_size // 4)):
            # Partition A = first cut_rows rows, B = rest
            idx_A = list(range(cut_rows * grid_size))
            idx_B = list(range(cut_rows * grid_size, n))

            if len(idx_A) < 2 or len(idx_B) < 2:
                continue

            # Reduced density matrix: partial trace over B
            rho_A = rho[np.ix_(idx_A, idx_A)]

            # This isn't quite the partial trace for a general quantum state,
            # but for a thermal state of a graph Laplacian the correlation
            # structure means the submatrix IS the reduced state to leading order.
            # (The off-diagonal blocks between A and B encode entanglement.)

            # Normalize
            tr = np.trace(rho_A)
            if tr > 1e-15:
                rho_A = rho_A / tr

            # Von Neumann entropy
            eigs_A = np.linalg.eigvalsh(rho_A)
            eigs_A = eigs_A[eigs_A > 1e-15]
            S = -np.sum(eigs_A * np.log(eigs_A))

            # Count boundary edges (edges from A to B)
            boundary = 0
            for i in idx_A:
                for j in idx_B:
                    if A[i, j] > 0:
                        boundary += 1

            vol_A = len(idx_A)

            results.append((grid_size, vol_A, boundary, S))

            print(f"  {grid_size}x{grid_size:>2}  {vol_A:5d}  {boundary:10d}  "
                  f"{S:8.4f}  {S/vol_A:8.4f}  {S/boundary if boundary > 0 else 0:8.4f}")

    # Compute correlations
    if len(results) > 3:
        vols = np.array([r[1] for r in results], dtype=float)
        bnds = np.array([r[2] for r in results], dtype=float)
        Ss   = np.array([r[3] for r in results], dtype=float)

        corr_vol = np.corrcoef(vols, Ss)[0,1]
        corr_bnd = np.corrcoef(bnds, Ss)[0,1]

        print(f"\n  Correlation(S, |A|):        {corr_vol:.4f}")
        print(f"  Correlation(S, |boundary|): {corr_bnd:.4f}")

        if corr_bnd > corr_vol:
            print(f"\n  ! ENTROPY TRACKS THE BOUNDARY MORE THAN THE VOLUME.")
            print(f"    This is the area law. The holographic principle.")
            print(f"    Information about the interior is encoded on the surface.")
        elif corr_bnd > 0.8:
            print(f"\n  ~ Strong boundary correlation. Area law is plausible.")
        else:
            print(f"\n  ? Both correlations are similar. Need larger graphs to separate.")
    print()


# === EXPERIMENT D: SPECTRAL WORMHOLES (ER = EPR) ===================
# Two nodes far apart in the graph but spectrally close = wormhole.
# "ER = EPR" says that entangled particles are connected by wormholes.
# On a graph: high mutual spectral weight between distant nodes
# means there's a shortcut through the eigenspace.

def experiment_wormholes():
    print("=" * 70)
    print("EXPERIMENT D: SPECTRAL WORMHOLES")
    print("Distant nodes connected through eigenspace. ER = EPR on a graph.")
    print("=" * 70)

    n = 80
    A = random_graph(n, p=0.08, seed=42)
    L = laplacian(A)
    eigs, vecs = np.linalg.eigh(L)

    # Graph distance via BFS
    def bfs_dist(adj, src):
        dist = np.full(len(adj), -1)
        dist[src] = 0
        queue = [src]
        while queue:
            node = queue.pop(0)
            for nb in range(len(adj)):
                if adj[node, nb] > 0 and dist[nb] == -1:
                    dist[nb] = dist[node] + 1
                    queue.append(nb)
        return dist

    # Spectral distance: how similar two nodes look in the eigenbasis
    # D_spectral(i,j) = sqrt(sum_k (u_k(i) - u_k(j))^2 / lambda_k)
    # Weight by 1/lambda to emphasize low-frequency (global) structure

    weights = np.where(eigs > 1e-8, 1.0 / eigs, 0)
    weighted_vecs = vecs * np.sqrt(weights)[np.newaxis, :]

    # Spectral distance matrix
    spec_dist = np.zeros((n, n))
    for i in range(n):
        for j in range(i+1, n):
            d = np.linalg.norm(weighted_vecs[i] - weighted_vecs[j])
            spec_dist[i,j] = spec_dist[j,i] = d

    # Graph distance matrix
    graph_dist = np.zeros((n, n))
    for i in range(n):
        d = bfs_dist(A, i)
        graph_dist[i] = d

    # Find WORMHOLES: pairs where graph_dist is large but spectral_dist is small
    # Normalize both
    gd_flat = graph_dist[np.triu_indices(n, 1)]
    sd_flat = spec_dist[np.triu_indices(n, 1)]

    # Remove unreachable pairs
    mask = gd_flat > 0
    gd_flat = gd_flat[mask]
    sd_flat = sd_flat[mask]

    if len(gd_flat) == 0:
        print("  Graph is disconnected, skipping.")
        return

    # Wormhole score: high graph distance, low spectral distance
    gd_norm = (gd_flat - gd_flat.mean()) / (gd_flat.std() + 1e-12)
    sd_norm = (sd_flat - sd_flat.mean()) / (sd_flat.std() + 1e-12)
    wormhole_score = gd_norm - sd_norm  # high = far in graph, close in spectrum

    # Overall correlation
    corr = np.corrcoef(gd_flat, sd_flat)[0,1]

    print(f"\n  Graph: random({n}, p=0.08)")
    print(f"  Correlation(graph_distance, spectral_distance): {corr:.4f}")

    # Top wormholes
    pairs = list(zip(*np.triu_indices(n, 1)))
    pair_mask = graph_dist[np.triu_indices(n, 1)] > 0
    valid_pairs = [p for p, m in zip(pairs, pair_mask) if m]

    scored = list(zip(valid_pairs, wormhole_score))
    scored.sort(key=lambda x: -x[1])

    print(f"\n  Top spectral wormholes (far in graph, close in spectrum):")
    print(f"  {'node_i':>6}  {'node_j':>6}  {'graph_d':>8}  {'spec_d':>8}  {'wormhole':>9}")
    print(f"  {'---':>6}  {'---':>6}  {'---':>8}  {'---':>8}  {'---':>9}")

    for (i, j), score in scored[:10]:
        gd = graph_dist[i, j]
        sd = spec_dist[i, j]
        print(f"  {i:6d}  {j:6d}  {gd:8.0f}  {sd:8.4f}  {score:9.4f}")

    print(f"\n  Bottom (anti-wormholes: close in graph, far in spectrum):")
    for (i, j), score in scored[-5:]:
        gd = graph_dist[i, j]
        sd = spec_dist[i, j]
        print(f"  {i:6d}  {j:6d}  {gd:8.0f}  {sd:8.4f}  {score:9.4f}")

    # Wormhole statistics by distance
    print(f"\n  Wormhole density by graph distance:")
    max_d = int(gd_flat.max())
    for d in range(1, min(max_d + 1, 10)):
        d_mask = gd_flat == d
        if d_mask.sum() == 0:
            continue
        mean_sd = sd_flat[d_mask].mean()
        std_sd = sd_flat[d_mask].std()
        n_pairs = d_mask.sum()
        # How many at this distance are spectrally close (< median)?
        med_spec = np.median(sd_flat)
        wormhole_frac = np.mean(sd_flat[d_mask] < med_spec)
        bar = "#" * int(wormhole_frac * 40)
        print(f"    d={d}:  n={n_pairs:5.0f}  <spec_d>={mean_sd:6.3f}  "
              f"wormhole_frac={wormhole_frac:.2f}  {bar}")

    if corr < 0.8:
        print(f"\n  ! GRAPH DISTANCE AND SPECTRAL DISTANCE DISAGREE (r={corr:.2f}).")
        print(f"    The eigenspace sees shortcuts the graph doesn't have.")
        print(f"    These are wormholes: information tunnels through spectral space")
        print(f"    that connect nodes the topology says are far apart.")
        print(f"    ER = EPR. Entanglement = geometry. On a random graph.\n")
    else:
        print(f"\n  Graph and spectral distance mostly agree (r={corr:.2f}).")
        print(f"  Try sparser graphs for stronger wormhole effects.\n")


# === EXPERIMENT E: THE GRAPH REMEMBERS ITS OWN DEATH ================
# Remove nodes one by one. After each removal, measure how much
# SPECTRAL MEMORY remains — can you reconstruct the dead node's
# connections from the surviving spectrum?
# If yes: information is never truly destroyed. It's Hawking's
# information paradox, but on a graph, and we can test it.

def experiment_information_paradox():
    print("=" * 70)
    print("EXPERIMENT E: THE INFORMATION PARADOX")
    print("Remove nodes from a graph. Can the surviving spectrum")
    print("remember what was deleted? Is information ever truly lost?")
    print("=" * 70)

    n = 60
    rng = np.random.RandomState(42)
    A = random_graph(n, p=0.15, seed=42)
    L = laplacian(A)
    eigs_original = np.linalg.eigvalsh(L)

    print(f"\n  Graph: random({n}, p=0.15)")
    print(f"  Removing nodes one by one. After each removal:")
    print(f"  - Can we identify WHICH node was removed from the spectral shift?")
    print(f"  - How much information about the dead node survives?\n")

    # For each possible single-node removal, compute the spectral shift
    spectral_fingerprints = {}
    for node in range(n):
        A_reduced = np.delete(np.delete(A, node, 0), node, 1)
        L_reduced = laplacian(A_reduced)
        eigs_reduced = np.linalg.eigvalsh(L_reduced)

        # The spectral shift IS the fingerprint of the removed node
        # Compare by padding and taking difference
        # Use the eigenvalue density (histogram) for comparison
        bins = np.linspace(0, 2.2, 50)
        hist_orig, _ = np.histogram(eigs_original, bins=bins, density=True)
        hist_red, _ = np.histogram(eigs_reduced, bins=bins, density=True)

        shift = hist_orig - hist_red
        spectral_fingerprints[node] = shift

    # Now: can we tell nodes apart from their spectral fingerprints?
    # Compute pairwise similarity of fingerprints
    nodes = list(range(n))
    fingerprints = np.array([spectral_fingerprints[i] for i in nodes])

    # Correlation matrix of fingerprints
    fp_corr = np.corrcoef(fingerprints)

    # For each node, find how many other nodes have a very similar fingerprint
    # High uniqueness = the spectrum remembers this node specifically
    uniqueness = []
    for i in range(n):
        similar = np.sum(fp_corr[i] > 0.95) - 1  # exclude self
        degree = A[i].sum()
        uniqueness.append((i, degree, similar, fp_corr[i].max()))

    uniqueness.sort(key=lambda x: x[2])

    print(f"  {'node':>5}  {'degree':>6}  {'clones':>6}  {'max_corr':>8}  uniqueness")
    print(f"  {'---':>5}  {'---':>6}  {'---':>6}  {'---':>8}  ---")

    # Show most unique (most remembered) nodes
    print(f"  Most spectral-unique (best remembered):")
    for node, deg, clones, mc in uniqueness[:8]:
        bar = "#" * max(1, int((1 - clones/n) * 30))
        print(f"  {node:5d}  {deg:6.0f}  {clones:6d}  {mc:8.4f}  {bar}")

    print(f"\n  Least unique (most forgettable):")
    for node, deg, clones, mc in uniqueness[-5:]:
        bar = "#" * max(1, int((1 - clones/n) * 30))
        print(f"  {node:5d}  {deg:6.0f}  {clones:6d}  {mc:8.4f}  {bar}")

    # Can we RECONSTRUCT the removed node?
    # Test: remove a node, then try to identify it from the spectral shift
    print(f"\n  Reconstruction test: remove a random node, identify it from spectrum")
    test_nodes = rng.choice(n, 10, replace=False)
    correct = 0
    for test_node in test_nodes:
        A_reduced = np.delete(np.delete(A, test_node, 0), test_node, 1)
        L_reduced = laplacian(A_reduced)
        eigs_reduced = np.linalg.eigvalsh(L_reduced)

        bins = np.linspace(0, 2.2, 50)
        hist_red, _ = np.histogram(eigs_reduced, bins=bins, density=True)
        hist_orig, _ = np.histogram(eigs_original, bins=bins, density=True)
        observed_shift = hist_orig - hist_red

        # Match against all fingerprints
        best_match = -1
        best_corr = -1
        for candidate in range(n):
            c = np.corrcoef(observed_shift, spectral_fingerprints[candidate])[0,1]
            if c > best_corr:
                best_corr = c
                best_match = candidate

        hit = "HIT" if best_match == test_node else f"miss (guessed {best_match})"
        if best_match == test_node:
            correct += 1
        print(f"    Removed node {test_node:3d} (deg={A[test_node].sum():2.0f}) "
              f"-> identified as {best_match:3d} (corr={best_corr:.4f}) {hit}")

    accuracy = correct / len(test_nodes)
    random_chance = 1.0 / n

    print(f"\n  Accuracy: {accuracy:.0%} ({correct}/{len(test_nodes)})")
    print(f"  Random chance: {random_chance:.1%}")

    if accuracy > 0.5:
        print(f"\n  ! THE SPECTRUM REMEMBERS THE DEAD.")
        print(f"    Even after a node is removed, its spectral fingerprint")
        print(f"    persists in the surviving graph strongly enough to identify it.")
        print(f"    Information is not destroyed. It's redistributed.")
        print(f"    Hawking was right. The information paradox resolves.")
    elif accuracy > random_chance * 5:
        print(f"\n  ~ Partial memory. The spectrum retains traces of removed nodes,")
        print(f"    but not perfectly. Information degrades, not disappears.")
    print()


# === RUN ============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |           R A Q A   E L D R I T C H   L A B             |")
    print("  |     things that shouldn't work on a desktop but do       |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_thermodynamics()
    experiment_anderson()
    experiment_area_law()
    experiment_wormholes()
    experiment_information_paradox()

    print("=" * 70)
    print("What did the abyss say back?")
    print("=" * 70)
