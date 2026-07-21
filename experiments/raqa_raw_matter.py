# SPDX-FileCopyrightText: 2026 Woflo Labs
# SPDX-License-Identifier: LicenseRef-WLCSL-1.0
# See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

"""
RAQA RAW MATTER — no repos, no graphs, just bits and silicon
=============================================================
The computer IS the experiment. Measure the physics of computation.
1. Bit-flip thermodynamics: how close to Landauer's limit?
2. Eigenvalue computation has a physical cost curve — measure it
3. Cache topology: is memory access itself a graph with structure?
4. Floating point as a physical system: where does precision die?
5. Random number entropy: does the PRNG have spectral structure?
6. Matrix multiplication phase transition: when does chaos emerge?
"""

import numpy as np
import time
import struct
import sys

np.set_printoptions(precision=6, linewidth=120, suppress=True)


# === EXPERIMENT 1: LANDAUER'S LIMIT ON YOUR DESK ====================
# Every bit erasure costs at least kT*ln(2) energy.
# We can't measure energy directly, but we CAN measure TIME,
# and time * power = energy. Estimate how close your CPU gets.

def experiment_landauer():
    print("=" * 70)
    print("  EXPERIMENT 1: HOW CLOSE TO LANDAUER'S LIMIT?")
    print("  Minimum energy to erase a bit: kT*ln(2) = 2.87e-21 J at 300K")
    print("=" * 70)

    # Measure time for different amounts of "bit erasure"
    # Overwriting memory is bit erasure in the Landauer sense

    sizes = [1000, 10_000, 100_000, 1_000_000, 10_000_000]

    print(f"\n  Overwriting arrays of different sizes (= erasing bits)")
    print(f"  Measuring time per bit-erasure operation\n")

    print(f"  {'n_bits':>12}  {'time_ns':>12}  {'ns/bit':>10}  {'bits/ns':>10}  {'est_J/bit':>12}")
    print(f"  {'---':>12}  {'---':>12}  {'---':>10}  {'---':>10}  {'---':>12}")

    # Assume ~15W TDP for a desktop CPU (rough)
    cpu_watts = 15.0
    landauer = 2.87e-21  # J at 300K

    prev_ns_per_bit = None

    for n in sizes:
        arr = np.zeros(n, dtype=np.uint8)

        # Measure overwrite time
        trials = 10
        times = []
        for _ in range(trials):
            t0 = time.perf_counter_ns()
            arr[:] = 0xFF  # erase (overwrite all bits to 1)
            t1 = time.perf_counter_ns()
            times.append(t1 - t0)

        median_ns = np.median(times)
        n_bits = n * 8
        ns_per_bit = median_ns / n_bits
        bits_per_ns = n_bits / median_ns if median_ns > 0 else 0

        # Energy estimate: time * power
        est_energy = (median_ns * 1e-9) * cpu_watts / n_bits

        ratio = est_energy / landauer

        print(f"  {n_bits:>12,}  {int(median_ns):>12,}  {ns_per_bit:>10.4f}  "
              f"{bits_per_ns:>10.1f}  {est_energy:>12.2e}  ({ratio:.0e}x Landauer)")

        prev_ns_per_bit = ns_per_bit

    print(f"\n  Landauer limit: {landauer:.2e} J/bit")
    print(f"  Your CPU wastes ~{ratio:.0e}x the theoretical minimum.")
    print(f"  That gap is where all computation happens —")
    print(f"  every useful operation is funded by this energy surplus.\n")


# === EXPERIMENT 2: THE EIGENVALUE COST CURVE ========================
# How does computation time scale with matrix size?
# Is it smooth or does it have phase transitions?
# The DEVIATION from O(n^3) is physical information.

def experiment_eigenvalue_cost():
    print("=" * 70)
    print("  EXPERIMENT 2: EIGENVALUE COST CURVE")
    print("  Does computation time scale smoothly, or are there phases?")
    print("=" * 70)

    sizes = [8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512]
    rng = np.random.RandomState(42)

    print(f"\n  {'n':>6}  {'time_us':>10}  {'t/n^3':>10}  {'ratio':>8}  curve")
    print(f"  {'---':>6}  {'---':>10}  {'---':>10}  {'---':>8}")

    prev_ratio = None
    ratios = []

    for n in sizes:
        A = rng.randn(n, n)
        A = (A + A.T) / 2  # symmetric

        trials = max(3, 20 // max(1, n // 64))
        times = []
        for _ in range(trials):
            t0 = time.perf_counter_ns()
            np.linalg.eigvalsh(A)
            t1 = time.perf_counter_ns()
            times.append(t1 - t0)

        median_ns = np.median(times)
        median_us = median_ns / 1000

        # Normalize by n^3
        t_per_n3 = median_ns / (n ** 3)
        ratios.append(t_per_n3)

        if prev_ratio is not None:
            change = t_per_n3 / prev_ratio
        else:
            change = 1.0

        bar_len = min(40, max(1, int(t_per_n3 / max(ratios) * 40))) if ratios else 1
        bar = "#" * bar_len

        print(f"  {n:6d}  {median_us:10.1f}  {t_per_n3:10.2f}  {change:8.2f}x  {bar}")

        prev_ratio = t_per_n3

    # Look for phase transitions
    ratios = np.array(ratios)
    if len(ratios) > 3:
        changes = ratios[1:] / ratios[:-1]
        max_jump = np.max(np.abs(np.log(changes)))
        jump_idx = np.argmax(np.abs(np.log(changes)))
        print(f"\n  Biggest cost jump: {changes[jump_idx]:.2f}x between n={sizes[jump_idx]} and n={sizes[jump_idx+1]}")
        if max_jump > np.log(1.5):
            print(f"  PHASE TRANSITION in computation cost around n~{sizes[jump_idx+1]}")
            print(f"  (likely a cache boundary — L1/L2/L3 overflow)")
        else:
            print(f"  Cost scales smoothly. No obvious phase transition.")
    print()


# === EXPERIMENT 3: FLOATING POINT DEATH MAP =========================
# Where does floating point precision collapse?
# Build a matrix near the edge of numerical stability.
# Watch eigenvalues decay, merge, and die.

def experiment_precision_death():
    print("=" * 70)
    print("  EXPERIMENT 3: THE FLOATING POINT DEATH MAP")
    print("  Where does numerical precision collapse?")
    print("=" * 70)

    n = 50

    print(f"\n  Building {n}x{n} matrices with condition numbers from 1 to 10^16")
    print(f"  Measuring eigenvalue accuracy (forward-inverse roundtrip error)\n")

    print(f"  {'cond':>12}  {'roundtrip_err':>14}  {'dead_eigs':>10}  {'alive%':>7}  status")
    print(f"  {'---':>12}  {'---':>14}  {'---':>10}  {'---':>7}")

    rng = np.random.RandomState(42)
    transition_cond = None

    for exp in range(0, 17):
        target_cond = 10.0 ** exp

        # Build matrix with specific condition number
        U, _ = np.linalg.qr(rng.randn(n, n))
        singular_values = np.logspace(0, -exp, n)
        A = U @ np.diag(singular_values) @ U.T
        A = (A + A.T) / 2

        # Eigendecomposition
        eigs, vecs = np.linalg.eigh(A)

        # Roundtrip: reconstruct and compare
        A_reconstructed = vecs @ np.diag(eigs) @ vecs.T
        err = np.linalg.norm(A - A_reconstructed) / np.linalg.norm(A)

        # How many eigenvalues are "dead" (indistinguishable from zero)?
        dead = np.sum(np.abs(eigs) < np.abs(eigs).max() * 1e-15)
        alive_pct = (n - dead) / n

        actual_cond = singular_values[0] / singular_values[-1]

        if err > 1e-10 and transition_cond is None:
            transition_cond = actual_cond

        if err > 0.1:
            status = "DEAD"
        elif err > 1e-6:
            status = "DYING"
        elif err > 1e-12:
            status = "STRESSED"
        else:
            status = "healthy"

        print(f"  {actual_cond:>12.0e}  {err:>14.2e}  {dead:>10d}  {alive_pct:>6.0%}  {status}")

    if transition_cond:
        print(f"\n  Precision begins dying at condition number ~{transition_cond:.0e}")
        print(f"  That's the event horizon. Beyond it, eigenvalues are noise.")
        print(f"  float64 has ~15.7 decimal digits. cond > 10^15 = information loss.\n")
    else:
        print(f"\n  float64 survives all tested condition numbers.\n")


# === EXPERIMENT 4: PRNG SPECTRAL STRUCTURE ==========================
# Is your random number generator ACTUALLY random?
# Build a matrix from PRNG output and test its eigenvalue statistics.
# Compare: PRNG vs true chaos (logistic map) vs structured (pi digits)

def experiment_prng_spectrum():
    print("=" * 70)
    print("  EXPERIMENT 4: DOES YOUR PRNG HAVE SPECTRAL STRUCTURE?")
    print("  Compare: numpy PRNG vs logistic map vs pi digits")
    print("=" * 70)

    n = 200

    sources = {}

    # Source 1: numpy PRNG (Mersenne Twister)
    rng = np.random.RandomState(42)
    data = rng.randn(n * n)
    M = data.reshape(n, n)
    M = (M + M.T) / 2
    sources["numpy PRNG"] = M

    # Source 2: logistic map (deterministic chaos)
    x = 0.1
    vals = []
    for _ in range(n * n):
        x = 3.9999 * x * (1 - x)  # fully chaotic regime
        vals.append(x)
    data2 = np.array(vals)
    data2 = (data2 - 0.5) * 2  # center
    M2 = data2.reshape(n, n)
    M2 = (M2 + M2.T) / 2
    sources["logistic map"] = M2

    # Source 3: structured (sequential integers, definitely not random)
    data3 = np.arange(n * n, dtype=float) / (n * n)
    data3 = (data3 - 0.5) * 2
    M3 = data3.reshape(n, n)
    M3 = (M3 + M3.T) / 2
    sources["sequential"] = M3

    # Source 4: repeated block (low entropy)
    block = rng.randn(20)
    data4 = np.tile(block, n * n // 20 + 1)[:n * n]
    M4 = data4.reshape(n, n)
    M4 = (M4 + M4.T) / 2
    sources["low entropy"] = M4

    print(f"\n  {n}x{n} symmetric matrices from different sources")
    print(f"  Testing eigenvalue statistics (GOE = truly random)\n")

    print(f"  {'source':>15}  {'<r>':>6}  {'var(s)':>7}  {'P(s<.1)':>8}  "
          f"{'class':>12}  eigenvalue range")
    print(f"  {'---':>15}  {'---':>6}  {'---':>7}  {'---':>8}  {'---':>12}")

    for name, M in sources.items():
        eigs = np.linalg.eigvalsh(M)

        # Unfold eigenvalues (local mean spacing = 1)
        # Use sliding window for local unfolding
        window = max(10, len(eigs) // 10)
        unfolded = []
        for i in range(window, len(eigs) - window):
            local_density = window * 2 / (eigs[i + window] - eigs[i - window] + 1e-30)
            unfolded.append(eigs[i] * local_density)

        unfolded = np.array(unfolded)
        spacings = np.diff(unfolded)
        spacings = spacings[spacings > 0]
        mean_s = spacings.mean() if len(spacings) > 0 else 1
        s_norm = spacings / mean_s if mean_s > 0 else spacings

        if len(s_norm) > 5:
            r_vals = np.minimum(s_norm[:-1], s_norm[1:]) / (np.maximum(s_norm[:-1], s_norm[1:]) + 1e-30)
            r_mean = r_vals.mean()
            var_s = s_norm.var()
            p_small = np.mean(s_norm < 0.1)

            if r_mean > 0.48:
                cls = "GOE"
            elif r_mean > 0.42:
                cls = "semi-Poisson"
            else:
                cls = "Poisson"
        else:
            r_mean = 0
            var_s = 0
            p_small = 0
            cls = "N/A"

        eig_range = f"[{eigs[0]:.1f}, {eigs[-1]:.1f}]"

        print(f"  {name:>15}  {r_mean:6.3f}  {var_s:7.3f}  {p_small:8.4f}  "
              f"{cls:>12}  {eig_range}")

    print(f"\n  GOE reference: <r>=0.531, var(s)=0.286, P(s<0.1)=0.004")
    print(f"  If PRNG and logistic both hit GOE: they're indistinguishable from quantum chaos.")
    print(f"  If sequential doesn't: structure breaks the universality class.\n")


# === EXPERIMENT 5: MATRIX MULTIPLICATION PHASE TRANSITION ===========
# Multiply random matrices together. After how many multiplications
# does the product become dominated by the leading eigenvector?
# This is the power method — but we're measuring the SPEED of
# information collapse. How fast does chaos become order?

def experiment_chaos_to_order():
    print("=" * 70)
    print("  EXPERIMENT 5: CHAOS TO ORDER")
    print("  How many matrix multiplications until randomness collapses")
    print("  into a single dominant direction?")
    print("=" * 70)

    rng = np.random.RandomState(42)

    for n in [10, 30, 100]:
        print(f"\n  n={n}:")
        print(f"  {'step':>6}  {'rank_eff':>9}  {'top_singular':>12}  "
              f"{'entropy':>8}  {'status':>10}")
        print(f"  {'---':>6}  {'---':>9}  {'---':>12}  {'---':>8}  {'---':>10}")

        M = np.eye(n)
        transition_step = None

        for step in range(1, 51):
            # Multiply by a new random matrix
            R = rng.randn(n, n) / np.sqrt(n)
            M = M @ R

            # Normalize to prevent overflow
            norm = np.linalg.norm(M)
            if norm > 0:
                M = M / norm

            # Measure how "collapsed" the product is
            U, s, Vt = np.linalg.svd(M)

            # Effective rank (participation ratio of singular values)
            s_norm = s / s.sum() if s.sum() > 0 else s
            rank_eff = 1.0 / (np.sum(s_norm**2) + 1e-30)

            # Entropy of singular value distribution
            p = s_norm[s_norm > 1e-15]
            entropy = -np.sum(p * np.log(p + 1e-30))

            if rank_eff < n * 0.1 and transition_step is None:
                transition_step = step

            if step <= 5 or step % 5 == 0 or (transition_step and step == transition_step):
                if rank_eff > n * 0.5:
                    status = "chaotic"
                elif rank_eff > n * 0.1:
                    status = "collapsing"
                elif rank_eff > 2:
                    status = "few modes"
                else:
                    status = "collapsed"

                marker = " <-- TRANSITION" if step == transition_step else ""
                print(f"  {step:6d}  {rank_eff:9.2f}  {s[0]:12.6f}  "
                      f"{entropy:8.4f}  {status:>10}{marker}")

        if transition_step:
            print(f"  Collapsed at step {transition_step}.")
            print(f"  {transition_step} random multiplications to destroy {n} dimensions of information.")
        else:
            print(f"  Still chaotic after 50 steps.")

    print(f"\n  This is the Lyapunov exponent made visible:")
    print(f"  how fast does repeated random transformation")
    print(f"  squeeze all information into one direction?\n")


# === EXPERIMENT 6: INFORMATION DENSITY OF REAL NUMBERS ==============
# How much information is in a float64?
# Perturb the least significant bits and measure when
# eigenvalues notice. That's the information content.

def experiment_bit_sensitivity():
    print("=" * 70)
    print("  EXPERIMENT 6: INFORMATION DENSITY OF A FLOAT64")
    print("  Flip bits from the bottom up. When do eigenvalues notice?")
    print("=" * 70)

    n = 50
    rng = np.random.RandomState(42)
    A = rng.randn(n, n)
    A = (A + A.T) / 2

    eigs_orig = np.linalg.eigvalsh(A)

    print(f"\n  {n}x{n} random symmetric matrix")
    print(f"  Flipping bits at different significance levels\n")

    print(f"  {'bit_pos':>8}  {'magnitude':>12}  {'eig_shift':>12}  {'modes_hit':>10}  {'detectable':>10}")
    print(f"  {'---':>8}  {'---':>12}  {'---':>12}  {'---':>10}  {'---':>10}")

    detection_bit = None

    for bit_pos in range(0, 53, 4):  # float64 has 52 mantissa bits
        # Create perturbation at specific bit level
        A_perturbed = A.copy()

        for i in range(n):
            for j in range(i, n):
                # Get the float as bits
                val = A[i, j]
                bits = struct.pack('d', val)
                int_val = int.from_bytes(bits, 'little')

                # Flip bit at position bit_pos
                int_val ^= (1 << bit_pos)

                new_bits = int_val.to_bytes(8, 'little')
                new_val = struct.unpack('d', new_bits)[0]

                if np.isfinite(new_val):
                    A_perturbed[i, j] = new_val
                    A_perturbed[j, i] = new_val

        eigs_pert = np.linalg.eigvalsh(A_perturbed)
        shift = np.sum(np.abs(eigs_orig - eigs_pert))
        modes_hit = np.sum(np.abs(eigs_orig - eigs_pert) > 1e-15)

        # Magnitude of perturbation
        perturbation_mag = np.linalg.norm(A_perturbed - A) / np.linalg.norm(A)

        detectable = "YES" if shift > 1e-12 else "no"

        if shift > 1e-12 and detection_bit is None:
            detection_bit = bit_pos

        print(f"  bit {bit_pos:>4}  {perturbation_mag:>12.2e}  {shift:>12.2e}  "
              f"{modes_hit:>10d}  {detectable:>10}")

    if detection_bit is not None:
        info_bits = 52 - detection_bit
        print(f"\n  Eigenvalues detect perturbations at bit {detection_bit} and above.")
        print(f"  That means {info_bits} of 52 mantissa bits carry eigenvalue-relevant information.")
        print(f"  The bottom {detection_bit} bits are spectral noise — invisible to the eigenspace.")
        print(f"  Information density: {info_bits/52:.0%} of float64 matters for spectral structure.\n")
    else:
        print(f"\n  Eigenvalues detect perturbations at ALL bit levels.\n")


# === RUN ============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |          R A Q A   R A W   M A T T E R   L A B          |")
    print("  |   no repos. no graphs. just bits and silicon.            |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_landauer()
    experiment_eigenvalue_cost()
    experiment_precision_death()
    experiment_prng_spectrum()
    experiment_chaos_to_order()
    experiment_bit_sensitivity()

    print("=" * 70)
    print("  The computer measured itself.")
    print("  Now it knows things about itself that it didn't before.")
    print("  That's RAQA. Measure. Rotate. Repeat.")
    print("=" * 70)
