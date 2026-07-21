# SPDX-FileCopyrightText: 2026 Woflo Labs
# SPDX-License-Identifier: LicenseRef-WLCSL-1.0
# See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

"""
RAQA BENEATH EIGEN — what's under the eigenvalues?
=====================================================
No Laplacians. No spectral decomposition. Going to the substrate.

1. Mutual information network: nonlinear coupling between file histories
2. Transfer entropy: causal arrows — does A's past predict B's future?
3. Persistent homology: topological holes in the co-change complex
4. Compression distance: how similar are two files' CHANGE HISTORIES?
5. Commit entropy: the raw information content of development itself
6. The edit distance graph: not WHAT files co-change, but HOW MUCH each changes
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

def parse_file_histories(path, n_commits=200):
    """Return per-file binary history vectors: 1 = file changed in commit, 0 = not."""
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
                if len(s) > 0: commits.append(set(s))
            cur=[]
        elif ln: cur.append(ln)

    all_files = set()
    for c in commits: all_files.update(c)
    all_files = sorted(all_files)

    # Binary history: 1 if file appeared in commit, 0 otherwise
    histories = {}
    for f in all_files:
        h = np.array([1 if f in c else 0 for c in commits], dtype=np.int8)
        if h.sum() >= 2:  # file must appear in at least 2 commits
            histories[f] = h

    return histories, commits

def get_repos():
    repos={"pretext":LOCAL}
    for name in ["flask","django","pytorch","rust-lang","vue","fastapi","express"]:
        p=os.path.join(WORK_DIR,name)
        if os.path.exists(p): repos[name]=p
    return repos


# === EXPERIMENT 1: MUTUAL INFORMATION NETWORK =======================
# Co-change count is LINEAR. Mutual information is NONLINEAR.
# MI captures any statistical dependency, not just co-occurrence.
# Two files can have MI > 0 even if they never change in the SAME
# commit — if one changing makes the other MORE LIKELY to change
# in a nearby commit.

def experiment_mutual_information():
    print("=" * 80)
    print("  MUTUAL INFORMATION NETWORK")
    print("  Nonlinear coupling between file histories.")
    print("  Captures dependencies co-change counting misses.")
    print("=" * 80)

    def mutual_info(x, y):
        """MI between two binary vectors."""
        n = len(x)
        if n == 0: return 0
        # Joint distribution
        p00 = np.sum((x==0) & (y==0)) / n
        p01 = np.sum((x==0) & (y==1)) / n
        p10 = np.sum((x==1) & (y==0)) / n
        p11 = np.sum((x==1) & (y==1)) / n
        # Marginals
        px0 = np.sum(x==0) / n; px1 = 1 - px0
        py0 = np.sum(y==0) / n; py1 = 1 - py0
        # MI
        mi = 0
        for pxy, px, py in [(p00,px0,py0),(p01,px0,py1),(p10,px1,py0),(p11,px1,py1)]:
            if pxy > 0 and px > 0 and py > 0:
                mi += pxy * np.log2(pxy / (px * py))
        return mi

    def cochange_count(x, y):
        return np.sum((x==1) & (y==1))

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 200)
        files = sorted(histories.keys())
        n = len(files)
        if n < 10: continue

        # Compute MI and co-change for all pairs (sample if too many)
        rng = np.random.RandomState(42)
        if n > 60:
            sample_files = [files[k] for k in rng.choice(n, 60, replace=False)]
        else:
            sample_files = files

        mi_values = []
        cc_values = []
        pairs = []

        for i in range(len(sample_files)):
            for j in range(i+1, len(sample_files)):
                mi = mutual_info(histories[sample_files[i]], histories[sample_files[j]])
                cc = cochange_count(histories[sample_files[i]], histories[sample_files[j]])
                mi_values.append(mi)
                cc_values.append(cc)
                pairs.append((sample_files[i], sample_files[j]))

        mi_arr = np.array(mi_values)
        cc_arr = np.array(cc_values, dtype=float)

        # Correlation between MI and co-change
        corr = np.corrcoef(mi_arr, cc_arr)[0,1] if cc_arr.std() > 0 and mi_arr.std() > 0 else 0

        # Files with HIGH MI but LOW co-change (the nonlinear surprises)
        if cc_arr.max() > 0:
            cc_norm = cc_arr / cc_arr.max()
            mi_norm = mi_arr / (mi_arr.max() + 1e-12)
            surprise = mi_norm - cc_norm
        else:
            surprise = mi_arr

        top_surprise = np.argsort(surprise)[-5:][::-1]

        print(f"\n  {rname}: {len(sample_files)} files, {len(commits)} commits")
        print(f"    Correlation(MI, co-change): {corr:.3f}")
        if corr < 0.7:
            print(f"    MI sees structure that co-change MISSES.")
        else:
            print(f"    MI and co-change mostly agree.")

        print(f"    Top nonlinear surprises (high MI, low co-change):")
        for idx in top_surprise:
            f1, f2 = pairs[idx]
            f1s = f1[-35:] if len(f1) > 35 else f1
            f2s = f2[-35:] if len(f2) > 35 else f2
            print(f"      MI={mi_arr[idx]:.4f}  co-ch={int(cc_arr[idx]):2d}  {f1s} <-> {f2s}")

    print()


# === EXPERIMENT 2: TRANSFER ENTROPY =================================
# Does file A's past predict file B's future? This is CAUSAL.
# Co-change is symmetric. Transfer entropy is DIRECTIONAL.
# TE(A→B) ≠ TE(B→A) tells you which file DRIVES the other.

def experiment_transfer_entropy():
    print("=" * 80)
    print("  TRANSFER ENTROPY: causal arrows between files")
    print("  TE(A->B) = how much does A's past help predict B's future?")
    print("  Asymmetric. Directional. Causal.")
    print("=" * 80)

    def transfer_entropy(source, target, lag=1):
        """TE(source -> target) with given lag."""
        n = len(source)
        if n < lag + 2: return 0
        # TE = H(target_future | target_past) - H(target_future | target_past, source_past)
        # For binary variables, compute directly from contingency tables
        counts = defaultdict(int)
        total = 0
        for t in range(lag, n):
            tp = target[t-lag]  # target past
            sp = source[t-lag]  # source past
            tf = target[t]      # target future
            counts[(tp, sp, tf)] += 1
            total += 1

        if total == 0: return 0

        # Marginal counts
        c_tp_sp = defaultdict(int)
        c_tp = defaultdict(int)
        c_tp_tf = defaultdict(int)
        for (tp, sp, tf), cnt in counts.items():
            c_tp_sp[(tp, sp)] += cnt
            c_tp[tp] += cnt
            c_tp_tf[(tp, tf)] += cnt

        # TE = sum p(tp,sp,tf) * log(p(tf|tp,sp) / p(tf|tp))
        te = 0
        for (tp, sp, tf), cnt in counts.items():
            p_joint = cnt / total
            p_tf_given_tp_sp = cnt / c_tp_sp[(tp, sp)]
            p_tf_given_tp = c_tp_tf[(tp, tf)] / c_tp[tp] if c_tp[tp] > 0 else 0
            if p_tf_given_tp > 0 and p_tf_given_tp_sp > 0:
                te += p_joint * np.log2(p_tf_given_tp_sp / p_tf_given_tp)
        return max(te, 0)

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 200)
        files = sorted(histories.keys())
        if len(files) < 10: continue

        rng = np.random.RandomState(42)
        sample = [files[k] for k in rng.choice(len(files), min(30, len(files)), replace=False)]

        # Compute TE for all directed pairs
        causal_arrows = []
        for i in range(len(sample)):
            for j in range(len(sample)):
                if i == j: continue
                te_ij = transfer_entropy(histories[sample[i]], histories[sample[j]], lag=1)
                te_ji = transfer_entropy(histories[sample[j]], histories[sample[i]], lag=1)
                if te_ij > 0.01 or te_ji > 0.01:
                    asymmetry = (te_ij - te_ji) / (te_ij + te_ji + 1e-12)
                    causal_arrows.append((sample[i], sample[j], te_ij, te_ji, asymmetry))

        if not causal_arrows: continue

        # Sort by asymmetry (strongest causal direction)
        causal_arrows.sort(key=lambda x: -abs(x[4]))

        print(f"\n  {rname}: {len(sample)} files")
        print(f"    {len(causal_arrows)} significant causal pairs (TE > 0.01)")

        print(f"    Strongest causal arrows:")
        print(f"    {'source':>35}  {'target':>35}  {'TE(s->t)':>8}  {'TE(t->s)':>8}  {'asym':>6}")
        print(f"    {'---':>35}  {'---':>35}  {'---':>8}  {'---':>8}  {'---':>6}")

        shown = set()
        for src, tgt, te_st, te_ts, asym in causal_arrows[:10]:
            pair = tuple(sorted([src, tgt]))
            if pair in shown: continue
            shown.add(pair)
            ss = src[-35:] if len(src) > 35 else src
            ts = tgt[-35:] if len(tgt) > 35 else tgt
            arrow = "->" if asym > 0.1 else ("<-" if asym < -0.1 else "<>")
            print(f"    {ss:>35}  {arrow}  {ts:<35}  {te_st:.4f}  {te_ts:.4f}  {asym:+.2f}")

        # Are there files that are pure DRIVERS (high outgoing TE, low incoming)?
        out_te = defaultdict(float)
        in_te = defaultdict(float)
        for src, tgt, te_st, te_ts, _ in causal_arrows:
            out_te[src] += te_st
            in_te[tgt] += te_st

        drivers = sorted(out_te.keys(), key=lambda f: out_te[f] - in_te.get(f, 0), reverse=True)
        if drivers:
            print(f"    Top DRIVERS (cause more than they're caused):")
            for f in drivers[:3]:
                fs = f[-45:] if len(f) > 45 else f
                print(f"      {fs}  out={out_te[f]:.3f}  in={in_te.get(f,0):.3f}")

    print()


# === EXPERIMENT 3: PERSISTENT HOMOLOGY ===============================
# Build a simplicial complex from co-change. Sweep the threshold.
# Track topological features: components (H0), loops (H1).
# Features that PERSIST across many thresholds are structurally real.
# Features that flash briefly are noise.

def experiment_persistent_homology():
    print("=" * 80)
    print("  PERSISTENT HOMOLOGY: topological holes in the co-change complex")
    print("  H0 = connected components. H1 = loops. Persistence = reality.")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 200)
        files = sorted(histories.keys())
        if len(files) < 10: continue

        # Build weighted co-change graph (weight = co-change count)
        rng = np.random.RandomState(42)
        if len(files) > 80:
            sample = [files[k] for k in rng.choice(len(files), 80, replace=False)]
        else:
            sample = files

        n = len(sample)
        weights = np.zeros((n, n))
        for i in range(n):
            for j in range(i+1, n):
                w = np.sum((histories[sample[i]]==1) & (histories[sample[j]]==1))
                weights[i,j] = weights[j,i] = w

        max_w = weights.max()
        if max_w == 0: continue

        # Sweep threshold from high to low (adding edges as we lower the bar)
        # Track H0 (connected components via union-find)
        thresholds = np.unique(weights[weights > 0])
        thresholds = np.sort(thresholds)[::-1]  # high to low

        parent = list(range(n))
        def find(x):
            while parent[x] != x: parent[x] = parent[parent[x]]; x = parent[x]
            return x
        def union(a, b):
            a, b = find(a), find(b)
            if a != b: parent[b] = a; return True
            return False

        h0_births = {i: max_w + 1 for i in range(n)}  # each node born at infinity
        h0_deaths = {}
        n_components = n
        h1_count = 0

        # Track loops: when we add an edge between two already-connected nodes
        loop_births = []

        for thresh in thresholds:
            for i in range(n):
                for j in range(i+1, n):
                    if weights[i,j] == thresh:
                        if find(i) == find(j):
                            # Already connected — this edge creates a LOOP (H1 feature)
                            h1_count += 1
                            loop_births.append(thresh)
                        else:
                            # Merge components — one H0 feature dies
                            dying = max(find(i), find(j))
                            h0_deaths[dying] = thresh
                            union(i, j)
                            n_components -= 1

        # Compute persistence of H0 features (how long each component lives)
        h0_persistence = []
        for node, birth in h0_births.items():
            death = h0_deaths.get(node, 0)  # components that never merge persist to 0
            persistence = birth - death
            h0_persistence.append(persistence)

        h0_persistence.sort(reverse=True)

        print(f"\n  {rname}: {n} files, max co-change = {int(max_w)}")
        print(f"    H0 (components): {n} born, {len(h0_deaths)} merge, "
              f"{n - len(h0_deaths)} survive to threshold 0")
        print(f"    H1 (loops): {h1_count} detected")

        # Top persistent H0 features (the "real" communities)
        real_communities = sum(1 for p in h0_persistence if p > max_w * 0.3)
        print(f"    Persistent communities (lifetime > 30% of range): {real_communities}")

        # Persistence diagram (simplified as bar chart)
        print(f"    H0 persistence barcode (top 10):")
        for i, p in enumerate(h0_persistence[:10]):
            bar_len = int(p / (max_w + 1) * 40)
            bar = "#" * bar_len
            print(f"      {p:6.1f}  |{bar}|")

        # H1 births histogram (at what threshold do loops appear?)
        if loop_births:
            loop_arr = np.array(loop_births)
            print(f"    H1 (loops) appear at thresholds: "
                  f"mean={loop_arr.mean():.1f}  "
                  f"median={np.median(loop_arr):.1f}  "
                  f"range=[{loop_arr.min():.0f}, {loop_arr.max():.0f}]")

            # Loops at high threshold = strong structural cycles
            strong_loops = sum(1 for l in loop_births if l > max_w * 0.5)
            print(f"    Strong loops (thresh > 50% max): {strong_loops}")
            if strong_loops > 0:
                print(f"    The co-change complex has GENUINE TOPOLOGICAL HOLES.")
                print(f"    These are file cycles where A→B→C→A co-change")
                print(f"    but there's no shortcut through the middle.")

    print()


# === EXPERIMENT 4: COMPRESSION DISTANCE ==============================
# NCD(A,B) = (C(AB) - min(C(A),C(B))) / max(C(A),C(B))
# where C(x) = compressed size of x.
# This measures how INFORMATIONALLY similar two file histories are.
# Works on RAW BITS. No decomposition. No linearity assumption.

def experiment_compression_distance():
    print("=" * 80)
    print("  COMPRESSION DISTANCE: raw informational similarity")
    print("  NCD uses zlib to measure how compressible A+B is vs A,B alone.")
    print("  No eigenvalues. No Laplacians. Just bits.")
    print("=" * 80)

    def ncd(a, b):
        """Normalized Compression Distance between two byte strings."""
        ca = len(zlib.compress(a, 9))
        cb = len(zlib.compress(b, 9))
        cab = len(zlib.compress(a + b, 9))
        return (cab - min(ca, cb)) / (max(ca, cb) + 1e-6)

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 200)
        files = sorted(histories.keys())
        if len(files) < 10: continue

        rng = np.random.RandomState(42)
        sample = [files[k] for k in rng.choice(len(files), min(30, len(files)), replace=False)]
        n = len(sample)

        # Convert histories to byte strings
        byte_hists = {}
        for f in sample:
            byte_hists[f] = histories[f].tobytes()

        # Compute NCD matrix
        ncd_matrix = np.zeros((n, n))
        cochange_matrix = np.zeros((n, n))

        for i in range(n):
            for j in range(i+1, n):
                d = ncd(byte_hists[sample[i]], byte_hists[sample[j]])
                ncd_matrix[i,j] = ncd_matrix[j,i] = d
                cc = np.sum((histories[sample[i]]==1) & (histories[sample[j]]==1))
                cochange_matrix[i,j] = cochange_matrix[j,i] = cc

        # Does NCD correlate with co-change?
        ncd_flat = ncd_matrix[np.triu_indices(n, 1)]
        cc_flat = cochange_matrix[np.triu_indices(n, 1)]
        corr = np.corrcoef(ncd_flat, cc_flat)[0,1] if cc_flat.std() > 0 else 0

        print(f"\n  {rname}: {n} files")
        print(f"    Correlation(NCD, co-change): {corr:+.3f}")
        print(f"    NCD range: [{ncd_flat.min():.3f}, {ncd_flat.max():.3f}]")
        print(f"    Mean NCD: {ncd_flat.mean():.3f}")

        # Files that are NCD-close but DON'T co-change (compression sees structure eigenvalues miss)
        surprise_pairs = []
        for i in range(n):
            for j in range(i+1, n):
                if cochange_matrix[i,j] == 0 and ncd_matrix[i,j] < np.percentile(ncd_flat, 25):
                    surprise_pairs.append((sample[i], sample[j], ncd_matrix[i,j]))

        if surprise_pairs:
            surprise_pairs.sort(key=lambda x: x[2])
            print(f"    COMPRESSION SURPRISES (NCD-close, zero co-change):")
            for f1, f2, d in surprise_pairs[:5]:
                f1s = f1[-35:] if len(f1) > 35 else f1
                f2s = f2[-35:] if len(f2) > 35 else f2
                print(f"      NCD={d:.3f}  {f1s} <-> {f2s}")
            print(f"    These files have similar CHANGE RHYTHMS without ever changing together.")
        else:
            print(f"    No compression surprises (NCD and co-change agree).")

    print()


# === EXPERIMENT 5: COMMIT ENTROPY ====================================
# The raw information content of the development process itself.
# How many bits per commit? How predictable is the SEQUENCE of changes?

def experiment_commit_entropy():
    print("=" * 80)
    print("  COMMIT ENTROPY: the raw information content of development")
    print("  How many bits per commit? How predictable is the change sequence?")
    print("=" * 80)

    for rname, rpath in get_repos().items():
        histories, commits = parse_file_histories(rpath, 200)
        files = sorted(histories.keys())
        if len(commits) < 20: continue

        # Entropy of the file-change distribution per commit
        commit_entropies = []
        for c in commits:
            n_changed = len(c)
            if n_changed == 0: continue
            # Entropy of "which files changed": -sum p log p where p = 1/n_changed
            # For uniform: H = log2(n_changed)
            commit_entropies.append(np.log2(n_changed) if n_changed > 0 else 0)

        if not commit_entropies: continue
        commit_entropies = np.array(commit_entropies)

        # Sequence entropy: treat the sequence of changed-file-sets as a Markov chain
        # What's the conditional entropy H(commit_t | commit_{t-1})?
        # Approximate: measure the compressibility of the commit sequence
        commit_str = "|".join([",".join(sorted(c)) for c in commits])
        raw_bytes = commit_str.encode("utf-8")
        compressed = zlib.compress(raw_bytes, 9)
        compression_ratio = len(compressed) / len(raw_bytes)

        # Vocabulary: how many unique "commit types" (unique file-sets)?
        commit_sigs = [frozenset(c) for c in commits]
        unique_types = len(set(commit_sigs))
        vocab_ratio = unique_types / len(commits)

        # Repeat rate: how often does the exact same file-set recur?
        sig_counts = Counter(commit_sigs)
        repeats = sum(1 for c in sig_counts.values() if c > 1)

        print(f"\n  {rname}: {len(commits)} commits, {len(files)} files")
        print(f"    Mean entropy per commit:     {commit_entropies.mean():.2f} bits")
        print(f"    Commit sequence compression: {compression_ratio:.3f} (lower = more predictable)")
        print(f"    Unique commit types:         {unique_types}/{len(commits)} ({vocab_ratio:.0%})")
        print(f"    Repeated commit patterns:    {repeats}")

        # Entropy profile over time
        window = max(5, len(commit_entropies) // 8)
        print(f"    Entropy over time: ", end="")
        for start in range(0, len(commit_entropies) - window + 1, window):
            avg_e = commit_entropies[start:start+window].mean()
            max_e = commit_entropies.max()
            level = int(avg_e / max_e * 7)
            print(" .:-=+#@"[min(level, 7)], end="")
        print()

        if compression_ratio < 0.3:
            print(f"    Development is HIGHLY PREDICTABLE. The commit sequence is compressible.")
            print(f"    The developer has strong patterns/routines.")
        elif compression_ratio < 0.6:
            print(f"    Moderately predictable. Some routines, some novelty.")
        else:
            print(f"    UNPREDICTABLE. High-entropy development. Each commit is a surprise.")

    print()


# === RUN ==============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |        B E N E A T H   E I G E N                       |")
    print("  |   no laplacians. no eigenvalues. just information.       |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_mutual_information()
    experiment_transfer_entropy()
    experiment_persistent_homology()
    experiment_compression_distance()
    experiment_commit_entropy()

    print("=" * 80)
    print("  beneath the eigenvalues there is information.")
    print("  beneath the information there is structure.")
    print("  beneath the structure there is something that doesn't have a name yet.")
    print("=" * 80)
