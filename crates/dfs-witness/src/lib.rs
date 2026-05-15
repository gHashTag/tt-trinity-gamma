//! Wave-40 Lane FF'' — DFS witness
//! OP_DFS_GATE = 0xE7 — R-SI-1 unique sacred opcode
//! anchor phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877

pub const OP_DFS_GATE: u8 = 0xE7;
pub const OP_HOLO_MUX_X4: u8 = 0xE6;
pub const OP_SUBTH_CLK: u8 = 0xE5;
pub const OP_AVS_RECONF: u8 = 0xE4;
pub const OP_LUT_NPU: u8 = 0xE3;
pub const OP_TOM: u8 = 0xE2;
pub const OP_TENET: u8 = 0xE1;

/// Linear V-f LUT: vcode (0..15) → fcode (0..15)
pub fn f_of_v(vcode: u8) -> u8 {
    (vcode & 0x0F).min(15)
}

/// Energy per op proportional to V^2 (abstract units)
pub fn energy_per_op(vcode: u8) -> u32 {
    let v = (vcode & 0x0F) as u32;
    v * v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_op_dfs_gate_is_0xe7() {
        assert_eq!(OP_DFS_GATE, 0xE7);
    }

    #[test]
    fn test_dfs_distinct_from_prior_chain() {
        assert_ne!(OP_DFS_GATE, OP_HOLO_MUX_X4);
        assert_ne!(OP_DFS_GATE, OP_SUBTH_CLK);
        assert_ne!(OP_DFS_GATE, OP_AVS_RECONF);
        assert_ne!(OP_DFS_GATE, OP_LUT_NPU);
        assert_ne!(OP_DFS_GATE, OP_TOM);
        assert_ne!(OP_DFS_GATE, OP_TENET);
    }

    #[test]
    fn test_f_of_v_monotone() {
        for v in 0u8..14 { assert!(f_of_v(v) <= f_of_v(v+1)); }
    }

    #[test]
    fn test_f_of_v_boundary() {
        assert_eq!(f_of_v(0), 0);
        assert_eq!(f_of_v(15), 15);
    }

    #[test]
    fn test_energy_cubic() {
        assert_eq!(energy_per_op(0), 0);
        assert_eq!(energy_per_op(1), 1);
        assert_eq!(energy_per_op(3), 9);
        assert_eq!(energy_per_op(15), 225);
    }

    #[test]
    fn test_energy_monotone_non_negative() {
        for v in 0u8..15 { assert!(energy_per_op(v) <= energy_per_op(v+1)); }
    }
}
