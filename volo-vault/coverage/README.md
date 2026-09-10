# Test coverage — `volo_vault`

Generated 2026-09-09 with `sui move test --coverage` / `sui move coverage summary` (sui 1.79.0) on the
full internal unit-test suite, against source equivalent to this directory (deployed head v13,
`0xdb8fca27462e39cb3cdb66c64baa498bfa037b3d8dce4046726eb4573371f02e`; the internal copy adds
`#[test_only]` hooks that are stripped from published bytecode — the built modules are byte-identical).

Test run: **553 tests, 553 passed, 0 failed.**

## Instruction coverage per module

| Module | Coverage |
|---|---|
| `zo_adaptor` | 100.00% |
| `withdraw_request` | 100.00% |
| `vault_utils` | 100.00% |
| `vault_receipt_info` | 100.00% |
| `user_entry` | 100.00% |
| `swap_request` | 100.00% |
| `suilend_adaptor` | 100.00% |
| `reward_manager` | 100.00% |
| `receipt_cancellation` | 100.00% |
| `receipt_adaptor` | 100.00% |
| `receipt` | 100.00% |
| `navi_adaptor` | 100.00% |
| `manager_cap` | 100.00% |
| `deposit_request` | 100.00% |
| `curator_position` | 100.00% |
| `vault_oracle` | 99.49% |
| `vault` | 99.12% |
| `vault_manage` | 98.84% |
| `operation` | 97.46% |
| `cetus_adaptor` | 25.50% |
| `momentum_adaptor` | 20.54% |
| **Total** | **96.82%** |

**Not reproducible from this repository.** This repository publishes a subset of the test suite; the
figures above come from the complete internal suite, so running `sui move test --coverage` here reports
lower numbers. The report is published for transparency about what the internal suite covers, per module
and per function.

**About the uncovered 3.2%.** What remains uncovered is not untested by choice; it is unreachable from a
Move unit test. `cetus_adaptor` and `momentum_adaptor` are bounded by their interface packages, whose
pool/position getters abort in unit tests, so only their price math is reachable there. The rest are
deprecated `abort` stubs whose parameters cannot be constructed in a test, and defensive `assert!`s that
cannot fail by construction. The adaptors are exercised by integration and mainnet-fork testing instead.

Per-function instruction counts (covered / uncovered) are in
[`coverage-functions.csv`](./coverage-functions.csv). The raw coverage map produced by that run is
committed as [`../.coverage_map.mvcov`](../.coverage_map.mvcov); `sui move coverage summary` /
`coverage source --module <name>` can be pointed at it to inspect the run itself.

Method: `sui move test --coverage` on a scratch copy with the named address pinned to `0x0` (the coverage
tooling cannot read a map produced while the package resolves its own address from `published-at`), then
`sui move coverage summary` and `--summarize-functions --csv`.
