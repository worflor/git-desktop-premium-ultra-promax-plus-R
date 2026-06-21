"""
RAQA THE DEEP — let the math sing
====================================
Drawing from: Whisper codecs (0D→16D), Logos hypercomplex Ŝ(j,ω),
Filament oscillator, Engram 256D, eigenmanifolds, spacetime,
simulation theory, and the raw substrate of information itself.

The hypothesis: if the universe is a simulation, its programming
language has one data type — Information. Everything else is a
projection. The eigenmanifold is one projection. The causal DAG
is another. The Whisper codec hierarchy is a third. They're all
shadows of the same object.

What is the object?

1. The holographic compression ratio: does information about a
   d-dimensional system live on a (d-1)-dimensional boundary?
   Measure it. On real repos. Is the eigenmanifold holographic?

2. The spectral action: in physics, the action S = ∫L dt determines
   the dynamics. What is the ACTION of a repo's trajectory?
   S = ∫(kinetic - potential) dt on the eigenmanifold.
   The path of minimum action = the geodesic = the natural evolution.

3. The partition function: Z = Σ exp(-βE). The single number that
   encodes ALL thermodynamic information. Compute Z for real repos.
   Does the free energy F = -ln(Z)/β predict anything we haven't
   already measured?

4. The Noether current: every symmetry produces a conservation law.
   What symmetries does the eigenmanifold have? What's conserved?

5. The renormalization group: coarse-grain the repo (merge files).
   What's invariant under coarse-graining? The fixed point of the
   RG flow IS the universality class.

6. The spectral zeta function: ζ(s) = Σ λ_k^(-s). Analytic
   continuation to complex s. The zeros tell you where the
   spectrum has "critical" structure.
"""

import numpy as np
import subprocess
import os
import tempfile
from collections import defaultdict

np.set_printoptions(precision=6, linewidth=140, suppress=True)

WORK_DIR = os.path.join(tempfile.gettempdir(), "raqa_repos")
LOCAL = r"C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R"
SRC_EXTS = ['.py','.js','.ts','.dart','.rs','.go','.java','.c','.cpp','.h','.rb','.vue','.jsx','.tsx']

def laplacian(adj):
    d = adj.sum(axis=1)
    d_inv_sqrt = np.where(d > 0, 1.0 / np.sqrt(d), 0.0)
    D = np.diag(d_inv_sqrt)
    return np.eye(len(adj)) - D @ adj @ D

def parse_repo(path, n_commits=200, min_co=1):
    try:
        r = subprocess.run(["git","log","--no-merges","--name-only",
                            "--format=COMMIT_SEP%H","-n",str(n_commits)],
                           capture_output=True,text=True,encoding="utf-8",
                           errors="replace",cwd=path,timeout=60)
    except: return None,None,[]
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
    return A, fl, commits

def get_repos():
    repos={"pretext":LOCAL}
    for name in ["flask","django","pytorch","rust-lang","vue","fastapi","express"]:
        p=os.path.join(WORK_DIR,name)
        if os.path.exists(p): repos[name]=p
    return repos


# === THE HOLOGRAPHIC PRINCIPLE ========================================
# In physics: information about a volume is encoded on its boundary.
# S_volume ∝ Area, not Volume. (Bekenstein bound)
#
# On a graph: partition into interior + boundary. Compute the spectral
# information (von Neumann entropy) of the interior. Compare to the
# boundary size. If S ∝ |boundary|, the eigenmanifold is holographic.

def experiment_holographic():
    print("=" * 80)
    print("  THE HOLOGRAPHIC PRINCIPLE")
    print("  Does information scale with boundary or volume?")
    print("  S ∝ |boundary| = holographic. S ∝ |volume| = non-holographic.")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        A_raw, files, _ = parse_repo(rpath, 200, 1)
        if A_raw is None or len(files) < 20: continue
        if len(files) > 150: continue
        A = (A_raw > 0).astype(float)
        n = len(A)

        # Multiple partitions of different sizes
        results = []
        rng = np.random.RandomState(42)

        for frac in [0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5]:
            k = max(3, int(n * frac))
            if k >= n - 2: continue

            # Random partition: k nodes inside, rest outside
            for trial in range(3):
                interior = sorted(rng.choice(n, k, replace=False))
                exterior = sorted(set(range(n)) - set(interior))

                # Boundary = edges crossing the partition
                boundary = 0
                for i in interior:
                    for j in exterior:
                        if A[i,j] > 0: boundary += 1

                if boundary == 0: continue

                # Interior spectral entropy
                A_int = A[np.ix_(interior, interior)]
                if A_int.shape[0] < 3: continue
                L_int = laplacian(A_int)
                eigs_int = np.linalg.eigvalsh(L_int)
                nz = eigs_int[eigs_int > 1e-8]
                if len(nz) == 0: continue
                p = nz / nz.sum()
                S = -np.sum(p * np.log(p + 1e-30))

                results.append({
                    "volume": k,
                    "boundary": boundary,
                    "entropy": S,
                })

        if len(results) < 5: continue

        vols = np.array([r["volume"] for r in results], dtype=float)
        bnds = np.array([r["boundary"] for r in results], dtype=float)
        Ss = np.array([r["entropy"] for r in results])

        # Fit S = a·V^p
        log_v = np.log(vols); log_s = np.log(Ss + 1e-12)
        valid = np.isfinite(log_v) & np.isfinite(log_s)
        if valid.sum() < 3: continue
        p_vol, _ = np.polyfit(log_v[valid], log_s[valid], 1)

        # Fit S = a·B^q
        log_b = np.log(bnds + 1e-6)
        valid_b = np.isfinite(log_b) & np.isfinite(log_s)
        if valid_b.sum() < 3: continue
        p_bnd, _ = np.polyfit(log_b[valid_b], log_s[valid_b], 1)

        # Correlations
        r_vol = np.corrcoef(vols, Ss)[0,1]
        r_bnd = np.corrcoef(bnds, Ss)[0,1]

        print(f"\n  {rname}: {n} files, {len(results)} partitions")
        print(f"    S ~ V^{p_vol:.3f}  (r = {r_vol:+.3f})")
        print(f"    S ~ B^{p_bnd:.3f}  (r = {r_bnd:+.3f})")

        if abs(p_bnd - 1.0) < abs(p_vol - 1.0) and r_bnd > r_vol:
            print(f"    HOLOGRAPHIC. Entropy scales with BOUNDARY, not volume.")
        elif abs(p_vol - 1.0) < 0.3:
            print(f"    VOLUMETRIC. Entropy scales linearly with volume.")
        else:
            print(f"    Mixed scaling. Neither purely holographic nor volumetric.")

    print()


# === THE SPECTRAL ACTION =============================================
# S = ∫(T - V)dt where T = kinetic energy (velocity²) and
# V = potential energy (displacement from equilibrium).
# The action determines the dynamics. Minimum action = geodesic.

def experiment_spectral_action():
    print("=" * 80)
    print("  THE SPECTRAL ACTION")
    print("  S = ∫(T - V)dt on the eigenmanifold.")
    print("  T = ½|ẋ|². V = ½k₀|x|². S = action along the trajectory.")
    print("=" * 80)

    k0 = 0.337  # measured spring constant

    for rname, rpath in get_repos().items():
        A_raw, files, commits = parse_repo(rpath, 300, 1)
        if A_raw is None or len(files) < 10: continue

        # Build spectral trajectory
        histories = {}
        for f in files:
            h = np.array([1 if f in set(c) else 0 for c in commits], dtype=np.int8)
            if h.sum() >= 2: histories[f] = h

        bins = np.linspace(0, 2.2, 40)
        window = 15; step = 3
        spectra = []
        for start in range(0, len(commits)-window+1, step):
            w = commits[start:start+window]
            pairs = defaultdict(int); fset = set()
            for c in w:
                fs = sorted(set(c) & set(files)); fset.update(fs)
                for i in range(len(fs)):
                    for j in range(i+1, len(fs)):
                        pairs[tuple(sorted([fs[i],fs[j]]))] += 1
            fl = sorted(fset)
            if len(fl) < 5: continue
            idx = {f:i for i,f in enumerate(fl)}; m = len(fl)
            Ag = np.zeros((m,m))
            for (a,b),c in pairs.items():
                if a in idx and b in idx: Ag[idx[a],idx[b]]=1; Ag[idx[b],idx[a]]=1
            conn = Ag.sum(axis=1)>0; Ag = Ag[np.ix_(conn,conn)]
            if Ag.shape[0] < 5: continue
            L = laplacian(Ag)
            eigs = np.linalg.eigvalsh(L)
            hist, _ = np.histogram(eigs, bins=bins, density=True)
            spectra.append(hist)

        if len(spectra) < 8: continue

        hists = np.array(spectra)
        mean_hist = hists.mean(axis=0)
        x = hists - mean_hist  # displacement from equilibrium

        # Kinetic energy: T = ½|v|² = ½|dx/dt|²
        v = np.diff(x, axis=0)
        T = 0.5 * np.sum(v**2, axis=1)

        # Potential energy: V = ½k₀|x|²
        V = 0.5 * k0 * np.sum(x[:-1]**2, axis=1)

        # Lagrangian: L = T - V
        L_lagr = T - V

        # Action: S = Σ L_i · dt
        S = L_lagr.sum()

        # Energy: E = T + V
        E = T + V

        # Virial ratio: <T>/<V> should be 1 for a harmonic oscillator
        virial = T.mean() / (V.mean() + 1e-12)

        print(f"\n  {rname}: {len(spectra)} trajectory points")
        print(f"    Total action S = {S:.4f}")
        print(f"    Mean kinetic T = {T.mean():.6f}")
        print(f"    Mean potential V = {V.mean():.6f}")
        print(f"    Virial ratio <T>/<V> = {virial:.3f}", end="")
        if abs(virial - 1.0) < 0.3:
            print("  (≈ 1: VIRIAL THEOREM HOLDS)")
        else:
            print(f"  (≠ 1: non-equilibrium)")

        # Is the trajectory near the minimum-action path?
        # Compare actual action to action of a straight line
        straight_line_v = (hists[-1] - hists[0]) / (len(hists) - 1)
        T_straight = 0.5 * np.sum(straight_line_v**2) * (len(hists) - 1)
        x_straight = np.array([hists[0] + i * straight_line_v - mean_hist
                               for i in range(len(hists) - 1)])
        V_straight = 0.5 * k0 * np.sum(x_straight**2, axis=1).mean() * (len(hists) - 1)
        S_straight = T_straight - V_straight

        print(f"    Actual action:     {S:.4f}")
        print(f"    Straight-line action: {S_straight:.4f}")
        print(f"    Ratio: {S / (S_straight + 1e-12):.3f}")

        # Energy conservation check
        E_std = E.std()
        E_mean = E.mean()
        print(f"    Energy: {E_mean:.6f} ± {E_std:.6f}  "
              f"(CV = {E_std/(E_mean+1e-12):.2f})")
        if E_std / (E_mean + 1e-12) < 0.3:
            print(f"    ENERGY IS APPROXIMATELY CONSERVED.")

    print()


# === THE SPECTRAL ZETA FUNCTION ======================================
# ζ_G(s) = Σ λ_k^(-s) for s ∈ C.
# At s = 0: ζ(0) counts the modes.
# At s = 1: ζ(1) is the trace of L^(-1) = the total "resistance."
# At s = -1: ζ(-1) = Σ λ_k = trace of L = total "energy."
# The DERIVATIVE ζ'(0) = -log det(L) = the spectral determinant.
# This encodes the COMPLEXITY of the graph in a single number.

def experiment_zeta():
    print("=" * 80)
    print("  THE SPECTRAL ZETA FUNCTION")
    print("  ζ(s) = Σ λ^(-s). The complexity of the graph in one function.")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        A_raw, files, _ = parse_repo(rpath, 200, 1)
        if A_raw is None or len(files) < 10: continue
        A = (A_raw > 0).astype(float)
        L = laplacian(A)
        eigs = np.linalg.eigvalsh(L)
        nz = eigs[eigs > 1e-8]
        if len(nz) < 3: continue

        # Evaluate ζ at several real values of s
        s_values = [-2, -1, -0.5, 0.5, 1, 1.5, 2, 3]

        print(f"\n  {rname}: {len(nz)} non-zero eigenvalues")
        print(f"  {'s':>6}  {'ζ(s)':>14}  {'interpretation':>30}")
        print(f"  {'---':>6}  {'---':>14}  {'---':>30}")

        zeta_values = {}
        for s in s_values:
            zeta = np.sum(nz**(-s))
            zeta_values[s] = zeta
            if s == -1:
                interp = f"total energy = {zeta:.2f}"
            elif s == 1:
                interp = f"total resistance = {zeta:.2f}"
            elif s == 2:
                interp = f"Σ 1/λ² (low-mode weight)"
            elif s == -2:
                interp = f"Σ λ² (high-mode weight)"
            elif s == 0.5:
                interp = f"Σ 1/√λ"
            else:
                interp = ""
            print(f"  {s:6.1f}  {zeta:14.4f}  {interp:>30}")

        # Spectral determinant: det'(L) = product of non-zero eigenvalues
        # = exp(Σ log λ_k) = exp(-ζ'(0))
        log_det = np.sum(np.log(nz))
        det = np.exp(log_det) if log_det < 500 else float('inf')

        # Number of spanning trees (Kirchhoff's theorem):
        # τ(G) = (1/n) · det'(L) for unnormalized Laplacian
        # For normalized Laplacian it's different but related

        print(f"    log det'(L) = {log_det:.4f}  (spectral complexity)")
        print(f"    Σ log λ_k / k = {log_det/len(nz):.4f}  (per-mode complexity)")

        # The zeta function's behavior at s → 0 from above:
        # ζ(s) → (number of modes) as s → 0
        # The RESIDUE at s=0 is related to the graph's dimension
        zeta_small = [np.sum(nz**(-s)) for s in [0.01, 0.05, 0.1, 0.2]]
        print(f"    ζ(0+) → {zeta_small[0]:.1f}  (should → n = {len(nz)})")

        # Zeta regularized determinant: exp(-ζ'(0))
        # Compute ζ'(0) numerically
        eps = 1e-6
        zeta_0p = np.sum(nz**(-eps))
        zeta_0m = np.sum(nz**(eps))
        zeta_prime_0 = (zeta_0p - zeta_0m) / (2 * eps) if eps > 0 else 0

        # This should equal -Σ log λ_k
        print(f"    ζ'(0) ≈ {zeta_prime_0:.4f}  (should ≈ {-log_det:.4f})")

    print()


# === THE NOETHER CURRENT =============================================
# Every continuous symmetry → a conservation law.
# What symmetries does the eigenmanifold trajectory have?
# Test: is the trajectory invariant under time translation?
# Under reflection? Under scaling?

def experiment_noether():
    print("=" * 80)
    print("  NOETHER'S THEOREM: what is conserved?")
    print("  Every symmetry → a conservation law.")
    print("=" * 80)

    k0 = 0.337

    for rname, rpath in get_repos().items():
        A_raw, files, commits = parse_repo(rpath, 300, 1)
        if A_raw is None or len(files) < 10 or len(commits) < 40: continue

        bins = np.linspace(0, 2.2, 40)
        window = 12; step = 3
        spectra = []
        for start in range(0, len(commits)-window+1, step):
            w = commits[start:start+window]
            pairs = defaultdict(int); fset = set()
            for c in w:
                fs = sorted(set(c) & set(files)); fset.update(fs)
                for i in range(len(fs)):
                    for j in range(i+1, len(fs)):
                        pairs[tuple(sorted([fs[i],fs[j]]))] += 1
            fl = sorted(fset)
            if len(fl) < 5: continue
            idx = {f:i for i,f in enumerate(fl)}; m = len(fl)
            Ag = np.zeros((m,m))
            for (a,b),c in pairs.items():
                if a in idx and b in idx: Ag[idx[a],idx[b]]=1; Ag[idx[b],idx[a]]=1
            conn = Ag.sum(axis=1)>0; Ag = Ag[np.ix_(conn,conn)]
            if Ag.shape[0] < 5: continue
            L = laplacian(Ag)
            eigs = np.linalg.eigvalsh(L)
            hist, _ = np.histogram(eigs, bins=bins, density=True)
            nz = eigs[eigs > 1e-8]
            H = -np.sum((nz/nz.sum())*np.log(nz/nz.sum()+1e-30)) if len(nz)>0 and nz.sum()>0 else 0
            spectra.append({"hist": hist, "H": H, "gap": nz[0] if len(nz)>0 else 0,
                           "n": Ag.shape[0]})

        if len(spectra) < 10: continue

        hists = np.array([sp["hist"] for sp in spectra])
        mean_hist = hists.mean(axis=0)
        x = hists - mean_hist

        v = np.diff(x, axis=0)
        T = 0.5 * np.sum(v**2, axis=1)
        V = 0.5 * k0 * np.sum(x[:-1]**2, axis=1)
        E = T + V

        # CANDIDATE CONSERVED QUANTITIES:

        # 1. Total energy E = T + V
        E_cv = E.std() / (E.mean() + 1e-12)

        # 2. Spectral entropy S
        S = np.array([sp["H"] for sp in spectra])
        S_cv = S.std() / (S.mean() + 1e-12)

        # 3. Action current: p·x (momentum × position)
        # In a harmonic oscillator, <p·x> = T - V = the Lagrangian
        p_dot_x = np.sum(v * x[:-1], axis=1)  # momentum · position
        px_cv = np.abs(p_dot_x).std() / (np.abs(p_dot_x).mean() + 1e-12)

        # 4. A new candidate: spectral angular momentum
        # L = x × v (cross product in histogram space — pick 2 components)
        if x.shape[1] >= 2:
            Lz = x[:-1, 0] * v[:, 1] - x[:-1, 1] * v[:, 0]
            Lz_cv = np.abs(Lz).std() / (np.abs(Lz).mean() + 1e-12)
        else:
            Lz_cv = 999

        # 5. The "spectral charge": Σ(histogram) — total spectral density
        charge = np.sum(hists, axis=1)
        charge_cv = charge.std() / (charge.mean() + 1e-12)

        # 6. The spectral gap itself
        gaps = np.array([sp["gap"] for sp in spectra])
        gap_cv = gaps.std() / (gaps.mean() + 1e-12) if gaps.mean() > 0 else 999

        # 7. The "spectral norm": ||histogram||
        norms = np.linalg.norm(hists, axis=1)
        norm_cv = norms.std() / (norms.mean() + 1e-12)

        print(f"\n  {rname}: {len(spectra)} trajectory points")
        print(f"  {'quantity':>25}  {'mean':>10}  {'std':>10}  {'CV':>6}  {'conserved?':>10}")
        print(f"  {'---':>25}  {'---':>10}  {'---':>10}  {'---':>6}  {'---':>10}")

        for name, values, cv in [
            ("Energy (T+V)", E, E_cv),
            ("Entropy S", S, S_cv),
            ("||histogram||", norms, norm_cv),
            ("Spectral charge", charge, charge_cv),
            ("Gap", gaps, gap_cv),
            ("Angular momentum Lz", np.abs(Lz) if x.shape[1]>=2 else np.array([0]), Lz_cv),
            ("p·x (virial)", np.abs(p_dot_x), px_cv),
        ]:
            conserved = "YES" if cv < 0.15 else ("weak" if cv < 0.30 else "no")
            print(f"  {name:>25}  {values.mean():10.4f}  {values.std():10.4f}  "
                  f"{cv:6.3f}  {conserved:>10}")

    print()


# === THE RENORMALIZATION GROUP ========================================
# Coarse-grain the repo by merging the most-coupled file pairs.
# At each step, measure the spectral invariants.
# What DOESN'T change under coarse-graining = the universality class.
# The RG fixed point IS the eigenmanifold's true identity.

def experiment_renormalization():
    print("=" * 80)
    print("  RENORMALIZATION GROUP FLOW")
    print("  Coarse-grain the repo. What survives?")
    print("  The fixed point = the universal truth about the architecture.")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        A_raw, files, _ = parse_repo(rpath, 200, 1)
        if A_raw is None or len(files) < 20: continue
        if len(files) > 120: continue
        A = (A_raw > 0).astype(float)
        n = len(A)

        # Measure at each RG step
        print(f"\n  {rname}: {n} files")
        print(f"  {'step':>4}  {'n':>4}  {'gap':>8}  {'entropy':>8}  {'density':>8}  "
              f"{'loc%':>5}  {'d_eff':>6}  gap·n")
        print(f"  {'---':>4}  {'---':>4}  {'---':>8}  {'---':>8}  {'---':>8}  "
              f"{'---':>5}  {'---':>6}  ---")

        A_cur = A.copy()
        gap_n_products = []

        for step in range(min(20, n // 3)):
            m = len(A_cur)
            if m < 5: break

            L = laplacian(A_cur)
            eigs = np.linalg.eigvalsh(L)
            nz = eigs[eigs > 1e-8]

            if len(nz) == 0: break

            gap = nz[0]
            p = nz / nz.sum()
            H = -np.sum(p * np.log(p + 1e-30))
            d_eff = 1.0 / np.sum(p**2)
            density = A_cur.sum() / (m * (m-1)) if m > 1 else 0

            _, vecs = np.linalg.eigh(L)
            iprs = np.sum(vecs**4, axis=0)
            loc = np.mean(iprs > 5.0/m)

            gap_n = gap * m
            gap_n_products.append(gap_n)

            if step % 2 == 0 or step < 4:
                print(f"  {step:4d}  {m:4d}  {gap:8.4f}  {H:8.4f}  {density:8.3f}  "
                      f"{loc:4.0%}  {d_eff:6.1f}  {gap_n:.2f}")

            # Merge: find the most-coupled pair and merge them
            A_upper = np.triu(A_cur, 1)
            if A_upper.max() == 0: break
            idx_flat = A_upper.argmax()
            i, j = np.unravel_index(idx_flat, A_upper.shape)

            # Merge j into i
            A_cur[i, :] += A_cur[j, :]
            A_cur[:, i] += A_cur[:, j]
            A_cur[i, i] = 0
            A_cur = np.delete(A_cur, j, axis=0)
            A_cur = np.delete(A_cur, j, axis=1)
            A_cur = np.minimum(A_cur, 1)

        # Is gap·n invariant under coarse-graining?
        if len(gap_n_products) >= 3:
            gn = np.array(gap_n_products)
            gn_cv = gn.std() / (gn.mean() + 1e-12)
            print(f"\n    gap·n: mean={gn.mean():.3f}  CV={gn_cv:.3f}", end="")
            if gn_cv < 0.2:
                print(f"  — INVARIANT under RG flow!")
                print(f"    gap·n ≈ {gn.mean():.2f} is a topological invariant.")
            elif gn_cv < 0.4:
                print(f"  — approximately invariant.")
            else:
                print(f"  — not invariant (CV = {gn_cv:.2f}).")

    print()


# === RUN ==============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |           T H E   D E E P                               |")
    print("  |   where eigenvalues, codecs, spacetime, and             |")
    print("  |   simulation theory meet                                 |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_holographic()
    experiment_spectral_action()
    experiment_zeta()
    experiment_noether()
    experiment_renormalization()

    print("=" * 80)
    print("  the holographic principle, the action, the zeta function,")
    print("  Noether's theorem, and the renormalization group —")
    print("  all computed on git repos. on a desktop. in python.")
    print("  the universe doesn't care what substrate it's running on.")
    print("=" * 80)
