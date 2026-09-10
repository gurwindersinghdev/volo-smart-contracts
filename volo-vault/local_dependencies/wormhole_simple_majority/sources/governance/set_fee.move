// SPDX-License-Identifier: Apache 2

/// This module implements handling a governance VAA to enact setting the
/// Wormhole message fee to another amount.
module wormhole_simple_majority::set_fee {
    use wormhole_simple_majority::bytes32::{Self};
    use wormhole_simple_majority::cursor::{Self};
    use wormhole_simple_majority::governance_message::{Self, DecreeTicket, DecreeReceipt};
    use wormhole_simple_majority::state::{Self, State};

    /// Specific governance payload ID (action) for setting Wormhole fee.
    const ACTION_SET_FEE: u8 = 3;

    struct GovernanceWitness has drop {}

    struct SetFee {
        amount: u64
    }

    public fun authorize_governance(
        wormhole_state: &State
    ): DecreeTicket<GovernanceWitness> {
        governance_message::authorize_verify_local(
            GovernanceWitness {},
            state::governance_chain(wormhole_state),
            state::governance_contract(wormhole_state),
            state::governance_module(),
            ACTION_SET_FEE
        )
    }

    /// Redeem governance VAA to configure Wormhole message fee amount in SUI
    /// denomination. This governance message is only relevant for Sui because
    /// fee administration is only relevant to one particular network (in this
    /// case Sui).
    ///
    /// NOTE: This method is guarded by a minimum build version check. This
    /// method could break backward compatibility on an upgrade.
    public fun set_fee(
        wormhole_state: &mut State,
        receipt: DecreeReceipt<GovernanceWitness>
    ): u64 {
        // This capability ensures that the current build version is used.
        let latest_only = state::assert_latest_only(wormhole_state);

        let payload =
            governance_message::take_payload(
                state::borrow_mut_consumed_vaas(&latest_only, wormhole_state),
                receipt
            );

        // Deserialize the payload as amount to change the Wormhole fee.
        let SetFee { amount } = deserialize(payload);

        state::set_message_fee(&latest_only, wormhole_state, amount);

        amount
    }

    fun deserialize(payload: vector<u8>): SetFee {
        let cur = cursor::new(payload);

        // This amount cannot be greater than max u64.
        let amount = bytes32::to_u64_be(bytes32::take_bytes(&mut cur));

        cursor::destroy_empty(cur);

        SetFee { amount: (amount as u64) }
    }

    #[test_only]
    public fun action(): u8 {
        ACTION_SET_FEE
    }
}
