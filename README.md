# Volo smart contracts

Source of the Volo Move packages deployed on Sui mainnet. Each deployed version is pinned here
(`Published.toml`, `published-at` in the manifests, and the MVR `git_info` record) so that deployed
bytecode can be resolved back to a commit of this repository.

| Package | Directory | Original package id | Deployed head | Version |
|---|---|---|---|---|
| Volo Vault (`volo_vault`) | [`volo-vault/`](./volo-vault) | `0xcd86f77503a755c48fe6c87e1b8e9a137ec0c1bf37aac8878b6083262b27fefa` | `0xdb8fca27462e39cb3cdb66c64baa498bfa037b3d8dce4046726eb4573371f02e` | v13 (2026-09-02, Pyth oracle) |
| Volo Liquid Staking (`liquid_staking`, vSUI) | [`liquid_staking/`](./liquid_staking) | `0x549e8b69270defbfafd4f94e17ec44cdbdd99820b33bda2278dea3b9a32d3f55` | `0x68d22cf8bdbcd11ecba1e094922873e4080d4d11133e2443fddda0bfd11dae20` | v2 |

vSUI coin type: `0x549e8b69270defbfafd4f94e17ec44cdbdd99820b33bda2278dea3b9a32d3f55::cert::CERT`.

MVR: `@volosui/volo-vault` resolves to the deployed Volo Vault head; its `git_info` for the deployed
version points at this repository, path `volo-vault`, pinned to a commit.

## Layout

- `volo-vault/` — the vault package: `sources/` (vault, operation, oracle, receipts, adaptors,
  requests), `tests/`, `local_dependencies/` (vendored NAVI lending core, Suilend, Momentum,
  Switchboard, Pyth Pro, Wormhole, zo-staking interfaces the package compiles against),
  `Move.toml` (development, `volo_vault = 0x0`), `Move.mainnet.toml` (mainnet address bindings),
  `Published.toml` (deployed version record), `coverage/` (test coverage report).
- `liquid_staking/` — the vSUI liquid staking package (v2 `stake_pool` / `validator_pool`, with the
  v1 modules retained as deprecated stubs for upgrade compatibility).
- `audit/` — third-party audit reports, see [`audit/README.md`](./audit/README.md).

## Build

Requires the `sui` CLI (built and tested with 1.79).

```bash
cd volo-vault && sui move build && sui move test
cd liquid_staking && sui move build && sui move test
```

The vault package pulls Pyth and Cetus from git and everything else from `local_dependencies/`,
so a clean checkout builds without additional setup.

## Test coverage

The `volo_vault` unit-test suite (553 tests) measures **96.82% instruction coverage** overall on the
v13 source — 97–100% on every vault, oracle, receipt, request and adaptor module except the Cetus and
Momentum CLMM wrappers, whose interface packages are stubs in unit tests and which are covered by
integration and mainnet-fork testing outside this repository.
The per-module and per-function report is in [`volo-vault/coverage/`](./volo-vault/coverage).

**Disclaimer.** This repository publishes only part of the test suite. The coverage figures above were
produced from the complete internal suite, so running `sui move test --coverage` on this checkout will
not reproduce them. The published tests are provided as documentation of behaviour, not as the
measurement basis.

## Verifying deployed bytecode

To compare this source against the deployed package, build with the mainnet address bindings:

```bash
cd volo-vault && cp Move.mainnet.toml Move.toml && sui move build
```

`Published.toml` records the deployed version and package ids for each package.

## License

MIT, see [`LICENSE`](./LICENSE). Vendored dependencies under
`volo-vault/local_dependencies/` and the reports under `audit/` keep their own licenses.
