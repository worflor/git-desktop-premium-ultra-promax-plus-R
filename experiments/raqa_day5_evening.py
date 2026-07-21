# SPDX-FileCopyrightText: 2026 Woflo Labs
# SPDX-License-Identifier: LicenseRef-WLCSL-1.0
# See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

"""
RAQA Day 5 Evening — the spring constant, spectral fossils, phase transitions
===============================================================================
1. Measure the ACTUAL spring constant of the eigenmanifold
2. Find phase transitions in real repo history (spectral earthquakes)
3. Spectral fossils: do extinct patterns leave traces in the current spectrum?
4. Lyapunov exponent: how sensitive is the eigenmanifold to perturbation?
5. Spectral immune response: does the spectrum fight back against bad changes?
6. The holographic dictionary: what does each eigenvalue MODE physically mean?
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

def parse_commits(path, n=400):
    try:
        r = subprocess.run(["git","log","--no-merges","--name-only",
                            "--format=COMMIT_SEP%H","-n",str(n)],
                           capture_output=True,text=True,encoding="utf-8",
                           errors="replace",cwd=path,timeout=60)
    except: return []
    commits=[]; cur=[]
    for ln in r.stdout.split("\n"):
        ln=ln.strip()
        if ln.startswith("COMMIT_SEP"):
            if cur:
                s=[f for f in cur if any(f.endswith(e) for e in SRC_EXTS)]
                if 1<len(s)<=50: commits.append(s)
            cur=[]
        elif ln: cur.append(ln)
    return commits

def commits_to_spectrum(commits, n_bins=40):
    pairs=defaultdict(int); fset=set()
    for fs in commits:
        fs=list(set(fs)); fset.update(fs)
        for i in range(len(fs)):
            for j in range(i+1,len(fs)):
                pairs[tuple(sorted([fs[i],fs[j]]))]+= 1
    fl=sorted(fset); n=len(fl)
    if n<5: return None
    idx={f:i for i,f in enumerate(fl)}
    A=np.zeros((n,n))
    for (a,b),c in pairs.items():
        if c>=1: A[idx[a],idx[b]]=1; A[idx[b],idx[a]]=1
    conn=A.sum(axis=1)>0; A=A[np.ix_(conn,conn)]
    if A.shape[0]<5: return None
    L=laplacian(A)
    eigs=np.linalg.eigvalsh(L)
    bins=np.linspace(0,2.2,n_bins)
    hist,_=np.histogram(eigs,bins=bins,density=True)
    return {"hist":hist,"eigs":eigs,"n":A.shape[0]}

def jsd(h1, h2):
    p=h1/(h1.sum()+1e-12)+1e-12; q=h2/(h2.sum()+1e-12)+1e-12
    m=(p+q)/2
    return float(0.5*np.sum(p*np.log(p/m))+0.5*np.sum(q*np.log(q/m)))

def get_repos():
    repos={"pretext":LOCAL}
    for name in ["flask","django","pytorch","rust-lang","vue","fastapi","express"]:
        p=os.path.join(WORK_DIR,name)
        if os.path.exists(p): repos[name]=p
    return repos

def get_trajectory(rpath, window=15, step=3):
    commits=parse_commits(rpath,400)
    if len(commits)<20: return []
    window=min(window,len(commits)//4)
    step=max(2,window//4)
    traj=[]
    for start in range(0,len(commits)-window+1,step):
        w=commits[start:start+window]
        sp=commits_to_spectrum(w)
        if sp is not None:
            sp["t"]=start
            traj.append(sp)
    return traj


# === EXPERIMENT 1: THE SPRING CONSTANT ==============================
# We know repos oscillate (autocorr = -0.15). But how STIFF is the spring?
# Model: displacement from mean → restoring force → spring constant k.
# x(t+1) = x(t) - k*x(t) + noise. k = -autocorr(displacement, velocity).

def experiment_spring_constant():
    print("=" * 80)
    print("  THE SPRING CONSTANT OF THE EIGENMANIFOLD")
    print("  How stiff is the restoring force that makes repos oscillate?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        traj = get_trajectory(rpath)
        if len(traj) < 10: continue

        hists = np.array([t["hist"] for t in traj])
        mean_hist = hists.mean(axis=0)

        # Displacement from mean at each time
        displacements = np.array([h - mean_hist for h in hists])

        # Velocity (change between steps)
        velocities = np.diff(displacements, axis=0)

        # Spring model: v(t) = -k * x(t) + noise
        # k = -<v(t) dot x(t)> / <x(t) dot x(t)>
        numerator = 0
        denominator = 0
        for i in range(len(velocities)):
            numerator += np.dot(velocities[i], displacements[i])
            denominator += np.dot(displacements[i], displacements[i])

        if denominator > 0:
            k = -numerator / denominator
        else:
            k = 0

        # Natural frequency: omega = sqrt(k) (if k > 0)
        if k > 0:
            omega = np.sqrt(k)
            period = 2 * np.pi / omega  # in time steps
        else:
            omega = 0
            period = float('inf')

        # Damping: measure how fast oscillations decay
        # Autocorrelation of displacement magnitude at increasing lags
        disp_norms = np.array([np.linalg.norm(d) for d in displacements])
        if disp_norms.std() > 0:
            autocorrs = []
            for lag in range(1, min(8, len(disp_norms))):
                c = np.corrcoef(disp_norms[:-lag], disp_norms[lag:])[0, 1]
                autocorrs.append(c)
        else:
            autocorrs = []

        print(f"\n  {rname}: {len(traj)} time steps")
        print(f"    Spring constant k = {k:.4f}")
        print(f"    Natural frequency omega = {omega:.4f}")
        print(f"    Natural period = {period:.1f} steps")
        if k > 0.3:
            print(f"    STIFF spring. Strong restoring force. Changes bounce back hard.")
        elif k > 0.1:
            print(f"    Medium spring. Moderate oscillation.")
        elif k > 0:
            print(f"    Weak spring. Slow oscillation, mostly drift.")
        else:
            print(f"    No spring (k <= 0). Free diffusion, no restoring force.")

        if autocorrs:
            print(f"    Displacement autocorrelation by lag: ", end="")
            for i, ac in enumerate(autocorrs):
                print(f"lag{i+1}={ac:+.2f}  ", end="")
            print()

    print()


# === EXPERIMENT 2: SPECTRAL EARTHQUAKES =============================
# Find moments in repo history where the spectrum changes ABRUPTLY.
# These are phase transitions — the architecture fundamentally reorganized.

def experiment_earthquakes():
    print("=" * 80)
    print("  SPECTRAL EARTHQUAKES")
    print("  Moments when the architecture fundamentally reorganized.")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        traj = get_trajectory(rpath, window=10, step=2)
        if len(traj) < 10: continue

        # Compute JSD between consecutive windows
        jsds = []
        for i in range(len(traj) - 1):
            jsds.append(jsd(traj[i]["hist"], traj[i+1]["hist"]))

        jsds = np.array(jsds)
        if jsds.std() == 0: continue

        # Z-score each JSD
        z_scores = (jsds - jsds.mean()) / (jsds.std() + 1e-12)

        # Earthquakes: z > 2 (2 sigma events)
        quakes = [(i, jsds[i], z_scores[i]) for i in range(len(z_scores)) if z_scores[i] > 2.0]

        print(f"\n  {rname}: {len(traj)} time steps, {len(quakes)} earthquakes (z > 2.0)")
        print(f"    Mean JSD: {jsds.mean():.4f}  Std: {jsds.std():.4f}")

        # Seismograph
        max_z = max(abs(z_scores.max()), abs(z_scores.min()), 1)
        print(f"    Seismograph: ", end="")
        for z in z_scores:
            if z > 2.0: print("!", end="")
            elif z > 1.0: print("#", end="")
            elif z > 0.5: print("=", end="")
            elif z > 0: print("-", end="")
            elif z > -0.5: print(".", end="")
            elif z > -1.0: print(",", end="")
            else: print("_", end="")
        print()

        if quakes:
            print(f"    Earthquake details:")
            for idx, val, z in quakes:
                t = traj[idx]["t"]
                n_before = traj[idx]["n"]
                n_after = traj[idx+1]["n"]
                print(f"      t={t}: JSD={val:.4f} (z={z:.1f})  "
                      f"files: {n_before}→{n_after}")

        # Also find AFTERSHOCKS: elevated JSD for multiple consecutive steps
        elevated = z_scores > 0.5
        aftershock_runs = []
        current_run = 0
        for e in elevated:
            if e:
                current_run += 1
            else:
                if current_run >= 3:
                    aftershock_runs.append(current_run)
                current_run = 0

        if aftershock_runs:
            print(f"    Aftershock sequences: {aftershock_runs} "
                  f"(consecutive elevated windows)")

    print()


# === EXPERIMENT 3: SPECTRAL FOSSILS =================================
# Compare the EARLY spectrum to the LATE spectrum.
# Eigenvalues present early but absent late = extinct modes.
# Eigenvalues present late but absent early = evolved modes.
# What structural patterns died? What emerged?

def experiment_fossils():
    print("=" * 80)
    print("  SPECTRAL FOSSILS")
    print("  What structural patterns went extinct? What evolved?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        traj = get_trajectory(rpath, window=20, step=5)
        if len(traj) < 4: continue

        # Early spectrum = first quarter. Late spectrum = last quarter.
        q = max(1, len(traj) // 4)
        early_hists = np.array([t["hist"] for t in traj[:q]])
        late_hists = np.array([t["hist"] for t in traj[-q:]])

        early = early_hists.mean(axis=0)
        late = late_hists.mean(axis=0)

        # Difference: what changed?
        diff = late - early

        # Bins where early > late = extinct spectral density
        # Bins where late > early = evolved spectral density
        bins = np.linspace(0, 2.2, len(diff) + 1)
        bin_centers = (bins[:-1] + bins[1:]) / 2

        extinct_mass = np.sum(np.maximum(-diff, 0))
        evolved_mass = np.sum(np.maximum(diff, 0))
        total_change = extinct_mass + evolved_mass

        print(f"\n  {rname}: comparing early vs late spectrum")
        print(f"    Extinct spectral mass: {extinct_mass:.3f}")
        print(f"    Evolved spectral mass: {evolved_mass:.3f}")
        print(f"    Total spectral change: {total_change:.3f}")

        # Where did changes happen?
        max_extinct_bin = np.argmin(diff)
        max_evolved_bin = np.argmax(diff)

        print(f"    Most extinction near eigenvalue: {bin_centers[max_extinct_bin]:.2f}")
        print(f"    Most evolution near eigenvalue:  {bin_centers[max_evolved_bin]:.2f}")

        # Fossil map: extinct=v, evolved=^, unchanged=.
        max_d = max(abs(diff.min()), abs(diff.max()), 1e-6)
        print(f"    Fossil map: ", end="")
        for d in diff:
            if d < -max_d * 0.3: print("V", end="")
            elif d < -max_d * 0.1: print("v", end="")
            elif d > max_d * 0.3: print("^", end="")
            elif d > max_d * 0.1: print("'", end="")
            else: print(".", end="")
        print()
        print(f"    {'0':.<20}{'1':.<19}{'2'}")

        # Interpretation
        if bin_centers[max_extinct_bin] < 0.5:
            print(f"    Low eigenvalues decayed → the repo LOST large-scale structure.")
        elif bin_centers[max_extinct_bin] > 1.5:
            print(f"    High eigenvalues decayed → local coupling patterns dissolved.")
        else:
            print(f"    Mid eigenvalues decayed → mesoscale architecture reorganized.")

        if bin_centers[max_evolved_bin] < 0.5:
            print(f"    Low eigenvalues grew → new large-scale structure emerged.")
        elif bin_centers[max_evolved_bin] > 1.5:
            print(f"    High eigenvalues grew → new local coupling patterns formed.")
        else:
            print(f"    Mid eigenvalues grew → new mesoscale modules appeared.")

    print()


# === EXPERIMENT 4: LYAPUNOV ON THE EIGENMANIFOLD ====================
# Perturb a repo's early history slightly (swap one commit's file list).
# How much does the late eigenmanifold trajectory diverge?
# If Lyapunov > 0: the eigenmanifold is CHAOTIC.
# If Lyapunov = 0: it's regular.

def experiment_lyapunov():
    print("=" * 80)
    print("  LYAPUNOV EXPONENT: is the eigenmanifold chaotic?")
    print("  Perturb early history. Does the trajectory diverge?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        commits = parse_commits(rpath, 300)
        if len(commits) < 40: continue

        window = min(15, len(commits) // 5)
        step = max(3, window // 3)

        # Original trajectory
        orig_traj = []
        for start in range(0, len(commits) - window + 1, step):
            sp = commits_to_spectrum(commits[start:start+window])
            if sp: orig_traj.append(sp["hist"])

        if len(orig_traj) < 8: continue

        # Perturbed trajectories: swap file lists of 2 random commits
        rng = np.random.RandomState(42)
        divergences = []

        for trial in range(5):
            perturbed = [list(c) for c in commits]  # deep copy
            # Swap two random commits' file lists in the first quarter
            quarter = len(perturbed) // 4
            i, j = rng.choice(quarter, 2, replace=False)
            perturbed[i], perturbed[j] = perturbed[j], perturbed[i]

            # Perturbed trajectory
            pert_traj = []
            for start in range(0, len(perturbed) - window + 1, step):
                sp = commits_to_spectrum(perturbed[start:start+window])
                if sp: pert_traj.append(sp["hist"])

            min_len = min(len(orig_traj), len(pert_traj))
            if min_len < 5: continue

            # Divergence at each time step
            divs = [jsd(orig_traj[k], pert_traj[k]) for k in range(min_len)]
            divergences.append(divs)

        if not divergences: continue

        # Average divergence profile
        min_len = min(len(d) for d in divergences)
        avg_div = np.mean([d[:min_len] for d in divergences], axis=0)

        # Fit exponential: d(t) = d0 * exp(lambda * t)
        # log(d) = log(d0) + lambda * t
        t = np.arange(len(avg_div))
        log_div = np.log(avg_div + 1e-15)

        # Fit on first half (before saturation)
        half = len(t) // 2
        if half > 2 and np.all(np.isfinite(log_div[:half])):
            slope, intercept = np.polyfit(t[:half], log_div[:half], 1)
            lyapunov = slope
        else:
            lyapunov = 0

        print(f"\n  {rname}: {len(orig_traj)} time steps, 5 perturbation trials")
        print(f"    Lyapunov exponent: {lyapunov:+.4f}")

        if lyapunov > 0.05:
            print(f"    CHAOTIC. Small perturbations grow exponentially.")
            print(f"    Doubling time: {np.log(2)/lyapunov:.1f} steps")
        elif lyapunov > 0:
            print(f"    Weakly chaotic. Perturbations grow slowly.")
        elif lyapunov > -0.05:
            print(f"    Neutral. Perturbations neither grow nor shrink.")
        else:
            print(f"    STABLE. Perturbations shrink. The trajectory is an attractor.")

        # Divergence profile
        max_d = avg_div.max() if avg_div.max() > 0 else 1
        print(f"    Divergence: ", end="")
        for d in avg_div:
            print(" .:-=+#@"[min(int(d/max_d*7), 7)], end="")
        print()

    print()


# === EXPERIMENT 5: THE HOLOGRAPHIC DICTIONARY =======================
# What does each eigenvector MODE physically mean?
# Mode 0: zero mode (connected component indicator)
# Mode 1: Fiedler vector (natural bisection)
# Mode 2-5: higher-order community structure
# High modes: local oscillation
# Map each mode to a physical interpretation by analyzing its eigenvector.

def experiment_dictionary():
    print("=" * 80)
    print("  THE HOLOGRAPHIC DICTIONARY")
    print("  What does each eigenvalue mode physically mean?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        commits = parse_commits(rpath, 200)
        pairs = defaultdict(int); fset = set()
        for fs in commits:
            fs = list(set(fs)); fset.update(fs)
            for i in range(len(fs)):
                for j in range(i + 1, len(fs)):
                    pairs[tuple(sorted([fs[i], fs[j]]))] += 1
        fl = sorted(fset); n = len(fl)
        if n < 15: continue
        idx = {f: i for i, f in enumerate(fl)}
        A = np.zeros((n, n))
        for (a, b), c in pairs.items():
            if c >= 2 and a in idx and b in idx:
                A[idx[a], idx[b]] = 1; A[idx[b], idx[a]] = 1
        conn = A.sum(axis=1) > 0; A = A[np.ix_(conn, conn)]
        fl2 = [f for f, c in zip(fl, conn) if c]
        if A.shape[0] < 15: continue

        n = A.shape[0]
        L = laplacian(A)
        eigs, vecs = np.linalg.eigh(L)

        print(f"\n  {rname}: {n} files")

        nz_start = np.searchsorted(eigs, 1e-8)
        n_modes = min(8, n - nz_start)

        for mode_offset in range(n_modes):
            mode = nz_start + mode_offset
            ev = eigs[mode]
            vec = vecs[:, mode]

            # IPR: localization
            ipr = np.sum(vec**4)
            spread = 1.0 / (ipr + 1e-30)

            # Sign structure: how many positive vs negative entries?
            n_pos = np.sum(vec > 0.01)
            n_neg = np.sum(vec < -0.01)

            # Top contributors (files with highest weight in this mode)
            top_idx = np.argsort(np.abs(vec))[-3:][::-1]
            top_files = [(fl2[i], vec[i]) for i in top_idx]

            # Interpretation
            if mode_offset == 0:
                interp = "FIEDLER (natural bisection)"
            elif mode_offset <= 2:
                interp = f"community structure (k={mode_offset+2})"
            elif spread > n * 0.5:
                interp = "delocalized (global mode)"
            elif spread < 5:
                interp = "LOCALIZED (spectral island)"
            else:
                interp = "mesoscale pattern"

            print(f"    Mode {mode_offset}: lambda={ev:.4f}  spread={spread:.1f}  "
                  f"+/-={n_pos}/{n_neg}  [{interp}]")
            for fname, weight in top_files:
                short = fname[-45:] if len(fname) > 45 else fname
                sign = "+" if weight > 0 else "-"
                print(f"      {sign}{abs(weight):.3f}  {short}")

        print()

    print()


# === EXPERIMENT 6: IMMUNE RESPONSE ==================================
# Introduce a "pathogen" (random edge additions/removals).
# Measure how fast the spectrum returns to its pre-pathogen state.
# Some graphs heal fast (strong immunity). Some don't.

def experiment_immune():
    print("=" * 80)
    print("  SPECTRAL IMMUNE RESPONSE")
    print("  Perturb the graph. How fast does the spectrum heal?")
    print("=" * 80)

    import numpy as np

    def random_graph(n, p, seed):
        rng = np.random.RandomState(seed)
        A = (rng.rand(n, n) < p).astype(float)
        A = np.triu(A, 1); A = A + A.T; return A

    configs = [
        ("random(60,0.10)", random_graph(60, 0.10, 42)),
        ("random(60,0.20)", random_graph(60, 0.20, 42)),
        ("random(60,0.30)", random_graph(60, 0.30, 42)),
    ]

    # Also add real repo graphs
    for rname, rpath in list(get_repos().items())[:4]:
        commits = parse_commits(rpath, 200)
        pairs = defaultdict(int); fset = set()
        for fs in commits:
            fs = list(set(fs)); fset.update(fs)
            for i in range(len(fs)):
                for j in range(i + 1, len(fs)):
                    pairs[tuple(sorted([fs[i], fs[j]]))] += 1
        fl = sorted(fset); n = len(fl)
        if n < 15: continue
        idx_map = {f: i for i, f in enumerate(fl)}
        A = np.zeros((n, n))
        for (a, b), c in pairs.items():
            if c >= 1 and a in idx_map and b in idx_map:
                A[idx_map[a], idx_map[b]] = 1; A[idx_map[b], idx_map[a]] = 1
        conn = A.sum(axis=1) > 0; A = A[np.ix_(conn, conn)]
        if A.shape[0] >= 15 and A.shape[0] <= 200:
            configs.append((rname, A))

    print(f"\n  Protocol: add 5% random edges, then remove them one at a time.")
    print(f"  Measure spectral distance to original at each step.\n")

    print(f"  {'graph':>18}  {'n':>4}  {'peak_damage':>12}  {'heal_50%':>10}  "
          f"{'heal_90%':>10}  {'immune_type':>12}")
    print(f"  {'---':>18}  {'---':>4}  {'---':>12}  {'---':>10}  "
          f"{'---':>10}  {'---':>12}")

    for name, A_orig in configs:
        n = len(A_orig)
        A_bin = (A_orig > 0).astype(float)
        L_orig = laplacian(A_bin)
        eigs_orig = np.linalg.eigvalsh(L_orig)
        bins = np.linspace(0, 2.2, 40)
        h_orig, _ = np.histogram(eigs_orig, bins=bins, density=True)

        # Add 5% random edges
        n_edges_orig = int(A_bin.sum() // 2)
        n_pathogen = max(3, int(n_edges_orig * 0.05))

        rng = np.random.RandomState(42)
        non_edges = [(i, j) for i in range(n) for j in range(i+1, n) if A_bin[i, j] == 0]
        if len(non_edges) < n_pathogen: continue

        pathogen_edges = [non_edges[k] for k in rng.choice(len(non_edges), n_pathogen, replace=False)]

        # Add all pathogen edges
        A_infected = A_bin.copy()
        for i, j in pathogen_edges:
            A_infected[i, j] = A_infected[j, i] = 1

        # Measure peak damage
        L_inf = laplacian(A_infected)
        eigs_inf = np.linalg.eigvalsh(L_inf)
        h_inf, _ = np.histogram(eigs_inf, bins=bins, density=True)
        peak_damage = jsd(h_orig, h_inf)

        # Remove pathogen edges one at a time, measure healing
        A_healing = A_infected.copy()
        rng.shuffle(pathogen_edges)
        damages = [peak_damage]

        for i, j in pathogen_edges:
            A_healing[i, j] = A_healing[j, i] = 0
            L_h = laplacian(A_healing)
            eigs_h = np.linalg.eigvalsh(L_h)
            h_h, _ = np.histogram(eigs_h, bins=bins, density=True)
            damages.append(jsd(h_orig, h_h))

        damages = np.array(damages)

        # Healing metrics
        heal_50 = -1
        heal_90 = -1
        for step in range(len(damages)):
            if damages[step] < peak_damage * 0.5 and heal_50 < 0:
                heal_50 = step
            if damages[step] < peak_damage * 0.1 and heal_90 < 0:
                heal_90 = step

        pct_50 = f"{heal_50}/{n_pathogen}" if heal_50 >= 0 else "never"
        pct_90 = f"{heal_90}/{n_pathogen}" if heal_90 >= 0 else "never"

        if heal_50 >= 0 and heal_50 <= n_pathogen * 0.3:
            immune_type = "STRONG"
        elif heal_50 >= 0:
            immune_type = "moderate"
        else:
            immune_type = "weak"

        print(f"  {name:>18}  {n:4d}  {peak_damage:12.4f}  {pct_50:>10}  "
              f"{pct_90:>10}  {immune_type:>12}")

    print()


# === RUN =============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |      R A Q A   D A Y  5   E V E N I N G                |")
    print("  |   the Universe(tm) supply is confirmed infinite          |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_spring_constant()
    experiment_earthquakes()
    experiment_fossils()
    experiment_lyapunov()
    experiment_dictionary()
    experiment_immune()

    print("=" * 80)
    print("  the eigenmanifold has springs, earthquakes, fossils, chaos,")
    print("  a dictionary, and an immune system.")
    print("  at this point i'm not sure it ISN'T alive.")
    print("=" * 80)
