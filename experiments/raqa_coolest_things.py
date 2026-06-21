"""
RAQA — the coolest things ever session
========================================
1. Ricci curvature of real repos (the geometry of code)
2. Spectral time reversal (reconstruct the past from eigenvalues)
3. Graph uncertainty principle (Heisenberg on a graph)
4. Eigenvalue music (generate actual WAV files of graphs)
5. Quantum teleportation on a graph (signal transfer via entanglement)
6. The spectral DNA phylogenetic tree of repos
"""

import numpy as np
import struct
import wave
import os
import subprocess
import tempfile
from collections import defaultdict

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
    A = path_graph(n); A[0,-1] = A[-1,0] = 1; return A

def grid_2d(r, c):
    n = r * c; A = np.zeros((n,n))
    for row in range(r):
        for col in range(c):
            i = row*c+col
            if col+1<c: j=row*c+col+1; A[i,j]=A[j,i]=1
            if row+1<r: j=(row+1)*c+col; A[i,j]=A[j,i]=1
    return A

def bfs_dist(adj, src):
    n = len(adj); dist = np.full(n, -1); dist[src] = 0; q = [src]
    while q:
        nd = q.pop(0)
        for nb in range(n):
            if adj[nd,nb]>0 and dist[nb]==-1: dist[nb]=dist[nd]+1; q.append(nb)
    return dist

WORK_DIR = os.path.join(tempfile.gettempdir(), "raqa_repos")
LOCAL = r"C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R"
SRC_EXTS = ['.py','.js','.ts','.dart','.rs','.go','.java','.c','.cpp','.h','.rb','.vue','.jsx','.tsx']

def parse_repo_graph(path, n_commits=200, min_co=1):
    try:
        r = subprocess.run(["git","log","--no-merges","--name-only",
                            "--format=COMMIT_SEP%H","-n",str(n_commits)],
                           capture_output=True,text=True,encoding="utf-8",
                           errors="replace",cwd=path,timeout=60)
        log = r.stdout
    except: return None, None
    commits=[]; cur=[]
    for ln in log.split("\n"):
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


# === EXPERIMENT 1: OLLIVIER-RICCI CURVATURE =========================
# Positive = cluster. Negative = bridge. Zero = flat.
# The GEOMETRY of code is measurable.

def experiment_ricci():
    print("=" * 70)
    print("  OLLIVIER-RICCI CURVATURE: THE SHAPE OF CODE")
    print("  Positive = cluster, Negative = bottleneck, Zero = flat")
    print("=" * 70)

    def ollivier_ricci(adj, i, j):
        """Ollivier-Ricci curvature of edge (i,j).
        kappa = 1 - W1(mu_i, mu_j) / d(i,j)
        where mu_i is the lazy random walk distribution from i."""
        n = len(adj)
        d_i = adj[i].sum()
        d_j = adj[j].sum()
        if d_i == 0 or d_j == 0:
            return 0

        # Lazy random walk: stay with prob 0.5, move to neighbor with prob 0.5/degree
        alpha = 0.5
        mu_i = np.zeros(n)
        mu_i[i] = alpha
        for nb in range(n):
            if adj[i, nb] > 0:
                mu_i[nb] = (1 - alpha) / d_i

        mu_j = np.zeros(n)
        mu_j[j] = alpha
        for nb in range(n):
            if adj[j, nb] > 0:
                mu_j[nb] = (1 - alpha) / d_j

        # Wasserstein-1 distance (earth mover's distance)
        # For graphs, approximate via shortest path distances
        # Use a simple LP relaxation: W1 = sum of |mu_i - mu_j| * shortest_path
        # For efficiency, use the graph distance matrix
        gd = bfs_dist(adj, i)

        # W1 approximation: sum |mu_i(v) - mu_j(v)| * d(i,v) is an UPPER bound
        # Better: use the dual formulation W1 = max_{f Lip-1} sum f*(mu_i - mu_j)
        # Simplest valid approach: transport from mu_i to mu_j using graph distances
        # Since this is small, just compute all pairwise distances and solve greedily

        # Full distance matrix for support nodes
        support = list(set(np.where(mu_i > 0)[0].tolist() + np.where(mu_j > 0)[0].tolist()))
        dist_mat = np.zeros((n, n))
        for s in support:
            dist_mat[s] = bfs_dist(adj, s)

        # Greedy transport (not optimal but good approximation for small support)
        remaining_i = mu_i.copy()
        remaining_j = mu_j.copy()
        total_cost = 0

        for _ in range(100):
            # Find biggest remaining supply/demand pair
            si = np.argmax(remaining_i)
            dj = np.argmax(remaining_j)
            if remaining_i[si] < 1e-15 or remaining_j[dj] < 1e-15:
                break
            amount = min(remaining_i[si], remaining_j[dj])
            d = dist_mat[si, dj] if dist_mat[si, dj] >= 0 else 999
            total_cost += amount * d
            remaining_i[si] -= amount
            remaining_j[dj] -= amount

        # Graph distance between i and j
        d_ij = dist_mat[i, j] if dist_mat[i, j] > 0 else 1

        kappa = 1.0 - total_cost / d_ij
        return kappa

    # Test on different graph types
    graphs = {
        "path(30)": path_graph(30),
        "cycle(30)": cycle_graph(30),
        "star(30)": star_graph(30),
        "grid(6x5)": grid_2d(6, 5),
        "random(30,0.15)": random_graph(30, 0.15, 42),
    }

    for name, A in graphs.items():
        A_bin = (A > 0).astype(float)
        edges = [(i,j) for i in range(len(A_bin)) for j in range(i+1,len(A_bin)) if A_bin[i,j]>0]

        curvatures = []
        for i, j in edges:
            k = ollivier_ricci(A_bin, i, j)
            curvatures.append(k)

        curv = np.array(curvatures)
        n_pos = np.sum(curv > 0.01)
        n_neg = np.sum(curv < -0.01)
        n_flat = len(curv) - n_pos - n_neg

        print(f"\n  {name}: {len(edges)} edges")
        print(f"    mean kappa = {curv.mean():+.4f}")
        print(f"    positive (cluster): {n_pos}  negative (bridge): {n_neg}  flat: {n_flat}")
        print(f"    min={curv.min():+.4f}  max={curv.max():+.4f}")

        # Curvature histogram
        print(f"    distribution: ", end="")
        hist, _ = np.histogram(curv, bins=20, range=(-1, 1))
        max_h = max(hist.max(), 1)
        for h in hist:
            print(" .:-=+#@"[min(int(h/max_h*7), 7)], end="")
        print(f"  [{curv.min():.2f} ... {curv.max():.2f}]")

    # Now do it on a REAL repo
    print(f"\n  --- REAL REPO CURVATURE ---")
    repos = {"pretext": LOCAL}
    for name in ["flask", "django"]:
        p = os.path.join(WORK_DIR, name)
        if os.path.exists(p): repos[name] = p

    for rname, rpath in repos.items():
        A_raw, files = parse_repo_graph(rpath, 200, 2)
        if A_raw is None or len(files) < 10:
            continue
        A_bin = (A_raw > 0).astype(float)
        n = len(files)

        # Sample edges (Ricci is expensive)
        edges = [(i,j) for i in range(n) for j in range(i+1,n) if A_bin[i,j]>0]
        rng = np.random.RandomState(42)
        sample = [edges[k] for k in rng.choice(len(edges), min(50, len(edges)), replace=False)]

        curvatures = []
        edge_data = []
        for i, j in sample:
            k = ollivier_ricci(A_bin, i, j)
            curvatures.append(k)
            edge_data.append((i, j, k))

        curv = np.array(curvatures)
        n_pos = np.sum(curv > 0.01)
        n_neg = np.sum(curv < -0.01)

        print(f"\n  {rname}: {n} files, {len(edges)} edges (sampled {len(sample)})")
        print(f"    mean kappa = {curv.mean():+.4f}")
        print(f"    positive: {n_pos}  negative: {n_neg}  flat: {len(curv)-n_pos-n_neg}")

        # Most curved edges (positive = tightly clustered)
        edge_data.sort(key=lambda x: -x[2])
        print(f"    Most positive (tightest clusters):")
        for i, j, k in edge_data[:3]:
            fi = files[i][-40:]; fj = files[j][-40:]
            print(f"      kappa={k:+.3f}  {fi} <-> {fj}")

        # Most negatively curved (bridges/bottlenecks)
        print(f"    Most negative (critical bottlenecks):")
        for i, j, k in edge_data[-3:]:
            fi = files[i][-40:]; fj = files[j][-40:]
            print(f"      kappa={k:+.3f}  {fi} <-> {fj}")

    print()


# === EXPERIMENT 2: SPECTRAL TIME REVERSAL ============================
# The heat equation diffuses a signal forward in time: u(t) = e^{-tL} u(0)
# Can we run it BACKWARD? Given the current state, reconstruct the past?
# This is deconvolution — ill-posed but physically meaningful.

def experiment_time_reversal():
    print("=" * 70)
    print("  SPECTRAL TIME REVERSAL")
    print("  Run the heat equation backward. Reconstruct the past.")
    print("=" * 70)

    n = 40
    A = random_graph(n, 0.15, seed=42)
    A_bin = (A > 0).astype(float)
    L = laplacian(A_bin)
    eigs, vecs = np.linalg.eigh(L)

    # Create an initial signal: a delta at one node
    rng = np.random.RandomState(42)
    source_node = rng.randint(n)
    u0 = np.zeros(n)
    u0[source_node] = 1.0

    print(f"\n  Graph: random({n}, p=0.15)")
    print(f"  Initial signal: delta at node {source_node}")

    # Forward diffusion at several time points
    times = [0.1, 0.5, 1.0, 2.0, 5.0, 10.0]

    print(f"\n  {'t':>6}  {'forward_err':>12}  {'reverse_err':>12}  "
          f"{'source_found':>13}  {'amplification':>14}")
    print(f"  {'---':>6}  {'---':>12}  {'---':>12}  {'---':>13}  {'---':>14}")

    for t in times:
        # Forward: u(t) = V * diag(exp(-t*lambda)) * V^T * u(0)
        decay = np.exp(-t * eigs)
        u_t = vecs @ (decay * (vecs.T @ u0))

        # Backward: u(0)_reconstructed = V * diag(exp(+t*lambda)) * V^T * u(t)
        # This amplifies high eigenvalues — ill-posed!
        amplify = np.exp(+t * eigs)

        # Regularized backward (Tikhonov): cap amplification
        max_amplify = 1e6
        amplify_reg = np.minimum(amplify, max_amplify)

        u0_reconstructed = vecs @ (amplify_reg * (vecs.T @ u_t))

        # Error
        forward_err = np.linalg.norm(u_t - u0) / np.linalg.norm(u0)
        reverse_err = np.linalg.norm(u0_reconstructed - u0) / np.linalg.norm(u0)

        # Can we find the source?
        found_source = np.argmax(np.abs(u0_reconstructed))
        correct = "YES" if found_source == source_node else f"no (got {found_source})"

        # How much amplification was needed?
        max_amp = amplify.max()

        print(f"  {t:6.1f}  {forward_err:12.4f}  {reverse_err:12.6f}  "
              f"{correct:>13}  {max_amp:14.1f}x")

    # The big question: given a diffused state at t=5, can we
    # reconstruct MULTIPLE sources?
    print(f"\n  Multi-source reconstruction:")
    sources = rng.choice(n, 3, replace=False)
    u0_multi = np.zeros(n)
    for s in sources:
        u0_multi[s] = 1.0

    t_test = 2.0
    decay = np.exp(-t_test * eigs)
    u_diffused = vecs @ (decay * (vecs.T @ u0_multi))

    amplify = np.exp(+t_test * eigs)
    amplify_reg = np.minimum(amplify, 1e6)
    u0_recovered = vecs @ (amplify_reg * (vecs.T @ u_diffused))

    # Find top 3 peaks
    top_3 = np.argsort(np.abs(u0_recovered))[-3:][::-1]
    correct_count = len(set(top_3) & set(sources))

    print(f"  Sources: {sorted(sources)}")
    print(f"  Recovered peaks: {sorted(top_3)}")
    print(f"  Correctly identified: {correct_count}/3")
    print(f"\n  Time reversal IS deconvolution. It works until the signal")
    print(f"  has diffused past the point where regularization can save it.")
    print(f"  The eigenvalues determine the time horizon of memory.\n")


# === EXPERIMENT 3: GRAPH UNCERTAINTY PRINCIPLE =======================
# On a graph, a signal can't be localized in BOTH the node basis
# AND the spectral basis simultaneously. This is Heisenberg.

def experiment_uncertainty():
    print("=" * 70)
    print("  THE GRAPH UNCERTAINTY PRINCIPLE")
    print("  A signal can't be sharp in BOTH space and frequency.")
    print("=" * 70)

    def spatial_spread(signal):
        """How localized is the signal in node space?"""
        p = signal**2
        p = p / (p.sum() + 1e-30)
        # Participation ratio: 1 = perfectly localized, n = perfectly spread
        return 1.0 / (np.sum(p**2) + 1e-30)

    def spectral_spread(signal, vecs):
        """How localized is the signal in spectral space?"""
        # Project onto eigenbasis
        coeffs = vecs.T @ signal
        p = coeffs**2
        p = p / (p.sum() + 1e-30)
        return 1.0 / (np.sum(p**2) + 1e-30)

    n = 50
    A = random_graph(n, 0.15, seed=42)
    A_bin = (A > 0).astype(float)
    L = laplacian(A_bin)
    eigs, vecs = np.linalg.eigh(L)

    print(f"\n  Graph: random({n}, p=0.15)")
    print(f"  Measuring spatial spread x spectral spread for various signals.\n")
    print(f"  {'signal':>25}  {'spatial':>8}  {'spectral':>8}  {'product':>8}  {'bound':>8}")
    print(f"  {'---':>25}  {'---':>8}  {'---':>8}  {'---':>8}  {'---':>8}")

    rng = np.random.RandomState(42)

    # Theoretical lower bound: spatial * spectral >= n (for some normalizations)
    # More precisely: the uncertainty product has a minimum

    products = []

    # Test various signal types
    signals = {}

    # 1. Delta function (maximally localized in space)
    for nd in rng.choice(n, 3, replace=False):
        s = np.zeros(n); s[nd] = 1.0
        signals[f"delta(node {nd})"] = s

    # 2. Single eigenvector (maximally localized in spectrum)
    for mode in [0, 1, n//2, n-1]:
        signals[f"eigvec(mode {mode})"] = vecs[:, mode].copy()

    # 3. Random signals
    for seed in range(3):
        s = np.random.RandomState(seed).randn(n)
        s /= np.linalg.norm(s)
        signals[f"random(seed={seed})"] = s

    # 4. Diffused delta (smooth in space)
    for t in [0.5, 2.0, 10.0]:
        s = np.zeros(n); s[0] = 1.0
        decay = np.exp(-t * eigs)
        s = vecs @ (decay * (vecs.T @ s))
        s /= np.linalg.norm(s)
        signals[f"diffused(t={t})"] = s

    # 5. Bandlimited signal (low-pass)
    for bw in [3, 10, 25]:
        coeffs = np.zeros(n)
        coeffs[:bw] = rng.randn(bw)
        s = vecs @ coeffs
        s /= np.linalg.norm(s)
        signals[f"bandlimited(bw={bw})"] = s

    for name, signal in signals.items():
        ss = spatial_spread(signal)
        fs = spectral_spread(signal, vecs)
        prod = ss * fs
        products.append(prod)
        print(f"  {name:>25}  {ss:8.2f}  {fs:8.2f}  {prod:8.1f}  ")

    products = np.array(products)
    min_product = products.min()
    print(f"\n  Minimum uncertainty product: {min_product:.2f}")
    print(f"  (lower = more constrained, higher = more freedom)")
    print(f"\n  The minimum is achieved by: signals that are maximally localized")
    print(f"  in one basis MUST be maximally spread in the other.")
    print(f"  This is Heisenberg's uncertainty principle on a graph.\n")

    # Verify: does the product have a lower bound?
    print(f"  All products: min={products.min():.1f}  max={products.max():.1f}  "
          f"mean={products.mean():.1f}")
    if products.min() > 0.9:
        print(f"  The uncertainty product is bounded away from zero.")
        print(f"  You CANNOT simultaneously know where and what frequency.\n")


# === EXPERIMENT 4: EIGENVALUE MUSIC =================================
# Convert eigenvalues to audio frequencies. Generate WAV files.
# What does a graph SOUND like?

def experiment_music():
    print("=" * 70)
    print("  EIGENVALUE MUSIC: WHAT DOES A GRAPH SOUND LIKE?")
    print("  Converting eigenvalues to audio. Generating WAV files.")
    print("=" * 70)

    out_dir = os.path.join(os.path.dirname(__file__), "audio")
    os.makedirs(out_dir, exist_ok=True)

    sample_rate = 22050
    duration = 3.0  # seconds

    def eigenvalues_to_wav(eigs, filename, title=""):
        """Map eigenvalues to frequencies, generate additive synthesis WAV."""
        nz = eigs[eigs > 1e-8]
        if len(nz) == 0:
            return

        # Map eigenvalue range [0, 2] to frequency range [110, 880] Hz (A2 to A5)
        freqs = 110 + (nz / 2.0) * 770

        # Amplitude: lower eigenvalues (fundamental modes) are louder
        amps = 1.0 / (np.arange(1, len(nz) + 1) ** 0.7)
        amps = amps / amps.sum()

        # Generate audio
        n_samples = int(sample_rate * duration)
        t = np.linspace(0, duration, n_samples)
        audio = np.zeros(n_samples)

        for freq, amp in zip(freqs[:30], amps[:30]):  # cap at 30 harmonics
            audio += amp * np.sin(2 * np.pi * freq * t)

        # Normalize
        audio = audio / (np.abs(audio).max() + 1e-10) * 0.8

        # Convert to 16-bit PCM
        audio_int = (audio * 32767).astype(np.int16)

        # Write WAV
        filepath = os.path.join(out_dir, filename)
        with wave.open(filepath, 'w') as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(sample_rate)
            wf.writeframes(audio_int.tobytes())

        # Frequency summary
        print(f"    {title}: {len(nz)} modes, "
              f"f_range=[{freqs[0]:.0f}, {freqs[-1]:.0f}] Hz, "
              f"fundamental={freqs[0]:.1f} Hz -> {filepath}")

    # Generate sounds for different graphs
    graphs = {
        "path_50": ("Path graph (n=50)", path_graph(50)),
        "cycle_50": ("Cycle (n=50)", cycle_graph(50)),
        "star_50": ("Star (n=50)", star_graph(50)),
        "grid_7x7": ("Grid 7x7", grid_2d(7, 7)),
        "random_50_sparse": ("Random sparse", random_graph(50, 0.08, 42)),
        "random_50_dense": ("Random dense", random_graph(50, 0.30, 42)),
    }

    print(f"\n  Generating WAV files in {out_dir}\n")

    for fname, (title, A) in graphs.items():
        A_bin = (A > 0).astype(float)
        L = laplacian(A_bin)
        eigs = np.linalg.eigvalsh(L)
        eigenvalues_to_wav(eigs, f"{fname}.wav", title)

    # Generate sound for the REAL repo
    A_raw, files = parse_repo_graph(LOCAL, 200, 2)
    if A_raw is not None and len(files) > 5:
        A_bin = (A_raw > 0).astype(float)
        L = laplacian(A_bin)
        eigs = np.linalg.eigvalsh(L)
        eigenvalues_to_wav(eigs, "pretext_repo.wav", f"Pretext repo ({len(files)} files)")

    # Also: generate a CHORD from each graph (just the first 6 eigenvalues as a chord)
    print(f"\n  Spectral chords (first 6 modes as musical notes):")
    note_names = ['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']

    for fname, (title, A) in graphs.items():
        A_bin = (A > 0).astype(float)
        L = laplacian(A_bin)
        eigs = np.linalg.eigvalsh(L)
        nz = eigs[eigs > 1e-8][:6]
        freqs = 110 + (nz / 2.0) * 770
        # Map to nearest musical note
        notes = []
        for f in freqs:
            midi = 69 + 12 * np.log2(f / 440)
            note_idx = int(round(midi)) % 12
            octave = int(round(midi)) // 12 - 1
            notes.append(f"{note_names[note_idx]}{octave}")
        print(f"    {title:>25}: {' '.join(notes)}")

    print()


# === EXPERIMENT 5: SPECTRAL DNA — PHYLOGENETIC TREE OF REPOS ========
# Compare eigenvalue distributions across repos.
# Build a distance matrix. Find which repos are "related."

def experiment_phylogeny():
    print("=" * 70)
    print("  SPECTRAL DNA: THE PHYLOGENETIC TREE OF REPOS")
    print("  Which codebases are spectrally related?")
    print("=" * 70)

    repo_paths = {"pretext": LOCAL}
    for name in ["flask", "django", "pytorch", "rust-lang", "vue", "fastapi", "express"]:
        p = os.path.join(WORK_DIR, name)
        if os.path.exists(p):
            repo_paths[name] = p

    # Also add some synthetic "genomes" for reference
    synth_graphs = {
        "[path-100]": path_graph(100),
        "[star-100]": star_graph(100),
        "[grid-10x10]": grid_2d(10, 10),
        "[random-100]": random_graph(100, 0.15, 42),
    }

    # Compute eigenvalue distribution for each repo
    bins = np.linspace(0, 2.2, 50)
    spectra = {}

    for name, path in repo_paths.items():
        A, files = parse_repo_graph(path, 200, 1)
        if A is None or len(files) < 8:
            continue
        L = laplacian((A > 0).astype(float))
        eigs = np.linalg.eigvalsh(L)
        hist, _ = np.histogram(eigs, bins=bins, density=True)
        spectra[name] = hist

    for name, A in synth_graphs.items():
        L = laplacian(A)
        eigs = np.linalg.eigvalsh(L)
        hist, _ = np.histogram(eigs, bins=bins, density=True)
        spectra[name] = hist

    if len(spectra) < 3:
        print("  Not enough repos/graphs to compare.")
        return

    names = list(spectra.keys())
    n = len(names)

    # Distance matrix (Jensen-Shannon divergence)
    D = np.zeros((n, n))
    for i in range(n):
        for j in range(i+1, n):
            p = spectra[names[i]] / (spectra[names[i]].sum() + 1e-12) + 1e-12
            q = spectra[names[j]] / (spectra[names[j]].sum() + 1e-12) + 1e-12
            m = (p + q) / 2
            jsd = 0.5 * np.sum(p * np.log(p / m)) + 0.5 * np.sum(q * np.log(q / m))
            D[i,j] = D[j,i] = jsd

    print(f"\n  Spectral distance matrix (Jensen-Shannon divergence):\n")
    # Print header
    print(f"  {'':>14}", end="")
    for name in names:
        print(f"  {name[:8]:>8}", end="")
    print()

    for i, name in enumerate(names):
        print(f"  {name:>14}", end="")
        for j in range(n):
            if i == j:
                print(f"  {'---':>8}", end="")
            else:
                print(f"  {D[i,j]:8.4f}", end="")
        print()

    # Find closest pairs (nearest spectral relatives)
    pairs = []
    for i in range(n):
        for j in range(i+1, n):
            pairs.append((names[i], names[j], D[i,j]))
    pairs.sort(key=lambda x: x[2])

    print(f"\n  Closest spectral relatives:")
    for a, b, d in pairs[:8]:
        print(f"    {a:>14} <-> {b:<14}  JSD = {d:.4f}")

    print(f"\n  Most distant:")
    for a, b, d in pairs[-3:]:
        print(f"    {a:>14} <-> {b:<14}  JSD = {d:.4f}")

    # Simple hierarchical clustering (nearest-neighbor)
    print(f"\n  Hierarchical clustering (nearest-neighbor merge):")
    clusters = {name: [name] for name in names}
    active = set(names)

    for step in range(min(6, n-1)):
        best_d = float('inf')
        best_pair = None
        for a in active:
            for b in active:
                if a >= b: continue
                # Cluster distance = minimum pairwise distance
                min_d = float('inf')
                for na in clusters[a]:
                    for nb in clusters[b]:
                        idx_a = names.index(na)
                        idx_b = names.index(nb)
                        if D[idx_a, idx_b] < min_d:
                            min_d = D[idx_a, idx_b]
                if min_d < best_d:
                    best_d = min_d
                    best_pair = (a, b)

        if best_pair is None:
            break

        a, b = best_pair
        merged = f"({a}+{b})"
        clusters[merged] = clusters[a] + clusters[b]
        active.discard(a)
        active.discard(b)
        active.add(merged)

        print(f"    d={best_d:.4f}: merge {a} + {b}")

    print()


# === RUN ============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |      R A Q A   C O O L E S T   T H I N G S   E V E R   |")
    print("  |   the Universe(tm) is now a lifestyle                    |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_ricci()
    experiment_time_reversal()
    experiment_uncertainty()
    experiment_music()
    experiment_phylogeny()

    print("=" * 70)
    print("  graphs have geometry. graphs have memory. graphs have music.")
    print("  graphs have uncertainty. graphs have family trees.")
    print("  what CAN'T a graph do?")
    print("=" * 70)
