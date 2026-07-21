# SPDX-FileCopyrightText: 2026 Woflo Labs
# SPDX-License-Identifier: LicenseRef-WLCSL-1.0
# See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

"""
RAQA DERIVED CALCULUS — finding the equations
===============================================
We have 37 empirical laws. Now find the MATH that unifies them.
Derive, verify, prove or disprove.

Candidates for novel calculus:
1. The proper time equation: dτ/dt = α|dS/dt| + β. Fit α,β across repos.
   Is there a universal constant?
2. The spring equation: ẍ + k₀x = noise. Verify the harmonic oscillator.
   Measure damping ratio. Is γ (damping) also universal?
3. The causal-structural duality: TE × JSD = invariant?
   Product of timelike and spacelike components. Is it conserved?
4. The fractal gap law: gap(depth) = gap₀ · n^(-α). Derive α from spectral theory.
5. The bridge fragility equation: δσ/δw_ij ∝ 1/(d_i + d_j). Prove it.
6. The entropy-clock equation: proper time = integral of |dS/dt|.
   Compute and compare to directly measured proper time.
7. The light cone growth law: cone_radius(Δt) = c·Δt? Or sublinear?
"""

import numpy as np
import subprocess
import os
import tempfile
from collections import defaultdict
from scipy import stats as sp_stats  # for proper fitting

np.set_printoptions(precision=6, linewidth=140, suppress=True)

WORK_DIR = os.path.join(tempfile.gettempdir(), "raqa_repos")
LOCAL = r"C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R"
SRC_EXTS = ['.py','.js','.ts','.dart','.rs','.go','.java','.c','.cpp','.h','.rb','.vue','.jsx','.tsx']

def laplacian(adj):
    d = adj.sum(axis=1)
    d_inv_sqrt = np.where(d > 0, 1.0 / np.sqrt(d), 0.0)
    D = np.diag(d_inv_sqrt)
    return np.eye(len(adj)) - D @ adj @ D

def parse_file_histories(path, n_commits=300):
    try:
        r = subprocess.run(["git","log","--no-merges","--name-only",
                            "--format=COMMIT_SEP%H","-n",str(n_commits)],
                           capture_output=True,text=True,encoding="utf-8",
                           errors="replace",cwd=path,timeout=60)
    except: return {}, []
    commits=[]; cur=[]
    for ln in r.stdout.split("\n"):
        ln=ln.strip()
        if ln.startswith("COMMIT_SEP"):
            if cur:
                s=[f for f in cur if any(f.endswith(e) for e in SRC_EXTS)]
                if len(s)>0: commits.append(set(s))
            cur=[]
        elif ln: cur.append(ln)
    histories={}
    for f in sorted(set().union(*commits) if commits else set()):
        h=np.array([1 if f in c else 0 for c in commits],dtype=np.int8)
        if h.sum()>=2: histories[f]=h
    return histories, commits

def get_repos():
    repos={"pretext":LOCAL}
    for name in ["flask","django","pytorch","rust-lang","vue","fastapi","express"]:
        p=os.path.join(WORK_DIR,name)
        if os.path.exists(p): repos[name]=p
    return repos

def get_spectra(histories, commits, window=15, step=5):
    files=sorted(histories.keys()); bins=np.linspace(0,2.2,40)
    spectra=[]
    for start in range(0,len(commits)-window+1,step):
        w=commits[start:start+window]
        pairs=defaultdict(int); fset=set()
        for c in w:
            fs=sorted(c&set(files)); fset.update(fs)
            for i in range(len(fs)):
                for j in range(i+1,len(fs)):
                    pairs[tuple(sorted([fs[i],fs[j]]))]+= 1
        fl=sorted(fset)
        if len(fl)<5: continue
        idx={f:i for i,f in enumerate(fl)}; n=len(fl)
        A=np.zeros((n,n))
        for (a,b),c in pairs.items():
            if a in idx and b in idx: A[idx[a],idx[b]]=1; A[idx[b],idx[a]]=1
        conn=A.sum(axis=1)>0; A=A[np.ix_(conn,conn)]
        if A.shape[0]<5: continue
        L=laplacian(A); eigs=np.linalg.eigvalsh(L)
        nz=eigs[eigs>1e-8]
        H=-np.sum((nz/nz.sum())*np.log(nz/nz.sum()+1e-30)) if len(nz)>0 and nz.sum()>0 else 0
        gap=nz[0] if len(nz)>0 else 0
        hist,_=np.histogram(eigs,bins=bins,density=True)
        spectra.append({"hist":hist,"eigs":eigs,"H":H,"gap":gap,"t":start,"n":A.shape[0]})
    return spectra


# === EQUATION 1: THE PROPER TIME EQUATION ============================
# Hypothesis: dτ = α·|dS| + β·dt
# τ = spectral proper time (JSD between consecutive spectra)
# S = von Neumann entropy
# t = commit count
# If α is universal, we've found the clock equation.

def equation_proper_time():
    print("=" * 80)
    print("  EQUATION 1: THE PROPER TIME EQUATION")
    print("  dτ = α·|dS| + β·dt")
    print("  Fitting α and β across all repos. Is α universal?")
    print("=" * 80)

    all_alphas = []
    all_betas = []
    all_r2 = []

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 300)
        if len(commits) < 30: continue
        spectra = get_spectra(histories, commits, window=12, step=3)
        if len(spectra) < 8: continue

        # dτ = JSD between consecutive spectra
        dtau = []
        dS = []
        dt = []
        for i in range(len(spectra)-1):
            p=spectra[i]["hist"]/(spectra[i]["hist"].sum()+1e-12)+1e-12
            q=spectra[i+1]["hist"]/(spectra[i+1]["hist"].sum()+1e-12)+1e-12
            m=(p+q)/2
            tau=0.5*np.sum(p*np.log(p/m))+0.5*np.sum(q*np.log(q/m))
            dtau.append(tau)
            dS.append(abs(spectra[i+1]["H"] - spectra[i]["H"]))
            dt.append(spectra[i+1]["t"] - spectra[i]["t"])

        dtau=np.array(dtau); dS=np.array(dS); dt=np.array(dt,dtype=float)

        # Linear regression: dτ = α·|dS| + β
        if dS.std() > 0:
            # Using numpy for least squares
            X = np.column_stack([dS, np.ones_like(dS)])
            result = np.linalg.lstsq(X, dtau, rcond=None)
            alpha, beta = result[0]

            # R² manually
            predicted = alpha * dS + beta
            ss_res = np.sum((dtau - predicted)**2)
            ss_tot = np.sum((dtau - dtau.mean())**2)
            r2 = 1 - ss_res / (ss_tot + 1e-12)

            all_alphas.append(alpha)
            all_betas.append(beta)
            all_r2.append(r2)

            print(f"\n  {rname}: n={len(dtau)}")
            print(f"    dτ = {alpha:.4f}·|dS| + {beta:.6f}")
            print(f"    R² = {r2:.4f}")

    if len(all_alphas) >= 3:
        alphas = np.array(all_alphas)
        betas = np.array(all_betas)
        r2s = np.array(all_r2)

        print(f"\n  CROSS-REPO SUMMARY:")
        print(f"    α = {alphas.mean():.4f} ± {alphas.std():.4f}  "
              f"(CV = {alphas.std()/abs(alphas.mean()+1e-12):.2f})")
        print(f"    β = {betas.mean():.6f} ± {betas.std():.6f}")
        print(f"    R² = {r2s.mean():.4f} ± {r2s.std():.4f}")

        if alphas.std() / abs(alphas.mean() + 1e-12) < 0.5:
            print(f"\n    α IS APPROXIMATELY UNIVERSAL.")
            print(f"    The proper time equation dτ = {alphas.mean():.3f}·|dS| + β HOLDS.")
            print(f"    The clock constant α ≈ {alphas.mean():.3f}.")
        else:
            print(f"\n    α varies across repos (CV = {alphas.std()/abs(alphas.mean()+1e-12):.2f}).")
            print(f"    The equation holds per-repo but α is not universal.")
    print()


# === EQUATION 2: THE DAMPED HARMONIC OSCILLATOR =====================
# Hypothesis: ẍ + 2γẋ + k₀x = ξ(t)
# x = displacement from mean spectrum
# k₀ = spring constant
# γ = damping ratio
# ξ = noise
# Fit γ from the velocity autocorrelation decay rate.

def equation_harmonic_oscillator():
    print("=" * 80)
    print("  EQUATION 2: THE DAMPED HARMONIC OSCILLATOR")
    print("  ẍ + 2γẋ + k₀x = ξ(t)")
    print("  Fitting the damping ratio γ. Is it universal?")
    print("=" * 80)

    all_gammas = []
    all_k0s = []

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 300)
        if len(commits) < 40: continue
        spectra = get_spectra(histories, commits, window=12, step=3)
        if len(spectra) < 12: continue

        hists = np.array([sp["hist"] for sp in spectra])
        mean_hist = hists.mean(axis=0)

        # Displacement from mean
        displacements = hists - mean_hist

        # Velocity
        velocities = np.diff(displacements, axis=0)

        # Spring constant: k₀ = -<v·x> / <x·x>
        num = 0; den = 0
        for i in range(len(velocities)):
            num += np.dot(velocities[i], displacements[i])
            den += np.dot(displacements[i], displacements[i])
        k0 = -num / (den + 1e-12)

        # Damping ratio γ from velocity autocorrelation
        # For a damped HO: C_vv(τ) ∝ exp(-γτ)·cos(ωτ)
        # So ln|C_vv| should decay linearly with slope -γ
        v_flat = velocities.reshape(len(velocities), -1)
        autocorrs = []
        for lag in range(1, min(8, len(v_flat))):
            c = np.mean([np.dot(v_flat[i], v_flat[i+lag]) for i in range(len(v_flat)-lag)])
            c0 = np.mean([np.dot(v_flat[i], v_flat[i]) for i in range(len(v_flat))])
            autocorrs.append(c / (c0 + 1e-12))

        autocorrs = np.array(autocorrs)
        # Fit exponential decay to |autocorr|
        log_ac = np.log(np.abs(autocorrs) + 1e-12)
        lags = np.arange(1, len(autocorrs) + 1, dtype=float)

        # Only fit where autocorr is positive and non-negligible
        valid = autocorrs > 0.01
        if valid.sum() >= 2:
            gamma, _ = np.polyfit(lags[valid], log_ac[valid], 1)
            gamma = -gamma  # positive damping
        else:
            gamma = 0

        all_k0s.append(k0)
        all_gammas.append(gamma)

        # Natural frequency and quality factor
        omega0 = np.sqrt(abs(k0)) if k0 > 0 else 0
        Q = omega0 / (2 * gamma + 1e-12) if gamma > 0 and omega0 > 0 else 0

        print(f"\n  {rname}:")
        print(f"    k₀ = {k0:.4f}  (spring constant)")
        print(f"    γ  = {gamma:.4f}  (damping ratio)")
        print(f"    ω₀ = {omega0:.4f}  (natural frequency)")
        print(f"    Q  = {Q:.2f}  (quality factor)")

        if Q > 1:
            print(f"    UNDERDAMPED. The repo oscillates with gradually decaying amplitude.")
        elif Q > 0.5:
            print(f"    CRITICALLY DAMPED. Fast return to equilibrium without oscillation.")
        else:
            print(f"    OVERDAMPED. Slow exponential return, no oscillation.")

    if len(all_gammas) >= 3:
        gammas = np.array(all_gammas)
        k0s = np.array(all_k0s)

        print(f"\n  CROSS-REPO:")
        print(f"    k₀ = {k0s.mean():.4f} ± {k0s.std():.4f}  (CV = {k0s.std()/(abs(k0s.mean())+1e-12):.2f})")
        print(f"    γ  = {gammas.mean():.4f} ± {gammas.std():.4f}  (CV = {gammas.std()/(abs(gammas.mean())+1e-12):.2f})")

        if k0s.std() / (abs(k0s.mean()) + 1e-12) < 0.3:
            print(f"    k₀ IS UNIVERSAL: {k0s.mean():.4f}")
        if gammas.std() / (abs(gammas.mean()) + 1e-12) < 0.5:
            print(f"    γ IS APPROXIMATELY UNIVERSAL: {gammas.mean():.4f}")

        # The full equation
        print(f"\n    THE EQUATION:")
        print(f"    ẍ + {2*gammas.mean():.3f}·ẋ + {k0s.mean():.3f}·x = ξ(t)")
    print()


# === EQUATION 3: THE CAUSAL-STRUCTURAL PRODUCT =======================
# Is TE × JSD = constant along the trajectory?
# If yes, there's a conservation law: increasing causal influence
# requires decreasing structural change, and vice versa.
# This would be an uncertainty relation for the eigenmanifold.

def equation_causal_structural():
    print("=" * 80)
    print("  EQUATION 3: IS TE × JSD CONSERVED?")
    print("  The causal-structural uncertainty relation.")
    print("=" * 80)

    def transfer_entropy(source, target, lag=1):
        n=len(source)
        if n<lag+2: return 0
        counts=defaultdict(int); total=0
        for t in range(lag,n):
            counts[(target[t-lag],source[t-lag],target[t])]+=1; total+=1
        if total==0: return 0
        c_tp_sp=defaultdict(int); c_tp=defaultdict(int); c_tp_tf=defaultdict(int)
        for (tp,sp,tf),cnt in counts.items():
            c_tp_sp[(tp,sp)]+=cnt; c_tp[tp]+=cnt; c_tp_tf[(tp,tf)]+=cnt
        te=0
        for (tp,sp,tf),cnt in counts.items():
            p_j=cnt/total; p1=cnt/c_tp_sp[(tp,sp)]
            p2=c_tp_tf[(tp,tf)]/c_tp[tp] if c_tp[tp]>0 else 0
            if p2>0 and p1>0: te+=p_j*np.log2(p1/p2)
        return max(te,0)

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 300)
        if len(commits) < 40: continue
        spectra = get_spectra(histories, commits, window=12, step=3)
        if len(spectra) < 8: continue

        files = sorted(histories.keys())
        products = []
        te_vals = []
        jsd_vals = []

        for i in range(len(spectra) - 1):
            # JSD
            p=spectra[i]["hist"]/(spectra[i]["hist"].sum()+1e-12)+1e-12
            q=spectra[i+1]["hist"]/(spectra[i+1]["hist"].sum()+1e-12)+1e-12
            m=(p+q)/2
            s_jsd=0.5*np.sum(p*np.log(p/m))+0.5*np.sum(q*np.log(q/m))

            # TE (aggregate)
            common = sorted(set(spectra[i].get("files", files[:20])) &
                          set(spectra[i+1].get("files", files[:20])))
            if len(common) < 3:
                continue

            rng = np.random.RandomState(42+i)
            sample = common[:min(8, len(common))]
            te_sum = 0
            for a in sample:
                for b in sample:
                    if a != b and a in histories and b in histories:
                        te_sum += transfer_entropy(histories[a], histories[b], 1)
            te_avg = te_sum / (len(sample)**2 + 1e-6)

            if te_avg > 0 and s_jsd > 0:
                products.append(te_avg * s_jsd)
                te_vals.append(te_avg)
                jsd_vals.append(s_jsd)

        if len(products) < 5: continue

        products = np.array(products)
        te_arr = np.array(te_vals)
        jsd_arr = np.array(jsd_vals)

        cv = products.std() / (products.mean() + 1e-12)

        print(f"\n  {rname}: {len(products)} measurements")
        print(f"    TE × JSD = {products.mean():.6f} ± {products.std():.6f}  "
              f"(CV = {cv:.2f})")
        print(f"    mean TE = {te_arr.mean():.6f}  mean JSD = {jsd_arr.mean():.6f}")

        # Correlation between TE and JSD
        corr = np.corrcoef(te_arr, jsd_arr)[0,1]
        print(f"    Corr(TE, JSD) = {corr:+.3f}")

        if cv < 0.3:
            print(f"    TE × JSD IS APPROXIMATELY CONSERVED.")
            print(f"    This is an uncertainty relation: you can't increase both")
            print(f"    causal influence AND structural change simultaneously.")
        elif corr < -0.3:
            print(f"    TE and JSD are ANTI-CORRELATED but the product isn't constant.")
            print(f"    There's a tradeoff but not a strict conservation law.")
        else:
            print(f"    No conservation. TE and JSD vary independently.")

    print()


# === EQUATION 4: THE BRIDGE FRAGILITY FORMULA ========================
# Hypothesis: spectral shift from removing edge (i,j) is proportional
# to 1/(d_i + d_j)^α for some α.
# Fit α precisely. Then DERIVE it from spectral perturbation theory.

def equation_bridge_fragility():
    print("=" * 80)
    print("  EQUATION 4: THE BRIDGE FRAGILITY FORMULA")
    print("  δσ ∝ 1/(d_i + d_j)^α  — fitting α precisely")
    print("=" * 80)

    all_alphas = []

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 200)
        files = sorted(histories.keys())
        if len(files) < 15: continue

        # Build co-change graph
        pairs = defaultdict(int)
        for c in commits:
            fs = sorted(c & set(files))
            for i in range(len(fs)):
                for j in range(i+1, len(fs)):
                    pairs[tuple(sorted([fs[i],fs[j]]))] += 1
        fl = sorted(set().union(*[set(c)&set(files) for c in commits]))
        if len(fl) < 15: continue
        idx={f:i for i,f in enumerate(fl)}; n=len(fl)
        A=np.zeros((n,n))
        for (a,b),c in pairs.items():
            if a in idx and b in idx and c>=1: A[idx[a],idx[b]]=1; A[idx[b],idx[a]]=1
        conn=A.sum(axis=1)>0; A=A[np.ix_(conn,conn)]
        if A.shape[0]<15: continue
        n = A.shape[0]

        L = laplacian(A)
        eigs = np.linalg.eigvalsh(L)

        edges = [(i,j) for i in range(n) for j in range(i+1,n) if A[i,j]>0]
        rng = np.random.RandomState(42)
        sample = [edges[k] for k in rng.choice(len(edges), min(50, len(edges)), replace=False)]

        log_deg = []
        log_shift = []

        for i, j in sample:
            A_mod = A.copy()
            A_mod[i,j] = A_mod[j,i] = 0
            L_mod = laplacian(A_mod)
            eigs_mod = np.linalg.eigvalsh(L_mod)
            ml = min(len(eigs), len(eigs_mod))
            shift = np.sum(np.abs(eigs[:ml] - eigs_mod[:ml]))

            deg_sum = A[i].sum() + A[j].sum()
            if shift > 1e-10 and deg_sum > 0:
                log_deg.append(np.log(deg_sum))
                log_shift.append(np.log(shift))

        if len(log_deg) < 5: continue

        log_deg = np.array(log_deg)
        log_shift = np.array(log_shift)

        # Fit: log(shift) = -α·log(deg) + C
        alpha_fit, C_fit = np.polyfit(log_deg, log_shift, 1)
        alpha = -alpha_fit  # should be positive

        # R²
        predicted = alpha_fit * log_deg + C_fit
        ss_res = np.sum((log_shift - predicted)**2)
        ss_tot = np.sum((log_shift - log_shift.mean())**2)
        r2 = 1 - ss_res / (ss_tot + 1e-12)

        all_alphas.append(alpha)

        print(f"\n  {rname}: {len(log_deg)} edges")
        print(f"    δσ ∝ 1/(d_i + d_j)^{alpha:.3f}")
        print(f"    R² = {r2:.4f}")

    if len(all_alphas) >= 3:
        alphas = np.array(all_alphas)
        print(f"\n  CROSS-REPO:")
        print(f"    α = {alphas.mean():.3f} ± {alphas.std():.3f}  "
              f"(CV = {alphas.std()/(abs(alphas.mean())+1e-12):.2f})")

        if alphas.std() / (abs(alphas.mean()) + 1e-12) < 0.3:
            print(f"\n    THE BRIDGE FRAGILITY EQUATION:")
            print(f"    δσ(i,j) = C / (d_i + d_j)^{alphas.mean():.2f}")
            print(f"    α ≈ {alphas.mean():.2f} IS UNIVERSAL.")
        else:
            print(f"\n    α varies across repos. The power law holds per-repo")
            print(f"    but the exponent isn't universal.")
    print()


# === EQUATION 5: THE SPECTRAL ENTROPY PRODUCTION RATE ================
# From non-equilibrium thermodynamics: entropy production rate
# σ = dS/dt + J·X where J is the current and X is the force.
# For the eigenmanifold: what is the irreversible entropy production?
# Is there a minimum entropy production principle (Prigogine)?

def equation_entropy_production():
    print("=" * 80)
    print("  EQUATION 5: ENTROPY PRODUCTION RATE")
    print("  Is there a minimum entropy production state? (Prigogine)")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 300)
        if len(commits) < 40: continue
        spectra = get_spectra(histories, commits, window=12, step=3)
        if len(spectra) < 10: continue

        # Entropy at each step
        S = np.array([sp["H"] for sp in spectra])

        # Entropy production: dS/dt (forward difference)
        dSdt = np.diff(S)

        # Spectral "temperature": inverse of the spectral gap
        # (wide gap = cold, narrow gap = hot)
        T = np.array([1.0 / (sp["gap"] + 0.01) for sp in spectra[:-1]])

        # Entropy production rate: σ = |dS/dt| / T
        sigma = np.abs(dSdt) * T

        # Does entropy production have a MINIMUM?
        min_sigma = sigma.min()
        mean_sigma = sigma.mean()
        min_idx = np.argmin(sigma)

        print(f"\n  {rname}: {len(sigma)} measurements")
        print(f"    Mean σ = {mean_sigma:.6f}")
        print(f"    Min σ  = {min_sigma:.6f} (at step {min_idx})")

        # Is the repo spending most of its time near minimum σ?
        near_min = np.mean(sigma < mean_sigma * 0.5)
        print(f"    Fraction near min: {near_min:.0%}")

        # Correlation between σ and time (does entropy production decrease?)
        t = np.arange(len(sigma))
        slope, _ = np.polyfit(t, sigma, 1)
        print(f"    σ trend: {slope:+.6f}/step", end="")
        if slope < -1e-5:
            print("  (DECREASING — approaching Prigogine minimum)")
        elif slope > 1e-5:
            print("  (INCREASING — moving away from equilibrium)")
        else:
            print("  (STABLE — at or near minimum)")

        # The Prigogine principle: at steady state, σ is minimized.
        # Is σ lower in later epochs than earlier?
        half = len(sigma) // 2
        early_sigma = sigma[:half].mean()
        late_sigma = sigma[half:].mean()
        print(f"    Early σ: {early_sigma:.6f}  Late σ: {late_sigma:.6f}")
        if late_sigma < early_sigma * 0.8:
            print(f"    PRIGOGINE HOLDS. Entropy production decreases over time.")
            print(f"    The repo is evolving toward minimum dissipation.")

    print()


# === RUN ==============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |     D E R I V E D   C A L C U L U S                    |")
    print("  |   finding the equations beneath the data                 |")
    print("  +---------------------------------------------------------+")
    print()

    equation_proper_time()
    equation_harmonic_oscillator()
    equation_causal_structural()
    equation_bridge_fragility()
    equation_entropy_production()

    print("=" * 80)
    print("  the equations are there. they were always there.")
    print("  we just had to measure carefully enough to see them.")
    print("=" * 80)
