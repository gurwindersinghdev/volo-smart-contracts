/// The previous version of the contract sent the fees to a recipient address but this state is not used anymore
/// This module is kept for backward compatibility
module pyth_pro_compatible::set_fee_recipient {
    use wormhole_simple_majority::cursor;
    use wormhole_simple_majority::external_address::{Self};

    use pyth_pro_compatible::state::{Self, State, LatestOnly};

    friend pyth_pro_compatible::governance;

    struct PythFeeRecipient {
        recipient: address
    }

    public(friend) fun execute(latest_only: &LatestOnly, state: &mut State, payload: vector<u8>) {
        let PythFeeRecipient { recipient } = from_byte_vec(payload);
        state::set_fee_recipient(latest_only, state, recipient);
    }

    fun from_byte_vec(payload: vector<u8>): PythFeeRecipient {
        let cur = cursor::new(payload);

        // Recipient must be non-zero address.
        let recipient = external_address::take_nonzero(&mut cur);

        cursor::destroy_empty(cur);

        PythFeeRecipient {
            recipient: external_address::to_address(recipient)
        }
    }
}
