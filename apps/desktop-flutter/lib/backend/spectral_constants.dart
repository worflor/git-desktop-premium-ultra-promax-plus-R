import 'dart:math' as math;

// φ — the golden ratio. Most irrational number; drives Kizuna's
// address scrambling (0x9E3779B9 = floor(2^32/φ)), shadow confidence
// decay (1/φ^t for t hops from reality), and the ritual decay knee.
const double phi = 1.6180339887498949;

// Gas-phase evaporation value: exp(−1). The evaporation function
// exp(−(1−c)²) at maximum spectral entropy (c=0) returns 1/e.
// Used as the thermodynamic minimum for shadow discount and
// transport integrity floor — the weakest signal that's still signal.
final double gasPhase = 1.0 / math.e; // ≈ 0.368

// Golden-ratio powers: heat-kernel decay at the φ scale.
// 1/φ^t for t = 1 (near), 2 (deeper), 3 (exiled).
final double phiDecay1 = 1.0 / phi;           // ≈ 0.618
final double phiDecay2 = 1.0 / (phi * phi);   // ≈ 0.382
final double phiDecay3 = 1.0 / (phi * phi * phi); // ≈ 0.236

// CC-axis evidence square: k² where k=4 is the number of
// distinguishable co-change regimes. Same information-theoretic
// basis as the Born mixer's evidence cap ln(4) = 2·ln(2).
const double kCcEvidenceSquare = 16.0; // 4²
