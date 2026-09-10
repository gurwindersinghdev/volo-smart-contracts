// SPDX-License-Identifier: Apache 2

/// This module implements handling a governance VAA to enact updating the
/// current guardian set to be a new set of guardian public keys. As a part of
/// this process, the previous guardian set's expiration time is set. Keep in
/// mind that the current guardian set has no expiration.
module wormhole_simple_majority::update_guardian_set {
    use std::vector::{Self};
    use sui::clock::{Clock};

    use wormhole_simple_majority::bytes::{Self};
    use wormhole_simple_majority::cursor::{Self};
    use wormhole_simple_majority::governance_message::{Self, DecreeTicket, DecreeReceipt};
    use wormhole_simple_majority::guardian::{Self, Guardian};
    use wormhole_simple_majority::guardian_set::{Self};
    use wormhole_simple_majority::state::{Self, State, LatestOnly};

    /// No guardians public keys found in VAA.
    const E_NO_GUARDIANS: u64 = 0;
    /// Guardian set index is not incremented from last known guardian set.
    const E_NON_INCREMENTAL_GUARDIAN_SETS: u64 = 1;

    /// Specific governance payload ID (action) for updating the guardian set.
    const ACTION_UPDATE_GUARDIAN_SET: u8 = 2;

    struct GovernanceWitness has drop {}

    /// Event reflecting a Guardian Set update.
    struct GuardianSetAdded has drop, copy {
        new_index: u32
    }

    struct UpdateGuardianSet {
        new_index: u32,
        guardians: vector<Guardian>,
    }

    public fun authorize_governance(
        wormhole_state: &State
    ): DecreeTicket<GovernanceWitness> {
        governance_message::authorize_verify_global(
            GovernanceWitness {},
            state::governance_chain(wormhole_state),
            state::governance_contract(wormhole_state),
            state::governance_module(),
            ACTION_UPDATE_GUARDIAN_SET
        )
    }

    /// Redeem governance VAA to update the current Guardian set with a new
    /// set of Guardian public keys. This governance action is applied globally
    /// across all networks.
    ///
    /// NOTE: This method is guarded by a minimum build version check. This
    /// method could break backward compatibility on an upgrade.
    public fun update_guardian_set(
        wormhole_state: &mut State,
        receipt: DecreeReceipt<GovernanceWitness>,
        the_clock: &Clock
    ): u32 {
        // This capability ensures that the current build version is used.
        let latest_only = state::assert_latest_only(wormhole_state);

        // Even though this disallows the VAA to be replayed, it may be
        // impossible to redeem the same VAA again because `governance_message`
        // requires new governance VAAs being signed by the most recent guardian
        // set).
        let payload =
            governance_message::take_payload(
                state::borrow_mut_consumed_vaas(&latest_only, wormhole_state),
                receipt
            );

        // Proceed with the update.
        handle_update_guardian_set(&latest_only, wormhole_state, payload, the_clock)
    }

    fun handle_update_guardian_set(
        latest_only: &LatestOnly,
        wormhole_state: &mut State,
        governance_payload: vector<u8>,
        the_clock: &Clock
    ): u32 {
        // Deserialize the payload as the updated guardian set.
        let UpdateGuardianSet {
            new_index,
            guardians
        } = deserialize(governance_payload);

        // Every new guardian set index must be incremental from the last known
        // guardian set.
        assert!(
            new_index == state::guardian_set_index(wormhole_state) + 1,
            E_NON_INCREMENTAL_GUARDIAN_SETS
        );

        // Expire the existing guardian set.
        state::expire_guardian_set(latest_only, wormhole_state, the_clock);

        // And store the new one.
        state::add_new_guardian_set(
            latest_only,
            wormhole_state,
            guardian_set::new(new_index, guardians)
        );

        sui::event::emit(GuardianSetAdded { new_index });

        new_index
    }

    fun deserialize(payload: vector<u8>): UpdateGuardianSet {
        let cur = cursor::new(payload);
        let new_index = bytes::take_u32_be(&mut cur);
        let num_guardians = bytes::take_u8(&mut cur);
        assert!(num_guardians > 0, E_NO_GUARDIANS);

        let guardians = vector::empty<Guardian>();
        let i = 0;
        while (i < num_guardians) {
            let key = bytes::take_bytes(&mut cur, 20);
            vector::push_back(&mut guardians, guardian::new(key));
            i = i + 1;
        };
        cursor::destroy_empty(cur);

        UpdateGuardianSet { new_index, guardians }
    }

    #[test_only]
    public fun action(): u8 {
        ACTION_UPDATE_GUARDIAN_SET
    }
}
