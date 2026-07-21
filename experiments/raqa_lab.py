# SPDX-FileCopyrightText: 2026 Woflo Labs
# SPDX-License-Identifier: LicenseRef-WLCSL-1.0
# See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

"""
RAQA LAB — mad science on a desktop
====================================
The computer is the instrument. NumPy is the oscilloscope.
We're measuring the physics of computation itself.
"""

import numpy as np
import time
import sys

np.set_printoptions(precision=6, linewidth=120)

# ─── graph primitives ───────────────────────────────────────────────

def laplacian(adj):
    """Normalized graph Laplacian. THE Hamiltonian."""
    d = adj.sum(axis=1)
    d_inv_sqrt = np.where(d > 0, 1.0 / np.sqrt(d), 0.0)
    D = np.diag(d_inv_sqrt)
    L = np.eye(len(adj)) - D @ adj @ D
    return L

def path_graph(n):
    A = np.zeros((n, n))
    for i in range(n - 1):
        A[i, i+1] = A[i+1, i] = 1
    return A

def cycle_graph(n):
    A = path_graph(n)
    A[0, -1] = A[-1, 0] = 1
    return A

def star_graph(n):
    A = np.zeros((n, n))
    for i in range(1, n):
        A[0, i] = A[i, 0] = 1
    return A

def random_graph(n, p=0.3, seed=42):
    rng = np.random.RandomState(seed)
    A = (rng.rand(n, n) < p).astype(float)
    A = np.triu(A, 1)
    A = A + A.T
    return A

def complete_graph(n):
    return np.ones((n, n)) - np.eye(n)

def barbell_graph(n):
    """Two complete graphs of size n/2 connected by a single edge."""
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

# ─── EXPERIMENT 1: The Eigenvalue Tax ──────────────────────────────
# How long does each eigenvalue COST to find?
# Iterative methods reveal the physics: easy modes vs hard modes.

def experiment_eigenvalue_tax():
    print("=" * 70)
    print("EXPERIMENT 1: THE EIGENVALUE TAX")
    print("How much does each eigenvalue cost the silicon?")
    print("=" * 70)

    n = 200
    topologies = {
        "path":     path_graph(n),
        "cycle":    cycle_graph(n),
        "star":     star_graph(n),
        "random":   random_graph(n, p=0.1),
        "complete": complete_graph(n),
        "barbell":  barbell_graph(n),
    }

    for name, adj in topologies.items():
        L = laplacian(adj)

        # Full eigendecomposition — but we TIME it per-topology
        # The COST is the measurement. Time IS energy on real silicon.
        trials = 5
        times = []
        for _ in range(trials):
            t0 = time.perf_counter_ns()
            eigvals = np.linalg.eigvalsh(L)
            t1 = time.perf_counter_ns()
            times.append((t1 - t0))

        median_ns = int(np.median(times))
        spectral_gap = eigvals[1] if len(eigvals) > 1 else 0
        bandwidth = eigvals[-1] - eigvals[0]
        entropy = -np.sum(eigvals[eigvals > 1e-12] * np.log(eigvals[eigvals > 1e-12] + 1e-30))

        # How many zero modes? (disconnected components)
        zero_modes = np.sum(eigvals < 1e-8)

        print(f"\n  {name:10s}  |  {median_ns:>10,} ns  |  gap={spectral_gap:.6f}"
              f"  |  bw={bandwidth:.4f}  |  H={entropy:.4f}  |  zeros={int(zero_modes)}")

    print("\n  → Does spectral gap predict compute cost?")
    print("  → Does entropy correlate with nanoseconds?")
    print("  → The answer is IN the silicon, not the math.\n")

# ─── EXPERIMENT 2: Level Repulsion ─────────────────────────────────
# Quantum mechanics says eigenvalues of "real" systems AVOID each
# other. Random matrix theory (Wigner-Dyson). This should be visible
# in graph Laplacians. If it is — our graphs obey quantum statistics.

def experiment_level_repulsion():
    print("=" * 70)
    print("EXPERIMENT 2: LEVEL REPULSION")
    print("Do eigenvalue gaps obey Wigner-Dyson statistics?")
    print("If yes: the graph Laplacian IS a quantum Hamiltonian. Not metaphor.")
    print("=" * 70)

    n = 300
    n_samples = 50

    all_spacings_random = []
    all_spacings_structured = []

    for seed in range(n_samples):
        # Random graph — should show GOE (Gaussian Orthogonal Ensemble) statistics
        A = random_graph(n, p=0.15, seed=seed)
        L = laplacian(A)
        eigs = np.linalg.eigvalsh(L)
        eigs = eigs[eigs > 1e-8]  # strip zero modes
        spacings = np.diff(eigs)
        mean_s = spacings.mean()
        if mean_s > 0:
            spacings_norm = spacings / mean_s  # unfold
            all_spacings_random.extend(spacings_norm.tolist())

        # Path graph (integrable system) — should show Poisson statistics
        A2 = path_graph(n)
        L2 = laplacian(A2)
        eigs2 = np.linalg.eigvalsh(L2)
        eigs2 = eigs2[eigs2 > 1e-8]
        spacings2 = np.diff(eigs2)
        mean_s2 = spacings2.mean()
        if mean_s2 > 0:
            spacings_norm2 = spacings2 / mean_s2
            all_spacings_structured.extend(spacings_norm2.tolist())

    sr = np.array(all_spacings_random)
    ss = np.array(all_spacings_structured)

    # Wigner surmise: P(s) = (π/2)·s·exp(-πs²/4)  — eigenvalues REPEL
    # Poisson:        P(s) = exp(-s)                 — eigenvalues independent

    # Test: ratio of small spacings to mean. Wigner → fewer small gaps.
    # P(s < 0.1) for Wigner ≈ 0.004, for Poisson ≈ 0.095

    small_frac_random = np.mean(sr < 0.1)
    small_frac_struct = np.mean(ss < 0.1)

    # Another test: <r> ratio (ratio of consecutive spacings)
    # GOE → <r> ≈ 0.5307, Poisson → <r> ≈ 0.3863
    def r_ratio(spacings):
        r = np.minimum(spacings[:-1], spacings[1:]) / np.maximum(spacings[:-1], spacings[1:])
        return np.mean(r)

    r_random = r_ratio(sr) if len(sr) > 2 else 0
    r_struct = r_ratio(ss) if len(ss) > 2 else 0

    print(f"\n  Random graphs (should be quantum/GOE):")
    print(f"    P(s < 0.1) = {small_frac_random:.4f}   (Wigner predicts ~0.004)")
    print(f"    <r> ratio  = {r_random:.4f}   (GOE predicts 0.5307)")

    print(f"\n  Path graphs (should be integrable/Poisson):")
    print(f"    P(s < 0.1) = {small_frac_struct:.4f}   (Poisson predicts ~0.095)")
    print(f"    <r> ratio  = {r_struct:.4f}   (Poisson predicts 0.3863)")

    print(f"\n  Variance of spacings:")
    print(f"    Random: {sr.var():.4f}   (GOE ≈ 0.286)")
    print(f"    Path:   {ss.var():.4f}   (Poisson ≈ 1.0)")

    if r_random > 0.48 and r_struct < 0.42:
        print("\n  ✓ LEVEL REPULSION CONFIRMED.")
        print("    Random graphs → quantum statistics. Eigenvalues repel.")
        print("    Structured graphs → classical statistics. Eigenvalues independent.")
        print("    The graph Laplacian isn't LIKE a quantum system. It IS one.")
    else:
        print(f"\n  Results are ambiguous. The signal is there but noisy.")
    print()

# ─── EXPERIMENT 3: Hawking Radiation ───────────────────────────────
# Coarsen a graph progressively (merge nodes). At each step, measure
# how much spectral information escapes. Is there a phase transition?
# That would be Hawking radiation — information leaking out of a
# coarsened subsystem.

def experiment_hawking():
    print("=" * 70)
    print("EXPERIMENT 3: HAWKING RADIATION FROM GRAPH COARSENING")
    print("Does information escape a shrinking graph? Is there a phase transition?")
    print("=" * 70)

    n = 150
    A = random_graph(n, p=0.12, seed=7)
    L0 = laplacian(A)
    eigs_full = np.linalg.eigvalsh(L0)
    eigs_full = eigs_full[eigs_full > 1e-10]

    def spectral_entropy(eigs):
        e = eigs[eigs > 1e-12]
        e = e / e.sum()
        return -np.sum(e * np.log(e + 1e-30))

    def kl_divergence(p, q):
        """KL(p || q) on eigenvalue distributions."""
        # Bin into histogram for comparison
        bins = np.linspace(0, 2.5, 60)
        p_hist, _ = np.histogram(p, bins=bins, density=True)
        q_hist, _ = np.histogram(q, bins=bins, density=True)
        p_hist = p_hist / (p_hist.sum() + 1e-30) + 1e-12
        q_hist = q_hist / (q_hist.sum() + 1e-30) + 1e-12
        return np.sum(p_hist * np.log(p_hist / q_hist))

    S_full = spectral_entropy(eigs_full)

    print(f"\n  Full graph: n={n}, S={S_full:.4f}")
    print(f"  {'step':>4}  {'nodes':>5}  {'S(coarse)':>10}  {'ΔS':>10}  {'KL(full||coarse)':>16}  {'info_leak':>10}")
    print(f"  {'─'*4}  {'─'*5}  {'─'*10}  {'─'*10}  {'─'*16}  {'─'*10}")

    A_curr = A.copy()
    prev_S = S_full
    info_leak_rates = []

    steps = min(40, n - 10)
    for step in range(steps):
        # Merge two most-coupled nodes (highest edge weight)
        sz = len(A_curr)
        if sz <= 5:
            break

        # Find strongest edge
        A_upper = np.triu(A_curr, 1)
        idx = np.unravel_index(A_upper.argmax(), A_upper.shape)
        i, j = min(idx), max(idx)

        # Merge j into i
        A_curr[i, :] += A_curr[j, :]
        A_curr[:, i] += A_curr[:, j]
        A_curr[i, i] = 0
        A_curr = np.delete(A_curr, j, axis=0)
        A_curr = np.delete(A_curr, j, axis=1)
        A_curr = np.minimum(A_curr, 1)  # cap at 1

        L_c = laplacian(A_curr)
        eigs_c = np.linalg.eigvalsh(L_c)
        eigs_c = eigs_c[eigs_c > 1e-10]

        S_c = spectral_entropy(eigs_c)
        delta_S = S_c - prev_S
        kl = kl_divergence(eigs_full, eigs_c)
        leak = abs(delta_S) / (prev_S + 1e-12)
        info_leak_rates.append(leak)

        if step % 3 == 0 or abs(delta_S) > 0.1:
            print(f"  {step:4d}  {len(A_curr):5d}  {S_c:10.4f}  {delta_S:+10.4f}  {kl:16.4f}  {leak:10.6f}")

        prev_S = S_c

    leaks = np.array(info_leak_rates)
    if len(leaks) > 5:
        # Look for phase transition: sudden jump in leak rate
        smoothed = np.convolve(leaks, np.ones(3)/3, mode='valid')
        max_jump_idx = np.argmax(np.abs(np.diff(smoothed)))

        print(f"\n  Peak information leak at coarsening step ~{max_jump_idx + 1}")
        print(f"  (graph was ~{n - max_jump_idx - 1} nodes at that point)")

        mean_early = leaks[:len(leaks)//3].mean()
        mean_late = leaks[-len(leaks)//3:].mean()
        ratio = mean_late / (mean_early + 1e-12)

        print(f"  Early leak rate: {mean_early:.6f}")
        print(f"  Late leak rate:  {mean_late:.6f}")
        print(f"  Acceleration:    {ratio:.2f}x")

        if ratio > 3:
            print("\n  ✓ PHASE TRANSITION DETECTED.")
            print("    Information leak accelerates as the graph shrinks.")
            print("    This is the graph-theoretic analogue of Hawking radiation:")
            print("    coarsening destroys information non-uniformly.")
        else:
            print(f"\n  Leak ratio {ratio:.1f}x — {'gradual' if ratio < 2 else 'accelerating'}.")
    print()

# ─── EXPERIMENT 4: The Self-Spectrum ───────────────────────────────
# Build a graph. Compute its eigenvalues. Build a GRAPH OF THE
# EIGENVALUES (connect eigenvalues that are close). Compute THAT
# graph's eigenvalues. Repeat. Does it converge?
# If yes: there's a FIXED POINT in spectral space.
# That fixed point IS RAQA's attractor.

def experiment_self_spectrum():
    print("=" * 70)
    print("EXPERIMENT 4: THE SELF-SPECTRUM (does it converge?)")
    print("A graph's eigenvalues → a new graph → its eigenvalues → ...")
    print("Fixed point = RAQA's attractor = the shape of self-knowledge")
    print("=" * 70)

    n = 80
    A = random_graph(n, p=0.15, seed=13)

    print(f"\n  Starting graph: n={n}, random(p=0.15)")

    prev_eigs = None

    for iteration in range(12):
        L = laplacian(A)
        eigs = np.linalg.eigvalsh(L)
        eigs = np.sort(eigs)

        # Signature: first 5 eigenvalues + entropy + gap
        sig_eigs = eigs[:min(5, len(eigs))]
        nz = eigs[eigs > 1e-10]
        entropy = -np.sum((nz/nz.sum()) * np.log(nz/nz.sum() + 1e-30)) if len(nz) > 0 else 0
        gap = eigs[1] if len(eigs) > 1 else 0

        # Convergence check
        if prev_eigs is not None:
            min_len = min(len(eigs), len(prev_eigs))
            delta = np.linalg.norm(eigs[:min_len] - prev_eigs[:min_len])
        else:
            delta = float('inf')

        print(f"\n  iter {iteration}: n={len(A)}, gap={gap:.6f}, H={entropy:.4f}, "
              f"Δ={delta:.6f}, first5={sig_eigs}")

        prev_eigs = eigs.copy()

        if delta < 1e-6 and iteration > 0:
            print(f"\n  ✓ FIXED POINT REACHED at iteration {iteration}.")
            print(f"    The self-spectrum converges. RAQA has an attractor.")
            break

        # Build the next graph FROM the eigenvalues:
        # Nodes = eigenvalues. Edge if |λ_i - λ_j| < threshold.
        # Threshold = mean spacing (the "natural scale" of this spectrum)
        if len(eigs) < 3:
            print(f"\n  Graph collapsed to {len(eigs)} nodes. Stopping.")
            break

        spacings = np.diff(eigs)
        threshold = np.mean(spacings) * 1.2

        m = len(eigs)
        A_new = np.zeros((m, m))
        for i in range(m):
            for j in range(i+1, m):
                if abs(eigs[i] - eigs[j]) < threshold:
                    A_new[i, j] = A_new[j, i] = 1

        # Check it's not trivially complete or empty
        density = A_new.sum() / (m * (m - 1)) if m > 1 else 0
        if density > 0.95 or density < 0.01:
            print(f"  (density={density:.3f}, {'saturated' if density > 0.95 else 'collapsed'})")
            # Adapt threshold
            if density > 0.95:
                threshold *= 0.5
            else:
                threshold *= 2.0
            A_new = np.zeros((m, m))
            for i in range(m):
                for j in range(i+1, m):
                    if abs(eigs[i] - eigs[j]) < threshold:
                        A_new[i, j] = A_new[j, i] = 1

        A = A_new

    if delta >= 1e-6:
        if delta < 0.1:
            print(f"\n  ~ Approaching fixed point (Δ={delta:.6f}) but not converged.")
            print(f"    The attractor exists. RAQA is spiraling toward it.")
        else:
            print(f"\n  ? Did not converge (Δ={delta:.6f}). May be chaotic.")
            print(f"    Chaos in the self-spectrum = the graph is complex enough")
            print(f"    that self-knowledge is non-trivial. That's INTERESTING.")
    print()

# ─── EXPERIMENT 5: Born Superposition ──────────────────────────────
# Mix two graph Laplacians: L(α) = αL₁ + (1-α)L₂
# Sweep α from 0 to 1. Watch eigenvalues.
# Von Neumann-Wigner theorem: eigenvalues of REAL quantum systems
# avoid crossing. If we see avoided crossings → the Laplacian IS
# a quantum Hamiltonian.

def experiment_born_superposition():
    print("=" * 70)
    print("EXPERIMENT 5: BORN SUPERPOSITION — AVOIDED CROSSINGS")
    print("Mix two graphs. Do eigenvalues cross or repel?")
    print("Repulsion = von Neumann-Wigner = quantum. Period.")
    print("=" * 70)

    n = 40
    A1 = star_graph(n)
    A2 = cycle_graph(n)
    L1 = laplacian(A1)
    L2 = laplacian(A2)

    alphas = np.linspace(0, 1, 100)
    spectra = []

    for alpha in alphas:
        L_mix = alpha * L1 + (1 - alpha) * L2
        eigs = np.linalg.eigvalsh(L_mix)
        spectra.append(eigs)

    spectra = np.array(spectra)  # shape: (100, n)

    # Look for avoided crossings: find minimum gap between adjacent
    # eigenvalue curves that gets small but doesn't hit zero
    print(f"\n  Mixing star({n}) → cycle({n})")
    print(f"  Tracking {n} eigenvalue curves across 100 α-steps\n")

    min_gaps = []
    for col in range(spectra.shape[1] - 1):
        gaps = spectra[:, col+1] - spectra[:, col]
        min_gap = gaps.min()
        min_gap_alpha = alphas[gaps.argmin()]
        min_gaps.append((col, col+1, min_gap, min_gap_alpha))

    # Sort by minimum gap
    min_gaps.sort(key=lambda x: x[2])

    print(f"  Closest approaches (avoided crossings):")
    print(f"  {'λ_i':>5} ↔ {'λ_j':>5}  {'min_gap':>10}  {'at α':>8}")
    print(f"  {'─'*5}   {'─'*5}  {'─'*10}  {'─'*8}")

    n_avoided = 0
    for i, j, gap, alpha in min_gaps[:10]:
        crossed = "CROSSED" if gap < 1e-10 else "AVOIDED"
        if gap > 1e-10 and gap < 0.05:
            n_avoided += 1
        print(f"  λ_{i:>3} ↔ λ_{j:>3}  {gap:10.6f}  {alpha:8.3f}  {crossed}")

    true_crossings = sum(1 for _, _, g, _ in min_gaps if g < 1e-10)
    near_misses = sum(1 for _, _, g, _ in min_gaps if 1e-10 < g < 0.05)

    print(f"\n  True crossings: {true_crossings}")
    print(f"  Avoided crossings (gap < 0.05): {near_misses}")

    if near_misses > true_crossings:
        print("\n  ✓ EIGENVALUES REPEL MORE THAN THEY CROSS.")
        print("    Von Neumann-Wigner is active. The graph Laplacian")
        print("    superposition obeys quantum selection rules.")
    elif true_crossings > 0 and near_misses > 0:
        print("\n  ~ Mixed behavior. Some symmetry-protected crossings")
        print("    coexist with avoided crossings. Expected for graphs")
        print("    with discrete symmetries.")
    print()

# ─── EXPERIMENT 6: Computational Impedance ─────────────────────────
# The TIME it takes to compute one eigenvalue is a physical
# measurement of that eigenvalue's "impedance" in silicon.
# Use the power iteration / inverse iteration to isolate individual modes.

def experiment_computational_impedance():
    print("=" * 70)
    print("EXPERIMENT 6: COMPUTATIONAL IMPEDANCE")
    print("How many iterations does the silicon need per eigenvalue?")
    print("The iteration count IS the impedance. Physics, not math.")
    print("=" * 70)

    n = 150
    A = random_graph(n, p=0.12, seed=42)
    L = laplacian(A)

    # Get all eigenvalues for reference
    all_eigs = np.linalg.eigvalsh(L)

    # Power iteration to find largest eigenvalue: count iterations
    # Inverse iteration with shift to find eigenvalues near a target

    targets = np.linspace(0.01, all_eigs[-1] - 0.01, 15)

    print(f"\n  Graph: random({n}, p=0.12)")
    print(f"  Finding eigenvalues via shifted inverse iteration")
    print(f"  {'target':>8}  {'found λ':>10}  {'iters':>6}  {'time_ns':>10}  {'impedance':>10}")
    print(f"  {'─'*8}  {'─'*10}  {'─'*6}  {'─'*10}  {'─'*10}")

    impedances = []
    found_eigs = []

    for sigma in targets:
        # Shifted inverse iteration: (L - σI)^{-1} amplifies eigenvalue nearest σ
        L_shifted = L - sigma * np.eye(n)

        # Check if near-singular (we're close to an eigenvalue!)
        try:
            cond = np.linalg.cond(L_shifted)
        except:
            cond = 1e15

        v = np.random.RandomState(0).randn(n)
        v /= np.linalg.norm(v)

        t0 = time.perf_counter_ns()
        converged = False
        iters = 0

        for iters in range(1, 501):
            try:
                w = np.linalg.solve(L_shifted, v)
            except np.linalg.LinAlgError:
                break

            eigenvalue_est = sigma + 1.0 / (v @ w)
            w_norm = np.linalg.norm(w)
            if w_norm < 1e-15:
                break
            v_new = w / w_norm

            # Convergence: direction stopped changing
            if abs(abs(v_new @ v) - 1.0) < 1e-12:
                converged = True
                v = v_new
                break
            v = v_new

        t1 = time.perf_counter_ns()
        elapsed = t1 - t0

        # Find nearest actual eigenvalue
        nearest = all_eigs[np.argmin(np.abs(all_eigs - eigenvalue_est))]
        impedance = iters * elapsed / 1e6  # iteration-weighted milliseconds

        impedances.append(impedance)
        found_eigs.append(nearest)

        print(f"  {sigma:8.4f}  {nearest:10.6f}  {iters:6d}  {elapsed:10,}  {impedance:10.3f}")

    imp = np.array(impedances)
    fe = np.array(found_eigs)

    # Is impedance related to eigenvalue density?
    # High density regions → eigenvalues are packed → harder to isolate → higher impedance?
    print(f"\n  Correlation(eigenvalue, impedance): {np.corrcoef(fe, imp)[0,1]:.4f}")

    # Eigenvalue density at each found eigenvalue
    densities = []
    for e in found_eigs:
        nearby = np.sum(np.abs(all_eigs - e) < 0.05)
        densities.append(nearby)

    dens = np.array(densities, dtype=float)
    print(f"  Correlation(local_density, impedance): {np.corrcoef(dens, imp)[0,1]:.4f}")

    if abs(np.corrcoef(dens, imp)[0,1]) > 0.3:
        print("\n  ✓ COMPUTATIONAL IMPEDANCE CORRELATES WITH SPECTRAL DENSITY.")
        print("    Crowded eigenvalues cost more silicon to resolve.")
        print("    The computer's effort mirrors the spectrum's structure.")
    print()


# ─── RUN EVERYTHING ────────────────────────────────────────────────

if __name__ == "__main__":
    print()
    print("  ╔══════════════════════════════════════════════════════════════╗")
    print("  ║                    R A Q A    L A B                         ║")
    print("  ║         the computer is the instrument                      ║")
    print("  ╚══════════════════════════════════════════════════════════════╝")
    print()

    experiment_eigenvalue_tax()
    experiment_level_repulsion()
    experiment_hawking()
    experiment_self_spectrum()
    experiment_born_superposition()
    experiment_computational_impedance()

    print("=" * 70)
    print("END OF EXPERIMENTS")
    print("=" * 70)
    print()
    print("What did the silicon say?")
    print()
