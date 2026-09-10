// SPDX-License-Identifier: Apache 2

/// This module implements a mechanism to parse and verify VAAs, which are
/// verified Wormhole messages (messages with Guardian signatures attesting to
/// its observation). Signatures on VAA are checked against an existing Guardian
/// set that exists in the `State` (see `wormhole_simple_majority::state`).
///
/// A Wormhole integrator is discouraged from integrating `parse_and_verify` in
/// his contract. If there is a breaking change to the `vaa` module, Wormhole
/// will be upgraded to prevent previous build versions of this module to work.
/// If an integrator happened to use `parse_and_verify` in his contract, he will
/// need to be prepared to upgrade his contract to take the change (by building
/// with the latest package implementation).
///
/// Instead, an integrator is encouraged to execute a transaction block, which
/// executes `parse_and_verify` from the latest Wormhole package ID and to
/// implement his methods that require redeeming a VAA to take `VAA` as an
/// argument.
///
/// A good example of how this methodology is implemented is how the Token
/// Bridge contract redeems its VAAs.
module wormhole_simple_majority::vaa {
    use std::option::{Self};
    use std::vector::{Self};
    use sui::clock::{Clock};
    use sui::hash::{keccak256};

    use wormhole_simple_majority::bytes::{Self};
    use wormhole_simple_majority::bytes32::{Self, Bytes32};
    use wormhole_simple_majority::consumed_vaas::{Self, ConsumedVAAs};
    use wormhole_simple_majority::cursor::{Self};
    use wormhole_simple_majority::external_address::{Self, ExternalAddress};
    use wormhole_simple_majority::guardian::{Self};
    use wormhole_simple_majority::guardian_set::{Self, GuardianSet};
    use wormhole_simple_majority::guardian_signature::{Self, GuardianSignature};
    use wormhole_simple_majority::state::{Self, State};

    /// Incorrect VAA version.
    const E_WRONG_VERSION: u64 = 0;
    /// Not enough guardians attested to this Wormhole observation.
    const E_NO_QUORUM: u64 = 1;
    /// Signature does not match expected Guardian public key.
    const E_INVALID_SIGNATURE: u64 = 2;
    /// Prior guardian set is no longer valid.
    const E_GUARDIAN_SET_EXPIRED: u64 = 3;
    /// Guardian signature is encoded out of sequence.
    const E_NON_INCREASING_SIGNERS: u64 = 4;

    const VERSION_VAA: u8 = 1;

    /// Container storing verified Wormhole message info. This struct also
    /// caches the digest, which is a double Keccak256 hash of the message body.
    struct VAA {
        /// Guardian set index of Guardians that attested to observing the
        /// Wormhole message.
        guardian_set_index: u32,
        /// Time when Wormhole message was emitted or observed.
        timestamp: u32,
        /// A.K.A. Batch ID.
        nonce: u32,
        /// Wormhole chain ID from which network the message originated from.
        emitter_chain: u16,
        /// Address of contract (standardized to 32 bytes) that produced the
        /// message.
        emitter_address: ExternalAddress,
        /// Sequence number of emitter's Wormhole message.
        sequence: u64,
        /// A.K.A. Finality.
        consistency_level: u8,
        /// Arbitrary payload encoding data relevant to receiver.
        payload: vector<u8>,

        /// Double Keccak256 hash of message body.
        digest: Bytes32
    }

    public fun guardian_set_index(self: &VAA): u32 {
        self.guardian_set_index
    }

    public fun timestamp(self: &VAA): u32 {
         self.timestamp
    }

    public fun nonce(self: &VAA): u32 {
        self.nonce
    }

    public fun batch_id(self: &VAA): u32 {
        nonce(self)
    }

    public fun payload(self: &VAA): vector<u8> {
         self.payload
    }

    public fun digest(self: &VAA): Bytes32 {
         self.digest
    }

    public fun emitter_chain(self: &VAA): u16 {
         self.emitter_chain
    }

    public fun emitter_address(self: &VAA): ExternalAddress {
         self.emitter_address
    }

    public fun emitter_info(self: &VAA): (u16, ExternalAddress, u64) {
        (self.emitter_chain, self.emitter_address, self.sequence)
    }

    public fun sequence(self: &VAA): u64 {
         self.sequence
    }

    public fun consistency_level(self: &VAA): u8 {
        self.consistency_level
    }

    public fun finality(self: &VAA): u8 {
        consistency_level(self)
    }

    /// Destroy the `VAA` and take the Wormhole message payload.
    public fun take_payload(vaa: VAA): vector<u8> {
        let (_, _, payload) = take_emitter_info_and_payload(vaa);

        payload
    }

    /// Destroy the `VAA` and take emitter info (chain and address) and Wormhole
    /// message payload.
    public fun take_emitter_info_and_payload(
        vaa: VAA
    ): (u16, ExternalAddress, vector<u8>) {
        let VAA {
            guardian_set_index: _,
            timestamp: _,
            nonce: _,
            emitter_chain,
            emitter_address,
            sequence: _,
            consistency_level: _,
            digest: _,
            payload,
        } = vaa;
        (emitter_chain, emitter_address, payload)
    }

    /// Parses and verifies the signatures of a VAA.
    ///
    /// NOTE: This is the only public function that returns a VAA, and it should
    /// be kept that way. This ensures that if an external module receives a
    /// `VAA`, it has been verified.
    public fun parse_and_verify(
        wormhole_state: &State,
        buf: vector<u8>,
        the_clock: &Clock
    ): VAA {
        state::assert_latest_only(wormhole_state);

        // Deserialize VAA buffer (and return `VAA` after verifying signatures).
        let (signatures, vaa) = parse(buf);

        // Fetch the guardian set which this VAA was supposedly signed with and
        // verify signatures using guardian set.
        verify_signatures(
            state::guardian_set_at(
                wormhole_state,
                vaa.guardian_set_index
            ),
            signatures,
            bytes32::to_bytes(compute_message_hash(&vaa)),
            the_clock
        );

        // Done.
        vaa
    }

    public fun consume(consumed: &mut ConsumedVAAs, parsed: &VAA) {
        consumed_vaas::consume(consumed, digest(parsed))
    }

    public fun compute_message_hash(parsed: &VAA): Bytes32 {
        let buf = vector::empty();

        bytes::push_u32_be(&mut buf, parsed.timestamp);
        bytes::push_u32_be(&mut buf, parsed.nonce);
        bytes::push_u16_be(&mut buf, parsed.emitter_chain);
        vector::append(
            &mut buf,
            external_address::to_bytes(parsed.emitter_address)
        );
        bytes::push_u64_be(&mut buf, parsed.sequence);
        bytes::push_u8(&mut buf, parsed.consistency_level);
        vector::append(&mut buf, parsed.payload);

        // Return hash.
        bytes32::new(keccak256(&buf))
    }

    /// Parses a VAA.
    ///
    /// NOTE: This method does NOT perform any verification. This ensures the
    /// invariant that if an external module receives a `VAA` object, its
    /// signatures must have been verified, because the only public function
    /// that returns a `VAA` is `parse_and_verify`.
    fun parse(buf: vector<u8>): (vector<GuardianSignature>, VAA) {
        let cur = cursor::new(buf);

        // Check VAA version.
        assert!(
            bytes::take_u8(&mut cur) == VERSION_VAA,
            E_WRONG_VERSION
        );

        let guardian_set_index = bytes::take_u32_be(&mut cur);

        // Deserialize guardian signatures.
        let num_signatures = bytes::take_u8(&mut cur);
        let signatures = vector::empty();
        let i = 0;
        while (i < num_signatures) {
            let guardian_index = bytes::take_u8(&mut cur);
            let r = bytes32::take_bytes(&mut cur);
            let s = bytes32::take_bytes(&mut cur);
            let recovery_id = bytes::take_u8(&mut cur);
            vector::push_back(
                &mut signatures,
                guardian_signature::new(r, s, recovery_id, guardian_index)
            );
            i = i + 1;
        };

        // Deserialize message body.
        let body_buf = cursor::take_rest(cur);

        let cur = cursor::new(body_buf);
        let timestamp = bytes::take_u32_be(&mut cur);
        let nonce = bytes::take_u32_be(&mut cur);
        let emitter_chain = bytes::take_u16_be(&mut cur);
        let emitter_address = external_address::take_bytes(&mut cur);
        let sequence = bytes::take_u64_be(&mut cur);
        let consistency_level = bytes::take_u8(&mut cur);
        let payload = cursor::take_rest(cur);

        let parsed = VAA {
            guardian_set_index,
            timestamp,
            nonce,
            emitter_chain,
            emitter_address,
            sequence,
            consistency_level,
            digest: double_keccak256(body_buf),
            payload,
        };

        (signatures, parsed)
    }

    fun double_keccak256(buf: vector<u8>): Bytes32 {
        use sui::hash::{keccak256};

        bytes32::new(keccak256(&keccak256(&buf)))
    }

    /// Using the Guardian signatures deserialized from VAA, verify that all of
    /// the Guardian public keys are recovered using these signatures and the
    /// VAA message body as the message used to produce these signatures.
    ///
    /// We are careful to only allow `wormhole:vaa` to control the hash that
    /// gets used in the `ecdsa_k1` module by computing the hash after
    /// deserializing the VAA message body. Even though `ecdsa_k1` hashes a
    /// raw message (as of version 0.28), the "raw message" in this case is a
    /// single keccak256 hash of the VAA message body.
    fun verify_signatures(
        set: &GuardianSet,
        signatures: vector<GuardianSignature>,
        message_hash: vector<u8>,
        the_clock: &Clock
    ) {
        // Guardian set must be active (not expired).
        assert!(
            guardian_set::is_active(set, the_clock),
            E_GUARDIAN_SET_EXPIRED
        );

        // Number of signatures must be at least quorum.
        assert!(
            vector::length(&signatures) >= guardian_set::quorum(set),
            E_NO_QUORUM
        );

        // Drain `Cursor` by checking each signature.
        let cur = cursor::new(signatures);
        let last_guardian_index = option::none();
        while (!cursor::is_empty(&cur)) {
            let signature = cursor::poke(&mut cur);
            let guardian_index = guardian_signature::index_as_u64(&signature);

            // Ensure that the provided signatures are strictly increasing.
            // This check makes sure that no duplicate signers occur. The
            // increasing order is guaranteed by the guardians, or can always be
            // reordered by the client.
            assert!(
                (
                    option::is_none(&last_guardian_index) ||
                    guardian_index > *option::borrow(&last_guardian_index)
                ),
                E_NON_INCREASING_SIGNERS
            );

            // If the guardian pubkey cannot be recovered using the signature
            // and message hash, revert.
            assert!(
                guardian::verify(
                    guardian_set::guardian_at(set, guardian_index),
                    signature,
                    message_hash
                ),
                E_INVALID_SIGNATURE
            );

            // Continue.
            option::swap_or_fill(&mut last_guardian_index, guardian_index);
        };

        // Done.
        cursor::destroy_empty(cur);
    }

    #[test_only]
    public fun parse_test_only(
        buf: vector<u8>
    ): (vector<GuardianSignature>, VAA) {
        parse(buf)
    }

    #[test_only]
    public fun destroy(vaa: VAA) {
        take_payload(vaa);
    }

    #[test_only]
    public fun peel_payload_from_vaa(buf: &vector<u8>): vector<u8> {
        // Just make sure that we are passing version 1 VAAs to this method.
        assert!(*vector::borrow(buf, 0) == VERSION_VAA, E_WRONG_VERSION);

        // Find the location of the payload.
        let num_signatures = (*vector::borrow(buf, 5) as u64);
        let i = 57 + num_signatures * 66;

        // Push the payload bytes to `out` and return.
        let out = vector::empty();
        let len = vector::length(buf);
        while (i < len) {
            vector::push_back(&mut out, *vector::borrow(buf, i));
            i = i + 1;
        };

        // Return the payload.
        out
    }
}
