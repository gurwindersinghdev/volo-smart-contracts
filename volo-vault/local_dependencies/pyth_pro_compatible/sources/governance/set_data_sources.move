module pyth_pro_compatible::set_data_sources {
    use std::vector;

    use wormhole_simple_majority::cursor;
    use wormhole_simple_majority::external_address::{Self};
    use wormhole_simple_majority::bytes32::{Self};

    use pyth_pro_compatible::deserialize;
    use pyth_pro_compatible::data_source::{Self, DataSource};
    use pyth_pro_compatible::state::{Self, State, LatestOnly};

    friend pyth_pro_compatible::governance;

    struct DataSources {
        sources: vector<DataSource>,
    }

    public(friend) fun execute(
        latest_only: &LatestOnly,
        state: &mut State,
        payload: vector<u8>
    ) {
        let DataSources { sources } = from_byte_vec(payload);
        state::set_data_sources(latest_only, state, sources);
    }

    fun from_byte_vec(bytes: vector<u8>): DataSources {
        let cursor = cursor::new(bytes);
        let data_sources_count = deserialize::deserialize_u8(&mut cursor);

        let sources = vector::empty();

        let i = 0;
        while (i < data_sources_count) {
            let emitter_chain_id = deserialize::deserialize_u16(&mut cursor);
            let emitter_address = external_address::new(bytes32::from_bytes(deserialize::deserialize_vector(&mut cursor, 32)));
            vector::push_back(&mut sources, data_source::new((emitter_chain_id as u64), emitter_address));

            i = i + 1;
        };

        cursor::destroy_empty(cursor);

        DataSources {
            sources
        }
    }
}
