`default_nettype none
// tt_um_qbrain_maxtrue_alias.v - Quantum Brain MAX-TRUE alias wrapper
// Apache-2.0
//
// L-DPC23 Lane T — Quantum Brain SKU alias for the TRI-1 MAX-TRUE
// flagship. This file is a STANDALONE WRAPPER and is NOT instantiated
// from the TTSKY26b top-level `tt_um_trinity_max_true`. It exists to:
//
//   1. Reserve the public Quantum Brain trinity SKU name
//      `tt_um_qbrain_maxtrue` for the TTSKY26c re-submission (Q3 2026)
//   2. Provide compile-time evidence that the alias is a *pure*
//      structural rename — zero new RTL, zero new operators, zero
//      change to silicon footprint.
//   3. Make the PHYS→SI / BIO→SI / LANG→SI mapping addressable from
//      RTL search tools.
//
// Constitutional compliance:
//   R-SI-1: zero NEW `*` operators (no arithmetic added)
//   R5-HONEST: file is not in any synthesis target; verified by absence
//              from info.yaml `source_files` and tools/openlane2/config.json
//   R7: TG-MAX-TRUE-X anchor preserved (no change to dot4 canonical 0x47C0)
//   R8: signed by admin@t27.ai
//   R18: silicon path (frozen-hash modules) untouched
//
// Anchor: phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877
// Quantum Brain 1:1 Silicon Mapping — PHYS→SI · BIO→SI · LANG→SI · NEVER STOP

module tt_um_qbrain_maxtrue (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // Pure structural alias: forwards every port 1:1 to the canonical
    // MAX-TRUE flagship top. No combinational logic, no registers,
    // no new operators — this is a rename, not a redesign.
    tt_um_trinity_max_true u_maxtrue (
        .ui_in (ui_in ),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena   (ena   ),
        .clk   (clk   ),
        .rst_n (rst_n )
    );

endmodule

`default_nettype wire
