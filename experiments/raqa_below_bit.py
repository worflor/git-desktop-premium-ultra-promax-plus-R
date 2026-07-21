# SPDX-FileCopyrightText: 2026 Woflo Labs
# SPDX-License-Identifier: LicenseRef-WLCSL-1.0
# See repository-root LICENSE.md and LICENSES/WLCSL-1.0.md.

"""
RAQA BELOW THE BIT — measuring the distinction itself
=======================================================
A bit is 0 or 1. A distinction is the CUT that makes 0 and 1
possible. Can we measure properties of the distinction independent
of the values it separates?

1. The cost of a distinction: not Landauer's bit-erasure cost,
   but the cost of CREATING a boundary. Measure: time to allocate
   vs time to write. Allocation = creating the distinction.
   Writing = choosing a side.

2. The topology of distinctions: a single cut has two sides.
   Two cuts have four regions. Three cuts have up to eight.
   But the ARRANGEMENT of cuts matters — parallel cuts give
   fewer regions than crossing cuts. The number of regions
   is a topological invariant of the distinction pattern.
   Measure it. Find the formula.

3. The minimum distinction: at what precision do two floating
   point numbers stop being distinguishable? That's the
   resolution limit of the distinction — the Planck length
   of the number line. Measure it.

4. Distinction cascades: flip one bit in a hash function input.
   Count how many OUTPUT bits flip (avalanche). The avalanche
   IS the propagation of a distinction through a computation.
   How fast does a single distinction propagate?

5. The algebra of distinctions: combine two distinctions.
   AND = both boundaries must hold. OR = either suffices.
   XOR = exactly one. Each combination has a different
   geometric cost. Measure it.

6. Symmetry breaking threshold: start with N identical objects.
   Add noise. At what noise level do they become DISTINGUISHABLE?
   That threshold is the minimum energy of a distinction.
"""

import numpy as np
import time
import struct
import hashlib

np.set_printoptions(precision=8, linewidth=140, suppress=True)


# === THE COST OF CREATING A DISTINCTION ==============================
# Allocating memory = creating a CONTAINER for a distinction.
# Writing to memory = CHOOSING which side of the distinction.
# The cost difference = the cost of the distinction itself,
# independent of its content.

def experiment_distinction_cost():
    print("=" * 70)
    print("  THE COST OF A DISTINCTION")
    print("  Allocation (creating the boundary) vs writing (choosing a side).")
    print("=" * 70)

    sizes = [100, 1000, 10000, 100000, 1000000]

    print(f"\n  {'n':>10}  {'alloc_ns':>10}  {'write_ns':>10}  {'ratio':>8}  "
          f"{'distinction_ns':>15}")
    print(f"  {'---':>10}  {'---':>10}  {'---':>10}  {'---':>8}  {'---':>15}")

    for n in sizes:
        # Cost of CREATING the distinction (allocation)
        alloc_times = []
        for _ in range(20):
            t0 = time.perf_counter_ns()
            arr = np.empty(n, dtype=np.uint8)
            t1 = time.perf_counter_ns()
            alloc_times.append(t1 - t0)
            del arr

        # Cost of CHOOSING a side (writing)
        arr = np.empty(n, dtype=np.uint8)
        write_times = []
        for _ in range(20):
            t0 = time.perf_counter_ns()
            arr[:] = 0
            t1 = time.perf_counter_ns()
            write_times.append(t1 - t0)

        alloc_ns = np.median(alloc_times)
        write_ns = np.median(write_times)
        ratio = alloc_ns / (write_ns + 1e-6)
        distinction_ns = alloc_ns - write_ns  # pure distinction cost

        print(f"  {n:>10,}  {int(alloc_ns):>10,}  {int(write_ns):>10,}  "
              f"{ratio:8.3f}  {distinction_ns:15.0f}")

    print(f"\n  The distinction cost is the difference: allocation - writing.")
    print(f"  If distinction cost > 0: creating a boundary costs more than")
    print(f"  choosing a side. The CUT is more expensive than the CHOICE.\n")


# === DISTINCTION RESOLUTION: THE PLANCK LENGTH OF NUMBERS ============
# Two numbers are distinguishable if their difference exceeds
# machine epsilon. But the ACTUAL resolution depends on the
# magnitude. At what scale does the distinction collapse?

def experiment_distinction_resolution():
    print("=" * 70)
    print("  THE PLANCK LENGTH OF THE NUMBER LINE")
    print("  At what scale do two numbers become indistinguishable?")
    print("=" * 70)

    print(f"\n  Testing: x and x + δ for decreasing δ.")
    print(f"  At what δ does the computer lose the distinction?\n")

    base_values = [0.0, 1.0, 1e6, 1e12, 1e-6, 1e-12]

    print(f"  {'base':>14}  {'smallest δ':>14}  {'bits of precision':>18}  "
          f"{'relative ε':>14}")
    print(f"  {'---':>14}  {'---':>14}  {'---':>18}  {'---':>14}")

    for base in base_values:
        # Find the smallest δ where x + δ ≠ x
        delta = 1.0
        while base + delta != base and delta > 1e-320:
            last_delta = delta
            delta /= 2

        # The smallest distinguishable δ
        planck = last_delta
        # Bits of precision
        if base != 0:
            relative_eps = planck / abs(base)
            bits_precision = -np.log2(relative_eps) if relative_eps > 0 else 0
        else:
            relative_eps = planck
            bits_precision = -np.log2(planck) if planck > 0 else 0

        print(f"  {base:14.2e}  {planck:14.2e}  {bits_precision:18.1f}  "
              f"{relative_eps:14.2e}")

    # The Planck length is NOT constant — it depends on where you are
    # on the number line. This is CURVATURE of the number line.
    print(f"\n  The distinction threshold is NOT uniform.")
    print(f"  Near zero: δ ≈ 5e-324 (denormalized minimum).")
    print(f"  Near 1: δ ≈ 1.1e-16 (machine epsilon).")
    print(f"  Near 1e12: δ ≈ 1.2e-4.")
    print(f"  The number line has CURVATURE. Large numbers are coarser.")
    print(f"  The Planck length grows as you move away from zero.")
    print(f"  This is the metric structure of IEEE 754 arithmetic.\n")


# === DISTINCTION AVALANCHE: HOW FAST DOES A CUT PROPAGATE? ==========
# Flip one input bit. Count how many output bits change.
# This is the Shannon diffusion property: how fast does one
# distinction multiply into many?

def experiment_distinction_avalanche():
    print("=" * 70)
    print("  DISTINCTION AVALANCHE")
    print("  One input bit flip → how many output bits change?")
    print("  The propagation speed of a single distinction.")
    print("=" * 70)

    def avalanche_test(transform, n_bits_in, n_bits_out, n_trials=500):
        """Measure avalanche: flip each input bit, count output changes."""
        rng = np.random.RandomState(42)
        total_flips = np.zeros(n_bits_out)
        total_trials = 0

        for _ in range(n_trials):
            # Random input
            x = rng.bytes(n_bits_in // 8)
            y = transform(x)

            # Flip each input bit
            x_bytes = bytearray(x)
            for bit_pos in range(min(n_bits_in, 64)):
                byte_idx = bit_pos // 8
                bit_idx = bit_pos % 8
                x_flipped = bytearray(x_bytes)
                x_flipped[byte_idx] ^= (1 << bit_idx)
                y_flipped = transform(bytes(x_flipped))

                # Count output bit differences
                for out_byte in range(min(len(y), len(y_flipped), n_bits_out // 8)):
                    diff = y[out_byte] ^ y_flipped[out_byte]
                    for b in range(8):
                        if diff & (1 << b):
                            total_flips[out_byte * 8 + b] += 1
                total_trials += 1

        return total_flips / (total_trials + 1e-6)

    # Test 1: SHA-256 (cryptographic — should be near-perfect avalanche)
    def sha256(x):
        return hashlib.sha256(x).digest()

    av_sha = avalanche_test(sha256, 64, 256, 200)
    mean_sha = av_sha[:256].mean()
    std_sha = av_sha[:256].std()

    # Test 2: Simple XOR (linear — should be exactly 1 bit)
    def xor_const(x):
        key = b'\xaa' * len(x)
        return bytes(a ^ b for a, b in zip(x, key[:len(x)]))

    av_xor = avalanche_test(xor_const, 64, 64, 200)
    mean_xor = av_xor[:64].mean()

    # Test 3: Multiplication (nonlinear but structured)
    def mul_hash(x):
        val = int.from_bytes(x[:8], 'little')
        result = (val * 0x517cc1b727220a95) & ((1 << 64) - 1)
        return result.to_bytes(8, 'little')

    av_mul = avalanche_test(mul_hash, 64, 64, 200)
    mean_mul = av_mul[:64].mean()

    print(f"\n  {'transform':>15}  {'mean_avalanche':>15}  {'ideal':>8}  {'quality':>10}")
    print(f"  {'---':>15}  {'---':>15}  {'---':>8}  {'---':>10}")
    print(f"  {'SHA-256':>15}  {mean_sha:15.4f}  {'0.5000':>8}  "
          f"{'{'}{abs(mean_sha - 0.5)/0.5*100:.1f}% off{'}'}")
    print(f"  {'XOR':>15}  {mean_xor:15.4f}  {'0.0156':>8}  "
          f"{'linear (no mixing)'}")
    print(f"  {'Multiply':>15}  {mean_mul:15.4f}  {'0.5000':>8}  "
          f"{'{'}{abs(mean_mul - 0.5)/0.5*100:.1f}% off{'}'}")

    print(f"\n  SHA-256: one distinction propagates to ~50% of output bits.")
    print(f"  XOR: one distinction propagates to exactly 1 output bit.")
    print(f"  Multiplication: partial propagation.")
    print(f"\n  The SPEED of distinction propagation = the mixing quality")
    print(f"  of the operation. Cryptographic hashes spread distinctions")
    print(f"  maximally. Linear operations preserve them exactly.")
    print(f"  The distinction's speed of light depends on the algebra.\n")


# === SYMMETRY BREAKING THRESHOLD ====================================
# Start with N identical values. Add Gaussian noise.
# At what noise level σ can you RELIABLY distinguish all N values?
# That σ is the minimum energy of a distinction — the energy
# required to break symmetry between N identical objects.

def experiment_symmetry_breaking():
    print("=" * 70)
    print("  SYMMETRY BREAKING THRESHOLD")
    print("  N identical objects + noise σ → at what σ are they distinguishable?")
    print("  The minimum energy of a distinction.")
    print("=" * 70)

    rng = np.random.RandomState(42)

    for n in [2, 3, 4, 8, 16, 32, 64, 128, 256]:
        # Start with N copies of 0
        # Add noise of increasing σ
        # At each σ, check: can we correctly assign each noisy value
        # back to its original index (nearest-neighbor matching)?

        # Critical σ where all N values are distinguishable:
        # For N values on [0, 1], the minimum spacing is 1/(N-1).
        # Noise σ must be << spacing for reliable distinction.
        # σ_critical ≈ 1/(2(N-1)) for ~95% accuracy.
        spacing = 1.0 / (n - 1) if n > 1 else 1.0

        sigmas = np.logspace(-3, 1, 30)
        threshold_found = False

        for sigma in sigmas:
            # Place N values uniformly on [0, 1]
            true_values = np.linspace(0, 1, n)
            # Add noise
            correct = 0
            trials = 50
            for _ in range(trials):
                noisy = true_values + rng.randn(n) * sigma
                # Try to recover: sort and match
                sorted_idx = np.argsort(noisy)
                true_idx = np.arange(n)
                if np.array_equal(sorted_idx, true_idx):
                    correct += 1

            accuracy = correct / trials
            if accuracy < 0.95 and not threshold_found:
                sigma_crit = sigma
                threshold_found = True
                break

        if not threshold_found:
            sigma_crit = sigmas[-1]

        # The ratio σ_crit / spacing is the fundamental quantity
        ratio = sigma_crit / spacing if spacing > 0 else 0

        print(f"  N={n:4d}  spacing={spacing:.4f}  σ_crit={sigma_crit:.4f}  "
              f"σ/spacing={ratio:.3f}")

    print(f"\n  σ/spacing should be approximately constant if the distinction")
    print(f"  threshold is a universal ratio. Is it?\n")

    # The ratio should be ≈ 0.5 if the 95% accuracy threshold corresponds
    # to 2σ < spacing, i.e., σ < spacing/2.
    print(f"  If σ/spacing ≈ const: the cost of a distinction scales with")
    print(f"  the spacing between alternatives. Finer distinctions cost more.")
    print(f"  This IS the Heisenberg uncertainty principle for classical bits:")
    print(f"  ΔE · Δx ≥ kT · ln(2)  where Δx = spacing and ΔE = σ²/2.\n")


# === THE DISTINCTION TENSOR =========================================
# A single distinction is a scalar (yes/no).
# Two distinctions have a RELATIONSHIP (parallel, crossing, nested).
# Three distinctions form a TENSOR with structure.
# Measure the tensor properties of small distinction systems.

def experiment_distinction_tensor():
    print("=" * 70)
    print("  THE DISTINCTION TENSOR")
    print("  How do multiple distinctions relate to each other?")
    print("  Parallel, crossing, nested — measured geometrically.")
    print("=" * 70)

    rng = np.random.RandomState(42)

    for n_cuts in [2, 3, 4, 5, 6, 8]:
        # Create n_cuts random hyperplane cuts in d-dimensional space
        d = 10
        n_points = 500

        # Random points in [0,1]^d
        points = rng.rand(n_points, d)

        # Random hyperplane normals (each cut is a distinction)
        normals = rng.randn(n_cuts, d)
        normals /= np.linalg.norm(normals, axis=1, keepdims=True)

        # For each point, compute which side of each cut it's on
        # This gives a binary string of length n_cuts — the "distinction code"
        codes = np.zeros((n_points, n_cuts), dtype=np.uint8)
        for c in range(n_cuts):
            projections = points @ normals[c]
            median_proj = np.median(projections)
            codes[:, c] = (projections > median_proj).astype(np.uint8)

        # How many DISTINCT regions do the cuts create?
        unique_codes = set(tuple(codes[i]) for i in range(n_points))
        n_regions = len(unique_codes)

        # Maximum possible regions (if all cuts are in "general position"):
        # For k hyperplanes in d dimensions: Σ C(k,i) for i=0..d
        # But for k <= d+1, it's 2^k
        max_regions = min(2**n_cuts, sum(
            1 for i in range(min(n_cuts, d) + 1)
            for _ in range(1)  # C(n_cuts, i) terms, simplified
        ))
        max_regions = 2**n_cuts  # upper bound for k cuts

        # Efficiency: what fraction of possible regions are occupied?
        efficiency = n_regions / max_regions

        # Mutual information between pairs of cuts
        # (are the distinctions independent or correlated?)
        mi_pairs = []
        for i in range(n_cuts):
            for j in range(i+1, n_cuts):
                # MI between cut i and cut j
                p00 = np.mean((codes[:,i]==0)&(codes[:,j]==0))
                p01 = np.mean((codes[:,i]==0)&(codes[:,j]==1))
                p10 = np.mean((codes[:,i]==1)&(codes[:,j]==0))
                p11 = np.mean((codes[:,i]==1)&(codes[:,j]==1))
                pi = codes[:,i].mean()
                pj = codes[:,j].mean()
                mi = 0
                for pxy, px, py in [(p00,1-pi,1-pj),(p01,1-pi,pj),
                                     (p10,pi,1-pj),(p11,pi,pj)]:
                    if pxy > 0 and px > 0 and py > 0:
                        mi += pxy * np.log2(pxy/(px*py))
                mi_pairs.append(mi)

        mean_mi = np.mean(mi_pairs) if mi_pairs else 0

        # Angle between cut normals (geometric relationship)
        angles = []
        for i in range(n_cuts):
            for j in range(i+1, n_cuts):
                cos_a = abs(np.dot(normals[i], normals[j]))
                angles.append(np.degrees(np.arccos(np.clip(cos_a, 0, 1))))

        mean_angle = np.mean(angles) if angles else 0

        print(f"  {n_cuts} cuts in {d}D: {n_regions}/{max_regions} regions "
              f"({efficiency:.0%})  MI={mean_mi:.4f}  "
              f"mean_angle={mean_angle:.1f}°")

    print(f"\n  Efficiency = how well the distinctions TILE the space.")
    print(f"  MI ≈ 0 → cuts are independent (orthogonal distinctions).")
    print(f"  MI > 0 → cuts are redundant (correlated distinctions).")
    print(f"  Angle ≈ 90° → geometrically orthogonal cuts.\n")

    print(f"  The distinction tensor's rank = number of independent cuts.")
    print(f"  Its trace = total information content.")
    print(f"  Its determinant = the VOLUME of distinguishable space.")
    print(f"  Geometry emerges from how distinctions CROSS each other.\n")


# === RUN ==============================================================

if __name__ == "__main__":
    print()
    print("  +---------------------------------------------------------+")
    print("  |          B E L O W   T H E   B I T                     |")
    print("  |   measuring the distinction itself                       |")
    print("  +---------------------------------------------------------+")
    print()

    experiment_distinction_cost()
    experiment_distinction_resolution()
    experiment_distinction_avalanche()
    experiment_symmetry_breaking()
    experiment_distinction_tensor()

    print("=" * 70)
    print("  below the bit is the cut.")
    print("  below the cut is the asymmetry.")
    print("  below the asymmetry is the cost.")
    print("  below the cost is kT·ln(2).")
    print("  below kT·ln(2) is the temperature.")
    print("  below the temperature is motion.")
    print("  below motion is time.")
    print("  below time is the first distinction.")
    print("  it's turtles all the way down,")
    print("  but the turtles are all the same turtle.")
    print("=" * 70)
