// SPDX-License-Identifier: Apache 2

/// This module implements a custom type representing a Guardian governance
/// action. Each governance action has an associated module name, relevant chain
/// and payload encoding instructions/data used to perform an administrative
/// change on a contract.
module wormhole_simple_majority::governance_message {
    use wormhole_simple_majority::bytes::{Self};
    use wormhole_simple_majority::bytes32::{Self, Bytes32};
    use wormhole_simple_majority::consumed_vaas::{Self, ConsumedVAAs};
    use wormhole_simple_majority::cursor::{Self};
    use wormhole_simple_majority::external_address::{ExternalAddress};
    use wormhole_simple_majority::state::{Self, State, chain_id};
    use wormhole_simple_majority::vaa::{Self, VAA};

    /// Guardian set used to sign VAA did not use current Guardian set.
    const E_OLD_GUARDIAN_SET_GOVERNANCE: u64 = 0;
    /// Governance chain does not match.
    const E_INVALID_GOVERNANCE_CHAIN: u64 = 1;
    /// Governance emitter address does not match.
    const E_INVALID_GOVERNANCE_EMITTER: u64 = 2;
    /// Governance module name does not match.
    const E_INVALID_GOVERNANCE_MODULE: u64 = 4;
    /// Governance action does not match.
    const E_INVALID_GOVERNANCE_ACTION: u64 = 5;
    /// Governance target chain not indicative of global action.
    const E_GOVERNANCE_TARGET_CHAIN_NONZERO: u64 = 6;
    /// Governance target chain not indicative of actino specifically for Sui
    /// Wormhole contract.
    const E_GOVERNANCE_TARGET_CHAIN_NOT_SUI: u64 = 7;

    /// The public constructors for `DecreeTicket` (`authorize_verify_global`
    /// and `authorize_verify_local`) require a witness of type `T`. This is to
    /// ensure that `DecreeTicket`s cannot be mixed up between modules
    /// maliciously.
    struct DecreeTicket<phantom T> {
        governance_chain: u16,
        governance_contract: ExternalAddress,
        module_name: Bytes32,
        action: u8,
        global: bool
    }

    struct DecreeReceipt<phantom T> {
        payload: vector<u8>,
        digest: Bytes32,
        sequence: u64
    }

    /// This method prepares `DecreeTicket` for global governance action. This
    /// means the VAA encodes target chain ID == 0.
    public fun authorize_verify_global<T: drop>(
        _witness: T,
        governance_chain: u16,
        governance_contract: ExternalAddress,
        module_name: Bytes32,
        action: u8
    ): DecreeTicket<T> {
        DecreeTicket {
            governance_chain,
            governance_contract,
            module_name,
            action,
            global: true
        }
    }

    /// This method prepares `DecreeTicket` for local governance action. This
    /// means the VAA encodes target chain ID == 21 (Sui's).
    public fun authorize_verify_local<T: drop>(
        _witness: T,
        governance_chain: u16,
        governance_contract: ExternalAddress,
        module_name: Bytes32,
        action: u8
    ): DecreeTicket<T> {
        DecreeTicket {
            governance_chain,
            governance_contract,
            module_name,
            action,
            global: false
        }
    }

    public fun sequence<T>(receipt: &DecreeReceipt<T>): u64 {
        receipt.sequence
    }

    /// This method unpacks `DecreeReceipt` and puts the VAA digest into a
    /// `ConsumedVAAs` container. Then it returns the governance payload.
    public fun take_payload<T>(
        consumed: &mut ConsumedVAAs,
        receipt: DecreeReceipt<T>
    ): vector<u8> {
        let DecreeReceipt { payload, digest, sequence: _ } = receipt;

        consumed_vaas::consume(consumed, digest);

        payload
    }

    /// Method to peek into the payload in `DecreeReceipt`.
    public fun payload<T>(receipt: &DecreeReceipt<T>): vector<u8> {
        receipt.payload
    }

    /// Destroy the receipt.
    public fun destroy<T>(receipt: DecreeReceipt<T>) {
        let DecreeReceipt { payload: _, digest: _, sequence: _ } = receipt;
    }

    /// This method unpacks a `DecreeTicket` to validate its members to make
    /// sure that the parameters match what was encoded in the VAA.
    public fun verify_vaa<T>(
        wormhole_state: &State,
        verified_vaa: VAA,
        ticket: DecreeTicket<T>
    ): DecreeReceipt<T> {
        state::assert_latest_only(wormhole_state);

        let DecreeTicket {
            governance_chain,
            governance_contract,
            module_name,
            action,
            global
        } = ticket;

        // Protect against governance actions enacted using an old guardian set.
        // This is not a protection found in the other Wormhole contracts.
        assert!(
            vaa::guardian_set_index(&verified_vaa) == state::guardian_set_index(wormhole_state),
            E_OLD_GUARDIAN_SET_GOVERNANCE
        );

        // Both the emitter chain and address must equal.
        assert!(
            vaa::emitter_chain(&verified_vaa) == governance_chain,
            E_INVALID_GOVERNANCE_CHAIN
        );
        assert!(
            vaa::emitter_address(&verified_vaa) == governance_contract,
            E_INVALID_GOVERNANCE_EMITTER
        );

        // Cache VAA digest.
        let digest = vaa::digest(&verified_vaa);

        // Get the VAA sequence number.
        let sequence = vaa::sequence(&verified_vaa);

        // Finally deserialize Wormhole payload as governance message.
        let (
            parsed_module_name,
            parsed_action,
            chain,
            payload
        ) = deserialize(vaa::take_payload(verified_vaa));

        assert!(module_name == parsed_module_name, E_INVALID_GOVERNANCE_MODULE);
        assert!(action == parsed_action, E_INVALID_GOVERNANCE_ACTION);

        // Target chain, which determines whether the governance VAA applies to
        // all chains or Sui.
        if (global) {
            assert!(chain == 0, E_GOVERNANCE_TARGET_CHAIN_NONZERO);
        } else {
            assert!(chain == chain_id(), E_GOVERNANCE_TARGET_CHAIN_NOT_SUI);
        };

        DecreeReceipt { payload, digest, sequence }
    }

    fun deserialize(buf: vector<u8>): (Bytes32, u8, u16, vector<u8>) {
        let cur = cursor::new(buf);

        (
            bytes32::take_bytes(&mut cur),
            bytes::take_u8(&mut cur),
            bytes::take_u16_be(&mut cur),
            cursor::take_rest(cur)
        )
    }

    #[test_only]
    public fun deserialize_test_only(
        buf: vector<u8>
    ): (
        Bytes32,
        u8,
        u16,
        vector<u8>
    ) {
        deserialize(buf)
    }

    #[test_only]
    public fun take_decree(buf: vector<u8>): vector<u8> {
        let (_, _, _, payload) = deserialize(buf);
        payload
    }
}
