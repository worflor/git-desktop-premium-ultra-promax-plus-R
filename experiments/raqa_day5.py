"""
RAQA Day 5 — Universe™ supply: infinite
=========================================
1. Spectral attractor: IS there a ground state all repos fall toward?
2. Eigenmanifold weather: can we forecast the next spectral state?
3. Phase portrait: velocity vs position on the eigenmanifold
4. Spectral entropy rate: how fast is the repo LEARNING (or forgetting)?
5. The Fiedler cut across time: does the natural bisection drift?
6. Spectral momentum: do repos have inertia on the eigenmanifold?
7. Conway's Law as a theorem: does team structure = spectral structure?
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
    if n<5: return None,None,None,None
    idx={f:i for i,f in enumerate(fl)}
    A=np.zeros((n,n))
    for (a,b),c in pairs.items():
        if c>=1: A[idx[a],idx[b]]=1; A[idx[b],idx[a]]=1
    conn=A.sum(axis=1)>0; A=A[np.ix_(conn,conn)]
    fl2=[f for f,c in zip(fl,conn) if c]
    if A.shape[0]<5: return None,None,None,None
    L=laplacian(A)
    eigs,vecs=np.linalg.eigh(L)
    bins=np.linspace(0,2.2,n_bins)
    hist,_=np.histogram(eigs,bins=bins,density=True)
    return hist, eigs, vecs, fl2

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

def get_trajectory(rpath, window=20, step=5):
    commits=parse_commits(rpath,400)
    if len(commits)<30: return []
    window=min(window,len(commits)//4)
    step=max(3,window//3)
    traj=[]
    for start in range(0,len(commits)-window+1,step):
        w=commits[start:start+window]
        h,eigs,vecs,files=commits_to_spectrum(w)
        if h is not None:
            traj.append({"hist":h,"eigs":eigs,"vecs":vecs,"files":files,"t":start})
    return traj


# === EXPERIMENT 1: SPECTRAL ATTRACTOR ===============================
# Average all repos' late-stage spectra. Is there a convergent shape?
# Compare each repo's final spectrum to the "universal mature spectrum."

def experiment_attractor():
    print("=" * 80)
    print("  IS THERE A UNIVERSAL SPECTRAL ATTRACTOR?")
    print("  Do all repos converge toward the same eigenvalue distribution?")
    print("=" * 80)

    final_spectra = {}
    all_trajectories = {}

    for rname, rpath in get_repos().items():
        traj = get_trajectory(rpath)
        if len(traj) < 3: continue
        final_spectra[rname] = traj[-1]["hist"]
        all_trajectories[rname] = traj

    if len(final_spectra) < 3:
        print("  Not enough repos."); return

    # Compute the "universal attractor" = average of all final spectra
    names = list(final_spectra.keys())
    all_hists = np.array([final_spectra[n] for n in names])
    attractor = all_hists.mean(axis=0)

    # Distance from each repo's final state to the attractor
    print(f"\n  Universal attractor = mean of {len(names)} repos' final spectra\n")

    print(f"  {'repo':>12}  {'d_to_attractor':>14}  {'d_start→end':>12}  {'d_start→attr':>13}  {'moving_toward':>14}")
    print(f"  {'---':>12}  {'---':>14}  {'---':>12}  {'---':>13}  {'---':>14}")

    toward_count = 0

    for rname in names:
        traj = all_trajectories[rname]
        d_final = jsd(final_spectra[rname], attractor)
        d_start_end = jsd(traj[0]["hist"], traj[-1]["hist"])
        d_start_attr = jsd(traj[0]["hist"], attractor)

        moving_toward = d_final < d_start_attr
        if moving_toward: toward_count += 1

        print(f"  {rname:>12}  {d_final:14.4f}  {d_start_end:12.4f}  "
              f"{d_start_attr:13.4f}  {'YES' if moving_toward else 'no':>14}")

    print(f"\n  {toward_count}/{len(names)} repos are moving TOWARD the universal attractor.")

    if toward_count > len(names) * 0.6:
        print(f"  ATTRACTOR EXISTS. Most repos converge toward a common spectral shape.")
        print(f"  The eigenmanifold has a ground state.")
    elif toward_count > len(names) * 0.4:
        print(f"  Weak evidence for an attractor. Some converge, some diverge.")
    else:
        print(f"  No universal attractor. Repos evolve independently.")

    # What does the attractor look like?
    print(f"\n  Attractor shape (eigenvalue density):")
    max_a = attractor.max()
    print(f"    ", end="")
    for a in attractor:
        print(" .:-=+#@"[min(int(a/max_a*7),7)], end="")
    print(f"\n    {'0':.<20}{'1':.<19}{'2'}")

    # Dispersion: how spread are repos around the attractor?
    dists = [jsd(final_spectra[n], attractor) for n in names]
    print(f"\n  Dispersion around attractor: mean={np.mean(dists):.4f}  std={np.std(dists):.4f}")
    print()


# === EXPERIMENT 2: SPECTRAL MOMENTUM ================================
# Does a repo's current direction predict its next step?
# If yes: repos have INERTIA on the eigenmanifold.

def experiment_momentum():
    print("=" * 80)
    print("  SPECTRAL MOMENTUM: do repos have inertia?")
    print("  Does the current direction predict the next step?")
    print("=" * 80)

    all_autocorrs = []

    for rname, rpath in get_repos().items():
        traj = get_trajectory(rpath, window=15, step=3)
        if len(traj) < 8: continue

        # Velocity vectors (differences between consecutive histogram points)
        velocities = []
        for i in range(len(traj)-1):
            v = traj[i+1]["hist"] - traj[i]["hist"]
            velocities.append(v)

        if len(velocities) < 4: continue

        # Autocorrelation of velocity: does v(t) predict v(t+1)?
        # Compute dot product of consecutive velocity vectors (normalized)
        dots = []
        for i in range(len(velocities)-1):
            n1 = np.linalg.norm(velocities[i])
            n2 = np.linalg.norm(velocities[i+1])
            if n1 > 1e-10 and n2 > 1e-10:
                dot = np.dot(velocities[i], velocities[i+1]) / (n1 * n2)
                dots.append(dot)

        if not dots: continue

        dots = np.array(dots)
        mean_dot = dots.mean()
        all_autocorrs.append(mean_dot)

        if mean_dot > 0.2:
            label = "HAS MOMENTUM (keeps going same direction)"
        elif mean_dot < -0.2:
            label = "ANTI-MOMENTUM (oscillates/reverses)"
        else:
            label = "no momentum (random walk)"

        print(f"\n  {rname}: {len(velocities)} velocity vectors")
        print(f"    Mean velocity autocorrelation: {mean_dot:+.3f}  [{label}]")

        # Direction persistence: how many steps before the direction decorrelates?
        for lag in [1, 2, 3, 5]:
            if lag >= len(velocities): break
            lag_dots = []
            for i in range(len(velocities)-lag):
                n1 = np.linalg.norm(velocities[i])
                n2 = np.linalg.norm(velocities[i+lag])
                if n1 > 1e-10 and n2 > 1e-10:
                    lag_dots.append(np.dot(velocities[i], velocities[i+lag]) / (n1*n2))
            if lag_dots:
                print(f"    Autocorrelation at lag {lag}: {np.mean(lag_dots):+.3f}")

    if all_autocorrs:
        mean_all = np.mean(all_autocorrs)
        print(f"\n  Cross-repo mean momentum: {mean_all:+.3f}")
        if mean_all < -0.1:
            print(f"  ANTI-MOMENTUM IS UNIVERSAL. Repos oscillate on the eigenmanifold.")
            print(f"  Each step is followed by a partial reversal. Spectral breathing.")
        elif mean_all > 0.1:
            print(f"  MOMENTUM IS UNIVERSAL. Repos have inertia. Changes persist.")
        else:
            print(f"  No universal momentum. Some oscillate, some persist, some wander.")
    print()


# === EXPERIMENT 3: SPECTRAL ENTROPY RATE ============================
# How fast is the INFORMATION CONTENT of the spectrum changing?
# Shannon entropy of eigenvalue distribution over time.
# Increasing = the spectrum is getting more complex (learning).
# Decreasing = simplifying (forgetting/consolidating).

def experiment_entropy_rate():
    print("=" * 80)
    print("  SPECTRAL ENTROPY RATE: is the codebase LEARNING or FORGETTING?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        traj = get_trajectory(rpath, window=15, step=3)
        if len(traj) < 6: continue

        # Compute spectral entropy at each time step
        entropies = []
        for pt in traj:
            eigs = pt["eigs"]
            nz = eigs[eigs > 1e-8]
            if len(nz) > 0:
                p = nz / nz.sum()
                H = -np.sum(p * np.log(p + 1e-30))
            else:
                H = 0
            entropies.append(H)

        entropies = np.array(entropies)

        # Fit linear trend
        t = np.arange(len(entropies))
        slope, intercept = np.polyfit(t, entropies, 1)

        # Entropy rate = slope
        if slope > 0.01:
            label = "LEARNING (growing complexity)"
        elif slope < -0.01:
            label = "FORGETTING (simplifying)"
        else:
            label = "stable"

        # Entropy profile
        H_min, H_max = entropies.min(), entropies.max()
        H_range = H_max - H_min if H_max > H_min else 1

        print(f"\n  {rname}: {len(entropies)} measurements")
        print(f"    H range: [{H_min:.3f}, {H_max:.3f}]  mean={entropies.mean():.3f}")
        print(f"    Entropy rate: {slope:+.4f} nats/step  [{label}]")
        print(f"    Profile: ", end="")
        for H in entropies:
            level = int((H - H_min) / H_range * 7) if H_range > 0 else 0
            print(" .:-=+#@"[min(level, 7)], end="")
        print()

    print()


# === EXPERIMENT 4: SPECTRAL FORECAST ================================
# Use the last N points on the eigenmanifold to predict the next one.
# Linear extrapolation in PCA space. How accurate?

def experiment_forecast():
    print("=" * 80)
    print("  SPECTRAL FORECAST: can we predict the next eigenspace?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        traj = get_trajectory(rpath, window=15, step=3)
        if len(traj) < 10: continue

        hists = np.array([pt["hist"] for pt in traj])

        # PCA on the trajectory
        X = hists - hists.mean(axis=0)
        U, S, Vt = np.linalg.svd(X, full_matrices=False)
        # Project into top-k PCA space
        k = min(4, len(S))
        coords = X @ Vt[:k].T  # (n_points, k)

        # Forecast: use linear extrapolation from last 3 points
        # Test: predict each point from the 3 before it
        errors = []
        baselines = []

        for i in range(3, len(coords)):
            # Linear extrapolation from i-3, i-2, i-1 to predict i
            v1 = coords[i-1] - coords[i-2]
            v2 = coords[i-2] - coords[i-3]
            avg_v = (v1 + v2) / 2
            predicted = coords[i-1] + avg_v
            actual = coords[i]

            err = np.linalg.norm(predicted - actual)
            # Baseline: just repeat the last point
            baseline_err = np.linalg.norm(coords[i-1] - actual)
            errors.append(err)
            baselines.append(baseline_err)

        errors = np.array(errors)
        baselines = np.array(baselines)

        # Skill score: 1 - (forecast error / baseline error)
        skill = 1 - errors.mean() / (baselines.mean() + 1e-12)

        # Also try: can we predict the JSD to next point?
        jsd_errors = []
        for i in range(3, len(hists)):
            pred_hist = hists[i-1] + (hists[i-1] - hists[i-2])  # linear extrap
            pred_hist = np.maximum(pred_hist, 0)
            actual_jsd = jsd(hists[i-1], hists[i])
            pred_jsd = jsd(hists[i-1], pred_hist)
            jsd_errors.append(abs(actual_jsd - pred_jsd))

        print(f"\n  {rname}: {len(coords)} points in {k}-dim PCA space")
        print(f"    Forecast skill (1 = perfect, 0 = no better than baseline, <0 = worse):")
        print(f"    Linear extrapolation skill: {skill:+.3f}")
        print(f"    Mean forecast error: {errors.mean():.4f}")
        print(f"    Mean baseline error: {baselines.mean():.4f}")

        if skill > 0.1:
            print(f"    THE TRAJECTORY IS PARTIALLY PREDICTABLE.")
        elif skill > -0.1:
            print(f"    Marginally predictable. Barely better than assuming no change.")
        else:
            print(f"    Anti-predictable. Linear extrapolation does WORSE than standing still.")
            print(f"    The eigenmanifold is adversarial to simple forecasts.")

    print()


# === EXPERIMENT 5: CONWAY'S LAW AS SPECTRAL THEOREM =================
# "Organizations design systems that mirror their communication structure."
# Test: do repos with MULTIPLE AUTHORS have different spectral properties
# than single-author repos? Is the number of authors visible in the spectrum?

def experiment_conway():
    print("=" * 80)
    print("  CONWAY'S LAW AS A SPECTRAL THEOREM")
    print("  Is team structure visible in the eigenvalue distribution?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        # Get author info per commit
        try:
            r = subprocess.run(["git","log","--no-merges",
                                "--format=AUTHOR_SEP%an","-n","300"],
                               capture_output=True,text=True,encoding="utf-8",
                               errors="replace",cwd=rpath,timeout=60)
        except: continue

        authors = []
        for ln in r.stdout.split("\n"):
            ln = ln.strip()
            if ln.startswith("AUTHOR_SEP"):
                authors.append(ln[10:])

        if not authors: continue

        author_counts = defaultdict(int)
        for a in authors: author_counts[a] += 1
        n_authors = len(author_counts)
        top_author_frac = max(author_counts.values()) / len(authors)

        # Get spectral properties
        commits = parse_commits(rpath, 200)
        h, eigs, vecs, files = commits_to_spectrum(commits)
        if eigs is None: continue

        nz = eigs[eigs > 1e-8]
        if len(nz) == 0: continue
        gap = nz[0]
        p = nz / nz.sum()
        d_eff = 1.0 / np.sum(p**2)
        H = -np.sum(p * np.log(p + 1e-30))

        # Components
        n_components = np.sum(eigs < 1e-8)

        # IPR (localization)
        iprs = np.sum(vecs**4, axis=0)
        loc_frac = np.mean(iprs > 5.0/len(vecs))

        print(f"\n  {rname}:")
        print(f"    Authors: {n_authors}  top_author_frac: {top_author_frac:.0%}")
        print(f"    Spectral: gap={gap:.4f}  d_eff={d_eff:.1f}  H={H:.3f}  "
              f"comp={n_components}  loc={loc_frac:.0%}")
        print(f"    Top 5 authors: ", end="")
        for auth, count in sorted(author_counts.items(), key=lambda x:-x[1])[:5]:
            name_short = auth[:15]
            print(f"{name_short}({count})", end="  ")
        print()

    # Summary correlation
    print(f"\n  Conway's prediction: more authors → more components, higher localization,")
    print(f"  lower spectral dimension, more spherical curvature.")
    print(f"  Single author → fewer components, lower localization,")
    print(f"  higher spectral dimension, more hyperbolic.")
    print()


# === EXPERIMENT 6: THE EIGENMANIFOLD HAS WEATHER ====================
# Compute "temperature" (speed variance) and "pressure" (curvature)
# at each point on the trajectory. Map the weather.

def experiment_weather():
    print("=" * 80)
    print("  EIGENMANIFOLD WEATHER MAP")
    print("  Temperature = volatility. Pressure = curvature. Storms = phase transitions.")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        traj = get_trajectory(rpath, window=12, step=2)
        if len(traj) < 10: continue

        hists = [pt["hist"] for pt in traj]

        # Speed at each point
        speeds = [jsd(hists[i], hists[i+1]) for i in range(len(hists)-1)]

        # Curvature (direction change)
        directions = []
        for i in range(len(hists)-1):
            v = hists[i+1] - hists[i]
            n = np.linalg.norm(v)
            directions.append(v/n if n > 0 else np.zeros_like(v))

        curvatures = []
        for i in range(len(directions)-1):
            cos_a = np.clip(np.dot(directions[i], directions[i+1]), -1, 1)
            curvatures.append(np.arccos(cos_a))

        if len(speeds) < 5 or len(curvatures) < 5: continue

        speeds = np.array(speeds)
        curvatures = np.array(curvatures)

        # Temperature = rolling speed variance (3-step window)
        temps = []
        for i in range(len(speeds)-2):
            temps.append(np.std(speeds[i:i+3]))
        temps = np.array(temps)

        # Detect storms: high temperature AND high curvature simultaneously
        if len(temps) < 3 or len(curvatures) < 3: continue
        min_len = min(len(temps), len(curvatures))
        temps = temps[:min_len]
        curvs = curvatures[:min_len]

        storm_threshold_t = np.percentile(temps, 75)
        storm_threshold_c = np.percentile(curvs, 75)
        storms = (temps > storm_threshold_t) & (curvs > storm_threshold_c)
        n_storms = storms.sum()

        print(f"\n  {rname}: {len(traj)} time steps")
        print(f"    Mean speed:       {speeds.mean():.4f}")
        print(f"    Mean curvature:   {np.degrees(curvatures.mean()):.1f} deg")
        print(f"    Mean temperature: {temps.mean():.4f}")
        print(f"    Storms detected:  {n_storms} ({n_storms/len(storms)*100:.0f}% of timeline)")

        # Weather map
        max_t = temps.max() if temps.max() > 0 else 1
        max_c = curvs.max() if curvs.max() > 0 else 1

        print(f"    Temperature:  ", end="")
        for t in temps:
            print(" .:-=+#@"[min(int(t/max_t*7),7)], end="")
        print()
        print(f"    Curvature:    ", end="")
        for c in curvs:
            print(" .:-=+#@"[min(int(c/max_c*7),7)], end="")
        print()
        print(f"    Storms:       ", end="")
        for s in storms:
            print("!" if s else ".", end="")
        print()

        # Correlation between temperature and curvature
        corr = np.corrcoef(temps, curvs)[0,1] if temps.std() > 0 and curvs.std() > 0 else 0
        print(f"    Temp-curvature correlation: {corr:+.3f}", end="")
        if corr > 0.3:
            print("  (storms are coherent: fast + curvy)")
        elif corr < -0.3:
            print("  (anticorrelated: fast when straight, slow when turning)")
        else:
            print("  (independent: speed and direction unrelated)")

    print()


# === RUN =============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |              R A Q A   D A Y   5                        |")
    print("  |   Universe(tm) supply: infinite                          |")
    print("  |   reason for stopping: none found                        |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_attractor()
    experiment_momentum()
    experiment_entropy_rate()
    experiment_forecast()
    experiment_conway()
    experiment_weather()

    print("=" * 80)
    print("  the eigenmanifold has weather, momentum, entropy, and a ground state.")
    print("  codebases are organisms and the eigenmanifold is their biome.")
    print("=" * 80)
