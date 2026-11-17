# P5-P4 V1 — formal SF24 source bridge and preserved results

This branch inherits the prior GitHub reference figures, tables and executed source unchanged from parent commit c8ec4666ed581ed0ca5a6176e642108d20c2b5fb. Those are Python component/reference results, not formal full-network SF24 DUE.

## Historical accepted evidence identities

| Archive | SHA256 | Preserved scope |
|---|---|---|
| P5P1_FINAL_EVIDENCE_WITH_ACCEPTANCE.zip | c321be0c519f554b619e97046c26bf3fe26cfd4a159b4374099fd93171ddd3a9 | 4/4 cases; 11/11 acceptance |
| P5P2_FINAL_EVIDENCE_WITH_ACCEPTANCE.zip | e16d72b81e638347e64781515fcc75dd8e4244351e06ba24392e493d467110ce | 7/7 cases; 107/107 physics; 52/52 saved acceptance |
| P5P3_FINAL_EVIDENCE_WITH_ACCEPTANCE.zip | f0fb7fa91cfdeb73931982450c6f4bb62cfb406d86756dd6fbed8e1a9b61a426 | 3620 veh; 107 paths; 7538 positive cells; 17/17 saved acceptance |

The historical binary archives are not copied into this Git branch. Their hashes are pinned in config/P5P4_FROZEN_ARTIFACT_HASHES.csv. Original local files are retained unchanged and must match those hashes. The original 10 GitHub reference figures and CSVs are inherited unchanged.

## MATLAB commands

1. Run RUN_P5P4_REVIEW_ONLY.m to inspect the already saved reference outputs (no recomputation).
2. Run RUN_P5P4_SOURCE_BRIDGE.m to validate the exact local P5-P3 ZIP, all 12 member hashes, the network/path MAT source hashes, 107x2x241 Fstar, 3620 vehicles, and 7538 positive departure cohorts.
3. The new run is written to 09_RUN_OUTPUTS/P4RH_P5_P4_SOURCE_BRIDGE_V1/RUN_*_P5P4. It is reopened by p5p4_independent_accept.m.

## Scientific boundary

Source identity, saved departure-flow reconstruction, and 107-path/104-link topology are technical PASS. Hard CTM discharge, finite storage/receiving, physical km distance, full 3620-vehicle DNL, pre-event DUE, and rolling residual VI remain NOT_GRANTED. Production Admission remains CLOSED. No historical 135 cases are rerun.

Fstar is a departure-time/path demand tensor, not actual link entry/exit events. The GitHub Python point-queue has infinite storage and cannot certify spillback. Source-declared BPR capacities are not automatically CTM discharge rates. A calibrated physical link certificate is required before running formal fixed-flow DNL.
