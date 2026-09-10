# Audit reports

Third-party security reviews of the packages in this repository, in chronological order.

| Report | Auditor | Date | Scope | Anchored to |
|---|---|---|---|---|
| [`Volo_V2_Increment_Veridise_2025.pdf`](./Volo_V2_Increment_Veridise_2025.pdf) | Veridise | May 2025 | Liquid staking v2 increment | `liquid_staking/` |
| [`Volo_V2_Increment_Movebit_2025.pdf`](./Volo_V2_Increment_Movebit_2025.pdf) | MoveBit | May 2025 | Liquid staking v2 increment | `liquid_staking/` |
| [`Vault_Full_Audit_Veridise_2025.pdf`](./Vault_Full_Audit_Veridise_2025.pdf) | Veridise | Jul 2025 | Volo Vault, full review | vault commit `48b4fedc9b99cb378fe3237b80f10611fcb3d0fe` |
| [`Vault_Full_Audit_Certora_2025.pdf`](./Vault_Full_Audit_Certora_2025.pdf) | Certora | 2025 | Volo Vault, full review | `volo-vault/` |
| [`Vault_V1.3_Audit_Veridise_2026.pdf`](./Vault_V1.3_Audit_Veridise_2026.pdf) | Veridise | Mar 25–31, 2026 (report V3, Jul 27, 2026) | Volo Vault v1.3: withdraw-and-swap requests, deposit cap; separate review of PR #27 (multi-market NAVI positions) | vault commits `f8b817d` (v1.3), `b151492` (PR #27) |

## Veridise — Volo Vault v1.3 (2026)

13 findings: 2 Critical, 2 High, 3 Medium, 2 Low, 3 Warning, 1 Informational. All acknowledged;
8 fixed, 5 acknowledged without further changes. Three appendix findings were classified by the
developers as intended behaviour. Fix commits are named per finding in the report.

This is the audit baseline for the vault release that preceded the Switchboard → Pyth oracle
migration (deployed as v13 on 2026-09-02). The oracle migration is not in scope of this report.

Earlier liquid staking reviews (Hacken, MoveBit, OtterSec, 2023) are published on the Volo docs site.
