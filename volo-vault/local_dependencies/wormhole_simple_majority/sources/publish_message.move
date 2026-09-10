// SPDX-License-Identifier: Apache 2

/// This module implements two methods: `prepare_message` and `publish_message`,
/// which are to be executed in a transaction block in this order.
///
/// `prepare_message` allows a contract to pack Wormhole message info (payload
/// that has meaning to an integrator plus nonce) in preparation to publish a
/// `WormholeMessage` event via `publish_message`. Only the owner of an
/// `EmitterCap` has the capability of creating this `MessageTicket`.
///
/// `publish_message` unpacks the `MessageTicket` and emits a
/// `WormholeMessage` with this message info and timestamp. This event is
/// observed by the Guardian network.
///
/// The purpose of splitting this message publishing into two steps is in case
/// Wormhole needs to be upgraded and there is a breaking change for this
/// module, an integrator would not be left broken. It is discouraged to put
/// `publish_message` in an integrator's package logic. Otherwise, this
/// integrator needs to be prepared to upgrade his contract to handle the latest
/// version of `publish_message`.
///
/// Instead, an integtrator is encouraged to execute a transaction block, which
/// executes `publish_message` using the latest Wormhole package ID and to
/// implement `prepare_message` in his contract to produce `MessageTicket`,
/// which `publish_message` consumes.
module wormhole_simple_majority::publish_message {
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use sui::object::{Self, ID};
    use sui::sui::{SUI};

    use wormhole_simple_majority::emitter::{Self, EmitterCap};
    use wormhole_simple_majority::state::{Self, State};

    /// This type is emitted via `sui::event` module. Guardians pick up this
    /// observation and attest to its existence.
    struct WormholeMessage has drop, copy {
        /// `EmitterCap` object ID.
        sender: ID,
        /// From `EmitterCap`.
        sequence: u64,
        /// A.K.A. Batch ID.
        nonce: u32,
        /// Arbitrary message data relevant to integrator.
        payload: vector<u8>,
        /// This will always be `0`.
        consistency_level: u8,
        /// `Clock` timestamp.
        timestamp: u64
    }

    /// This type represents Wormhole message data. The sender is the object ID
    /// of an `EmitterCap`, who acts as the capability of creating this type.
    /// The only way to destroy this type is calling `publish_message` with
    /// a fee to emit a `WormholeMessage` with the unpacked members of this
    /// struct.
    struct MessageTicket {
        /// `EmitterCap` object ID.
        sender: ID,
        /// From `EmitterCap`.
        sequence: u64,
        /// A.K.A. Batch ID.
        nonce: u32,
        /// Arbitrary message data relevant to integrator.
        payload: vector<u8>
    }

    /// `prepare_message` constructs Wormhole message parameters. An
    /// `EmitterCap` provides the capability to send an arbitrary payload.
    ///
    /// NOTE: Integrators of Wormhole should be calling only this method from
    /// their contracts. This method is not guarded by version control (thus not
    /// requiring a reference to the Wormhole `State` object), so it is intended
    /// to work for any package version.
    public fun prepare_message(
        emitter_cap: &mut EmitterCap,
        nonce: u32,
        payload: vector<u8>
    ): MessageTicket {
        // Produce sequence number for this message. This will also be the
        // return value for this method.
        let sequence = emitter::use_sequence(emitter_cap);

        MessageTicket {
            sender: object::id(emitter_cap),
            sequence,
            nonce,
            payload
        }
    }

    /// `publish_message` emits a message as a Sui event. This method uses the
    /// input `EmitterCap` as the registered sender of the
    /// `WormholeMessage`. It also produces a new sequence for this emitter.
    ///
    /// NOTE: This method is guarded by a minimum build version check. This
    /// method could break backward compatibility on an upgrade.
    ///
    /// It is important for integrators to refrain from calling this method
    /// within their contracts. This method is meant to be called in a
    /// transaction block after receiving a `MessageTicket` from calling
    /// `prepare_message` within a contract. If in a circumstance where this
    /// module has a breaking change in an upgrade, `prepare_message` will not
    /// be affected by this change.
    ///
    /// See `prepare_message` for more details.
    public fun publish_message(
        wormhole_state: &mut State,
        message_fee: Coin<SUI>,
        prepared_msg: MessageTicket,
        the_clock: &Clock
    ): u64 {
        // This capability ensures that the current build version is used.
        let latest_only = state::assert_latest_only(wormhole_state);

        // Deposit `message_fee`. This method interacts with the `FeeCollector`,
        // which will abort if `message_fee` does not equal the collector's
        // expected fee amount.
        state::deposit_fee(
            &latest_only,
            wormhole_state,
            coin::into_balance(message_fee)
        );

        let MessageTicket {
            sender,
            sequence,
            nonce,
            payload
        } = prepared_msg;

        // Truncate to seconds.
        let timestamp = clock::timestamp_ms(the_clock) / 1000;

        // Sui is an instant finality chain, so we don't need confirmations.
        let consistency_level = 0;

        // Emit Sui event with `WormholeMessage`.
        sui::event::emit(
            WormholeMessage {
                sender,
                sequence,
                nonce,
                payload,
                consistency_level,
                timestamp
            }
        );

        // Done.
        sequence
    }

    #[test_only]
    public fun destroy(prepared_msg: MessageTicket) {
        let MessageTicket {
            sender: _,
            sequence: _,
            nonce: _,
            payload: _
        } = prepared_msg;
    }
}
