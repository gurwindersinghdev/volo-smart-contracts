// SPDX-License-Identifier: Apache 2

/// This module implements handling a governance VAA to enact transferring some
/// amount of collected fees to an intended recipient.
module wormhole_simple_majority::transfer_fee {
    use sui::coin::{Self};
    use sui::transfer::{Self};
    use sui::tx_context::{TxContext};

    use wormhole_simple_majority::bytes32::{Self};
    use wormhole_simple_majority::cursor::{Self};
    use wormhole_simple_majority::external_address::{Self};
    use wormhole_simple_majority::governance_message::{Self, DecreeTicket, DecreeReceipt};
    use wormhole_simple_majority::state::{Self, State, LatestOnly};

    /// Specific governance payload ID (action) for setting Wormhole fee.
    const ACTION_TRANSFER_FEE: u8 = 4;

    struct GovernanceWitness has drop {}

    struct TransferFee {
        amount: u64,
        recipient: address
    }

    public fun authorize_governance(
        wormhole_state: &State
    ): DecreeTicket<GovernanceWitness> {
        governance_message::authorize_verify_local(
            GovernanceWitness {},
            state::governance_chain(wormhole_state),
            state::governance_contract(wormhole_state),
            state::governance_module(),
            ACTION_TRANSFER_FEE
        )
    }

    /// Redeem governance VAA to transfer collected Wormhole fees to the
    /// recipient encoded in its Wormhole governance message. This governance
    /// message is only relevant for Sui because fee administration is only
    /// relevant to one particular network (in this case Sui).
    ///
    /// NOTE: This method is guarded by a minimum build version check. This
    /// method could break backward compatibility on an upgrade.
    public fun transfer_fee(
        wormhole_state: &mut State,
        receipt: DecreeReceipt<GovernanceWitness>,
        ctx: &mut TxContext
    ): u64 {
        // This capability ensures that the current build version is used.
        let latest_only = state::assert_latest_only(wormhole_state);

        let payload =
            governance_message::take_payload(
                state::borrow_mut_consumed_vaas(&latest_only, wormhole_state),
                receipt
            );

        // Proceed with setting the new message fee.
        handle_transfer_fee(&latest_only, wormhole_state, payload, ctx)
    }

    fun handle_transfer_fee(
        latest_only: &LatestOnly,
        wormhole_state: &mut State,
        governance_payload: vector<u8>,
        ctx: &mut TxContext
    ): u64 {
        // Deserialize the payload as amount to withdraw and to whom SUI should
        // be sent.
        let TransferFee { amount, recipient } = deserialize(governance_payload);

        transfer::public_transfer(
            coin::from_balance(
                state::withdraw_fee(latest_only, wormhole_state, amount),
                ctx
            ),
            recipient
        );

        amount
    }

    fun deserialize(payload: vector<u8>): TransferFee {
        let cur = cursor::new(payload);

        // This amount cannot be greater than max u64.
        let amount = bytes32::to_u64_be(bytes32::take_bytes(&mut cur));

        // Recipient must be non-zero address.
        let recipient = external_address::take_nonzero(&mut cur);

        cursor::destroy_empty(cur);

        TransferFee {
            amount: (amount as u64),
            recipient: external_address::to_address(recipient)
        }
    }

    #[test_only]
    public fun action(): u8 {
        ACTION_TRANSFER_FEE
    }
}
