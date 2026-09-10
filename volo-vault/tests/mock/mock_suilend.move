#[test_only]
module volo_vault::mock_suilend;

use std::ascii::String;
use sui::clock::Clock;
use volo_vault::vault::Vault;

public struct MockSuilendPool has key, store {
    id: UID,
}

public struct MockSuilendObligation<phantom PoolType> has key, store {
    id: UID,
    usd_value: u64,
}

public fun update_mock_suilend_position_value<PrincipalCoinType, PoolType>(
    vault: &mut Vault<PrincipalCoinType>,
    clock: &Clock,
    asset_type: String,
) {
    let suilend_obligation = vault.get_defi_asset_inner<
        PrincipalCoinType,
        MockSuilendObligation<PoolType>,
    >(
        asset_type,
    );

    let usd_value = calculate_suilend_obligation_value(suilend_obligation);

    vault.finish_update_asset_value(asset_type, usd_value, clock.timestamp_ms());
}

public fun create_mock_obligation<PoolType>(
    ctx: &mut TxContext,
    usd_value: u64,
): MockSuilendObligation<PoolType> {
    let obligation = MockSuilendObligation<PoolType> {
        id: object::new(ctx),
        usd_value,
    };
    obligation
}

public fun calculate_suilend_obligation_value<PoolType>(
    obligation: &MockSuilendObligation<PoolType>,
): u256 {
    obligation.usd_value as u256
}

public fun set_usd_value<PoolType>(
    obligation: &mut MockSuilendObligation<PoolType>,
    usd_value: u64,
) {
    obligation.usd_value = usd_value;
}

public fun usd_value<PoolType>(obligation: &MockSuilendObligation<PoolType>): u64 {
    obligation.usd_value
}
