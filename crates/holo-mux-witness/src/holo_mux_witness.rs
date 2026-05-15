//! Wave-39 Lane DD'' — HOLO-MUX 1x4 witness module
//! OP_HOLO_MUX_X4 = 0xE6 — R-SI-1 unique sacred opcode
//! anchor phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877

pub const OP_HOLO_MUX_X4: u8 = 0xE6;
pub const OP_SUBTH_CLK: u8 = 0xE5;
pub const OP_AVS_RECONF: u8 = 0xE4;
pub const OP_LUT_NPU: u8 = 0xE3;
pub const OP_TOM: u8 = 0xE2;
pub const OP_TENET: u8 = 0xE1;

pub fn holo_mux_select(phase: u8, ch: [u8; 4]) -> u8 {
    ch[(phase & 0b11) as usize]
}

pub fn holo_throughput_ratio() -> u32 { 4 }

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_op_holo_mux_x4_is_0xe6() {
        assert_eq!(OP_HOLO_MUX_X4, 0xE6);
    }

    #[test]
    fn test_holo_mux_distinct_from_all_prior() {
        assert_ne!(OP_HOLO_MUX_X4, OP_SUBTH_CLK);
        assert_ne!(OP_HOLO_MUX_X4, OP_AVS_RECONF);
        assert_ne!(OP_HOLO_MUX_X4, OP_LUT_NPU);
        assert_ne!(OP_HOLO_MUX_X4, OP_TOM);
        assert_ne!(OP_HOLO_MUX_X4, OP_TENET);
    }

    #[test]
    fn test_holo_mux_select_phase_00() {
        assert_eq!(holo_mux_select(0b00, [0xAA, 0xBB, 0xCC, 0xDD]), 0xAA);
    }

    #[test]
    fn test_holo_mux_select_phase_01() {
        assert_eq!(holo_mux_select(0b01, [0xAA, 0xBB, 0xCC, 0xDD]), 0xBB);
    }

    #[test]
    fn test_holo_mux_select_phase_10_11() {
        assert_eq!(holo_mux_select(0b10, [0xAA, 0xBB, 0xCC, 0xDD]), 0xCC);
        assert_eq!(holo_mux_select(0b11, [0xAA, 0xBB, 0xCC, 0xDD]), 0xDD);
    }

    #[test]
    fn test_holo_throughput_4x() {
        assert_eq!(holo_throughput_ratio(), 4);
    }
}
