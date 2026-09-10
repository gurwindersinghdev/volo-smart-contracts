// SPDX-License-Identifier: Apache 2

/// This module implements a capability (`EmitterCap`), which allows one to send
/// Wormhole messages. Its external address is determined by the capability's
/// `id`, which is a 32-byte vector.
module wormhole_simple_majority::emitter {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{TxContext};

    use wormhole_simple_majority::state::{Self, State};

    friend wormhole_simple_majority::publish_message;

    /// Event reflecting when `new` is called.
    struct EmitterCreated has drop, copy {
        emitter_cap: ID
    }

    /// Event reflecting when `destroy` is called.
    struct EmitterDestroyed has drop, copy {
        emitter_cap: ID
    }

    /// `EmitterCap` is a Sui object that gives a user or smart contract the
    /// capability to send Wormhole messages. For every Wormhole message
    /// emitted, a unique `sequence` is used.
    struct EmitterCap has key, store {
        id: UID,

        /// Sequence number of the next wormhole message.
        sequence: u64
    }

    /// Generate a new `EmitterCap`.
    public fun new(wormhole_state: &State, ctx: &mut TxContext): EmitterCap {
        state::assert_latest_only(wormhole_state);

        let cap =
            EmitterCap {
                id: object::new(ctx),
                sequence: 0
            };

        sui::event::emit(
            EmitterCreated { emitter_cap: object::id(&cap)}
        );

        cap
    }

    /// Returns current sequence (which will be used in the next Wormhole
    /// message emitted).
    public fun sequence(self: &EmitterCap): u64 {
        self.sequence
    }

    /// Once a Wormhole message is emitted, an `EmitterCap` upticks its
    /// internal `sequence` for the next message.
    public(friend) fun use_sequence(self: &mut EmitterCap): u64 {
        let sequence = self.sequence;
        self.sequence = sequence + 1;
        sequence
    }

    /// Destroys an `EmitterCap`.
    ///
    /// Note that this operation removes the ability to send messages using the
    /// emitter id, and is irreversible.
    public fun destroy(wormhole_state: &State, cap: EmitterCap) {
        state::assert_latest_only(wormhole_state);

        sui::event::emit(
            EmitterDestroyed { emitter_cap: object::id(&cap) }
        );

        let EmitterCap { id, sequence: _ } = cap;
        object::delete(id);
    }

    #[test_only]
    public fun destroy_test_only(cap: EmitterCap) {
        let EmitterCap { id, sequence: _ } = cap;
        object::delete(id);
    }

    #[test_only]
    public fun dummy(): EmitterCap {
        EmitterCap {
            id: object::new(&mut sui::tx_context::dummy()),
            sequence: 0
        }
    }
}
