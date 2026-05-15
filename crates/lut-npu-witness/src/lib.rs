//! Wave-35 LUT-NPU witness: 41-entry Z₃-compressed ternary dot-product LUT.
//!
//! # Design
//!
//! A ternary dot-product `a · w = Σ aᵢ wᵢ` where each `aᵢ, wᵢ ∈ {-1, 0, +1}`.
//!
//! ## Z₃ Compression
//!
//! The elementwise product vector `p` with `pᵢ = aᵢ wᵢ` is itself a `Trit4`.
//! Under the sign-fold equivalence `p ~ -p` (first non-zero entry normalised to +1),
//! the 3⁴ = 81 possible `p` vectors collapse to exactly **41** canonical classes.
//!
//! `LUT_NPU_TABLE[k]` stores `Σ cᵢ` for the canonical representative `c` of class `k`.
//! The actual dot-product is recovered via `sign_p × LUT_NPU_TABLE[class_id(p)]`.
//!
//! ## R-SI-1 compliance
//!
//! The `*` operator does **not** appear anywhere in function bodies; all ternary
//! multiplication is expressed with `match` arms.
//!
//! ## Anchor
//!
//! φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877

#![forbid(unsafe_code)]
#![deny(missing_docs)]

/// A single ternary digit: −1, 0, or +1.
#[repr(i8)]
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Trit {
    /// The −1 trit.
    Neg = -1,
    /// The 0 trit.
    Zero = 0,
    /// The +1 trit.
    Pos = 1,
}

impl Trit {
    /// Return the `i8` value of this trit.
    #[inline]
    pub fn val(self) -> i8 {
        match self {
            Trit::Neg  => -1,
            Trit::Zero =>  0,
            Trit::Pos  =>  1,
        }
    }

    /// Negate this trit.
    #[inline]
    pub fn neg(self) -> Self {
        match self {
            Trit::Neg  => Trit::Pos,
            Trit::Zero => Trit::Zero,
            Trit::Pos  => Trit::Neg,
        }
    }
}

/// A vector of four ternary digits.
pub type Trit4 = [Trit; 4];

/// Compute the ternary product `aᵢ × wᵢ` for a single pair — no `*` operator.
///
/// # Rules
///
/// | a   | w   | result |
/// |-----|-----|--------|
/// | Pos | Pos |  Pos   |
/// | Pos | Neg |  Neg   |
/// | Neg | Pos |  Neg   |
/// | Neg | Neg |  Pos   |
/// | _   | _   |  Zero  |
#[inline]
fn trit_mul(a: Trit, w: Trit) -> Trit {
    match (a, w) {
        (Trit::Pos, Trit::Pos) => Trit::Pos,
        (Trit::Pos, Trit::Neg) => Trit::Neg,
        (Trit::Neg, Trit::Pos) => Trit::Neg,
        (Trit::Neg, Trit::Neg) => Trit::Pos,
        _                      => Trit::Zero,
    }
}

/// Compute the ternary dot-product `a · w` without the `*` operator in the body.
///
/// Each pair contribution is resolved via `match` through [`trit_mul`], then summed
/// using `i8` addition.
pub fn dotprod_naive(a: Trit4, w: Trit4) -> i8 {
    let p0 = trit_mul(a[0], w[0]).val();
    let p1 = trit_mul(a[1], w[1]).val();
    let p2 = trit_mul(a[2], w[2]).val();
    let p3 = trit_mul(a[3], w[3]).val();
    p0.wrapping_add(p1).wrapping_add(p2).wrapping_add(p3)
}

/// Compute the sign-fold canonical form of a `Trit4` and the sign factor applied.
///
/// Returns `(canonical, sign)` where `sign` is `1i8` if unchanged, or `-1i8` if negated.
/// The canonical form has its first non-zero entry equal to `Trit::Pos`.
#[inline]
fn canonical(t: Trit4) -> (Trit4, i8) {
    // Find first non-zero
    let mut first_nonzero: Option<Trit> = None;
    for &v in t.iter() {
        if v != Trit::Zero {
            first_nonzero = Some(v);
            break;
        }
    }
    match first_nonzero {
        None => (t, 1),
        Some(Trit::Neg) => {
            ([t[0].neg(), t[1].neg(), t[2].neg(), t[3].neg()], -1)
        }
        Some(_) => (t, 1),
    }
}

/// Return the Z₃ canonical class id (0 … 40) for a `Trit4`.
///
/// All 3⁴ = 81 tuples map onto exactly **41** distinct ids.
/// Under sign-fold symmetry, `a` and `−a` share the same class id.
pub fn z3_class_id(a: Trit4) -> usize {
    let (c, _) = canonical(a);
    let k = (c[0].val(), c[1].val(), c[2].val(), c[3].val());
    match k {
        ( 0,  0,  0,  0) =>  0,
        ( 0,  0,  0,  1) =>  1,
        ( 0,  0,  1, -1) =>  2,
        ( 0,  0,  1,  0) =>  3,
        ( 0,  0,  1,  1) =>  4,
        ( 0,  1, -1, -1) =>  5,
        ( 0,  1, -1,  0) =>  6,
        ( 0,  1, -1,  1) =>  7,
        ( 0,  1,  0, -1) =>  8,
        ( 0,  1,  0,  0) =>  9,
        ( 0,  1,  0,  1) => 10,
        ( 0,  1,  1, -1) => 11,
        ( 0,  1,  1,  0) => 12,
        ( 0,  1,  1,  1) => 13,
        ( 1, -1, -1, -1) => 14,
        ( 1, -1, -1,  0) => 15,
        ( 1, -1, -1,  1) => 16,
        ( 1, -1,  0, -1) => 17,
        ( 1, -1,  0,  0) => 18,
        ( 1, -1,  0,  1) => 19,
        ( 1, -1,  1, -1) => 20,
        ( 1, -1,  1,  0) => 21,
        ( 1, -1,  1,  1) => 22,
        ( 1,  0, -1, -1) => 23,
        ( 1,  0, -1,  0) => 24,
        ( 1,  0, -1,  1) => 25,
        ( 1,  0,  0, -1) => 26,
        ( 1,  0,  0,  0) => 27,
        ( 1,  0,  0,  1) => 28,
        ( 1,  0,  1, -1) => 29,
        ( 1,  0,  1,  0) => 30,
        ( 1,  0,  1,  1) => 31,
        ( 1,  1, -1, -1) => 32,
        ( 1,  1, -1,  0) => 33,
        ( 1,  1, -1,  1) => 34,
        ( 1,  1,  0, -1) => 35,
        ( 1,  1,  0,  0) => 36,
        ( 1,  1,  0,  1) => 37,
        ( 1,  1,  1, -1) => 38,
        ( 1,  1,  1,  0) => 39,
        ( 1,  1,  1,  1) => 40,
        _ => unreachable!("canonical form is always one of the 41 classes"),
    }
}

/// 41-entry Z₃-compressed LUT for ternary dot-products.
///
/// Entry `k` stores `Σ cᵢ` where `c` is the canonical representative of class `k`.
/// The sign factor (from [`canonical`]) restores the true dot-product sign.
///
/// Table computed as: `LUT_NPU_TABLE[k] = sum(canonical_class_k)`.
///
/// # Anchor
/// φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877
pub const LUT_NPU_TABLE: [i8; 41] = [
     0,  1,  0,  1,  2,
    -1,  0,  1,  0,  1,
     2,  1,  2,  3, -2,
    -1,  0, -1,  0,  1,
     0,  1,  2, -1,  0,
     1,  0,  1,  2,  1,
     2,  3,  0,  1,  2,
     1,  2,  3,  2,  3,
     4,
];

/// Compute the ternary dot-product `a · w` via the 41-entry Z₃ LUT.
///
/// Algorithm:
/// 1. Compute the elementwise ternary product vector `p` with `pᵢ = aᵢ × wᵢ`.
/// 2. Find the canonical class of `p` and the sign factor (±1).
/// 3. Return `sign × LUT_NPU_TABLE[class_id(p)]`.
///
/// This is provably equivalent to [`dotprod_naive`] for all 81 × 81 input pairs.
pub fn dotprod_via_lut_npu(a: Trit4, w: Trit4) -> i8 {
    // Step 1: elementwise ternary product — no `*` operator, uses trit_mul
    let p: Trit4 = [
        trit_mul(a[0], w[0]),
        trit_mul(a[1], w[1]),
        trit_mul(a[2], w[2]),
        trit_mul(a[3], w[3]),
    ];

    // Step 2: Z₃ canonical form + sign factor
    let (_, sign) = canonical(p);
    let class = z3_class_id(p);

    // Step 3: LUT lookup — sign is ±1, multiply via match (no `*`)
    let lut_val = LUT_NPU_TABLE[class];
    match sign {
        1  =>  lut_val,
        -1 => {
            // Negate i8 via two's complement addition: -x = (!x).wrapping_add(1)
            (!lut_val).wrapping_add(1)
        }
        _  => unreachable!("sign is always 1 or -1"),
    }
}

/// Helper: negate a `Trit4`.
pub fn neg_trit4(a: Trit4) -> Trit4 {
    [a[0].neg(), a[1].neg(), a[2].neg(), a[3].neg()]
}

/// All 81 possible `Trit4` vectors, in lexicographic order.
pub fn all_trit4s() -> [[Trit; 4]; 81] {
    use Trit::{Neg, Zero, Pos};
    let vals = [Neg, Zero, Pos];
    let mut out = [[Trit::Zero; 4]; 81];
    let mut idx = 0;
    for &a in vals.iter() {
        for &b in vals.iter() {
            for &c in vals.iter() {
                for &d in vals.iter() {
                    out[idx] = [a, b, c, d];
                    idx = idx.wrapping_add(1);
                }
            }
        }
    }
    out
}
