# SPDX-FileCopyrightText: 2026 Woflo Labs
# SPDX-License-Identifier: LicenseRef-WLCSL-1.0
# See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

"""
RAQA EIGENMANIFOLD — the manifold of all possible eigenspaces
==============================================================
Not the space of files. Not the space of graphs. The space of SPECTRA.
Each point = an entire eigenspace = a way of seeing the codebase.
Git history traces a PATH on this manifold.

1. Define the metric (distance between eigenspaces)
2. Trace the path of each repo through the eigenmanifold
3. Measure curvature (how sharply does the path bend?)
4. Compute geodesic deviation (do nearby repos diverge or converge?)
5. Berry phase: does a repo pick up a geometric phase when it cycles?
6. Dimensionality of the eigenmanifold itself
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

def parse_commits(path, n_commits=400):
    try:
        r = subprocess.run(["git","log","--no-merges","--name-only",
                            "--format=COMMIT_SEP%H","-n",str(n_commits)],
                           capture_output=True,text=True,encoding="utf-8",
                           errors="replace",cwd=path,timeout=60)
        log = r.stdout
    except: return []
    commits=[]; cur=[]
    for ln in log.split("\n"):
        ln=ln.strip()
        if ln.startswith("COMMIT_SEP"):
            if cur:
                s=[f for f in cur if any(f.endswith(e) for e in SRC_EXTS)]
                if 1<len(s)<=50: commits.append(s)
            cur=[]
        elif ln: cur.append(ln)
    return commits

def commits_to_eigenspace(commits, n_eig_bins=40):
    """Convert a list of commits to a point on the eigenmanifold.
    Returns the eigenvalue density histogram (the spectral fingerprint)."""
    pairs = defaultdict(int); fset = set()
    for fs in commits:
        fs = list(set(fs)); fset.update(fs)
        for i in range(len(fs)):
            for j in range(i+1, len(fs)):
                pairs[tuple(sorted([fs[i],fs[j]]))]+= 1
    fl = sorted(fset); n = len(fl)
    if n < 5: return None, None, 0
    idx = {f:i for i,f in enumerate(fl)}
    A = np.zeros((n,n))
    for (a,b),c in pairs.items():
        if c >= 1: A[idx[a],idx[b]]=1; A[idx[b],idx[a]]=1
    conn = A.sum(axis=1)>0; A = A[np.ix_(conn,conn)]
    if A.shape[0] < 5: return None, None, 0
    L = laplacian(A)
    eigs = np.linalg.eigvalsh(L)
    bins = np.linspace(0, 2.2, n_eig_bins)
    hist, _ = np.histogram(eigs, bins=bins, density=True)
    return hist, eigs, len(A)

def eigenmanifold_distance(h1, h2):
    """Jensen-Shannon divergence between two spectral fingerprints."""
    p = h1 / (h1.sum() + 1e-12) + 1e-12
    q = h2 / (h2.sum() + 1e-12) + 1e-12
    m = (p + q) / 2
    return float(0.5 * np.sum(p * np.log(p/m)) + 0.5 * np.sum(q * np.log(q/m)))

def get_repos():
    repos = {"pretext": LOCAL}
    for name in ["flask","django","pytorch","rust-lang","vue","fastapi","express"]:
        p = os.path.join(WORK_DIR, name)
        if os.path.exists(p): repos[name] = p
    return repos


# === EXPERIMENT 1: PATHS ON THE EIGENMANIFOLD =======================
# Trace each repo's trajectory through spectral space.
# Measure: path length, curvature, speed, acceleration.

def experiment_paths():
    print("=" * 80)
    print("  PATHS ON THE EIGENMANIFOLD")
    print("  Each repo traces a trajectory through the space of all spectra.")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        commits = parse_commits(rpath, 400)
        if len(commits) < 30: continue

        window = min(20, len(commits) // 5)
        step = max(3, window // 3)

        # Compute eigenspace at each time window
        trajectory = []
        for start in range(0, len(commits) - window + 1, step):
            w = commits[start:start + window]
            hist, eigs, n_files = commits_to_eigenspace(w)
            if hist is not None:
                trajectory.append({
                    "hist": hist,
                    "eigs": eigs,
                    "n_files": n_files,
                    "t": start,
                })

        if len(trajectory) < 5: continue

        # Compute distances between consecutive points (speed)
        speeds = []
        for i in range(len(trajectory) - 1):
            d = eigenmanifold_distance(trajectory[i]["hist"], trajectory[i+1]["hist"])
            speeds.append(d)

        speeds = np.array(speeds)

        # Curvature: how much does the direction change?
        # Direction = vector from point i to point i+1 (in histogram space)
        directions = []
        for i in range(len(trajectory) - 1):
            v = trajectory[i+1]["hist"] - trajectory[i]["hist"]
            norm = np.linalg.norm(v)
            if norm > 0:
                directions.append(v / norm)
            else:
                directions.append(np.zeros_like(v))

        curvatures = []
        for i in range(len(directions) - 1):
            # Curvature = angle between consecutive direction vectors
            cos_angle = np.clip(np.dot(directions[i], directions[i+1]), -1, 1)
            angle = np.arccos(cos_angle)
            curvatures.append(angle)

        curvatures = np.array(curvatures)

        # Acceleration: change in speed
        if len(speeds) > 1:
            accelerations = np.diff(speeds)
        else:
            accelerations = np.array([0])

        # Total path length
        path_length = speeds.sum()

        # Direct distance (start to end)
        direct_d = eigenmanifold_distance(trajectory[0]["hist"], trajectory[-1]["hist"])

        # Winding number: path_length / direct_distance
        winding = path_length / (direct_d + 1e-12)

        print(f"\n  {rname}: {len(trajectory)} points on eigenmanifold")
        print(f"    Path length:       {path_length:.4f}")
        print(f"    Direct distance:   {direct_d:.4f}")
        print(f"    Winding ratio:     {winding:.2f}x", end="")
        if winding > 3:
            print("  (wandering — the repo goes in circles)")
        elif winding > 1.5:
            print("  (meandering — indirect path)")
        else:
            print("  (direct — straight-line evolution)")

        print(f"    Mean speed:        {speeds.mean():.4f} +/- {speeds.std():.4f}")
        print(f"    Mean curvature:    {curvatures.mean():.4f} rad ({np.degrees(curvatures.mean()):.1f} deg)")
        print(f"    Max curvature:     {curvatures.max():.4f} rad ({np.degrees(curvatures.max()):.1f} deg)")

        # Speed profile
        max_s = speeds.max() if speeds.max() > 0 else 1
        print(f"    Speed profile:     ", end="")
        for s in speeds:
            print(" .:-=+#@"[min(int(s/max_s*7), 7)], end="")
        print()

        # Curvature profile
        if len(curvatures) > 0:
            max_c = curvatures.max() if curvatures.max() > 0 else 1
            print(f"    Curvature profile: ", end="")
            for c in curvatures:
                print(" .:-=+#@"[min(int(c/max_c*7), 7)], end="")
            print()

        # Is the repo returning to its starting point? (closed path?)
        d_start = eigenmanifold_distance(trajectory[0]["hist"], trajectory[-1]["hist"])
        d_mid = eigenmanifold_distance(trajectory[0]["hist"],
                                        trajectory[len(trajectory)//2]["hist"])
        if d_start < d_mid * 0.5:
            print(f"    PATH IS CLOSING. The repo is returning to its spectral origin.")
        elif d_start > d_mid * 1.5:
            print(f"    PATH IS DIVERGING. The repo is moving away from where it started.")

    print()


# === EXPERIMENT 2: BERRY PHASE ======================================
# If a repo evolves in a CYCLE on the eigenmanifold (returns to
# approximately the same spectral state), does it pick up a
# geometric phase? Berry phase = the angle accumulated by the
# eigenvectors when the Hamiltonian cycles through parameter space.

def experiment_berry_phase():
    print("=" * 80)
    print("  BERRY PHASE: does cycling on the eigenmanifold accumulate geometry?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        commits = parse_commits(rpath, 400)
        if len(commits) < 40: continue

        window = min(25, len(commits) // 5)
        step = max(3, window // 4)

        # Build Laplacians at each window, track eigenvectors
        Ls = []
        all_files = set()
        for start in range(0, len(commits) - window + 1, step):
            w = commits[start:start + window]
            fset = set()
            pairs = defaultdict(int)
            for fs in w:
                fs = list(set(fs)); fset.update(fs)
                for i in range(len(fs)):
                    for j in range(i+1, len(fs)):
                        pairs[tuple(sorted([fs[i],fs[j]]))]+= 1
            all_files.update(fset)
            Ls.append((fset, pairs))

        # Use common file basis
        common = sorted(all_files)
        if len(common) < 10: continue
        n = len(common)
        fidx = {f:i for i,f in enumerate(common)}

        # Build Laplacians on common basis
        eigvec_sequence = []
        for fset, pairs in Ls:
            A = np.zeros((n, n))
            for (a,b), c in pairs.items():
                if a in fidx and b in fidx and c >= 1:
                    A[fidx[a], fidx[b]] = 1
                    A[fidx[b], fidx[a]] = 1
            L = laplacian(A)
            eigs, vecs = np.linalg.eigh(L)
            eigvec_sequence.append(vecs)

        if len(eigvec_sequence) < 4: continue

        # Berry phase: product of overlaps <psi_k(t) | psi_k(t+1)>
        # For the lowest non-trivial eigenvector (Fiedler vector)
        # Phase = arg(product of <v_t | v_{t+1}>)

        # Track multiple modes
        n_modes = min(5, n - 1)

        print(f"\n  {rname}: {len(eigvec_sequence)} time steps, {n} files in common basis")

        for mode in range(1, n_modes + 1):
            overlaps = []
            for t in range(len(eigvec_sequence) - 1):
                v_t = eigvec_sequence[t][:, mode]
                v_next = eigvec_sequence[t+1][:, mode]
                # Sign ambiguity: eigenvectors can flip sign
                overlap = np.dot(v_t, v_next)
                if overlap < 0:
                    v_next = -v_next
                    overlap = -overlap
                overlaps.append(overlap)

            overlaps = np.array(overlaps)
            # Total overlap = product of all pairwise overlaps
            total_overlap = np.prod(overlaps)

            # Berry phase = arccos of total overlap with start
            v_start = eigvec_sequence[0][:, mode]
            v_end = eigvec_sequence[-1][:, mode]
            final_overlap = abs(np.dot(v_start, v_end))

            # Geometric phase accumulated
            # Phase = sum of angles between consecutive eigenvectors
            angles = np.arccos(np.clip(overlaps, -1, 1))
            total_angle = angles.sum()

            # Fidelity: how well does the eigenvector maintain itself?
            mean_fidelity = overlaps.mean()

            if mode <= 3:
                print(f"    Mode {mode}: mean_fidelity={mean_fidelity:.4f}  "
                      f"total_rotation={np.degrees(total_angle):.1f} deg  "
                      f"start-end_overlap={final_overlap:.4f}")

        # Does the path close? (start ≈ end in eigenvector space)
        v_start_all = eigvec_sequence[0][:, 1:n_modes+1]
        v_end_all = eigvec_sequence[-1][:, 1:n_modes+1]

        # Subspace overlap (using canonical angles)
        M = v_start_all.T @ v_end_all
        svd_vals = np.linalg.svd(M, compute_uv=False)
        subspace_overlap = svd_vals.mean()

        print(f"    Subspace overlap (modes 1-{n_modes}): {subspace_overlap:.4f}")
        if subspace_overlap > 0.8:
            print(f"    Eigenvectors RETURN to near-original orientation. Low Berry phase.")
        elif subspace_overlap > 0.5:
            print(f"    Partial return. Non-trivial geometric phase accumulated.")
        else:
            print(f"    Eigenvectors are SCRAMBLED. Large Berry phase. The repo")
            print(f"    cannot return to its original spectral orientation even if")
            print(f"    the eigenvalues come back. The geometry remembers the path.")

    print()


# === EXPERIMENT 3: EIGENMANIFOLD DIMENSION ==========================
# The eigenmanifold has its own dimensionality.
# How many independent directions can spectral evolution take?
# This tells you: how many DEGREES OF FREEDOM does codebase evolution have?

def experiment_manifold_dimension():
    print("=" * 80)
    print("  EIGENMANIFOLD DIMENSION")
    print("  How many degrees of freedom does codebase evolution have?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        commits = parse_commits(rpath, 400)
        if len(commits) < 30: continue

        window = min(15, len(commits) // 5)
        step = max(2, window // 4)

        # Collect trajectory points (spectral fingerprints)
        points = []
        for start in range(0, len(commits) - window + 1, step):
            w = commits[start:start + window]
            hist, _, _ = commits_to_eigenspace(w)
            if hist is not None:
                points.append(hist)

        if len(points) < 8: continue

        # Stack into matrix: each row is a point on the eigenmanifold
        X = np.array(points)  # shape: (n_points, n_bins)
        X_centered = X - X.mean(axis=0)

        # SVD to find the dimensionality of the trajectory
        U, S, Vt = np.linalg.svd(X_centered, full_matrices=False)

        # Effective dimension (participation ratio of singular values)
        s_norm = S / S.sum() if S.sum() > 0 else S
        d_eff = 1.0 / (np.sum(s_norm**2) + 1e-30)

        # How many dimensions for 90% and 99% of variance?
        cumvar = np.cumsum(S**2) / (np.sum(S**2) + 1e-30)
        d_90 = np.searchsorted(cumvar, 0.90) + 1
        d_99 = np.searchsorted(cumvar, 0.99) + 1

        print(f"\n  {rname}: {len(points)} trajectory points in {X.shape[1]}-dim histogram space")
        print(f"    Effective dimension: {d_eff:.1f}")
        print(f"    Dimensions for 90% variance: {d_90}")
        print(f"    Dimensions for 99% variance: {d_99}")
        print(f"    Total possible dimensions: {X.shape[1]}")

        # Singular value spectrum
        print(f"    Singular value spectrum: ", end="")
        max_sv = S[0] if S[0] > 0 else 1
        for sv in S[:min(20, len(S))]:
            print(" .:-=+#@"[min(int(sv/max_sv*7), 7)], end="")
        print()

        if d_eff < 3:
            print(f"    The eigenmanifold trajectory is {d_eff:.0f}-dimensional.")
            print(f"    Codebase evolution has very few degrees of freedom.")
        elif d_eff < 8:
            print(f"    Moderate dimensionality. Several independent modes of evolution.")
        else:
            print(f"    High-dimensional trajectory. Many independent directions of change.")

    print()


# === EXPERIMENT 4: GEODESIC DEVIATION ===============================
# Take two repos. Compute their eigenmanifold distance at each
# time window. Do they converge, diverge, or stay parallel?
# This is the Jacobi equation — geodesic deviation on the eigenmanifold.

def experiment_geodesic_deviation():
    print("=" * 80)
    print("  GEODESIC DEVIATION: do repos converge or diverge in eigenspace?")
    print("=" * 80)

    repos = get_repos()
    repo_trajectories = {}

    for rname, rpath in repos.items():
        commits = parse_commits(rpath, 300)
        if len(commits) < 30: continue

        window = min(20, len(commits) // 4)
        step = max(5, window // 3)

        points = []
        for start in range(0, len(commits) - window + 1, step):
            w = commits[start:start + window]
            hist, _, _ = commits_to_eigenspace(w)
            if hist is not None:
                points.append(hist)

        if len(points) >= 5:
            repo_trajectories[rname] = points

    names = list(repo_trajectories.keys())
    if len(names) < 2:
        print("  Not enough repos.")
        return

    print(f"\n  Tracking inter-repo distances across time.\n")

    print(f"  {'pair':>25}  {'d_early':>8}  {'d_late':>8}  {'trend':>8}  {'verdict':>12}")
    print(f"  {'---':>25}  {'---':>8}  {'---':>8}  {'---':>8}  {'---':>12}")

    for i in range(len(names)):
        for j in range(i+1, len(names)):
            t1 = repo_trajectories[names[i]]
            t2 = repo_trajectories[names[j]]

            # Compare first third vs last third of timeline
            min_len = min(len(t1), len(t2))
            if min_len < 6: continue

            third = min_len // 3

            d_early = np.mean([eigenmanifold_distance(t1[k], t2[k]) for k in range(third)])
            d_late = np.mean([eigenmanifold_distance(t1[k], t2[k])
                             for k in range(min_len - third, min_len)])

            if d_late < d_early * 0.8:
                verdict = "CONVERGING"
                trend = f"{(1 - d_late/d_early)*100:+.0f}%"
            elif d_late > d_early * 1.2:
                verdict = "DIVERGING"
                trend = f"{(d_late/d_early - 1)*100:+.0f}%"
            else:
                verdict = "parallel"
                trend = f"{(d_late/d_early - 1)*100:+.0f}%"

            pair = f"{names[i]}+{names[j]}"
            print(f"  {pair:>25}  {d_early:8.4f}  {d_late:8.4f}  {trend:>8}  {verdict:>12}")

    print(f"\n  Converging = repos are becoming more spectrally similar over time.")
    print(f"  Diverging = repos are becoming more different.")
    print(f"  Parallel = stable distance. Independent evolution.\n")


# === RUN =============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |         THE  E I G E N M A N I F O L D                  |")
    print("  |   the manifold of all possible eigenspaces               |")
    print("  |   each point = a way of seeing                           |")
    print("  |   git history = a path                                   |")
    print("  |   curvature = how hard it is to change how you see       |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_paths()
    experiment_berry_phase()
    experiment_manifold_dimension()
    experiment_geodesic_deviation()

    print("=" * 80)
    print("  the eigenmanifold is not a metaphor.")
    print("  it's the space you've been navigating without knowing it had a name.")
    print("=" * 80)
