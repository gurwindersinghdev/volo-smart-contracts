# Vendored: Pyth "pro compatible" Sui contracts

Source: https://github.com/pyth-network/pyth-crosschain
Rev:    aa291266173173480efef77b9454f2dbc2b4fd62
Paths:  target_chains/sui/contracts            -> local_dependencies/pyth_pro_compatible
        target_chains/sui/vendor/wormhole_simple_majority/wormhole
                                               -> local_dependencies/wormhole_simple_majority

Manifests are the upstream `Move.pro_compatible.sui_mainnet.toml` / `Move.sui_mainnet.toml`
(published-at 0x55300367a2d40813727ccac4ecee977a39fb9cdb46f2e6b2c354b9798f5de2c0 and
0x99de5c967d8206ef4b75c0afab3df2a59eb02b05c282821db803831008ac25b4).

Only change vs upstream: the named addresses were renamed

    pyth     -> pyth_pro_compatible
    wormhole -> wormhole_simple_majority

(in `[addresses]` and in every `module <addr>::` / `use <addr>::` path), because volo_vault
already depends on the solendprotocol Pyth fork, which owns the `pyth` / `wormhole` names.
Move errors with "Address `pyth` is defined more than once" otherwise.

A named-address rename does not change module identity — module identity is
(address value, module name) — so these modules still resolve to the on-chain packages at
0x55300367... / 0x99de5c96... . To refresh, re-copy from upstream and re-apply:

    find . -name '*.move' -print0 | xargs -0 perl -pi -e \
      's/\bpyth::/pyth_pro_compatible::/g; s/\bwormhole::/wormhole_simple_majority::/g;'
