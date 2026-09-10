# `volo_vault`

The Volo Vault Move package. Users deposit a single principal coin type and receive vault shares;
an operator allocates the vault's assets across integrated DeFi protocols, and the vault prices
every position through its oracle to derive one total USD value and one share price.

Deployed package ids, build instructions and bytecode verification are in the
[repository README](../README.md).

## Modules

| Area | Modules |
|---|---|
| Core | `volo_vault` (vault state, share accounting, value updates), `operation` (operator flows), `manage` (configuration), `manager_cap` |
| Oracle | `oracle` — Pyth price feeds, per-asset staleness and deviation checks |
| User flows | `user_entry`, `requests/deposit_request`, `requests/withdraw_request`, `requests/swap_request` |
| Receipts | `receipt`, `receipt_cancellation`, `vault_receipt_info` |
| Positions | `curator_position` (curator-managed off-vault value), `reward_manager` |
| Adaptors | `adaptors/` — NAVI, Suilend, Cetus, Momentum, zo staking, and vault-in-vault receipts |

`local_dependencies/` holds the vendored interface packages the vault compiles against; they are
not part of this package's published bytecode.

## Conventions

- Shares are `u256`. USD values are `u256` scaled by the oracle's price decimals.
- Ratios and fees use basis-point style scaling via `RATE_SCALING`.
- Entry points guard on `check_version()`; upgrades bump the package version, and superseded
  entry points are kept in place for upgrade compatibility rather than removed.
- Value updates are transactional: an operation opens with a value snapshot and must close with a
  complete, fresh set of asset values before shares can be minted or burned.

## Tests and audits

`tests/` contains the published portion of the unit-test suite. The coverage report is in
[`coverage/`](./coverage); third-party audit reports are in [`../audit/`](../audit).
