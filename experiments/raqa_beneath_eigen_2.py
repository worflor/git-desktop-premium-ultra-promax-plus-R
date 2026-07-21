# SPDX-FileCopyrightText: 2026 Woflo Labs
# SPDX-License-Identifier: LicenseRef-WLCSL-1.0
# See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

"""
RAQA BENEATH EIGEN pt 2 — deeper still
========================================
The first pass found: temporal structure, causal arrows, topological holes,
compression rhythms. Now go further:

1. Causal depth: how DEEP are the causal chains? A→B→C→D? How long?
2. Rhythmic fingerprints: cluster files by change-rhythm (not co-change)
3. Topological hole anatomy: WHICH files form loops, and why?
4. Information flow rate: bits per commit transferred between subsystems
5. The developmental clock: does the repo have a metabolic cycle?
6. Compression archaeology: can zlib recover DELETED structural patterns?
"""

import numpy as np
import subprocess
import os
import tempfile
import zlib
from collections import defaultdict, Counter

np.set_printoptions(precision=4, linewidth=140, suppress=True)

WORK_DIR = os.path.join(tempfile.gettempdir(), "raqa_repos")
LOCAL = r"C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R"
SRC_EXTS = ['.py','.js','.ts','.dart','.rs','.go','.java','.c','.cpp','.h','.rb','.vue','.jsx','.tsx']

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
    all_files=set()
    for c in commits: all_files.update(c)
    histories={}
    for f in sorted(all_files):
        h=np.array([1 if f in c else 0 for c in commits], dtype=np.int8)
        if h.sum()>=2: histories[f]=h
    return histories, commits

def get_repos():
    repos={"pretext":LOCAL}
    for name in ["flask","django","pytorch","rust-lang","vue","fastapi","express"]:
        p=os.path.join(WORK_DIR,name)
        if os.path.exists(p): repos[name]=p
    return repos

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
        p_j=cnt/total
        p1=cnt/c_tp_sp[(tp,sp)]
        p2=c_tp_tf[(tp,tf)]/c_tp[tp] if c_tp[tp]>0 else 0
        if p2>0 and p1>0: te+=p_j*np.log2(p1/p2)
    return max(te,0)


# === EXPERIMENT 1: CAUSAL CHAIN DEPTH ================================
# Build the transfer entropy DAG. Find the LONGEST causal chain.
# How deep does causality go? A→B→C→D→...?

def experiment_causal_depth():
    print("=" * 80)
    print("  CAUSAL CHAIN DEPTH")
    print("  How deep do causal cascades go? A->B->C->D->...?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 200)
        files = sorted(histories.keys())
        if len(files) < 10: continue

        rng = np.random.RandomState(42)
        sample = [files[k] for k in rng.choice(len(files), min(40, len(files)), replace=False)]
        n = len(sample)

        # Build directed causal graph (TE > threshold)
        te_threshold = 0.015
        causal_edges = {}  # (i,j) -> TE value
        for i in range(n):
            for j in range(n):
                if i == j: continue
                te = transfer_entropy(histories[sample[i]], histories[sample[j]], lag=1)
                te_rev = transfer_entropy(histories[sample[j]], histories[sample[i]], lag=1)
                # Only keep the edge if it's significantly directional
                if te > te_threshold and te > te_rev * 1.5:
                    causal_edges[(i, j)] = te

        if not causal_edges: continue

        # Find longest path in DAG (topological sort + DP)
        # First check for cycles (which would make it not a DAG)
        adj = defaultdict(list)
        for (i, j) in causal_edges:
            adj[i].append(j)

        # DFS for longest path
        memo = {}
        def longest_from(node, visited):
            if node in memo: return memo[node]
            if node in visited: return (node,)
            visited.add(node)
            best_path = (node,)
            for nxt in adj[node]:
                sub_path = longest_from(nxt, visited.copy())
                candidate = (node,) + sub_path
                if len(candidate) > len(best_path):
                    best_path = candidate
            memo[node] = best_path
            return best_path

        longest = []
        for start in range(n):
            path = longest_from(start, set())
            if len(path) > len(longest):
                longest = path

        print(f"\n  {rname}: {n} files, {len(causal_edges)} causal edges (TE > {te_threshold})")
        print(f"    Longest causal chain: {len(longest)} steps")

        if len(longest) >= 3:
            print(f"    Chain:")
            for step, node in enumerate(longest):
                fname = sample[node][-40:] if len(sample[node]) > 40 else sample[node]
                if step < len(longest) - 1:
                    next_node = longest[step + 1]
                    te_val = causal_edges.get((node, next_node), 0)
                    print(f"      {step}: {fname}  --({te_val:.3f})->")
                else:
                    print(f"      {step}: {fname}")

        # Causal depth distribution: for each node, what's the longest chain FROM it?
        depths = {}
        for start in range(n):
            path = longest_from(start, set())
            depths[start] = len(path) - 1  # depth = edges, not nodes

        depth_dist = Counter(depths.values())
        max_depth = max(depths.values()) if depths else 0

        print(f"    Depth distribution:")
        for d in sorted(depth_dist.keys()):
            bar = "#" * depth_dist[d]
            print(f"      depth {d}: {depth_dist[d]:3d} files  {bar}")

        # Average causal depth
        mean_depth = np.mean(list(depths.values()))
        print(f"    Mean causal depth: {mean_depth:.1f}")

    print()


# === EXPERIMENT 2: RHYTHMIC CLUSTERING ==============================
# Cluster files by TEMPORAL PATTERN, not co-change.
# Two files in the same rhythm cluster change at the same CADENCE
# even if they never change in the same commit.

def experiment_rhythmic_clusters():
    print("=" * 80)
    print("  RHYTHMIC CLUSTERING")
    print("  Group files by change-rhythm, not co-change.")
    print("  Same beat, different measures.")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 200)
        files = sorted(histories.keys())
        if len(files) < 15: continue

        rng = np.random.RandomState(42)
        sample = [files[k] for k in rng.choice(len(files), min(50, len(files)), replace=False)]
        n = len(sample)

        # Extract rhythmic features per file:
        # - change frequency (fraction of commits)
        # - burstiness (variance of inter-change intervals)
        # - autocorrelation at lag 1 (does changing predict changing again?)
        features = []
        for f in sample:
            h = histories[f]
            freq = h.mean()
            # Inter-change intervals
            change_idx = np.where(h == 1)[0]
            if len(change_idx) > 1:
                intervals = np.diff(change_idx)
                burstiness = intervals.std() / (intervals.mean() + 1e-6)
                # Autocorrelation
                ac = np.corrcoef(h[:-1], h[1:])[0, 1] if len(h) > 2 else 0
                if np.isnan(ac): ac = 0
            else:
                burstiness = 0
                ac = 0
            features.append([freq, burstiness, ac])

        X = np.array(features)
        # Normalize
        for col in range(X.shape[1]):
            s = X[:, col].std()
            if s > 0: X[:, col] = (X[:, col] - X[:, col].mean()) / s

        # K-means in rhythm-space
        k = min(4, n // 4)
        centers = X[rng.choice(n, k, replace=False)]
        labels = np.zeros(n, dtype=int)
        for _ in range(30):
            for i in range(n): labels[i] = np.argmin([np.linalg.norm(X[i]-c) for c in centers])
            for j in range(k):
                m = X[labels == j]
                if len(m) > 0: centers[j] = m.mean(axis=0)

        print(f"\n  {rname}: {n} files, {k} rhythm clusters")

        for cl in range(k):
            members = [i for i in range(n) if labels[i] == cl]
            if not members: continue
            avg_freq = np.mean([features[i][0] for i in members])
            avg_burst = np.mean([features[i][1] for i in members])
            avg_ac = np.mean([features[i][2] for i in members])

            # How many of these files ALSO co-change?
            cochange_pairs = 0
            total_pairs = 0
            for a in range(len(members)):
                for b in range(a+1, len(members)):
                    total_pairs += 1
                    ia, ib = members[a], members[b]
                    cc = np.sum((histories[sample[ia]]==1) & (histories[sample[ib]]==1))
                    if cc > 0: cochange_pairs += 1
            cochange_frac = cochange_pairs / total_pairs if total_pairs > 0 else 0

            if avg_burst < 0.5:
                rhythm = "STEADY (regular cadence)"
            elif avg_burst < 1.5:
                rhythm = "MODERATE (some bursts)"
            else:
                rhythm = "BURSTY (irregular)"

            if avg_ac > 0.1:
                persistence = "persistent (streaky)"
            elif avg_ac < -0.1:
                persistence = "anti-persistent (alternating)"
            else:
                persistence = "memoryless"

            print(f"    Cluster {cl}: {len(members)} files  "
                  f"freq={avg_freq:.3f}  burst={avg_burst:.2f}  ac={avg_ac:+.2f}")
            print(f"      Rhythm: {rhythm}  |  {persistence}")
            print(f"      Co-change overlap: {cochange_frac:.0%} of pairs also co-change")
            for idx in members[:3]:
                fs = sample[idx][-45:] if len(sample[idx]) > 45 else sample[idx]
                print(f"        {fs}")

    print()


# === EXPERIMENT 3: THE DEVELOPMENTAL CLOCK ===========================
# Does the commit sequence have a PERIOD?
# Autocorrelation of the commit-size time series.
# If there's a peak at some lag, the repo has a metabolic cycle.

def experiment_developmental_clock():
    print("=" * 80)
    print("  THE DEVELOPMENTAL CLOCK")
    print("  Does the commit sequence have a metabolic period?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 300)
        if len(commits) < 30: continue

        # Commit size time series
        sizes = np.array([len(c) for c in commits], dtype=float)
        if sizes.std() == 0: continue

        # Autocorrelation
        centered = sizes - sizes.mean()
        var = np.sum(centered**2)
        max_lag = min(len(sizes) // 3, 30)

        autocorrs = []
        for lag in range(1, max_lag + 1):
            ac = np.sum(centered[:-lag] * centered[lag:]) / var
            autocorrs.append(ac)

        autocorrs = np.array(autocorrs)

        # Find peaks in autocorrelation (potential periods)
        peaks = []
        for i in range(1, len(autocorrs) - 1):
            if autocorrs[i] > autocorrs[i-1] and autocorrs[i] > autocorrs[i+1] and autocorrs[i] > 0.1:
                peaks.append((i + 1, autocorrs[i]))

        print(f"\n  {rname}: {len(commits)} commits")
        print(f"    Mean commit size: {sizes.mean():.1f} files  std: {sizes.std():.1f}")

        # Autocorrelation plot
        print(f"    Autocorrelation: ", end="")
        for ac in autocorrs:
            if ac > 0.3: print("@", end="")
            elif ac > 0.15: print("#", end="")
            elif ac > 0.05: print("=", end="")
            elif ac > -0.05: print(".", end="")
            elif ac > -0.15: print(",", end="")
            else: print("_", end="")
        print()

        if peaks:
            print(f"    Detected periods:")
            for lag, strength in peaks[:3]:
                print(f"      Period = {lag} commits (strength = {strength:.3f})")
            # Is the strongest peak at a "round" number?
            strongest_lag = peaks[0][0]
            print(f"    DEVELOPMENTAL CLOCK PERIOD: ~{strongest_lag} commits")
        else:
            print(f"    No periodic signal detected. Arrhythmic development.")

        # Also: is commit size PREDICTABLE from its position in the sequence?
        # (linear trend)
        t = np.arange(len(sizes))
        slope, intercept = np.polyfit(t, sizes, 1)
        if slope > 0.01:
            print(f"    Trend: commits are GROWING ({slope:.3f} files/commit)")
        elif slope < -0.01:
            print(f"    Trend: commits are SHRINKING ({slope:.3f} files/commit)")
        else:
            print(f"    No significant trend in commit size.")

    print()


# === EXPERIMENT 4: INFORMATION FLOW BETWEEN SUBSYSTEMS ===============
# Split files into subsystems (by directory). Measure transfer entropy
# BETWEEN subsystems, not individual files. Which modules drive which?

def experiment_subsystem_flow():
    print("=" * 80)
    print("  INFORMATION FLOW BETWEEN SUBSYSTEMS")
    print("  Which modules DRIVE which? Measured in bits.")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 200)
        if len(histories) < 15: continue

        # Group files by top-level directory
        subsystems = defaultdict(list)
        for f in histories:
            parts = f.split("/")
            if len(parts) >= 2:
                key = "/".join(parts[:2])
            else:
                key = parts[0]
            subsystems[key].append(f)

        # Filter to subsystems with >= 3 files
        subsystems = {k: v for k, v in subsystems.items() if len(v) >= 3}
        if len(subsystems) < 2: continue

        # Aggregate history per subsystem: 1 if ANY file in the subsystem changed
        sub_names = sorted(subsystems.keys())
        sub_histories = {}
        for sname in sub_names:
            combined = np.zeros(len(commits), dtype=np.int8)
            for f in subsystems[sname]:
                combined |= histories[f]
            sub_histories[sname] = combined

        print(f"\n  {rname}: {len(sub_names)} subsystems")

        # Transfer entropy between all subsystem pairs
        te_matrix = {}
        for i, si in enumerate(sub_names):
            for j, sj in enumerate(sub_names):
                if i == j: continue
                te = transfer_entropy(sub_histories[si], sub_histories[sj], lag=1)
                if te > 0.005:
                    te_matrix[(si, sj)] = te

        if not te_matrix: continue

        # Top causal flows
        flows = sorted(te_matrix.items(), key=lambda x: -x[1])

        print(f"    Top information flows:")
        print(f"    {'source':>30}  {'target':>30}  {'TE (bits)':>10}")
        print(f"    {'---':>30}  {'---':>30}  {'---':>10}")

        for (src, tgt), te in flows[:8]:
            ss = src[-30:] if len(src) > 30 else src
            ts = tgt[-30:] if len(tgt) > 30 else tgt
            bar_len = int(te / flows[0][1] * 20)
            bar = "#" * bar_len
            print(f"    {ss:>30}  ->  {ts:<30}  {te:10.4f}  {bar}")

        # Net flow per subsystem
        out_flow = defaultdict(float)
        in_flow = defaultdict(float)
        for (src, tgt), te in te_matrix.items():
            out_flow[src] += te
            in_flow[tgt] += te

        print(f"\n    Net flow (out - in):")
        net_flows = [(s, out_flow[s] - in_flow.get(s, 0)) for s in sub_names if s in out_flow or s in in_flow]
        net_flows.sort(key=lambda x: -x[1])
        for s, nf in net_flows[:5]:
            ss = s[-35:] if len(s) > 35 else s
            direction = "SOURCE" if nf > 0.01 else ("SINK" if nf < -0.01 else "neutral")
            print(f"      {ss:>35}  net={nf:+.3f}  [{direction}]")

    print()


# === EXPERIMENT 5: TEMPORAL MUTUAL INFORMATION =======================
# Standard MI asks: do A and B change in the SAME commit?
# Temporal MI asks: do A and B change in NEARBY commits?
# Expand the window: MI at lag 0, 1, 2, 3...
# If MI(lag=2) > MI(lag=0), the relationship is DELAYED not simultaneous.

def experiment_temporal_mi():
    print("=" * 80)
    print("  TEMPORAL MUTUAL INFORMATION")
    print("  Do files change in NEARBY commits, not just the SAME commit?")
    print("  Delayed coupling that co-change counting completely misses.")
    print("=" * 80)

    def mi_at_lag(x, y, lag):
        if lag == 0: return _mi(x, y)
        n = len(x)
        if lag >= n: return 0
        return _mi(x[:-lag], y[lag:])

    def _mi(x, y):
        n = len(x)
        if n == 0: return 0
        p00=np.sum((x==0)&(y==0))/n; p01=np.sum((x==0)&(y==1))/n
        p10=np.sum((x==1)&(y==0))/n; p11=np.sum((x==1)&(y==1))/n
        px0=np.sum(x==0)/n; px1=1-px0; py0=np.sum(y==0)/n; py1=1-py0
        mi=0
        for pxy,px,py in [(p00,px0,py0),(p01,px0,py1),(p10,px1,py0),(p11,px1,py1)]:
            if pxy>0 and px>0 and py>0: mi+=pxy*np.log2(pxy/(px*py))
        return mi

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 200)
        files = sorted(histories.keys())
        if len(files) < 10: continue

        rng = np.random.RandomState(42)
        sample = [files[k] for k in rng.choice(len(files), min(25, len(files)), replace=False)]
        n = len(sample)

        # For each pair: MI at lag 0, 1, 2, 3
        delayed_pairs = []
        for i in range(n):
            for j in range(i+1, n):
                mi0 = mi_at_lag(histories[sample[i]], histories[sample[j]], 0)
                mi1 = mi_at_lag(histories[sample[i]], histories[sample[j]], 1)
                mi2 = mi_at_lag(histories[sample[i]], histories[sample[j]], 2)
                mi3 = mi_at_lag(histories[sample[i]], histories[sample[j]], 3)

                # Is the relationship DELAYED? (MI peaks at lag > 0)
                peak_lag = np.argmax([mi0, mi1, mi2, mi3])
                peak_mi = [mi0, mi1, mi2, mi3][peak_lag]

                if peak_lag > 0 and peak_mi > 0.02:
                    delayed_pairs.append((sample[i], sample[j], peak_lag,
                                         mi0, mi1, mi2, mi3))

        print(f"\n  {rname}: {n} files")
        n_pairs = n * (n-1) // 2
        n_delayed = len(delayed_pairs)
        print(f"    Delayed coupling pairs: {n_delayed}/{n_pairs} ({n_delayed/n_pairs*100:.0f}%)")

        if delayed_pairs:
            delayed_pairs.sort(key=lambda x: -max(x[3:]))
            print(f"    Top delayed relationships (MI peaks at lag > 0):")
            print(f"    {'file A':>35}  {'file B':>35}  {'peak':>4}  {'MI@0':>5}  {'MI@1':>5}  {'MI@2':>5}  {'MI@3':>5}")
            for f1, f2, peak, mi0, mi1, mi2, mi3 in delayed_pairs[:8]:
                f1s = f1[-35:] if len(f1) > 35 else f1
                f2s = f2[-35:] if len(f2) > 35 else f2
                mi_vals = [mi0, mi1, mi2, mi3]
                mi_strs = [f"{m:.3f}" if k != peak else f"[{m:.3f}]" for k, m in enumerate(mi_vals)]
                print(f"    {f1s:>35}  {f2s:>35}  lag{peak}  {' '.join(mi_strs)}")

            # What fraction of all coupling is DELAYED?
            total_mi0 = sum(x[3] for x in delayed_pairs)
            total_peak = sum(max(x[3:]) for x in delayed_pairs)
            if total_peak > 0:
                hidden_frac = 1 - total_mi0 / total_peak
                print(f"\n    Fraction of coupling that's INVISIBLE at lag 0: {hidden_frac:.0%}")
                if hidden_frac > 0.3:
                    print(f"    SIGNIFICANT HIDDEN COUPLING. {hidden_frac:.0%} of relationships")
                    print(f"    only appear when you look 1-3 commits into the future.")
                    print(f"    Co-change counting misses this entirely.")

    print()


# === RUN ==============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |     B E N E A T H   E I G E N   p t  2                  |")
    print("  |   deeper still. the substrate speaks.                    |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_causal_depth()
    experiment_rhythmic_clusters()
    experiment_developmental_clock()
    experiment_subsystem_flow()
    experiment_temporal_mi()

    print("=" * 80)
    print("  beneath the eigenvalues: causal chains, rhythmic twins,")
    print("  metabolic clocks, subsystem flows, and delayed coupling.")
    print("  the linear lens was useful. what's underneath is alive.")
    print("=" * 80)
