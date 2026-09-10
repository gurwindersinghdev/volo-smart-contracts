// SPDX-License-Identifier: Apache 2

/// This module implements the mechanism to publish the Wormhole contract and
/// initialize `State` as a shared object.
module wormhole_simple_majority::setup {
    use std::vector::{Self};
    use sui::object::{Self, UID};
    use sui::package::{Self, UpgradeCap};
    use sui::transfer::{Self};
    use sui::tx_context::{Self, TxContext};

    use wormhole_simple_majority::cursor::{Self};
    use wormhole_simple_majority::state::{Self};

    /// Capability created at `init`, which will be destroyed once
    /// `init_and_share_state` is called. This ensures only the deployer can
    /// create the shared `State`.
    struct DeployerCap has key, store {
        id: UID
    }

    /// Called automatically when module is first published. Transfers
    /// `DeployerCap` to sender.
    ///
    /// Only `setup::init_and_share_state` requires `DeployerCap`.
    fun init(ctx: &mut TxContext) {
        let deployer = DeployerCap { id: object::new(ctx) };
        transfer::transfer(deployer, tx_context::sender(ctx));
    }

    #[test_only]
    public fun init_test_only(ctx: &mut TxContext) {
        init(ctx);

        // This will be created and sent to the transaction sender
        // automatically when the contract is published.
        transfer::public_transfer(
            sui::package::test_publish(object::id_from_address(@wormhole_simple_majority), ctx),
            tx_context::sender(ctx)
        );
    }

    #[allow(lint(share_owned))]
    /// Only the owner of the `DeployerCap` can call this method. This
    /// method destroys the capability and shares the `State` object.
    public fun complete(
        deployer: DeployerCap,
        upgrade_cap: UpgradeCap,
        governance_chain: u16,
        governance_contract: vector<u8>,
        guardian_set_index: u32,
        initial_guardians: vector<vector<u8>>,
        guardian_set_seconds_to_live: u32,
        message_fee: u64,
        ctx: &mut TxContext
    ) {
        wormhole_simple_majority::package_utils::assert_package_upgrade_cap<DeployerCap>(
            &upgrade_cap,
            package::compatible_policy(),
            1
        );

        // Destroy deployer cap.
        let DeployerCap { id } = deployer;
        object::delete(id);

        let guardians = {
            let out = vector::empty();
            let cur = cursor::new(initial_guardians);
            while (!cursor::is_empty(&cur)) {
                vector::push_back(
                    &mut out,
                    wormhole_simple_majority::guardian::new(cursor::poke(&mut cur))
                );
            };
            cursor::destroy_empty(cur);
            out
        };

        // Share new state.
        transfer::public_share_object(
            state::new(
                upgrade_cap,
                governance_chain,
                wormhole_simple_majority::external_address::new_nonzero(
                    wormhole_simple_majority::bytes32::from_bytes(governance_contract)
                ),
                guardian_set_index,
                guardians,
                guardian_set_seconds_to_live,
                message_fee,
                ctx
            )
        );
    }
}
