# SPDX-FileCopyrightText: 2026 Woflo Labs
# SPDX-License-Identifier: LicenseRef-WLCSL-1.0
# See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

"""
RAQA FRONTIER — five new experiments across real repos
=======================================================
1. Temporal eigenspace: does eigenspace drift over git history?
2. Spectral twins: which files are structurally interchangeable?
3. Universality class: if not GOE, what ARE real repo statistics?
4. Minimum attack surface: fewest edges to maximally disrupt eigenspace
5. Spectral prediction: can eigenspace predict future co-changes?
"""

import numpy as np
import subprocess
import os
import tempfile
from collections import defaultdict

np.set_printoptions(precision=4, linewidth=140, suppress=True)

WORK_DIR = os.path.join(tempfile.gettempdir(), "raqa_repos")
LOCAL_REPO = r"C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R"

REPOS = {
    "pretext":   LOCAL_REPO,
    "flask":     os.path.join(WORK_DIR, "flask"),
    "django":    os.path.join(WORK_DIR, "django"),
    "pytorch":   os.path.join(WORK_DIR, "pytorch"),
    "rust-lang": os.path.join(WORK_DIR, "rust-lang"),
    "vue":       os.path.join(WORK_DIR, "vue"),
}

SRC_EXTS = ['.py','.js','.ts','.dart','.rs','.go','.java','.c','.cpp','.h',
            '.rb','.vue','.jsx','.tsx','.kt']

def run_git(args, cwd):
    try:
        r = subprocess.run(["git"] + args, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", cwd=cwd, timeout=60)
        return r.stdout
    except:
        return ""

def laplacian(adj):
    d = adj.sum(axis=1)
    d_inv_sqrt = np.where(d > 0, 1.0 / np.sqrt(d), 0.0)
    D = np.diag(d_inv_sqrt)
    return np.eye(len(adj)) - D @ adj @ D

def parse_commits(repo_path, n_commits=300):
    log = run_git(["log", "--no-merges", "--name-only",
                   "--format=COMMIT_SEP%H", "-n", str(n_commits)], cwd=repo_path)
    commits = []
    current = []
    for line in log.split("\n"):
        line = line.strip()
        if line.startswith("COMMIT_SEP"):
            if current:
                src = [f for f in current if any(f.endswith(e) for e in SRC_EXTS)]
                if 1 < len(src) <= 50:
                    commits.append(src)
            current = []
        elif line:
            current.append(line)
    if current:
        src = [f for f in current if any(f.endswith(e) for e in SRC_EXTS)]
        if 1 < len(src) <= 50:
            commits.append(src)
    return commits

def build_graph(commits, min_co=1):
    pairs = defaultdict(int)
    files = set()
    for fs in commits:
        fs = list(set(fs))
        files.update(fs)
        for i in range(len(fs)):
            for j in range(i+1, len(fs)):
                pairs[tuple(sorted([fs[i], fs[j]]))] += 1
    flist = sorted(files)
    idx = {f: i for i, f in enumerate(flist)}
    n = len(flist)
    A = np.zeros((n, n))
    for (a, b), c in pairs.items():
        if c >= min_co:
            A[idx[a], idx[b]] = c
            A[idx[b], idx[a]] = c
    conn = A.sum(axis=1) > 0
    A = A[np.ix_(conn, conn)]
    flist = [f for f, c in zip(flist, conn) if c]
    return A, flist


# === EXPERIMENT 1: TEMPORAL EIGENSPACE DRIFT ========================
# Split a repo's history into windows. Compute eigenspace per window.
# Measure how much eigenspace changes between windows.
# Does it drift smoothly? Jump? Oscillate?

def experiment_temporal():
    print("=" * 80)
    print("  EXPERIMENT 1: TEMPORAL EIGENSPACE DRIFT")
    print("  How does eigenspace change over a repo's history?")
    print("=" * 80)

    for repo_name, repo_path in REPOS.items():
        if not os.path.exists(repo_path):
            continue

        commits = parse_commits(repo_path, n_commits=300)
        if len(commits) < 30:
            continue

        # Split into overlapping windows of ~50 commits, sliding by 25
        window_size = min(50, len(commits) // 3)
        step = max(10, window_size // 2)
        windows = []
        for start in range(0, len(commits) - window_size + 1, step):
            windows.append(commits[start:start + window_size])

        if len(windows) < 3:
            continue

        # Compute eigenvalues per window
        spectra = []
        file_counts = []
        for w in windows:
            A, fs = build_graph(w, min_co=1)
            if len(fs) < 5:
                spectra.append(None)
                file_counts.append(0)
                continue
            L = laplacian((A > 0).astype(float))
            eigs = np.linalg.eigvalsh(L)
            spectra.append(eigs)
            file_counts.append(len(fs))

        # Measure drift between consecutive windows via spectral distance
        # Use histogram comparison (eigenvalue density)
        bins = np.linspace(0, 2.2, 40)
        drifts = []
        for i in range(len(spectra) - 1):
            if spectra[i] is None or spectra[i+1] is None:
                continue
            h1, _ = np.histogram(spectra[i], bins=bins, density=True)
            h2, _ = np.histogram(spectra[i+1], bins=bins, density=True)
            # Jensen-Shannon divergence (symmetric)
            m = (h1 + h2) / 2 + 1e-12
            h1n = h1 / (h1.sum() + 1e-12) + 1e-12
            h2n = h2 / (h2.sum() + 1e-12) + 1e-12
            mn = m / (m.sum() + 1e-12)
            jsd = 0.5 * np.sum(h1n * np.log(h1n / mn)) + 0.5 * np.sum(h2n * np.log(h2n / mn))
            drifts.append(jsd)

        if not drifts:
            continue

        drifts = np.array(drifts)
        max_drift_idx = np.argmax(drifts)

        print(f"\n  {repo_name}: {len(windows)} windows of ~{window_size} commits")
        print(f"    Mean drift (JSD):  {drifts.mean():.4f}")
        print(f"    Max drift:         {drifts.max():.4f} (between windows {max_drift_idx} and {max_drift_idx+1})")
        print(f"    Min drift:         {drifts.min():.4f}")
        print(f"    Std:               {drifts.std():.4f}")

        # Is drift smooth or jumpy?
        if len(drifts) > 3:
            autocorr = np.corrcoef(drifts[:-1], drifts[1:])[0, 1]
            print(f"    Autocorrelation:   {autocorr:+.3f}", end="")
            if autocorr > 0.3:
                print("  (smooth drift)")
            elif autocorr < -0.3:
                print("  (oscillating)")
            else:
                print("  (random/jumpy)")

        # Timeline visualization
        max_d = max(drifts.max(), 1e-6)
        print(f"    Timeline: ", end="")
        for d in drifts:
            level = int(d / max_d * 7)
            print(" .:-=+#@"[min(level, 7)], end="")
        print()

    print()


# === EXPERIMENT 2: SPECTRAL TWINS ===================================
# Files with nearly identical spectral fingerprints.
# They're interchangeable from the spectrum's point of view.
# This is what causes misses in the information paradox.

def experiment_twins():
    print("=" * 80)
    print("  EXPERIMENT 2: SPECTRAL TWINS")
    print("  Files that are structurally interchangeable.")
    print("=" * 80)

    for repo_name, repo_path in REPOS.items():
        if not os.path.exists(repo_path):
            continue

        commits = parse_commits(repo_path, n_commits=200)
        A, files = build_graph(commits, min_co=2)
        if len(files) < 10:
            A, files = build_graph(commits, min_co=1)
        if len(files) < 10:
            continue

        n = len(files)
        A_bin = (A > 0).astype(float)
        L = laplacian(A_bin)
        eigs = np.linalg.eigvalsh(L)

        # Compute spectral fingerprint per node (eigenvalue shift on removal)
        bins = np.linspace(0, 2.2, 50)
        hist_orig, _ = np.histogram(eigs, bins=bins, density=True)
        fingerprints = []

        for node in range(n):
            A_red = np.delete(np.delete(A_bin, node, 0), node, 1)
            if A_red.shape[0] < 2:
                fingerprints.append(np.zeros(len(bins) - 1))
                continue
            L_red = laplacian(A_red)
            eigs_red = np.linalg.eigvalsh(L_red)
            hist_red, _ = np.histogram(eigs_red, bins=bins, density=True)
            fingerprints.append(hist_orig - hist_red)

        fps = np.array(fingerprints)

        # Pairwise correlation of fingerprints
        # Find twin pairs (corr > 0.99)
        twins = []
        for i in range(n):
            for j in range(i + 1, n):
                c = np.corrcoef(fps[i], fps[j])[0, 1]
                if not np.isnan(c) and c > 0.95:
                    twins.append((i, j, c))

        twins.sort(key=lambda x: -x[2])

        print(f"\n  {repo_name}: {n} files")
        print(f"  Twin pairs (spectral correlation > 0.95): {len(twins)}")

        if twins:
            # Group into twin clusters
            twin_groups = []
            assigned = set()
            for i, j, c in twins:
                found = False
                for g in twin_groups:
                    if i in g or j in g:
                        g.add(i)
                        g.add(j)
                        found = True
                        break
                if not found:
                    twin_groups.append({i, j})
                assigned.add(i)
                assigned.add(j)

            n_singletons = n - len(assigned)

            print(f"  Twin clusters: {len(twin_groups)}")
            print(f"  Singleton files (unique fingerprint): {n_singletons} ({n_singletons/n:.0%})")

            for gidx, group in enumerate(twin_groups[:5]):
                members = sorted(group)
                # What do these files have in common?
                degs = [int(A_bin[m].sum()) for m in members]
                print(f"    Cluster {gidx}: {len(members)} files, degrees={degs}")
                for m in members[:4]:
                    fname = files[m]
                    if len(fname) > 60:
                        fname = "..." + fname[-57:]
                    print(f"      {fname}")
                if len(members) > 4:
                    print(f"      ...and {len(members) - 4} more")
        else:
            print(f"  No twins found. Every file has a unique spectral fingerprint.")

    print()


# === EXPERIMENT 3: UNIVERSALITY CLASS ===============================
# Real repos are NOT GOE. So what ARE they?
# Measure the full nearest-neighbor spacing distribution
# and compare against known universality classes:
# Poisson, GOE, GUE, semi-Poisson, Berry-Tabor

def experiment_universality():
    print("=" * 80)
    print("  EXPERIMENT 3: WHAT UNIVERSALITY CLASS ARE REAL REPOS?")
    print("  If not GOE (quantum chaotic), then what?")
    print("=" * 80)

    all_spacings = defaultdict(list)

    for repo_name, repo_path in REPOS.items():
        if not os.path.exists(repo_path):
            continue

        commits = parse_commits(repo_path, n_commits=200)
        A, files = build_graph(commits, min_co=1)
        if len(files) < 15:
            continue

        A_bin = (A > 0).astype(float)
        L = laplacian(A_bin)
        eigs = np.linalg.eigvalsh(L)
        nz = eigs[eigs > 1e-8]

        if len(nz) < 10:
            continue

        spacings = np.diff(nz)
        mean_s = spacings.mean()
        if mean_s > 0:
            spacings_norm = spacings / mean_s
            all_spacings[repo_name] = spacings_norm.tolist()

    if not all_spacings:
        print("  No repos with enough data.")
        return

    # For each repo, compute diagnostic statistics
    print(f"\n  Reference values:")
    print(f"    Poisson:      <r>=0.386  var(s)=1.000  P(s<0.1)=0.095  <s^2>=2.00")
    print(f"    GOE:          <r>=0.531  var(s)=0.286  P(s<0.1)=0.004  <s^2>=1.57")
    print(f"    Semi-Poisson: <r>=0.423  var(s)=0.750  P(s<0.1)=0.033  <s^2>=1.50")
    print(f"    Picket-fence: <r>=1.000  var(s)=0.000  P(s<0.1)=0.000  <s^2>=1.00\n")

    print(f"  {'repo':>12}  {'<r>':>6}  {'var(s)':>7}  {'P(s<.1)':>8}  {'<s^2>':>6}  {'class':>15}")
    print(f"  {'---':>12}  {'---':>6}  {'---':>7}  {'---':>8}  {'---':>6}  {'---':>15}")

    class_votes = defaultdict(int)

    for repo_name, spacings in all_spacings.items():
        s = np.array(spacings)
        if len(s) < 5:
            continue

        r_vals = np.minimum(s[:-1], s[1:]) / (np.maximum(s[:-1], s[1:]) + 1e-30)
        r_mean = r_vals.mean()

        var_s = s.var()
        p_small = np.mean(s < 0.1)
        s2_mean = np.mean(s**2)

        # Classify
        if r_mean > 0.48 and var_s < 0.4:
            cls = "GOE (quantum)"
        elif r_mean > 0.90 and var_s < 0.05:
            cls = "picket-fence"
        elif var_s > 0.8 and p_small > 0.06:
            cls = "Poisson"
        elif 0.40 < r_mean < 0.48 and 0.4 < var_s < 0.8:
            cls = "semi-Poisson"
        elif var_s < 0.4 and r_mean < 0.48:
            cls = "sub-Poisson"
        else:
            cls = "intermediate"

        class_votes[cls] += 1

        print(f"  {repo_name:>12}  {r_mean:6.3f}  {var_s:7.3f}  {p_small:8.3f}  {s2_mean:6.3f}  {cls:>15}")

    # Distribution of spacings across ALL repos combined
    all_s = []
    for spacings in all_spacings.values():
        all_s.extend(spacings)
    all_s = np.array(all_s)

    if len(all_s) > 20:
        print(f"\n  Combined ({len(all_s)} spacings from {len(all_spacings)} repos):")
        r_all = np.minimum(all_s[:-1], all_s[1:]) / (np.maximum(all_s[:-1], all_s[1:]) + 1e-30)
        print(f"    <r> = {r_all.mean():.4f}")
        print(f"    var(s) = {all_s.var():.4f}")
        print(f"    P(s<0.1) = {np.mean(all_s < 0.1):.4f}")
        print(f"    <s^2> = {np.mean(all_s**2):.4f}")

        # ASCII histogram of spacing distribution
        print(f"\n  Spacing distribution (all repos combined):")
        hist_bins = np.linspace(0, 4, 30)
        hist, _ = np.histogram(all_s, bins=hist_bins, density=True)
        max_h = hist.max()

        # Overlay theoretical curves
        s_vals = (hist_bins[:-1] + hist_bins[1:]) / 2
        poisson = np.exp(-s_vals)
        goe = (np.pi / 2) * s_vals * np.exp(-np.pi * s_vals**2 / 4)

        for row in range(12, -1, -1):
            threshold = row / 12.0 * max_h
            line = "    "
            for i in range(len(hist)):
                ch = " "
                if hist[i] >= threshold:
                    ch = "#"
                elif poisson[i] >= threshold and poisson[i] < threshold + max_h / 12:
                    ch = "."
                elif goe[i] >= threshold and goe[i] < threshold + max_h / 12:
                    ch = "o"
                line += ch
            print(line)
        print(f"    {'0':.<15}{'2':.<14}{'4'}")
        print(f"    # = real data, . = Poisson, o = GOE")

    print(f"\n  Verdict by class: {dict(class_votes)}")
    most_common = max(class_votes, key=class_votes.get) if class_votes else "?"
    print(f"  Most common: {most_common}\n")


# === EXPERIMENT 4: MINIMUM SPECTRAL ATTACK SURFACE ==================
# What is the SMALLEST set of edges whose removal maximally
# disrupts the eigenspace? This is the structural Achilles heel.

def experiment_attack_surface():
    print("=" * 80)
    print("  EXPERIMENT 4: MINIMUM SPECTRAL ATTACK SURFACE")
    print("  Fewest edges to maximally disrupt eigenspace.")
    print("=" * 80)

    for repo_name, repo_path in REPOS.items():
        if not os.path.exists(repo_path):
            continue

        commits = parse_commits(repo_path, n_commits=200)
        A, files = build_graph(commits, min_co=2)
        if len(files) < 10:
            A, files = build_graph(commits, min_co=1)
        if len(files) < 10:
            continue

        n = len(files)
        A_bin = (A > 0).astype(float)
        L = laplacian(A_bin)
        eigs = np.linalg.eigvalsh(L)
        n_edges = int(A_bin.sum() // 2)

        # Rank edges by spectral shift (fragility)
        edges = [(i, j) for i in range(n) for j in range(i + 1, n) if A_bin[i, j] > 0]
        rng = np.random.RandomState(42)

        # Sample if too many edges
        sample = edges if len(edges) <= 80 else [edges[k] for k in rng.choice(len(edges), 80, replace=False)]

        edge_shifts = []
        for i, j in sample:
            A_mod = A_bin.copy()
            A_mod[i, j] = A_mod[j, i] = 0
            L_mod = laplacian(A_mod)
            eigs_mod = np.linalg.eigvalsh(L_mod)
            ml = min(len(eigs), len(eigs_mod))
            shift = np.sum(np.abs(eigs[:ml] - eigs_mod[:ml]))
            edge_shifts.append((i, j, shift))

        edge_shifts.sort(key=lambda x: -x[2])

        # Greedy attack: remove edges in order of fragility
        # Measure cumulative spectral disruption
        total_shift_at_k = []
        A_attack = A_bin.copy()
        eigs_current = eigs.copy()

        for k in range(min(10, len(edge_shifts))):
            i, j, _ = edge_shifts[k]
            A_attack[i, j] = A_attack[j, i] = 0
            L_attack = laplacian(A_attack)
            eigs_attack = np.linalg.eigvalsh(L_attack)
            ml = min(len(eigs), len(eigs_attack))
            cumulative_shift = np.sum(np.abs(eigs[:ml] - eigs_attack[:ml]))
            total_shift_at_k.append(cumulative_shift)

        # Compare to random removal
        A_random = A_bin.copy()
        random_edges = [edges[k] for k in rng.choice(len(edges), min(10, len(edges)), replace=False)]
        random_shifts = []
        for k in range(min(10, len(random_edges))):
            i, j = random_edges[k]
            A_random[i, j] = A_random[j, i] = 0
            L_rand = laplacian(A_random)
            eigs_rand = np.linalg.eigvalsh(L_rand)
            ml = min(len(eigs), len(eigs_rand))
            random_shifts.append(np.sum(np.abs(eigs[:ml] - eigs_rand[:ml])))

        print(f"\n  {repo_name}: {n} files, {n_edges} edges")
        print(f"  Greedy fragility attack vs random removal:\n")
        print(f"  {'edges removed':>14}  {'greedy shift':>12}  {'random shift':>12}  {'ratio':>6}")
        print(f"  {'---':>14}  {'---':>12}  {'---':>12}  {'---':>6}")

        for k in range(min(10, len(total_shift_at_k), len(random_shifts))):
            g = total_shift_at_k[k]
            r = random_shifts[k]
            ratio = g / r if r > 0 else float('inf')
            print(f"  {k+1:>14}  {g:12.4f}  {r:12.4f}  {ratio:6.1f}x")

        if total_shift_at_k and random_shifts:
            final_ratio = total_shift_at_k[-1] / (random_shifts[-1] + 1e-12)
            pct_of_edges = min(10, len(edge_shifts)) / n_edges * 100
            print(f"\n  Removing {pct_of_edges:.1f}% of edges via greedy attack causes")
            print(f"  {final_ratio:.1f}x more spectral disruption than random removal.")

            # Which files appear most in the attack surface?
            attack_nodes = defaultdict(int)
            for i, j, _ in edge_shifts[:10]:
                attack_nodes[i] += 1
                attack_nodes[j] += 1
            top_targets = sorted(attack_nodes.items(), key=lambda x: -x[1])[:5]
            if top_targets:
                print(f"  Most targeted files:")
                for node, count in top_targets:
                    fname = files[node][-50:] if len(files[node]) > 50 else files[node]
                    deg = int(A_bin[node].sum())
                    print(f"    {fname} (deg={deg}, in {count} attack edges)")

    print()


# === EXPERIMENT 5: SPECTRAL PREDICTION ON REAL REPOS ================
# Train eigenspace on EARLY commits, predict co-changes in LATE commits.
# This is temporal prediction — does the past spectrum predict the future?

def experiment_prediction():
    print("=" * 80)
    print("  EXPERIMENT 5: CAN THE PAST SPECTRUM PREDICT FUTURE CO-CHANGES?")
    print("  Train on early commits, predict late co-changes.")
    print("=" * 80)

    for repo_name, repo_path in REPOS.items():
        if not os.path.exists(repo_path):
            continue

        commits = parse_commits(repo_path, n_commits=300)
        if len(commits) < 40:
            continue

        # Split: first 2/3 for training, last 1/3 for testing
        split = len(commits) * 2 // 3
        train_commits = commits[:split]
        test_commits = commits[split:]

        A_train, files_train = build_graph(train_commits, min_co=1)
        A_test, files_test = build_graph(test_commits, min_co=1)

        if len(files_train) < 10 or len(files_test) < 5:
            continue

        # Find files that appear in BOTH periods
        common = set(files_train) & set(files_test)
        if len(common) < 8:
            continue

        common = sorted(common)
        idx_train = {f: i for i, f in enumerate(files_train)}
        idx_test = {f: i for i, f in enumerate(files_test)}

        # Build submatrices for common files
        cidx_train = [idx_train[f] for f in common]
        cidx_test = [idx_test[f] for f in common]

        A_tr = (A_train[np.ix_(cidx_train, cidx_train)] > 0).astype(float)
        A_te = (A_test[np.ix_(cidx_test, cidx_test)] > 0).astype(float)

        nc = len(common)

        # Eigenspace of training graph
        L = laplacian(A_tr)
        eigs, vecs = np.linalg.eigh(L)
        nz = eigs > 1e-8
        if not np.any(nz):
            continue
        w = 1.0 / np.sqrt(eigs[nz])
        coords = vecs[:, nz] * w[np.newaxis, :]

        # For each pair: spectral distance in training eigenspace
        # Label: does this pair co-change in the test period?

        # New edges in test that didn't exist in train
        new_edges = []
        stable_non_edges = []

        for i in range(nc):
            for j in range(i + 1, nc):
                spec_d = np.linalg.norm(coords[i] - coords[j])
                was_edge = A_tr[i, j] > 0
                is_edge = A_te[i, j] > 0

                if not was_edge and is_edge:
                    new_edges.append((i, j, spec_d, True))
                elif not was_edge and not is_edge:
                    stable_non_edges.append((i, j, spec_d, False))

        if len(new_edges) < 3 or len(stable_non_edges) < 3:
            continue

        # Sample negatives to match positive count (balanced evaluation)
        rng = np.random.RandomState(42)
        n_neg = min(len(stable_non_edges), len(new_edges) * 5)
        neg_sample = [stable_non_edges[k] for k in rng.choice(len(stable_non_edges), n_neg, replace=False)]

        all_pairs = new_edges + neg_sample
        scores = np.array([-p[2] for p in all_pairs])  # neg distance = high score
        labels = np.array([1 if p[3] else 0 for p in all_pairs])

        # AUC
        pos_scores = scores[labels == 1]
        neg_scores = scores[labels == 0]
        auc = 0
        for ps in pos_scores:
            auc += np.sum(neg_scores < ps) + 0.5 * np.sum(neg_scores == ps)
        n_pos = len(pos_scores)
        n_neg_count = len(neg_scores)
        auc /= (n_pos * n_neg_count) if n_pos * n_neg_count > 0 else 1

        # Precision@k
        k = len(new_edges)
        top_k_idx = np.argsort(-scores)[:k]
        prec_at_k = np.mean(labels[top_k_idx])

        # Mean spectral distance of new edges vs non-edges
        mean_new = np.mean([p[2] for p in new_edges])
        mean_non = np.mean([p[2] for p in neg_sample])

        print(f"\n  {repo_name}: {nc} common files, {len(new_edges)} new co-changes in test period")
        print(f"    Spectral distance (train eigenspace):")
        print(f"      Future co-changes: mean_d = {mean_new:.4f}")
        print(f"      Stable non-edges:  mean_d = {mean_non:.4f}")
        print(f"      Ratio: {mean_non / mean_new:.2f}x  (>1 = future edges are spectrally closer)")
        print(f"    AUC: {auc:.3f}  Precision@{k}: {prec_at_k:.1%}")
        if auc > 0.6:
            print(f"    THE PAST SPECTRUM PREDICTS FUTURE CO-CHANGES.")
        elif auc > 0.55:
            print(f"    Weak but positive signal.")
        else:
            print(f"    No predictive signal in this repo.")

    print()


# === RUN ============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |          R A Q A   F R O N T I E R   L A B               |")
    print("  |    five new experiments across real repos                 |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_temporal()
    experiment_twins()
    experiment_universality()
    experiment_attack_surface()
    experiment_prediction()

    print("=" * 80)
    print("  Frontier complete. What's new?")
    print("=" * 80)
