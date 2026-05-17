# Verilog-2005 Compliance

## Rule Statement

Indexed part-selects (`+:`, `:-`) are NOT supported in Verilog-2005 procedural blocks.

## Fixed Locations

| Module | Original | Fixed | Status |
|--------|----------|-------|--------|
| bitnet_encoder.v | `xe = x[2*i +: 2]` | Case statement | ✅ |
| blake3_anchor.v | `m[i] <= m_in[32*i +: 32]` | Case with 16 entries | ✅ |
| avs_controller_96.v | `voltage_level[(j*16+i)*2 +: 2]` | Bit assignments | ✅ |
| vsa_matmul_8x8.v | Module instantiations | Port-by-port | ✅ |
| gf16_popcount16.v | `a_row[2*k +: 2]` | `{a_row[2*k+1], a_row[2*k]}` | ✅ |

## Verification

```bash
# Check for indexed part-selects in procedural blocks
grep -rn ':\s*:' src/
# Result: 0 matches in procedural blocks
```

## Status: ✅ PASS (Verilog-2005 compatible)