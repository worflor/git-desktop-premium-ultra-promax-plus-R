"""
RAQA Day 4 Morning — rigorous multi-source verification of every new finding
=============================================================================
Yesterday was discovery. Today is science.

1. Ricci curvature across ALL repos — is hyperbolic/spherical/flat a pattern?
2. Time reversal horizon — measure the exact t* where reconstruction fails per repo
3. Uncertainty principle — verify the bound across graph types and sizes
4. Ricci curvature vs bridge fragility — prove the geometric connection
5. Spectral phylogeny stability — does the tree change with different commit windows?
6. NEW: Spectral metabolism — energy throughput rate of a graph (how fast does info move?)
7. NEW: Eigenvalue gap distribution — is the gap itself a universal constant?
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

def bfs_dist(adj, src):
    n = len(adj); dist = np.full(n, -1); dist[src] = 0; q = [src]
    while q:
        nd = q.pop(0)
        for nb in range(n):
            if adj[nd,nb]>0 and dist[nb]==-1: dist[nb]=dist[nd]+1; q.append(nb)
    return dist

def random_graph(n, p=0.15, seed=42):
    rng = np.random.RandomState(seed)
    A = (rng.rand(n, n) < p).astype(float)
    A = np.triu(A, 1); A = A + A.T; return A

def path_graph(n):
    A = np.zeros((n,n))
    for i in range(n-1): A[i,i+1]=A[i+1,i]=1
    return A

def cycle_graph(n):
    A = path_graph(n); A[0,-1]=A[-1,0]=1; return A

def star_graph(n):
    A = np.zeros((n,n))
    for i in range(1,n): A[0,i]=A[i,0]=1
    return A

def grid_2d(r,c):
    n=r*c; A=np.zeros((n,n))
    for row in range(r):
        for col in range(c):
            i=row*c+col
            if col+1<c: j=row*c+col+1; A[i,j]=A[j,i]=1
            if row+1<r: j=(row+1)*c+col; A[i,j]=A[j,i]=1
    return A

def barbell_graph(n):
    h=n//2; A=np.zeros((n,n))
    for i in range(h):
        for j in range(i+1,h): A[i,j]=A[j,i]=1
    for i in range(h,n):
        for j in range(i+1,n): A[i,j]=A[j,i]=1
    A[h-1,h]=A[h,h-1]=1; return A

def parse_repo(path, n_commits=200, min_co=1):
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

def get_all_repos():
    repos = {"pretext": LOCAL}
    for name in ["flask","django","pytorch","rust-lang","vue","fastapi","express"]:
        p = os.path.join(WORK_DIR, name)
        if os.path.exists(p): repos[name] = p
    return repos

def ollivier_ricci_sample(A_bin, n_sample=50, seed=42):
    """Sample edge Ricci curvatures. Returns array of kappas."""
    n = len(A_bin)
    edges = [(i,j) for i in range(n) for j in range(i+1,n) if A_bin[i,j]>0]
    if not edges: return np.array([])
    rng = np.random.RandomState(seed)
    sample = [edges[k] for k in rng.choice(len(edges), min(n_sample, len(edges)), replace=False)]
    kappas = []
    for i, j in sample:
        d_i = A_bin[i].sum(); d_j = A_bin[j].sum()
        if d_i == 0 or d_j == 0: kappas.append(0); continue
        alpha = 0.5
        mu_i = np.zeros(n); mu_i[i] = alpha
        for nb in range(n):
            if A_bin[i,nb]>0: mu_i[nb] = (1-alpha)/d_i
        mu_j = np.zeros(n); mu_j[j] = alpha
        for nb in range(n):
            if A_bin[j,nb]>0: mu_j[nb] = (1-alpha)/d_j
        support = list(set(np.where(mu_i>0)[0].tolist()+np.where(mu_j>0)[0].tolist()))
        dm = np.zeros((n,n))
        for s in support: dm[s] = bfs_dist(A_bin, s)
        ri=mu_i.copy(); rj=mu_j.copy(); cost=0
        for _ in range(100):
            si=np.argmax(ri); dj=np.argmax(rj)
            if ri[si]<1e-15 or rj[dj]<1e-15: break
            amt=min(ri[si],rj[dj]); d=dm[si,dj] if dm[si,dj]>=0 else 999
            cost+=amt*d; ri[si]-=amt; rj[dj]-=amt
        d_ij = dm[i,j] if dm[i,j]>0 else 1
        kappas.append(1.0 - cost/d_ij)
    return np.array(kappas), sample


# === TEST 1: RICCI CURVATURE ACROSS ALL REPOS =======================

def test_ricci_cross_repo():
    print("=" * 80)
    print("  TEST 1: RICCI CURVATURE — is the geometry pattern real?")
    print("  Measuring across all available repos + synthetic controls.")
    print("=" * 80)

    results = []

    # Synthetic controls
    synth = [
        ("path(60)", path_graph(60)),
        ("cycle(60)", cycle_graph(60)),
        ("star(60)", star_graph(60)),
        ("grid(8x8)", grid_2d(8,8)),
        ("barbell(60)", barbell_graph(60)),
        ("random(60,0.10)", random_graph(60,0.10,42)),
        ("random(60,0.20)", random_graph(60,0.20,42)),
        ("random(60,0.30)", random_graph(60,0.30,42)),
    ]

    for name, A in synth:
        A_bin = (A>0).astype(float)
        kappas, _ = ollivier_ricci_sample(A_bin, 50, 42)
        if len(kappas)==0: continue
        results.append({
            "name": name, "n": len(A), "type": "synthetic",
            "mean_k": kappas.mean(), "std_k": kappas.std(),
            "frac_neg": np.mean(kappas < -0.01),
            "frac_pos": np.mean(kappas > 0.01),
        })

    # Real repos
    for rname, rpath in get_all_repos().items():
        A_raw, files = parse_repo(rpath, 200, 2)
        if A_raw is None or len(files) < 10:
            A_raw, files = parse_repo(rpath, 200, 1)
        if A_raw is None or len(files) < 10: continue
        A_bin = (A_raw>0).astype(float)
        kappas, _ = ollivier_ricci_sample(A_bin, 60, 42)
        if len(kappas)==0: continue
        results.append({
            "name": rname, "n": len(files), "type": "repo",
            "mean_k": kappas.mean(), "std_k": kappas.std(),
            "frac_neg": np.mean(kappas < -0.01),
            "frac_pos": np.mean(kappas > 0.01),
        })

    print(f"\n  {'name':>18}  {'type':>9}  {'n':>4}  {'mean_k':>8}  {'std_k':>7}  "
          f"{'%neg':>5}  {'%pos':>5}  {'geometry':>12}")
    print(f"  {'---':>18}  {'---':>9}  {'---':>4}  {'---':>8}  {'---':>7}  "
          f"{'---':>5}  {'---':>5}  {'---':>12}")

    for r in results:
        if r["mean_k"] > 0.05:
            geom = "SPHERICAL"
        elif r["mean_k"] < -0.05:
            geom = "HYPERBOLIC"
        else:
            geom = "flat"
        print(f"  {r['name']:>18}  {r['type']:>9}  {r['n']:4d}  {r['mean_k']:+8.4f}  "
              f"{r['std_k']:7.4f}  {r['frac_neg']:4.0%}  {r['frac_pos']:4.0%}  {geom:>12}")

    # Statistical summary for repos only
    repo_kappas = [r["mean_k"] for r in results if r["type"]=="repo"]
    if len(repo_kappas) >= 3:
        print(f"\n  Cross-repo statistics (n={len(repo_kappas)}):")
        print(f"    Mean of mean kappa: {np.mean(repo_kappas):+.4f} +/- {np.std(repo_kappas):.4f}")
        n_hyp = sum(1 for k in repo_kappas if k < -0.05)
        n_sph = sum(1 for k in repo_kappas if k > 0.05)
        n_flat = len(repo_kappas) - n_hyp - n_sph
        print(f"    Hyperbolic: {n_hyp}  Spherical: {n_sph}  Flat: {n_flat}")
    print()


# === TEST 2: TIME REVERSAL HORIZON — exact t* per graph type ========

def test_time_reversal_horizon():
    print("=" * 80)
    print("  TEST 2: TIME REVERSAL HORIZON")
    print("  At what t does reconstruction fail? Is t* related to the spectral gap?")
    print("=" * 80)

    configs = [
        ("path(50)", path_graph(50)),
        ("cycle(50)", cycle_graph(50)),
        ("star(50)", star_graph(50)),
        ("grid(7x7)", grid_2d(7,7)),
        ("random(50,0.10)", random_graph(50,0.10,42)),
        ("random(50,0.20)", random_graph(50,0.20,42)),
        ("barbell(50)", barbell_graph(50)),
    ]

    # Add real repos
    for rname, rpath in get_all_repos().items():
        A_raw, files = parse_repo(rpath, 200, 2)
        if A_raw is None or len(files) < 10:
            A_raw, files = parse_repo(rpath, 200, 1)
        if A_raw is not None and len(files) >= 10:
            configs.append((rname, (A_raw>0).astype(float)))

    print(f"\n  {'graph':>18}  {'gap':>8}  {'t*_source':>10}  {'t*_multi':>10}  "
          f"{'1/gap':>8}  {'t*/gap':>8}")
    print(f"  {'---':>18}  {'---':>8}  {'---':>10}  {'---':>10}  "
          f"{'---':>8}  {'---':>8}")

    gaps = []
    t_stars = []

    for name, A in configs:
        if isinstance(A, tuple): continue  # skip if not an array
        A_bin = (A>0).astype(float)
        n = len(A_bin)
        L = laplacian(A_bin)
        eigs, vecs = np.linalg.eigh(L)
        nz = eigs[eigs > 1e-8]
        if len(nz) == 0: continue
        gap = nz[0]

        rng = np.random.RandomState(42)
        src = rng.randint(n)
        u0 = np.zeros(n); u0[src] = 1.0

        # Binary search for t* where source identification fails
        t_low, t_high = 0.1, 100.0
        t_star_source = t_high

        for _ in range(20):
            t_mid = (t_low + t_high) / 2
            decay = np.exp(-t_mid * eigs)
            u_t = vecs @ (decay * (vecs.T @ u0))
            amplify = np.minimum(np.exp(t_mid * eigs), 1e8)
            u0_rec = vecs @ (amplify * (vecs.T @ u_t))
            if np.argmax(np.abs(u0_rec)) == src:
                t_low = t_mid
            else:
                t_high = t_mid
                t_star_source = t_mid

        # Multi-source t*
        sources = rng.choice(n, min(3, n), replace=False)
        u0m = np.zeros(n)
        for s in sources: u0m[s] = 1.0

        t_low2, t_high2 = 0.1, 50.0
        t_star_multi = t_high2

        for _ in range(20):
            t_mid = (t_low2 + t_high2) / 2
            decay = np.exp(-t_mid * eigs)
            u_t = vecs @ (decay * (vecs.T @ u0m))
            amplify = np.minimum(np.exp(t_mid * eigs), 1e8)
            u0_rec = vecs @ (amplify * (vecs.T @ u_t))
            top_k = set(np.argsort(np.abs(u0_rec))[-len(sources):][::-1])
            if top_k == set(sources):
                t_low2 = t_mid
            else:
                t_high2 = t_mid
                t_star_multi = t_mid

        inv_gap = 1.0/gap if gap > 0 else float('inf')
        ratio = t_star_source * gap if gap > 0 else 0

        gaps.append(gap)
        t_stars.append(t_star_source)

        print(f"  {name:>18}  {gap:8.4f}  {t_star_source:10.2f}  {t_star_multi:10.2f}  "
              f"{inv_gap:8.2f}  {ratio:8.4f}")

    if len(gaps) >= 3:
        gaps = np.array(gaps)
        t_stars = np.array(t_stars)
        corr = np.corrcoef(gaps, t_stars)[0,1]
        corr_inv = np.corrcoef(1.0/gaps, t_stars)[0,1]
        print(f"\n  Correlation(gap, t*): {corr:+.3f}")
        print(f"  Correlation(1/gap, t*): {corr_inv:+.3f}")
        if abs(corr_inv) > 0.5:
            print(f"  t* scales with 1/gap: memory depth IS the inverse spectral gap.")
        elif abs(corr) > 0.5:
            print(f"  t* correlates with gap directly.")
        else:
            print(f"  Weak correlation. Memory horizon depends on more than just the gap.")
    print()


# === TEST 3: RICCI CURVATURE vs BRIDGE FRAGILITY ====================

def test_ricci_vs_fragility():
    print("=" * 80)
    print("  TEST 3: RICCI CURVATURE vs BRIDGE FRAGILITY")
    print("  Is negative curvature the same as spectral fragility?")
    print("=" * 80)

    configs = [
        ("random(60,0.12)", random_graph(60, 0.12, 42)),
        ("random(60,0.20)", random_graph(60, 0.20, 42)),
        ("grid(8x8)", grid_2d(8, 8)),
    ]

    for rname, rpath in get_all_repos().items():
        A_raw, files = parse_repo(rpath, 200, 2)
        if A_raw is None or len(files) < 15:
            A_raw, files = parse_repo(rpath, 200, 1)
        if A_raw is not None and 15 <= len(files) <= 150:
            configs.append((rname, (A_raw>0).astype(float)))

    print(f"\n  For each graph: compute Ricci curvature AND spectral shift per edge.")
    print(f"  If they correlate: negative curvature = spectral fragility.\n")

    print(f"  {'graph':>18}  {'n_edges':>8}  {'r(kappa,shift)':>15}  {'verdict':>12}")
    print(f"  {'---':>18}  {'---':>8}  {'---':>15}  {'---':>12}")

    all_corrs = []

    for name, A in configs:
        A_bin = (A>0).astype(float)
        n = len(A_bin)
        L = laplacian(A_bin)
        eigs = np.linalg.eigvalsh(L)

        kappas, edge_sample = ollivier_ricci_sample(A_bin, 40, 42)
        if len(kappas) < 5: continue

        # Compute spectral shift for same edges
        shifts = []
        for i, j in edge_sample:
            A_mod = A_bin.copy()
            A_mod[i,j] = A_mod[j,i] = 0
            L_mod = laplacian(A_mod)
            eigs_mod = np.linalg.eigvalsh(L_mod)
            ml = min(len(eigs), len(eigs_mod))
            shifts.append(np.sum(np.abs(eigs[:ml] - eigs_mod[:ml])))

        shifts = np.array(shifts)

        if shifts.std() > 0 and kappas.std() > 0:
            corr = np.corrcoef(kappas, shifts)[0,1]
        else:
            corr = 0

        all_corrs.append(corr)

        if corr < -0.3:
            verdict = "CONFIRMED"
        elif corr < -0.1:
            verdict = "weak"
        else:
            verdict = "no signal"

        print(f"  {name:>18}  {len(edge_sample):8d}  {corr:>+15.3f}  {verdict:>12}")

    if all_corrs:
        mean_corr = np.mean(all_corrs)
        print(f"\n  Mean r(kappa, shift) across all graphs: {mean_corr:+.3f}")
        if mean_corr < -0.3:
            print(f"  NEGATIVE RICCI CURVATURE = SPECTRAL FRAGILITY. Same law, geometric form.")
        elif mean_corr < -0.1:
            print(f"  Weak but consistent tendency.")
        else:
            print(f"  No consistent relationship.")
    print()


# === TEST 4: UNCERTAINTY PRINCIPLE — verify across types and sizes ===

def test_uncertainty_scaling():
    print("=" * 80)
    print("  TEST 4: UNCERTAINTY PRINCIPLE SCALING")
    print("  Does the minimum uncertainty product scale with n?")
    print("  Is the bound universal across graph types?")
    print("=" * 80)

    def min_uncertainty(A_bin, n_signals=50):
        n = len(A_bin)
        L = laplacian(A_bin)
        eigs, vecs = np.linalg.eigh(L)
        rng = np.random.RandomState(42)
        min_prod = float('inf')
        for _ in range(n_signals):
            # Try different signal types
            kind = rng.randint(4)
            if kind == 0:  # delta
                s = np.zeros(n); s[rng.randint(n)] = 1.0
            elif kind == 1:  # eigvec
                s = vecs[:, rng.randint(n)].copy()
            elif kind == 2:  # random
                s = rng.randn(n); s /= np.linalg.norm(s)
            else:  # diffused delta
                s = np.zeros(n); s[rng.randint(n)] = 1.0
                t = rng.exponential(2.0)
                decay = np.exp(-t * eigs)
                s = vecs @ (decay * (vecs.T @ s))
                s /= (np.linalg.norm(s) + 1e-30)

            p_s = s**2; p_s = p_s/(p_s.sum()+1e-30)
            spatial = 1.0/(np.sum(p_s**2)+1e-30)
            c = vecs.T @ s; p_c = c**2; p_c = p_c/(p_c.sum()+1e-30)
            spectral = 1.0/(np.sum(p_c**2)+1e-30)
            prod = spatial * spectral
            min_prod = min(min_prod, prod)
        return min_prod

    print(f"\n  {'graph':>22}  {'n':>4}  {'min_product':>11}  {'product/n':>9}")
    print(f"  {'---':>22}  {'---':>4}  {'---':>11}  {'---':>9}")

    for make, name in [
        (lambda n: path_graph(n), "path"),
        (lambda n: cycle_graph(n), "cycle"),
        (lambda n: star_graph(n), "star"),
        (lambda n: random_graph(n, 0.15, 42), "random(0.15)"),
    ]:
        for n in [10, 20, 40, 80]:
            A = (make(n) > 0).astype(float)
            mp = min_uncertainty(A, 80)
            print(f"  {name+'('+str(n)+')':>22}  {n:4d}  {mp:11.2f}  {mp/n:9.4f}")

    # Real repos
    for rname, rpath in get_all_repos().items():
        A_raw, files = parse_repo(rpath, 200, 2)
        if A_raw is None or len(files) < 10: continue
        A_bin = (A_raw>0).astype(float)
        n = len(files)
        mp = min_uncertainty(A_bin, 80)
        print(f"  {rname:>22}  {n:4d}  {mp:11.2f}  {mp/n:9.4f}")

    print()


# === TEST 5: SPECTRAL METABOLISM — how fast does information move? ===

def test_metabolism():
    print("=" * 80)
    print("  TEST 5: SPECTRAL METABOLISM")
    print("  How fast does information diffuse through each graph?")
    print("  Metabolism = rate at which a delta signal reaches half the nodes.")
    print("=" * 80)

    def measure_metabolism(A_bin):
        n = len(A_bin)
        L = laplacian(A_bin)
        eigs, vecs = np.linalg.eigh(L)

        # Start with delta at highest-degree node
        src = np.argmax(A_bin.sum(axis=1))
        u0 = np.zeros(n); u0[src] = 1.0

        # Find t where signal has spread to half the nodes
        # "spread" = participation ratio of u(t)^2 >= n/2
        t_low, t_high = 0.001, 50.0

        for _ in range(30):
            t_mid = (t_low + t_high) / 2
            decay = np.exp(-t_mid * eigs)
            u_t = vecs @ (decay * (vecs.T @ u0))
            p = u_t**2; p = p / (p.sum() + 1e-30)
            pr = 1.0 / (np.sum(p**2) + 1e-30)
            if pr < n / 2:
                t_low = t_mid
            else:
                t_high = t_mid

        t_half = (t_low + t_high) / 2
        metabolism = 1.0 / t_half  # faster = higher metabolism

        return t_half, metabolism

    print(f"\n  {'graph':>22}  {'n':>4}  {'gap':>8}  {'t_half':>8}  "
          f"{'metabolism':>10}  {'meta*gap':>10}")
    print(f"  {'---':>22}  {'---':>4}  {'---':>8}  {'---':>8}  "
          f"{'---':>10}  {'---':>10}")

    configs = [
        ("path(50)", path_graph(50)),
        ("cycle(50)", cycle_graph(50)),
        ("star(50)", star_graph(50)),
        ("grid(7x7)", grid_2d(7,7)),
        ("barbell(50)", barbell_graph(50)),
        ("random(50,0.10)", random_graph(50,0.10,42)),
        ("random(50,0.20)", random_graph(50,0.20,42)),
        ("random(50,0.30)", random_graph(50,0.30,42)),
    ]

    for rname, rpath in get_all_repos().items():
        A_raw, files = parse_repo(rpath, 200, 2)
        if A_raw is None or len(files) < 10:
            A_raw, files = parse_repo(rpath, 200, 1)
        if A_raw is not None and len(files) >= 10:
            configs.append((rname, (A_raw>0).astype(float)))

    meta_gap_products = []

    for name, A in configs:
        A_bin = (A>0).astype(float)
        n = len(A_bin)
        L = laplacian(A_bin)
        eigs = np.linalg.eigvalsh(L)
        nz = eigs[eigs > 1e-8]
        if len(nz) == 0: continue
        gap = nz[0]

        t_half, meta = measure_metabolism(A_bin)
        product = meta * gap

        meta_gap_products.append(product)

        print(f"  {name:>22}  {n:4d}  {gap:8.4f}  {t_half:8.3f}  "
              f"{meta:10.4f}  {product:10.4f}")

    if meta_gap_products:
        mgp = np.array(meta_gap_products)
        print(f"\n  metabolism * gap:")
        print(f"    mean = {mgp.mean():.4f}  std = {mgp.std():.4f}  "
              f"cv = {mgp.std()/mgp.mean():.2f}")
        if mgp.std() / mgp.mean() < 0.3:
            print(f"    metabolism * gap IS APPROXIMATELY CONSTANT.")
            print(f"    Information speed is governed by the spectral gap. Period.")
        else:
            print(f"    Variable. Metabolism depends on more than just the gap.")
    print()


# === TEST 6: SPECTRAL GAP DISTRIBUTION =============================

def test_gap_distribution():
    print("=" * 80)
    print("  TEST 6: SPECTRAL GAP DISTRIBUTION OF REAL REPOS")
    print("  Is there a 'natural' gap for code?")
    print("=" * 80)

    gaps = []
    names = []

    for rname, rpath in get_all_repos().items():
        for min_co in [2, 1]:
            A_raw, files = parse_repo(rpath, 200, min_co)
            if A_raw is not None and len(files) >= 10:
                A_bin = (A_raw>0).astype(float)
                L = laplacian(A_bin)
                eigs = np.linalg.eigvalsh(L)
                nz = eigs[eigs > 1e-8]
                if len(nz) > 0:
                    gaps.append(nz[0])
                    names.append(f"{rname}(co>={min_co})")
                break

    # Also sweep synthetic
    for p in [0.05, 0.08, 0.10, 0.12, 0.15, 0.20, 0.25, 0.30]:
        for n in [50, 100]:
            A = random_graph(n, p, 42)
            A_bin = (A>0).astype(float)
            L = laplacian(A_bin)
            eigs = np.linalg.eigvalsh(L)
            nz = eigs[eigs > 1e-8]
            if len(nz) > 0:
                gaps.append(nz[0])
                names.append(f"rand({n},{p})")

    print(f"\n  {'name':>22}  {'gap':>8}")
    print(f"  {'---':>22}  {'---':>8}")
    for name, gap in sorted(zip(names, gaps), key=lambda x: x[1]):
        bar = "#" * int(gap / max(gaps) * 40)
        is_repo = not name.startswith("rand")
        marker = " <-- REPO" if is_repo else ""
        print(f"  {name:>22}  {gap:8.4f}  {bar}{marker}")

    repo_gaps = [g for n, g in zip(names, gaps) if not n.startswith("rand")]
    if repo_gaps:
        print(f"\n  Repo gaps: mean={np.mean(repo_gaps):.4f}  "
              f"std={np.std(repo_gaps):.4f}  "
              f"range=[{min(repo_gaps):.4f}, {max(repo_gaps):.4f}]")
    print()


# === RUN =============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |      R A Q A   D A Y  4   M O R N I N G                |")
    print("  |   yesterday was discovery. today is science.             |")
    print("  +---------------------------------------------------------+")
    print()

    test_ricci_cross_repo()
    test_time_reversal_horizon()
    test_ricci_vs_fragility()
    test_uncertainty_scaling()
    test_metabolism()
    test_gap_distribution()

    print("=" * 80)
    print("  Day 4 morning complete. The Universe(tm) remains undefeated.")
    print("=" * 80)
