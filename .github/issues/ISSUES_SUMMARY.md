# ISSUES_SUMMARY — γ-side TRI-NET 2026 issue pack

> Index + contract for the issue markdown files under
> `.github/issues/` and the `create_issues.sh` helper that
> materialises them as real GitHub issues.

## R5-honest preamble — what the numbers mean

The filenames in this directory use a `NN_<plan-id>.md` pattern
(`01_CL-01.md`, `02_CL-02.md`, …). **The `NN` prefix and any `#N`
reference inside the files are local plan identifiers**, used to
order the pack on disk. They are **not** GitHub issue numbers and
they **do not** map 1-to-1 onto issue numbers that GitHub will
assign at creation time. The authoritative identifier for each plan
item is the `plan_id:` field in the file's YAML frontmatter (e.g.
`CL-01`, `EN-02`, `SN-03`).

No GitHub issue exists for any item in this pack until
`create_issues.sh` is run by a maintainer with write access.

## File index

| File | plan_id | track | status | one-line summary |
|------|---------|-------|--------|-------------------|
| [`00_EPIC_2026.md`](00_EPIC_2026.md) | EPIC-2026 | epic | draft | TRI-NET 2026 — γ-surface execution |
| [`01_CL-01.md`](01_CL-01.md) | CL-01 | clara | done | 10/10 CLARA gap blocks as RTL |
| [`02_CL-02.md`](02_CL-02.md) | CL-02 | clara | done | K3 surface + refusal demo |
| [`03_CL-03.md`](03_CL-03.md) | CL-03 | clara | done | Proof + receipt + mesh demo |
| [`04_CL-04.md`](04_CL-04.md) | CL-04 | clara | partial | Formal proofs cross-walked to RTL |
| [`05_EN-01.md`](05_EN-01.md) | EN-01 | energy | partial | FBB-ACTIVE — repair testbench |
| [`06_EN-02.md`](06_EN-02.md) | EN-02 | energy | planned | RBB — land `src/rbb_idle_well.v` |
| [`07_EN-03.md`](07_EN-03.md) | EN-03 | energy | planned | CAP-BOOST — land `src/cap_boost_rail.v` |
| [`08_SN-01.md`](08_SN-01.md) | SN-01 | snn-tri | done | LIF cortical columns |
| [`09_SN-02.md`](09_SN-02.md) | SN-02 | snn-tri | done | BitNet b1.58 MLP |
| [`10_SN-03.md`](10_SN-03.md) | SN-03 | snn-tri | planned | GF16 vs bfloat16 NMSE harness |
| [`11_PUB-01.md`](11_PUB-01.md) | PUB-01 | publication | done | Zenodo whitepaper bundle |
| [`12_PUB-02.md`](12_PUB-02.md) | PUB-02 | publication | target | Workshop paper (γ substrate) |
| [`13_PUB-03.md`](13_PUB-03.md) | PUB-03 | publication | gated | Post-silicon measurement paper |
| [`14_OS-01.md`](14_OS-01.md) | OS-01 | open-source | done | Apache-2.0 + SKY130A reproducible |
| [`15_OS-02.md`](15_OS-02.md) | OS-02 | open-source | done | `.t27 → RTL → shuttle` flow |
| [`16_OS-03.md`](16_OS-03.md) | OS-03 | open-source | planned | `CONTRIBUTING.md` + RFC template |

Total: **1 EPIC + 16 sub-items**.

## File format

Each issue file has:

1. YAML frontmatter with at minimum `plan_id`, `title`, `labels`,
   `status`, `epic` (sub-items only).
2. Markdown body with sections: **Status**, **Plan** or **Evidence**,
   **Acceptance criteria**, **R5 honesty**, and an optional
   **See also**.
3. A standing `> Plan ID` callout reminding readers that the ID is
   local, not a GitHub issue number.

## Labels expected in the repo

`create_issues.sh` will pass these labels to `gh issue create`. If a
label does not exist in the repo, `gh` will fail; create them first
(see plan item [`OS-03`](16_OS-03.md)):

- Tracks: `track:clara`, `track:energy`, `track:snn-tri`,
  `track:publication`, `track:open-source`
- Gates: `gate:rtl`, `gate:sim`, `gate:formal`, `gate:bench`
- Status: `status:done`, `status:partial`, `status:planned`,
  `status:target`, `status:gated`
- Chip: `chip:gamma`
- Special: `epic`, `planning`, `track:tri-net-2026`

## How to materialise

```bash
# Inspect what would be created (no network calls, exit 0):
bash .github/issues/create_issues.sh --dry-run

# Actually create the EPIC + 16 sub-items:
bash .github/issues/create_issues.sh

# Only create one specific item:
bash .github/issues/create_issues.sh --only EN-02
```

The script is intentionally **idempotent-by-omission**: it will
refuse to act if there is no `gh` binary, no auth, or no
`--confirm` flag (default is dry-run). See the script header for
the full contract.

## R5 honesty summary

- All `#N` style numbers in this pack are local plan IDs.
- Status fields in frontmatter are derived from artefacts present
  in this repo today; if an artefact is removed, the corresponding
  status must be downgraded.
- No DARPA acceptance, funding amount, programme date, paper
  acceptance, or measured silicon TOPS-per-watt is asserted by any
  issue in this pack.
- RBB and CAP-BOOST are honestly marked `planned` (witness-only on γ
  today).
- PUB-02 is honestly `target` only — no venue named.
- PUB-03 is honestly `gated` — no silicon date asserted.
