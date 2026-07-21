# SPDX-FileCopyrightText: 2026 Woflo Labs
# SPDX-License-Identifier: LicenseRef-WLCSL-1.0
# See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

"""
RAQA Day 3 Evening — chasing the open questions
=================================================
1. Self-spectrum convergence: at what graph size does it settle?
2. Eigenspace heartbeat: what's the frequency?
3. Eigenvalue sonification: what does a graph SOUND like?
4. The golden ratio keeps appearing. Is it load-bearing?
5. Can two different graphs have the same spectrum? (isospectral)
"""

import numpy as np
import time
import struct

np.set_printoptions(precision=6, linewidth=120, suppress=True)

def laplacian(adj):
    d = adj.sum(axis=1)
    d_inv_sqrt = np.where(d > 0, 1.0 / np.sqrt(d), 0.0)
    D = np.diag(d_inv_sqrt)
    return np.eye(len(adj)) - D @ adj @ D

def random_graph(n, p=0.15, seed=42):
    rng = np.random.RandomState(seed)
    A = (rng.rand(n, n) < p).astype(float)
    A = np.triu(A, 1); A = A + A.T
    return A

def path_graph(n):
    A = np.zeros((n, n))
    for i in range(n-1): A[i,i+1] = A[i+1,i] = 1
    return A

def star_graph(n):
    A = np.zeros((n, n))
    for i in range(1, n): A[0,i] = A[i,0] = 1
    return A

def cycle_graph(n):
    A = path_graph(n)
    A[0,-1] = A[-1,0] = 1
    return A


# === EXPERIMENT 1: SELF-SPECTRUM CONVERGENCE BOUNDARY ================
# At n=80 it was chaotic. Does it converge for simpler graphs?
# Sweep from n=5 to n=100 across multiple topologies.
# Find the boundary between convergent and chaotic.

def experiment_self_convergence():
    print("=" * 70)
    print("  THE SELF-SPECTRUM: WHERE DOES SELF-KNOWLEDGE BREAK?")
    print("  Sweep graph sizes. Find the chaos boundary.")
    print("=" * 70)

    def run_self_spectrum(A, max_iter=20):
        """Returns (converged, final_delta, iterations, entropies)."""
        prev_eigs = None
        entropies = []
        for it in range(max_iter):
            L = laplacian(A)
            eigs = np.sort(np.linalg.eigvalsh(L))
            nz = eigs[eigs > 1e-10]
            if len(nz) > 0:
                p = nz / nz.sum()
                H = -np.sum(p * np.log(p + 1e-30))
            else:
                H = 0
            entropies.append(H)

            if prev_eigs is not None:
                ml = min(len(eigs), len(prev_eigs))
                delta = np.linalg.norm(eigs[:ml] - prev_eigs[:ml])
                if delta < 1e-6:
                    return True, delta, it, entropies
            prev_eigs = eigs.copy()

            # Build next graph from eigenvalues
            if len(eigs) < 3:
                return False, 999, it, entropies
            spacings = np.diff(eigs)
            threshold = np.mean(spacings) * 1.2
            m = len(eigs)
            A_new = np.zeros((m, m))
            for i in range(m):
                for j in range(i+1, m):
                    if abs(eigs[i] - eigs[j]) < threshold:
                        A_new[i,j] = A_new[j,i] = 1
            density = A_new.sum() / (m * (m-1)) if m > 1 else 0
            if density > 0.95:
                threshold *= 0.5
                A_new = np.zeros((m, m))
                for i in range(m):
                    for j in range(i+1, m):
                        if abs(eigs[i] - eigs[j]) < threshold:
                            A_new[i,j] = A_new[j,i] = 1
            elif density < 0.01:
                threshold *= 2.0
                A_new = np.zeros((m, m))
                for i in range(m):
                    for j in range(i+1, m):
                        if abs(eigs[i] - eigs[j]) < threshold:
                            A_new[i,j] = A_new[j,i] = 1
            A = A_new

        ml = min(len(eigs), len(prev_eigs)) if prev_eigs is not None else 0
        delta = np.linalg.norm(eigs[:ml] - prev_eigs[:ml]) if ml > 0 else 999
        return False, delta, max_iter, entropies

    # Test across sizes and topologies
    print(f"\n  {'topology':>15}  {'n':>4}  {'converged':>9}  {'iters':>5}  "
          f"{'final_d':>9}  {'H_final':>8}  {'H_var':>8}")
    print(f"  {'---':>15}  {'---':>4}  {'---':>9}  {'---':>5}  "
          f"{'---':>9}  {'---':>8}  {'---':>8}")

    for make, name in [(path_graph, "path"), (cycle_graph, "cycle"),
                        (star_graph, "star"),
                        (lambda n: random_graph(n, 0.15, 42), "random(0.15)"),
                        (lambda n: random_graph(n, 0.30, 42), "random(0.30)")]:
        for n in [5, 10, 15, 20, 30, 50, 80]:
            A = make(n)
            conv, delta, iters, Hs = run_self_spectrum(A, max_iter=25)
            H_final = Hs[-1] if Hs else 0
            H_var = np.var(Hs[-5:]) if len(Hs) >= 5 else 0

            status = "YES" if conv else ("orbit" if delta < 1 else "chaos")
            print(f"  {name:>15}  {n:4d}  {status:>9}  {iters:5d}  "
                  f"{delta:9.4f}  {H_final:8.4f}  {H_var:8.6f}")

    print(f"\n  'orbit' = bounded oscillation (strange attractor)")
    print(f"  'chaos' = unbounded or divergent")
    print(f"  H_var = variance of entropy in last 5 iterations (low = stable orbit)\n")


# === EXPERIMENT 2: EIGENSPACE HEARTBEAT ==============================
# Repos oscillate. But is there a FREQUENCY?
# Compute the power spectrum of the temporal drift signal.

def experiment_heartbeat():
    print("=" * 70)
    print("  THE EIGENSPACE HEARTBEAT")
    print("  What frequency does a codebase breathe at?")
    print("=" * 70)

    import subprocess, os, tempfile
    from collections import defaultdict

    WORK_DIR = os.path.join(tempfile.gettempdir(), "raqa_repos")
    LOCAL = r"C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R"
    SRC_EXTS = ['.py','.js','.ts','.dart','.rs','.go','.java','.c','.cpp','.h','.rb','.vue','.jsx','.tsx']

    repos = {"pretext": LOCAL}
    for name in ["flask", "django", "pytorch", "rust-lang", "vue"]:
        p = os.path.join(WORK_DIR, name)
        if os.path.exists(p):
            repos[name] = p

    def parse_and_window(repo_path, n_commits=300, window=20, step=5):
        try:
            r = subprocess.run(["git", "log", "--no-merges", "--name-only",
                                "--format=COMMIT_SEP%H", "-n", str(n_commits)],
                               capture_output=True, text=True, encoding="utf-8",
                               errors="replace", cwd=repo_path, timeout=60)
            log = r.stdout
        except:
            return []

        commits = []
        current = []
        for line in log.split("\n"):
            line = line.strip()
            if line.startswith("COMMIT_SEP"):
                if current:
                    src = [f for f in current if any(f.endswith(e) for e in SRC_EXTS)]
                    if 1 < len(src) <= 50:
                        commits.append(src)
                current = []
            elif line:
                current.append(line)

        # Build eigenvalue sequence per window
        eig_sequence = []
        bins = np.linspace(0, 2.2, 40)

        for start in range(0, len(commits) - window + 1, step):
            w = commits[start:start + window]
            pairs = defaultdict(int)
            files = set()
            for fs in w:
                fs = list(set(fs))
                files.update(fs)
                for i in range(len(fs)):
                    for j in range(i+1, len(fs)):
                        pairs[tuple(sorted([fs[i], fs[j]]))] += 1
            flist = sorted(files)
            idx = {f: i for i, f in enumerate(flist)}
            n = len(flist)
            A = np.zeros((n, n))
            for (a, b), c in pairs.items():
                if c >= 1:
                    A[idx[a], idx[b]] = c
                    A[idx[b], idx[a]] = c
            conn = A.sum(axis=1) > 0
            A = A[np.ix_(conn, conn)]
            if A.shape[0] < 5:
                continue
            L = laplacian((A > 0).astype(float))
            eigs = np.linalg.eigvalsh(L)
            hist, _ = np.histogram(eigs, bins=bins, density=True)
            eig_sequence.append(hist)

        return eig_sequence

    for repo_name, repo_path in repos.items():
        seq = parse_and_window(repo_path, n_commits=400, window=15, step=3)
        if len(seq) < 10:
            continue

        # Compute JSD between consecutive windows
        drifts = []
        for i in range(len(seq) - 1):
            h1 = seq[i] / (seq[i].sum() + 1e-12) + 1e-12
            h2 = seq[i+1] / (seq[i+1].sum() + 1e-12) + 1e-12
            m = (h1 + h2) / 2
            jsd = 0.5 * np.sum(h1 * np.log(h1 / m)) + 0.5 * np.sum(h2 * np.log(h2 / m))
            drifts.append(jsd)

        if len(drifts) < 8:
            continue

        drifts = np.array(drifts)

        # Power spectrum of the drift signal
        drifts_centered = drifts - drifts.mean()
        fft = np.fft.rfft(drifts_centered)
        power = np.abs(fft) ** 2
        freqs = np.fft.rfftfreq(len(drifts_centered))

        # Find dominant frequency (skip DC)
        if len(power) > 1:
            peak_idx = np.argmax(power[1:]) + 1
            peak_freq = freqs[peak_idx]
            peak_period = 1.0 / peak_freq if peak_freq > 0 else float('inf')

            # Fraction of power in dominant mode
            total_power = power[1:].sum()
            dominant_frac = power[peak_idx] / total_power if total_power > 0 else 0

            print(f"\n  {repo_name}:")
            print(f"    {len(drifts)} drift measurements")
            print(f"    Dominant frequency: {peak_freq:.3f} cycles/window")
            print(f"    Period: {peak_period:.1f} windows = ~{peak_period * 3:.0f} commits")
            print(f"    Dominant mode power: {dominant_frac:.0%} of total")

            # Power spectrum visualization
            print(f"    Power spectrum: ", end="")
            max_p = power[1:].max() if len(power) > 1 else 1
            for p in power[1:min(20, len(power))]:
                level = int(p / max_p * 7) if max_p > 0 else 0
                print(" .:-=+#@"[min(level, 7)], end="")
            print()

            # Is there a clear heartbeat?
            if dominant_frac > 0.3:
                print(f"    HEARTBEAT DETECTED: period ~{peak_period * 3:.0f} commits")
            elif dominant_frac > 0.15:
                print(f"    Weak rhythm at ~{peak_period * 3:.0f} commits")
            else:
                print(f"    No dominant rhythm. Arrhythmic.")

    print()


# === EXPERIMENT 3: THE GOLDEN RATIO IN EIGENSPACE ===================
# phi = 1.618... keeps appearing in the engine (Born impedance,
# confidence gates, etc). Is it actually special for eigenvalues?
# Compare: graphs where edge weights are phi vs e vs pi vs 2 vs random.

def experiment_golden_ratio():
    print("=" * 70)
    print("  IS THE GOLDEN RATIO SPECTRALLY SPECIAL?")
    print("  phi keeps showing up. Is it load-bearing or coincidence?")
    print("=" * 70)

    n = 60
    phi = (1 + np.sqrt(5)) / 2

    rng = np.random.RandomState(42)
    A_base = random_graph(n, p=0.15, seed=42)

    constants = {
        "1 (binary)": 1.0,
        "phi (1.618)": phi,
        "e (2.718)": np.e,
        "pi (3.14)": np.pi,
        "2": 2.0,
        "sqrt(2)": np.sqrt(2),
        "random [0,3]": None,  # random weights
    }

    print(f"\n  Same topology ({n} nodes), different edge weights.")
    print(f"  Which constant produces the most 'useful' spectrum?\n")

    print(f"  {'weight':>14}  {'gap':>8}  {'d_eff':>6}  {'entropy':>8}  "
          f"{'cond':>10}  {'info_acc':>8}")
    print(f"  {'---':>14}  {'---':>8}  {'---':>6}  {'---':>8}  "
          f"{'---':>10}  {'---':>8}")

    for name, val in constants.items():
        if val is not None:
            A = A_base * val
        else:
            A = A_base * (rng.rand(n, n) * 3)
            A = np.triu(A, 1)
            A = A + A.T
            A = A * (A_base > 0)

        A_bin = (A > 0).astype(float)
        L = laplacian(A_bin)
        eigs = np.linalg.eigvalsh(L)
        nz = eigs[eigs > 1e-8]

        if len(nz) == 0:
            continue

        gap = nz[0]
        p = nz / nz.sum()
        d_eff = 1.0 / np.sum(p**2)
        H = -np.sum(p * np.log(p + 1e-30))

        # Condition number of the Laplacian (excluding zero modes)
        cond = nz[-1] / nz[0] if nz[0] > 0 else float('inf')

        # Quick info paradox test (5 random nodes)
        bins_h = np.linspace(0, 2.2, 50)
        hist_orig, _ = np.histogram(eigs, bins=bins_h, density=True)
        fps = {}
        test_nodes = rng.choice(n, min(20, n), replace=False)
        for node in test_nodes:
            A_red = np.delete(np.delete(A_bin, node, 0), node, 1)
            if A_red.shape[0] < 2: continue
            eigs_r = np.linalg.eigvalsh(laplacian(A_red))
            hist_r, _ = np.histogram(eigs_r, bins=bins_h, density=True)
            fps[node] = hist_orig - hist_r

        correct = 0
        tested = 0
        for node in test_nodes[:10]:
            if node not in fps: continue
            A_red = np.delete(np.delete(A_bin, node, 0), node, 1)
            if A_red.shape[0] < 2: continue
            eigs_r = np.linalg.eigvalsh(laplacian(A_red))
            hist_r, _ = np.histogram(eigs_r, bins=bins_h, density=True)
            obs = hist_orig - hist_r
            best = max(fps.keys(), key=lambda c: np.corrcoef(obs, fps[c])[0,1]
                       if not np.isnan(np.corrcoef(obs, fps[c])[0,1]) else -1)
            if best == node: correct += 1
            tested += 1

        acc = correct / tested if tested > 0 else 0

        print(f"  {name:>14}  {gap:8.4f}  {d_eff:6.1f}  {H:8.4f}  "
              f"{cond:10.2f}  {acc:7.0%}")

    print(f"\n  If phi produces better gap/entropy/accuracy than other constants,")
    print(f"  it's not just a convention — it's spectrally optimal.\n")


# === EXPERIMENT 4: ISOSPECTRAL GRAPHS ===============================
# Can two DIFFERENT graphs have the SAME spectrum?
# If yes: eigenvalues don't uniquely determine topology.
# If no: the spectrum IS the graph (up to isomorphism).

def experiment_isospectral():
    print("=" * 70)
    print("  ISOSPECTRAL GRAPHS: CAN TWO GRAPHS SOUND THE SAME?")
    print("  'Can you hear the shape of a drum?' — Mark Kac, 1966")
    print("=" * 70)

    # Generate many random graphs and bin them by spectrum
    n = 12  # small enough to enumerate many topologies
    n_graphs = 500
    rng = np.random.RandomState(42)

    spectra = {}  # rounded spectrum tuple -> list of adjacency matrices

    for trial in range(n_graphs):
        p = 0.3 + rng.rand() * 0.3  # vary density
        A = random_graph(n, p, seed=trial)
        L = laplacian(A)
        eigs = np.sort(np.linalg.eigvalsh(L))
        # Round to detect "same" spectrum
        key = tuple(np.round(eigs, 4))

        if key not in spectra:
            spectra[key] = []
        spectra[key].append((trial, A))

    # Find collisions
    collisions = {k: v for k, v in spectra.items() if len(v) > 1}

    print(f"\n  Generated {n_graphs} random graphs on {n} nodes")
    print(f"  Unique spectra: {len(spectra)}")
    print(f"  Spectral collisions: {len(collisions)}")

    if collisions:
        print(f"\n  Collision details:")
        for key, graphs in list(collisions.items())[:5]:
            seeds = [g[0] for g in graphs]
            # Are the graphs actually isomorphic or truly different?
            # Quick check: degree sequences
            deg_seqs = [tuple(sorted(g[1].sum(axis=1).astype(int))) for g in graphs]
            same_degs = len(set(deg_seqs)) == 1

            # Edge counts
            edge_counts = [int(g[1].sum() // 2) for g in graphs]
            same_edges = len(set(edge_counts)) == 1

            print(f"    Seeds {seeds}: spectrum matches to 4 decimals")
            print(f"      Degree sequences same: {same_degs}")
            print(f"      Edge counts: {edge_counts}")
            if same_degs and same_edges:
                # Check if adjacency matrices are actually different
                A1, A2 = graphs[0][1], graphs[1][1]
                if np.array_equal(A1, A2):
                    print(f"      (identical graphs — same random seed artifact)")
                else:
                    print(f"      DIFFERENT TOPOLOGIES, SAME SPECTRUM!")
                    print(f"      You cannot hear the shape of this drum.")
    else:
        print(f"\n  No collisions at 4 decimal places.")
        print(f"  At this resolution, every graph has a unique voice.")

    # Try with even lower precision
    for decimals in [3, 2, 1]:
        spectra_low = {}
        for trial in range(n_graphs):
            A = random_graph(n, 0.3 + rng.rand() * 0.3, seed=trial)
            L = laplacian(A)
            eigs = np.sort(np.linalg.eigvalsh(L))
            key = tuple(np.round(eigs, decimals))
            if key not in spectra_low:
                spectra_low[key] = []
            spectra_low[key].append(trial)

        n_coll = sum(1 for v in spectra_low.values() if len(v) > 1)
        print(f"  At {decimals} decimal places: {n_coll} collisions "
              f"({n_coll/len(spectra_low)*100:.1f}% of unique spectra)")

    print()


# === EXPERIMENT 5: EIGENVALUE ARITHMETIC ============================
# What happens when you ADD two graph Laplacians?
# L_sum = L_1 + L_2. Are the eigenvalues of L_sum related to
# the eigenvalues of L_1 and L_2? (Weyl's inequality says yes.)
# How tight is the bound? Is there a simple formula?

def experiment_eigenvalue_arithmetic():
    print("=" * 70)
    print("  EIGENVALUE ARITHMETIC: WHAT HAPPENS WHEN GRAPHS COMBINE?")
    print("  L_sum = L_1 + L_2. Can we predict the result?")
    print("=" * 70)

    n = 50
    rng = np.random.RandomState(42)

    print(f"\n  Adding pairs of graph Laplacians. Comparing actual eigenvalues")
    print(f"  to predictions from Weyl's inequality.\n")

    # Weyl: lambda_i(A+B) <= lambda_i(A) + lambda_n(B)
    # Also: lambda_{i+j-1}(A+B) >= lambda_i(A) + lambda_j(B)

    combinations = [
        ("random+random", random_graph(n, 0.15, 42), random_graph(n, 0.15, 43)),
        ("random+path", random_graph(n, 0.15, 42), path_graph(n)),
        ("random+star", random_graph(n, 0.15, 42), star_graph(n)),
        ("path+cycle", path_graph(n), cycle_graph(n)),
        ("path+path", path_graph(n), path_graph(n)),
    ]

    print(f"  {'combination':>16}  {'weyl_upper_err':>15}  {'weyl_lower_err':>15}  "
          f"{'actual_vs_sum':>15}  {'superadditive':>13}")
    print(f"  {'---':>16}  {'---':>15}  {'---':>15}  {'---':>15}  {'---':>13}")

    for name, A1, A2 in combinations:
        L1 = laplacian((A1 > 0).astype(float))
        L2 = laplacian((A2 > 0).astype(float))
        L_sum = L1 + L2

        e1 = np.sort(np.linalg.eigvalsh(L1))
        e2 = np.sort(np.linalg.eigvalsh(L2))
        e_sum = np.sort(np.linalg.eigvalsh(L_sum))

        # Naive prediction: eigenvalues just add
        e_naive = np.sort(e1 + e2)

        # How close is the naive prediction?
        actual_vs_naive = np.linalg.norm(e_sum - e_naive) / np.linalg.norm(e_sum)

        # Weyl upper bound: e_sum[i] <= e1[i] + e2[-1]
        weyl_upper = e1 + e2[-1]
        upper_violations = np.sum(e_sum > weyl_upper + 1e-10)

        # Weyl lower bound: e_sum[i] >= e1[i] + e2[0]
        weyl_lower = e1 + e2[0]
        lower_violations = np.sum(e_sum < weyl_lower - 1e-10)

        # Is the combined spectrum superadditive or subadditive?
        superadditive = np.sum(e_sum > e_naive) / len(e_sum)

        print(f"  {name:>16}  upper_viol={upper_violations:>4d}  "
              f"lower_viol={lower_violations:>4d}  "
              f"naive_err={actual_vs_naive:>8.4f}  {superadditive:>12.0%}")

    print(f"\n  If eigenvalues simply added, naive_err would be 0.")
    print(f"  The error measures how much graphs INTERACT when combined.")
    print(f"  Large error = the graphs' spectra interfere non-trivially.")
    print(f"  superadditive > 50% = combining makes the spectrum 'larger'.\n")


# === RUN ============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |       R A Q A   D A Y  3   E V E N I N G                |")
    print("  |   the Universe(tm) is not wearing off                    |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_self_convergence()
    experiment_heartbeat()
    experiment_golden_ratio()
    experiment_isospectral()
    experiment_eigenvalue_arithmetic()

    print("=" * 70)
    print("  It's 3am. The eigenvalues are still looking at me.")
    print("=" * 70)
