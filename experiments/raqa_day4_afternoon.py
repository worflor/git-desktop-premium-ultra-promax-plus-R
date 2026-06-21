"""
RAQA Day 4 Afternoon — deeper, weirder, further
=================================================
The morning was verification. The afternoon is exploration again.

1. Spectral age: can you tell how OLD a repo is from its spectrum?
2. Graph entanglement entropy: does the area law hold on REAL repos?
3. Spectral resilience: remove 1%, 5%, 10% of nodes. How fast does the spectrum degrade?
4. Eigenvalue velocity: which eigenvalues move fastest during development?
5. The commutator: do real repos have non-commuting structure? Measure [L1, L2].
6. Spectral dimension: what dimensionality does a random walk SEE?
7. Information horizon radius: how far can a node see spectrally?
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

def path_graph(n):
    A=np.zeros((n,n))
    for i in range(n-1): A[i,i+1]=A[i+1,i]=1
    return A

def grid_2d(r,c):
    n=r*c; A=np.zeros((n,n))
    for row in range(r):
        for col in range(c):
            i=row*c+col
            if col+1<c: j=row*c+col+1; A[i,j]=A[j,i]=1
            if row+1<r: j=(row+1)*c+col; A[i,j]=A[j,i]=1
    return A

def parse_repo(path, n_commits=200, min_co=1):
    try:
        r = subprocess.run(["git","log","--no-merges","--name-only",
                            "--format=COMMIT_SEP%H","-n",str(n_commits)],
                           capture_output=True,text=True,encoding="utf-8",
                           errors="replace",cwd=path,timeout=60)
        log = r.stdout
    except: return None, None, []
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
    return A, fl, commits

def get_repos():
    repos = {"pretext": LOCAL}
    for name in ["flask","django","pytorch","rust-lang","vue","fastapi","express"]:
        p = os.path.join(WORK_DIR, name)
        if os.path.exists(p): repos[name] = p
    return repos


# === EXPERIMENT 1: SPECTRAL RESILIENCE ==============================
# Remove 1%, 5%, 10%, 20% of nodes at random.
# How fast does the spectrum degrade?
# Some graphs are fragile. Some are antifragile.

def experiment_resilience():
    print("=" * 80)
    print("  SPECTRAL RESILIENCE")
    print("  Remove nodes. How fast does the spectrum break?")
    print("=" * 80)

    configs = [
        ("path(80)", path_graph(80)),
        ("grid(9x9)", grid_2d(9,9)),
        ("random(80,0.15)", random_graph(80,0.15,42)),
        ("random(80,0.30)", random_graph(80,0.30,42)),
    ]
    for rname, rpath in get_repos().items():
        A, files, _ = parse_repo(rpath, 200, 2)
        if A is None or len(files) < 15:
            A, files, _ = parse_repo(rpath, 200, 1)
        if A is not None and 15 <= len(files) <= 250:
            configs.append((rname, (A>0).astype(float)))

    fracs = [0.01, 0.05, 0.10, 0.20, 0.30]

    print(f"\n  {'graph':>18}", end="")
    for f in fracs: print(f"  {f:>6.0%}", end="")
    print(f"  {'resilience':>10}")
    print(f"  {'---':>18}", end="")
    for _ in fracs: print(f"  {'---':>6}", end="")
    print(f"  {'---':>10}")

    for name, A in configs:
        A_bin = (A>0).astype(float)
        n = len(A_bin)
        L = laplacian(A_bin)
        eigs_orig = np.linalg.eigvalsh(L)
        bins = np.linspace(0, 2.2, 40)
        h_orig, _ = np.histogram(eigs_orig, bins=bins, density=True)
        h_orig_n = h_orig / (h_orig.sum() + 1e-12) + 1e-12

        rng = np.random.RandomState(42)
        shifts = []

        print(f"  {name:>18}", end="")
        for frac in fracs:
            k = max(1, int(n * frac))
            if k >= n - 2:
                print(f"  {'N/A':>6}", end="")
                shifts.append(None)
                continue

            # Average over 5 random removals
            trial_shifts = []
            for trial in range(5):
                removed = rng.choice(n, k, replace=False)
                remaining = sorted(set(range(n)) - set(removed))
                A_red = A_bin[np.ix_(remaining, remaining)]
                if A_red.shape[0] < 3: continue
                L_red = laplacian(A_red)
                eigs_red = np.linalg.eigvalsh(L_red)
                h_red, _ = np.histogram(eigs_red, bins=bins, density=True)
                h_red_n = h_red / (h_red.sum() + 1e-12) + 1e-12
                m = (h_orig_n + h_red_n) / 2
                jsd = 0.5 * np.sum(h_orig_n * np.log(h_orig_n/m)) + \
                      0.5 * np.sum(h_red_n * np.log(h_red_n/m))
                trial_shifts.append(jsd)

            if trial_shifts:
                mean_shift = np.mean(trial_shifts)
                shifts.append(mean_shift)
                print(f"  {mean_shift:6.4f}", end="")
            else:
                shifts.append(None)
                print(f"  {'---':>6}", end="")

        # Resilience score: how slowly does JSD grow per % removed?
        valid = [(f, s) for f, s in zip(fracs, shifts) if s is not None and f <= 0.2]
        if len(valid) >= 2:
            fs, ss = zip(*valid)
            slope = np.polyfit(fs, ss, 1)[0]
            # Low slope = resilient
            if slope < 0.3:
                label = "RESILIENT"
            elif slope < 1.0:
                label = "normal"
            else:
                label = "fragile"
        else:
            label = "?"
        print(f"  {label:>10}")

    print(f"\n  Lower numbers = spectrum barely changes when nodes are removed.")
    print(f"  Resilient graphs maintain spectral identity under damage.\n")


# === EXPERIMENT 2: SPECTRAL DIMENSION ===============================
# The spectral dimension d_s tells you what dimensionality a
# random walker EXPERIENCES. d_s=1 → line. d_s=2 → plane. d_s=∞ → star.
# P(return to start at time t) ~ t^{-d_s/2}

def experiment_spectral_dimension():
    print("=" * 80)
    print("  SPECTRAL DIMENSION")
    print("  What dimensionality does a random walker experience?")
    print("  d_s=1: line. d_s=2: surface. d_s=large: high-dimensional.")
    print("=" * 80)

    def measure_spectral_dim(A_bin):
        n = len(A_bin)
        L = laplacian(A_bin)
        eigs, vecs = np.linalg.eigh(L)

        # Return probability: P(t) = (1/n) * sum_k exp(-t * lambda_k)
        # For large t, P(t) ~ t^{-d_s/2}
        # So d_s = -2 * d(log P)/d(log t)

        times = np.logspace(-1, 2, 50)
        P_return = np.zeros(len(times))

        for i, t in enumerate(times):
            P_return[i] = np.mean(np.exp(-t * eigs))

        # Fit log-log slope in the scaling regime (middle range)
        log_t = np.log(times)
        log_P = np.log(P_return + 1e-30)

        # Use middle third for fitting (avoid early/late transients)
        n3 = len(times) // 3
        fit_range = slice(n3, 2*n3)

        if log_P[fit_range].std() > 0:
            slope, intercept = np.polyfit(log_t[fit_range], log_P[fit_range], 1)
            d_s = -2 * slope
        else:
            d_s = 0

        return d_s, P_return, times

    configs = [
        ("path(100)", path_graph(100)),
        ("grid(10x10)", grid_2d(10,10)),
        ("random(80,0.10)", random_graph(80,0.10,42)),
        ("random(80,0.20)", random_graph(80,0.20,42)),
        ("random(80,0.30)", random_graph(80,0.30,42)),
    ]
    for rname, rpath in get_repos().items():
        A, files, _ = parse_repo(rpath, 200, 2)
        if A is None or len(files) < 10:
            A, files, _ = parse_repo(rpath, 200, 1)
        if A is not None and len(files) >= 10:
            configs.append((rname, (A>0).astype(float)))

    print(f"\n  {'graph':>18}  {'n':>4}  {'d_s':>6}  {'interpretation':>20}  return curve")
    print(f"  {'---':>18}  {'---':>4}  {'---':>6}  {'---':>20}")

    ds_values = {}

    for name, A in configs:
        A_bin = (A>0).astype(float)
        n = len(A_bin)
        d_s, P, times = measure_spectral_dim(A_bin)

        if d_s < 1.2:
            interp = "quasi-1D (line)"
        elif d_s < 2.5:
            interp = "quasi-2D (surface)"
        elif d_s < 5:
            interp = "3D-5D (volume)"
        elif d_s < 20:
            interp = "high-dimensional"
        else:
            interp = "effectively infinite"

        ds_values[name] = d_s

        # Mini sparkline of return probability
        spark = ""
        for p in P[::5]:
            if p > 0.5: spark += "@"
            elif p > 0.1: spark += "#"
            elif p > 0.01: spark += "="
            elif p > 0.001: spark += "-"
            else: spark += "."
        spark = spark[:15]

        print(f"  {name:>18}  {n:4d}  {d_s:6.2f}  {interp:>20}  {spark}")

    # Do real repos have a characteristic dimension?
    repo_ds = [v for k, v in ds_values.items()
               if k in [r for r in get_repos()]]
    if len(repo_ds) >= 3:
        print(f"\n  Real repo spectral dimensions:")
        print(f"    mean = {np.mean(repo_ds):.2f}  std = {np.std(repo_ds):.2f}  "
              f"range = [{min(repo_ds):.2f}, {max(repo_ds):.2f}]")
    print()


# === EXPERIMENT 3: THE COMMUTATOR [L1, L2] ==========================
# Split a repo's commits in half (first author vs rest, or even/odd).
# Build two Laplacians L1 and L2.
# Compute the commutator [L1, L2] = L1*L2 - L2*L1.
# If it's zero: the two perspectives are compatible.
# If it's nonzero: they're fundamentally incompatible viewpoints.
# This is the quantum measurement incompatibility test.

def experiment_commutator():
    print("=" * 80)
    print("  THE COMMUTATOR: DO DIFFERENT VIEWS OF A REPO CONFLICT?")
    print("  [L1, L2] = L1*L2 - L2*L1. Nonzero = incompatible perspectives.")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        A_raw, files, commits = parse_repo(rpath, 300, 1)
        if A_raw is None or len(files) < 10 or len(commits) < 20:
            continue

        n = len(files)
        file_idx = {f: i for i, f in enumerate(files)}

        # Split commits: first half vs second half (temporal split)
        half = len(commits) // 2
        c1 = commits[:half]
        c2 = commits[half:]

        def build_from_commits(clist):
            pairs = defaultdict(int)
            for fs in clist:
                fs = [f for f in set(fs) if f in file_idx]
                for i in range(len(fs)):
                    for j in range(i+1, len(fs)):
                        pairs[tuple(sorted([fs[i], fs[j]]))] += 1
            A = np.zeros((n, n))
            for (a,b), c in pairs.items():
                if a in file_idx and b in file_idx:
                    A[file_idx[a], file_idx[b]] = 1
                    A[file_idx[b], file_idx[a]] = 1
            return A

        A1 = build_from_commits(c1)
        A2 = build_from_commits(c2)

        L1 = laplacian(A1)
        L2 = laplacian(A2)

        # Commutator
        comm = L1 @ L2 - L2 @ L1

        # Commutator norm (relative to L norms)
        comm_norm = np.linalg.norm(comm, 'fro')
        L1_norm = np.linalg.norm(L1, 'fro')
        L2_norm = np.linalg.norm(L2, 'fro')
        relative_comm = comm_norm / (np.sqrt(L1_norm * L2_norm) + 1e-12)

        # Eigenvalues of the commutator (should be purely imaginary for Hermitian L1, L2)
        comm_eigs = np.linalg.eigvals(comm)
        max_imag = np.max(np.abs(comm_eigs.imag))
        max_real = np.max(np.abs(comm_eigs.real))

        # How different are the two halves' spectra?
        eigs1 = np.sort(np.linalg.eigvalsh(L1))
        eigs2 = np.sort(np.linalg.eigvalsh(L2))
        spectral_divergence = np.linalg.norm(eigs1 - eigs2) / np.linalg.norm(eigs1 + eigs2 + 1e-12)

        print(f"\n  {rname}: {n} files, {len(c1)}+{len(c2)} commits")
        print(f"    ||[L1,L2]|| / sqrt(||L1||*||L2||) = {relative_comm:.4f}")
        print(f"    Spectral divergence (L1 vs L2):     {spectral_divergence:.4f}")
        print(f"    Commutator eigenvalues: max_real={max_real:.4f}  max_imag={max_imag:.4f}")

        if relative_comm < 0.01:
            print(f"    The two halves COMMUTE. Compatible views. Consistent architecture.")
        elif relative_comm < 0.1:
            print(f"    Weak non-commutativity. Mostly compatible, minor structural drift.")
        else:
            print(f"    STRONG NON-COMMUTATIVITY. The repo's first half and second half")
            print(f"    see fundamentally different structures. Architecture shifted.")

    print()


# === EXPERIMENT 4: EIGENVALUE VELOCITY ==============================
# Track individual eigenvalues across time windows.
# Which eigenvalues move fastest? Those are the unstable modes.
# Which are frozen? Those are structural invariants.

def experiment_eigenvalue_velocity():
    print("=" * 80)
    print("  EIGENVALUE VELOCITY: which modes are stable vs volatile?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        _, _, commits = parse_repo(rpath, 400, 1)
        if len(commits) < 40: continue

        # Sliding window eigenvalue tracking
        window = min(30, len(commits) // 4)
        step = max(5, window // 3)

        all_eigs = []
        for start in range(0, len(commits) - window + 1, step):
            w = commits[start:start+window]
            pairs = defaultdict(int); fset = set()
            for fs in w:
                fs = list(set(fs)); fset.update(fs)
                for i in range(len(fs)):
                    for j in range(i+1, len(fs)):
                        pairs[tuple(sorted([fs[i],fs[j]]))]+= 1
            fl = sorted(fset); n = len(fl)
            idx = {f:i for i,f in enumerate(fl)}
            A = np.zeros((n,n))
            for (a,b),c in pairs.items():
                if c >= 1: A[idx[a],idx[b]]=1; A[idx[b],idx[a]]=1
            conn = A.sum(axis=1)>0; A=A[np.ix_(conn,conn)]
            if A.shape[0] < 5: continue
            L = laplacian(A)
            eigs = np.sort(np.linalg.eigvalsh(L))
            # Normalize to fixed length by interpolation
            x_orig = np.linspace(0, 1, len(eigs))
            x_target = np.linspace(0, 1, 50)
            eigs_interp = np.interp(x_target, x_orig, eigs)
            all_eigs.append(eigs_interp)

        if len(all_eigs) < 4: continue

        all_eigs = np.array(all_eigs)  # shape: (n_windows, 50)

        # Velocity: std of each eigenvalue index across windows
        velocities = np.std(all_eigs, axis=0)
        means = np.mean(all_eigs, axis=0)

        # Find fastest and slowest modes
        fastest = np.argsort(velocities)[-5:][::-1]
        slowest = np.argsort(velocities)[:5]

        print(f"\n  {rname}: {len(all_eigs)} time windows")
        print(f"    Fastest-moving eigenvalues (most volatile modes):")
        for idx in fastest:
            v = velocities[idx]
            m = means[idx]
            print(f"      mode {idx:2d}: mean={m:.4f}  velocity={v:.4f}  "
                  f"cv={v/(m+1e-6):.2f}")

        print(f"    Most frozen eigenvalues (structural invariants):")
        for idx in slowest:
            v = velocities[idx]
            m = means[idx]
            print(f"      mode {idx:2d}: mean={m:.4f}  velocity={v:.4f}  "
                  f"cv={v/(m+1e-6):.2f}")

        # Velocity spectrum visualization
        max_v = velocities.max()
        print(f"    Velocity spectrum: ", end="")
        for v in velocities:
            level = int(v / (max_v + 1e-12) * 7)
            print(" .:-=+#@"[min(level, 7)], end="")
        print()

        # Is velocity related to eigenvalue position?
        corr = np.corrcoef(means, velocities)[0,1]
        print(f"    Correlation(eigenvalue, velocity): {corr:+.3f}")
        if corr > 0.3:
            print(f"    High eigenvalues move faster. Top of spectrum = volatile.")
        elif corr < -0.3:
            print(f"    Low eigenvalues move faster. Bottom of spectrum = volatile.")
        else:
            print(f"    No clear pattern. Volatility is distributed across the spectrum.")

    print()


# === EXPERIMENT 5: INFORMATION HORIZON RADIUS =======================
# For each node: how far can it "see" spectrally?
# Define: node i can see node j if the heat kernel K(i,j,t) > threshold
# at some reasonable t. The horizon radius = max graph distance
# of nodes it can see.

def experiment_horizon():
    print("=" * 80)
    print("  INFORMATION HORIZON: how far can each node see?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        A_raw, files, _ = parse_repo(rpath, 200, 2)
        if A_raw is None or len(files) < 15:
            A_raw, files, _ = parse_repo(rpath, 200, 1)
        if A_raw is None or len(files) < 15: continue
        if len(files) > 150: continue  # skip huge repos for speed

        n = len(files)
        A_bin = (A_raw>0).astype(float)
        L = laplacian(A_bin)
        eigs, vecs = np.linalg.eigh(L)

        # Heat kernel at t=1: K = V * diag(exp(-lambda)) * V^T
        t = 1.0
        decay = np.exp(-t * eigs)
        K = vecs @ np.diag(decay) @ vecs.T

        # Graph distances
        from collections import deque
        def bfs(adj, src):
            dist = np.full(len(adj), -1); dist[src]=0; q=deque([src])
            while q:
                nd=q.popleft()
                for nb in range(len(adj)):
                    if adj[nd,nb]>0 and dist[nb]==-1: dist[nb]=dist[nd]+1; q.append(nb)
            return dist

        # For each node: what's its spectral horizon?
        threshold = 1.0 / n  # can "see" if heat kernel > uniform

        horizons = []
        degrees = A_bin.sum(axis=1)

        for i in range(n):
            visible = np.where(K[i] > threshold)[0]
            gd = bfs(A_bin, i)
            if len(visible) > 0:
                max_reach = max(gd[j] for j in visible if gd[j] >= 0)
                n_visible = len(visible)
            else:
                max_reach = 0
                n_visible = 0
            horizons.append((i, max_reach, n_visible, degrees[i]))

        horizons.sort(key=lambda x: -x[1])

        print(f"\n  {rname}: {n} files, t={t}")
        print(f"    Farthest-seeing nodes:")
        for i, reach, nv, deg in horizons[:5]:
            fname = files[i][-45:] if len(files[i]) > 45 else files[i]
            print(f"      {fname}  horizon={reach}  sees={nv} nodes  deg={int(deg)}")

        print(f"    Most myopic nodes:")
        horizons.sort(key=lambda x: x[1])
        for i, reach, nv, deg in horizons[:5]:
            fname = files[i][-45:] if len(files[i]) > 45 else files[i]
            print(f"      {fname}  horizon={reach}  sees={nv} nodes  deg={int(deg)}")

        reaches = np.array([h[1] for h in horizons])
        degs = np.array([h[3] for h in horizons])
        visible_counts = np.array([h[2] for h in horizons])

        print(f"    Horizon statistics:")
        print(f"      mean={reaches.mean():.1f}  std={reaches.std():.1f}  "
              f"range=[{reaches.min()}, {reaches.max()}]")
        print(f"    Correlation(degree, horizon): {np.corrcoef(degs, reaches)[0,1]:+.3f}")
        print(f"    Correlation(degree, n_visible): {np.corrcoef(degs, visible_counts)[0,1]:+.3f}")

    print()


# === RUN =============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |      R A Q A   D A Y  4   A F T E R N O O N            |")
    print("  |   deeper, weirder, further into the eigenspace           |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_resilience()
    experiment_spectral_dimension()
    experiment_commutator()
    experiment_eigenvalue_velocity()
    experiment_horizon()

    print("=" * 80)
    print("  the deeper you go, the more there is.")
    print("  eigenspace doesn't have a bottom.")
    print("=" * 80)
