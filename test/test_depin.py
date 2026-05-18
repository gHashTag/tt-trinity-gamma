# SPDX-License-Identifier: Apache-2.0
# Cocotb stubs for DePIN modules: depin_b4_mesh8 and depin_b7_porep
# Author: Dmitrii Vasilev (sole author, admin@t27.ai)

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, FallingEdge


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

async def reset_dut(dut, cycles=2):
    """Drive rst_n low for *cycles* clock edges, then release."""
    dut.rst_n.value = 0
    for _ in range(cycles):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


# ---------------------------------------------------------------------------
# B4 — 8-port mesh router stub test
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_b4_mesh8_antipodal(dut):
    """Verify antipodal forwarding: port_out_n == port_in_s after one clock."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    # Drive all inputs to 0
    dut.port_in_n.value  = 0
    dut.port_in_e.value  = 0
    dut.port_in_s.value  = 0
    dut.port_in_w.value  = 0
    dut.port_in_ne.value = 0
    dut.port_in_nw.value = 0
    dut.port_in_se.value = 0
    dut.port_in_sw.value = 0

    await reset_dut(dut)

    # Apply test vector
    dut.port_in_s.value  = 0xAB
    dut.port_in_n.value  = 0x12
    dut.port_in_w.value  = 0x34
    dut.port_in_e.value  = 0x56
    dut.port_in_sw.value = 0x78
    dut.port_in_ne.value = 0x9A
    dut.port_in_nw.value = 0xBC
    dut.port_in_se.value = 0xDE

    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)

    assert dut.port_out_n.value  == 0xAB, f"port_out_n expected 0xAB, got {dut.port_out_n.value}"
    assert dut.port_out_s.value  == 0x12, f"port_out_s expected 0x12, got {dut.port_out_s.value}"
    assert dut.port_out_e.value  == 0x34, f"port_out_e expected 0x34, got {dut.port_out_e.value}"
    assert dut.port_out_w.value  == 0x56, f"port_out_w expected 0x56, got {dut.port_out_w.value}"
    assert dut.port_out_ne.value == 0x78, f"port_out_ne expected 0x78, got {dut.port_out_ne.value}"
    assert dut.port_out_sw.value == 0x9A, f"port_out_sw expected 0x9A, got {dut.port_out_sw.value}"
    assert dut.port_out_nw.value == 0xDE, f"port_out_nw expected 0xDE, got {dut.port_out_nw.value}"
    assert dut.port_out_se.value == 0xBC, f"port_out_se expected 0xBC, got {dut.port_out_se.value}"


# ---------------------------------------------------------------------------
# B7 — PoRep VDE round-counter stub test
# ---------------------------------------------------------------------------

@cocotb.test()
async def test_b7_porep_layer_complete(dut):
    """Verify layer_complete asserts after round_counter reaches 10."""
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

    dut.sector_data_hash.value = 0x1234
    dut.randomness.value       = 0xAB

    await reset_dut(dut)

    # Clock through enough cycles to reach round_counter == 10
    for cycle in range(15):
        await RisingEdge(dut.clk)

    await FallingEdge(dut.clk)
    assert dut.layer_complete.value == 1, (
        f"layer_complete expected 1 after 10+ rounds, got {dut.layer_complete.value}"
    )
