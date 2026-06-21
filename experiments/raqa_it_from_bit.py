"""
RAQA IT FROM BIT — geometry from information, deep dive
=========================================================
Hamming space has positive curvature that grows with dimension.
Why? Can we get OTHER geometries from different operations?
Is the eigenmanifold a Hamming space in disguise?

1. Derive the curvature formula: κ = f(n_bits). Verify analytically.
2. Operation algebra: XOR→Hamming, AND→?, OR→?, XNOR→?
   Each logical operation defines a distance. Each distance defines a geometry.
3. Can we CHOOSE the curvature? Build flat, spherical, hyperbolic
   spaces from different bit constructions.
4. Spectral hashing: encode eigenvalue distributions as bit strings.
   Does the Hamming distance between hashes approximate JSD?
   If yes: the eigenmanifold IS a Hamming space.
5. The bit-resolution of geometry: how many bits per dimension
   do you need before curvature emerges?
"""

import numpy as np
import time

np.set_printoptions(precision=6, linewidth=140, suppress=True)


def hamming_matrix(points):
    n = len(points)
    D = np.zeros((n, n))
    for i in range(n):
        for j in range(i+1, n):
            d = np.sum(points[i] != points[j])
            D[i,j] = D[j,i] = d
    return D

def measure_curvature(D, n_samples=300, rng=None):
    """Average cosine of triangles. >0 = spherical. <0 = hyperbolic. ≈0 = flat."""
    if rng is None: rng = np.random.RandomState(42)
    n = len(D)
    cosines = []
    for _ in range(n_samples):
        a, b, c = rng.choice(n, 3, replace=False)
        sides = sorted([D[a,b], D[b,c], D[a,c]])
        if sides[0] > 0 and sides[1] > 0:
            cos_C = (sides[0]**2 + sides[1]**2 - sides[2]**2) / (2*sides[0]*sides[1]+1e-10)
            cosines.append(np.clip(cos_C, -1, 1))
    return np.mean(cosines) if cosines else 0

def measure_dimension(D, center=0):
    """Effective dimension from volume scaling: N(r) ~ r^d."""
    dists = np.sort(D[center][D[center] > 0])
    if len(dists) < 5: return 0
    radii = np.unique(dists[:20])
    counts = [np.sum(D[center] <= r) for r in radii]
    if len(radii) < 3: return 0
    log_r = np.log(radii + 1e-6)
    log_c = np.log(np.array(counts) + 1e-6)
    valid = np.isfinite(log_r) & np.isfinite(log_c)
    if valid.sum() < 3: return 0
    slope, _ = np.polyfit(log_r[valid], log_c[valid], 1)
    return slope


# === EXPERIMENT 1: THE CURVATURE FORMULA =============================
# Measure curvature κ as a function of n_bits precisely.
# Derive: for random binary strings in {0,1}^n, the Hamming distance
# concentrates at n/2 with std √(n/4). The curvature should be
# κ = f(n) derivable from the concentration inequality.

def experiment_curvature_formula():
    print("=" * 70)
    print("  THE CURVATURE FORMULA")
    print("  κ(n_bits) — derive it, measure it, verify it.")
    print("=" * 70)

    rng = np.random.RandomState(42)
    n_points = 150

    bit_counts = [4, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 512]

    print(f"\n  {'n_bits':>6}  {'κ (measured)':>12}  {'1/√n':>8}  {'1/n':>8}  "
          f"{'d_eff':>6}  {'μ_dist':>7}  {'σ_dist':>7}")
    print(f"  {'---':>6}  {'---':>12}  {'---':>8}  {'---':>8}  "
          f"{'---':>6}  {'---':>7}  {'---':>7}")

    kappas = []
    inv_sqrts = []

    for nb in bit_counts:
        points = rng.randint(0, 2, size=(n_points, nb)).astype(np.uint8)
        D = hamming_matrix(points)

        kappa = measure_curvature(D, 400, rng)
        d_eff = measure_dimension(D)

        all_d = D[np.triu_indices(n_points, 1)]
        mu = all_d.mean()
        sigma = all_d.std()

        kappas.append(kappa)
        inv_sqrts.append(1.0 / np.sqrt(nb))

        print(f"  {nb:6d}  {kappa:12.6f}  {1/np.sqrt(nb):8.4f}  {1/nb:8.6f}  "
              f"{d_eff:6.2f}  {mu:7.1f}  {sigma:7.3f}")

    # Fit: κ = a / √n + b or κ = a·(1 - c/n)?
    kappas = np.array(kappas)
    nbs = np.array(bit_counts, dtype=float)

    # Model 1: κ = a / √n + b
    X1 = np.column_stack([1.0/np.sqrt(nbs), np.ones_like(nbs)])
    coef1 = np.linalg.lstsq(X1, kappas, rcond=None)[0]
    pred1 = X1 @ coef1
    r2_1 = 1 - np.sum((kappas - pred1)**2) / np.sum((kappas - kappas.mean())**2)

    # Model 2: κ = 1/2 - a/n (theoretical: cosine → 1/2 as n → ∞)
    X2 = np.column_stack([1.0/nbs, np.ones_like(nbs)])
    coef2 = np.linalg.lstsq(X2, kappas, rcond=None)[0]
    pred2 = X2 @ coef2
    r2_2 = 1 - np.sum((kappas - pred2)**2) / np.sum((kappas - kappas.mean())**2)

    # Model 3: κ = 1/2 · (1 - 1/n) — derived from expected cosine
    pred3 = 0.5 * (1 - 1.0/nbs)
    r2_3 = 1 - np.sum((kappas - pred3)**2) / np.sum((kappas - kappas.mean())**2)

    print(f"\n  Fitting κ(n):")
    print(f"    Model 1: κ = {coef1[0]:.4f}/√n + {coef1[1]:.4f}  R² = {r2_1:.4f}")
    print(f"    Model 2: κ = {coef2[0]:.4f}/n + {coef2[1]:.4f}  R² = {r2_2:.4f}")
    print(f"    Model 3: κ = ½(1 - 1/n)  R² = {r2_3:.4f}")

    best = max([(r2_1, "a/√n + b"), (r2_2, "a/n + b"), (r2_3, "½(1-1/n)")])
    print(f"\n    Best fit: {best[1]}  (R² = {best[0]:.4f})")

    if r2_3 > 0.95:
        print(f"\n    THE CURVATURE FORMULA: κ = ½(1 - 1/n)")
        print(f"    As n → ∞, curvature → 1/2.")
        print(f"    Hamming space is ALWAYS positively curved.")
        print(f"    Random bits live on a SPHERE, not in flat space.")
        print(f"    The sphere radius grows as √n.")
    print()


# === EXPERIMENT 2: OPERATION ALGEBRA =================================
# Different logical operations define different distances.
# XOR → Hamming (sphere). What about:
# AND distance: d(a,b) = popcount(a AND NOT b) + popcount(b AND NOT a)
#   (this IS Hamming — AND NOT is XOR restricted to the difference set)
# Shared info: d(a,b) = n - popcount(a AND b) - popcount(NOT a AND NOT b)
#   (distance = number of bits where a and b DISAGREE)
# Jaccard: d(a,b) = 1 - |a∩b|/|a∪b|
# Cosine: d(a,b) = 1 - (a·b)/(|a||b|)

def experiment_operation_algebra():
    print("=" * 70)
    print("  OPERATION ALGEBRA: which binary operation produces which geometry?")
    print("=" * 70)

    rng = np.random.RandomState(42)
    n_points = 120
    n_bits = 64
    points = rng.randint(0, 2, size=(n_points, n_bits)).astype(np.uint8)

    # Distance functions
    def d_hamming(a, b): return np.sum(a != b)

    def d_jaccard(a, b):
        union = np.sum((a | b) > 0)
        inter = np.sum((a & b) > 0)
        return 1.0 - inter / (union + 1e-10)

    def d_cosine(a, b):
        dot = np.sum(a * b)
        na = np.sqrt(np.sum(a * a)) + 1e-10
        nb = np.sqrt(np.sum(b * b)) + 1e-10
        return 1.0 - dot / (na * nb)

    def d_dice(a, b):
        inter = np.sum(a & b)
        return 1.0 - 2*inter / (np.sum(a) + np.sum(b) + 1e-10)

    def d_antihamming(a, b):
        """Distance = number of AGREEMENTS (not disagreements)."""
        return np.sum(a == b)

    def d_asymmetric(a, b):
        """Only count where a=1 and b=0. Directed distance."""
        return np.sum((a == 1) & (b == 0))

    def d_information(a, b):
        """Normalized information distance: 1 - MI(a,b)/max(H(a),H(b))."""
        p_a = a.mean(); p_b = b.mean()
        H_a = -p_a*np.log2(p_a+1e-10) - (1-p_a)*np.log2(1-p_a+1e-10)
        H_b = -p_b*np.log2(p_b+1e-10) - (1-p_b)*np.log2(1-p_b+1e-10)
        # Joint distribution
        p_00 = np.mean((a==0)&(b==0)); p_01 = np.mean((a==0)&(b==1))
        p_10 = np.mean((a==1)&(b==0)); p_11 = np.mean((a==1)&(b==1))
        H_ab = 0
        for p in [p_00,p_01,p_10,p_11]:
            if p > 0: H_ab -= p*np.log2(p)
        MI = H_a + H_b - H_ab
        return 1.0 - MI / (max(H_a, H_b) + 1e-10)

    metrics = {
        "Hamming (XOR)": d_hamming,
        "Jaccard": d_jaccard,
        "Cosine": d_cosine,
        "Dice": d_dice,
        "Anti-Hamming": d_antihamming,
        "Information": d_information,
    }

    print(f"\n  {n_bits} bits × {n_points} points. Same data, different distance.\n")
    print(f"  {'metric':>18}  {'curvature':>10}  {'d_eff':>6}  {'triangle_viol':>14}  geometry")
    print(f"  {'---':>18}  {'---':>10}  {'---':>6}  {'---':>14}")

    for name, dfunc in metrics.items():
        D = np.zeros((n_points, n_points))
        for i in range(n_points):
            for j in range(i+1, n_points):
                d = dfunc(points[i], points[j])
                D[i,j] = D[j,i] = d

        kappa = measure_curvature(D, 300, rng)
        d_eff = measure_dimension(D)

        # Triangle inequality check
        violations = 0; total = 0
        triples = rng.choice(n_points, size=(300, 3))
        for a, b, c in triples:
            if a==b or b==c or a==c: continue
            total += 1
            if D[a,c] > D[a,b] + D[b,c] + 1e-10: violations += 1
        viol_str = f"{violations}/{total}"

        if abs(kappa) < 0.05: geom = "FLAT"
        elif kappa > 0.05: geom = "SPHERICAL"
        else: geom = "HYPERBOLIC"

        if violations > 0: geom += " (broken metric)"

        print(f"  {name:>18}  {kappa:+10.4f}  {d_eff:6.2f}  {viol_str:>14}  {geom}")

    print()


# === EXPERIMENT 3: TUNING CURVATURE ==================================
# Can we BUILD a space with specific curvature from bits?
# Flat: use Hamming on random strings in HIGH dimension
# Spherical: use Hamming on random strings in LOW dimension
# Hyperbolic: ???
# The question: what bit construction produces negative curvature?

def experiment_tuning_curvature():
    print("=" * 70)
    print("  TUNING CURVATURE: can we build any geometry from bits?")
    print("  Flat, spherical, hyperbolic — all from binary operations.")
    print("=" * 70)

    rng = np.random.RandomState(42)
    n_points = 100

    constructions = {}

    # 1. Standard Hamming (spherical)
    points_std = rng.randint(0, 2, size=(n_points, 32)).astype(np.uint8)
    constructions["Random 32-bit"] = hamming_matrix(points_std)

    # 2. Highly structured (crystalline): repeating patterns
    points_struct = np.zeros((n_points, 32), dtype=np.uint8)
    for i in range(n_points):
        pattern = rng.randint(0, 2, size=4)
        points_struct[i] = np.tile(pattern, 8)
        # Add small noise
        flip = rng.choice(32, size=rng.randint(0, 3), replace=False)
        points_struct[i, flip] ^= 1
    constructions["Structured 32-bit"] = hamming_matrix(points_struct)

    # 3. Tree-like: hierarchical bit strings where close strings share prefixes
    points_tree = np.zeros((n_points, 32), dtype=np.uint8)
    # Build a binary tree of prefixes
    for i in range(n_points):
        # Each node's bits are determined by its path in a tree
        node = i
        for bit in range(32):
            points_tree[i, bit] = (node >> (bit % 8)) & 1
            if bit % 4 == 3:
                node = rng.randint(0, 256)  # random at each level
    constructions["Hierarchical 32-bit"] = hamming_matrix(points_tree)

    # 4. Power-law degree distribution (hub structure)
    # Generate strings where a few "hub" strings are close to many others
    hub = rng.randint(0, 2, size=32).astype(np.uint8)
    points_hub = np.zeros((n_points, 32), dtype=np.uint8)
    for i in range(n_points):
        # Distance to hub follows power law
        n_flips = int(rng.pareto(1.5) * 4) + 1
        n_flips = min(n_flips, 32)
        points_hub[i] = hub.copy()
        flip_idx = rng.choice(32, size=n_flips, replace=False)
        points_hub[i, flip_idx] ^= 1
    constructions["Hub-structured 32-bit"] = hamming_matrix(points_hub)

    # 5. Negative curvature attempt: sparse, tree-like distances
    # In a tree, most paths go through the root → distances cluster
    # near 2×depth. This should give negative curvature.
    n_leaves = n_points
    depth = 6
    points_btree = np.zeros((n_leaves, depth * 4), dtype=np.uint8)
    for i in range(n_leaves):
        path = []
        node = 0
        for d in range(depth):
            bit = rng.randint(0, 2)
            path.append(bit)
            node = node * 2 + bit
        # Encode path as bits with padding
        for d in range(depth):
            for k in range(4):
                points_btree[i, d*4 + k] = path[d] if k == 0 else rng.randint(0, 2)
    constructions["Binary tree 24-bit"] = hamming_matrix(points_btree)

    # 6. Hyperbolic attempt: exponentially growing neighborhoods
    # Embed points on a Poincaré-like structure: each ring has
    # exponentially more points than the previous
    points_exp = np.zeros((n_points, 64), dtype=np.uint8)
    for i in range(n_points):
        # Ring = log2(i+1), each ring has twice as many points
        ring = int(np.log2(i + 1))
        # First `ring` bits encode the ring, rest are random within ring
        for b in range(min(ring, 64)):
            points_exp[i, b] = (i >> b) & 1
        for b in range(ring, 64):
            points_exp[i, b] = rng.randint(0, 2)
    constructions["Exponential-ring 64-bit"] = hamming_matrix(points_exp)

    print(f"\n  {'construction':>25}  {'curvature':>10}  {'d_eff':>6}  geometry")
    print(f"  {'---':>25}  {'---':>10}  {'---':>6}")

    for name, D in constructions.items():
        kappa = measure_curvature(D, 400, rng)
        d_eff = measure_dimension(D)

        if kappa < -0.05: geom = "HYPERBOLIC"
        elif kappa < 0.05: geom = "FLAT"
        else: geom = "SPHERICAL"

        print(f"  {name:>25}  {kappa:+10.4f}  {d_eff:6.2f}  {geom}")

    print()


# === EXPERIMENT 4: SPECTRAL HASHING ==================================
# Encode each repo's eigenvalue distribution as a bit string.
# Does Hamming distance between hashes approximate JSD?
# If yes: the eigenmanifold IS a Hamming space.

def experiment_spectral_hashing():
    print("=" * 70)
    print("  SPECTRAL HASHING: is the eigenmanifold a Hamming space?")
    print("  Encode spectra as bits. Compare Hamming distance to JSD.")
    print("=" * 70)

    import subprocess, os, tempfile
    from collections import defaultdict

    WORK_DIR = os.path.join(tempfile.gettempdir(), "raqa_repos")
    LOCAL = r"C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R"
    SRC_EXTS = ['.py','.js','.ts','.dart','.rs','.go','.java','.c','.cpp','.h','.rb','.vue','.jsx','.tsx']

    def parse_and_spectrum(path, n_commits=200):
        try:
            r = subprocess.run(["git","log","--no-merges","--name-only",
                                "--format=COMMIT_SEP%H","-n",str(n_commits)],
                               capture_output=True,text=True,encoding="utf-8",
                               errors="replace",cwd=path,timeout=60)
        except: return None
        commits=[]; cur=[]
        for ln in r.stdout.split("\n"):
            ln=ln.strip()
            if ln.startswith("COMMIT_SEP"):
                if cur:
                    s=[f for f in cur if any(f.endswith(e) for e in SRC_EXTS)]
                    if 1<len(s)<=50: commits.append(s)
                cur=[]
            elif ln: cur.append(ln)

        bins = np.linspace(0, 2.2, 40)
        window = 15; step = 5
        spectra = []
        for start in range(0, len(commits)-window+1, step):
            w = commits[start:start+window]
            pairs = defaultdict(int); fset = set()
            for c in w:
                fs = list(set(c)); fset.update(fs)
                for i in range(len(fs)):
                    for j in range(i+1, len(fs)):
                        pairs[tuple(sorted([fs[i],fs[j]]))] += 1
            fl = sorted(fset)
            if len(fl) < 5: continue
            idx={f:i for i,f in enumerate(fl)}; n=len(fl)
            A=np.zeros((n,n))
            for (a,b),c in pairs.items():
                if a in idx and b in idx: A[idx[a],idx[b]]=1; A[idx[b],idx[a]]=1
            conn=A.sum(axis=1)>0; A=A[np.ix_(conn,conn)]
            if A.shape[0]<5: continue
            d=A.sum(axis=1)
            d_inv=np.where(d>0,1/np.sqrt(d),0)
            L=np.eye(len(A))-np.diag(d_inv)@A@np.diag(d_inv)
            eigs=np.linalg.eigvalsh(L)
            hist,_=np.histogram(eigs,bins=bins,density=True)
            spectra.append(hist)
        return spectra

    repos = {"pretext": LOCAL}
    for name in ["flask","django","pytorch","rust-lang","vue","fastapi","express"]:
        p = os.path.join(WORK_DIR, name)
        if os.path.exists(p): repos[name] = p

    # Collect all spectra from all repos
    all_spectra = []
    all_labels = []

    for rname, rpath in repos.items():
        spectra = parse_and_spectrum(rpath)
        if spectra is None: continue
        for sp in spectra:
            all_spectra.append(sp)
            all_labels.append(rname)

    if len(all_spectra) < 10:
        print("  Not enough spectra."); return

    hists = np.array(all_spectra)
    n_spectra = len(hists)

    # Encode each spectrum as a bit string via locality-sensitive hashing
    # Method: threshold each bin at the median → binary code
    n_hash_bits = hists.shape[1]  # one bit per histogram bin
    medians = np.median(hists, axis=0)
    bit_strings = (hists > medians[np.newaxis, :]).astype(np.uint8)

    # Compute JSD matrix
    jsd_matrix = np.zeros((n_spectra, n_spectra))
    for i in range(n_spectra):
        for j in range(i+1, n_spectra):
            p = hists[i] / (hists[i].sum() + 1e-12) + 1e-12
            q = hists[j] / (hists[j].sum() + 1e-12) + 1e-12
            m = (p + q) / 2
            jsd = 0.5*np.sum(p*np.log(p/m)) + 0.5*np.sum(q*np.log(q/m))
            jsd_matrix[i,j] = jsd_matrix[j,i] = jsd

    # Compute Hamming distance matrix
    hamming_flat = hamming_matrix(bit_strings)

    # Correlation between JSD and Hamming
    jsd_flat = jsd_matrix[np.triu_indices(n_spectra, 1)]
    ham_flat = hamming_flat[np.triu_indices(n_spectra, 1)]

    corr = np.corrcoef(jsd_flat, ham_flat)[0,1]

    print(f"\n  {n_spectra} spectra from {len(repos)} repos")
    print(f"  Hash: {n_hash_bits}-bit strings (median threshold per bin)")
    print(f"  Correlation(JSD, Hamming): {corr:.4f}")

    if corr > 0.7:
        print(f"\n  THE EIGENMANIFOLD IS A HAMMING SPACE.")
        print(f"  Spectral distances are faithfully preserved by binary hashing.")
        print(f"  The continuous eigenvalue density ρ(λ) can be discretized")
        print(f"  into bits without losing geometric structure.")
    elif corr > 0.4:
        print(f"\n  APPROXIMATE Hamming embedding. Structure partially preserved.")
    else:
        print(f"\n  Poor embedding. JSD structure doesn't reduce to Hamming.")

    # Check curvature of the Hamming space of spectral hashes
    kappa_jsd = measure_curvature(jsd_matrix, 300)
    kappa_ham = measure_curvature(hamming_flat, 300)

    print(f"\n  Curvature of JSD space:     {kappa_jsd:+.4f}")
    print(f"  Curvature of Hamming space: {kappa_ham:+.4f}")

    if abs(kappa_jsd - kappa_ham) < 0.05:
        print(f"  CURVATURES MATCH. The hashing preserves geometry.")
    print()


# === EXPERIMENT 5: BIT-RESOLUTION OF GEOMETRY ========================
# How many bits do you need before curvature STABILIZES?
# Below some threshold, the space is too coarse for geometry.
# Above it, adding more bits doesn't change the curvature.
# That threshold is the BIT-RESOLUTION of geometry — the minimum
# information needed for space to exist.

def experiment_bit_resolution():
    print("=" * 70)
    print("  BIT-RESOLUTION OF GEOMETRY")
    print("  How many bits before geometry stabilizes?")
    print("  The minimum information for space to exist.")
    print("=" * 70)

    rng = np.random.RandomState(42)
    n_points = 100

    print(f"\n  {'bits':>5}  {'curvature':>10}  {'dimension':>10}  "
          f"{'κ_converged':>12}  {'Δκ':>8}")
    print(f"  {'---':>5}  {'---':>10}  {'---':>10}  {'---':>12}  {'---':>8}")

    prev_kappa = None
    converged_at = None

    for nb in [1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 16, 20, 24, 32, 48, 64, 96, 128]:
        points = rng.randint(0, 2, size=(n_points, nb)).astype(np.uint8)
        D = hamming_matrix(points)
        kappa = measure_curvature(D, 300, rng)
        d_eff = measure_dimension(D)

        delta = abs(kappa - prev_kappa) if prev_kappa is not None else 999
        converged = delta < 0.01

        if converged and converged_at is None:
            converged_at = nb

        status = "CONVERGED" if converged else ""
        print(f"  {nb:5d}  {kappa:+10.4f}  {d_eff:10.2f}  {status:>12}  {delta:8.4f}")

        prev_kappa = kappa

    if converged_at:
        print(f"\n  Geometry converges at {converged_at} bits.")
        print(f"  Below {converged_at} bits, curvature is unstable — not enough")
        print(f"  information for a well-defined geometry.")
        print(f"  This is the PLANCK LENGTH of bit-space: the minimum")
        print(f"  resolution at which spacetime makes sense.")
    print()


# === RUN ==============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |        I T   F R O M   B I T   —   D E E P              |")
    print("  |   geometry from information. all the way down.           |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_curvature_formula()
    experiment_operation_algebra()
    experiment_tuning_curvature()
    experiment_spectral_hashing()
    experiment_bit_resolution()

    print("=" * 70)
    print("  geometry is not fundamental. it's emergent.")
    print("  bits are not geometry. geometry is bits.")
    print("  the eigenmanifold is a shadow on a cave wall.")
    print("  the cave is made of information.")
    print("=" * 70)
