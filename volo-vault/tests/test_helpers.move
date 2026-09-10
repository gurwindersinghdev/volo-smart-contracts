#[test_only]
module volo_vault::test_helpers;

use std::type_name;
use sui::clock::Clock;
use sui::test_scenario::Scenario;
use volo_vault::btc_test_coin::BTC_TEST_COIN;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::usdc_test_coin::USDC_TEST_COIN;
use volo_vault::vault_oracle::{Self, OracleConfig};


const MOCK_AGGREGATOR_SUI: address = @0xd;
const MOCK_AGGREGATOR_USDC: address = @0xe;
const MOCK_AGGREGATOR_BTC: address = @0xf;

#[test_only]
public fun set_aggregators(s: &mut Scenario, clock: &mut Clock, config: &mut OracleConfig) {
    let owner = s.sender();

    let sui_asset_type = type_name::with_defining_ids<SUI_TEST_COIN>().into_string();
    let usdc_asset_type = type_name::with_defining_ids<USDC_TEST_COIN>().into_string();
    let btc_asset_type = type_name::with_defining_ids<BTC_TEST_COIN>().into_string();

    s.next_tx(owner);
    {
        vault_oracle::set_aggregator(
            config,
            clock,
            sui_asset_type,
            9,
            MOCK_AGGREGATOR_SUI,
        );
        vault_oracle::set_aggregator(
            config,
            clock,
            usdc_asset_type,
            6,
            MOCK_AGGREGATOR_USDC,
        );
        vault_oracle::set_aggregator(
            config,
            clock,
            btc_asset_type,
            8,
            MOCK_AGGREGATOR_BTC,
        );
    }
}

#[test_only]
public fun set_prices(
    s: &mut Scenario,
    clock: &mut Clock,
    config: &mut OracleConfig,
    prices: vector<u256>,
) {
    let owner = s.sender();

    let sui_asset_type = type_name::with_defining_ids<SUI_TEST_COIN>().into_string();
    let usdc_asset_type = type_name::with_defining_ids<USDC_TEST_COIN>().into_string();
    let btc_asset_type = type_name::with_defining_ids<BTC_TEST_COIN>().into_string();

    s.next_tx(owner);
    {
        vault_oracle::set_current_price(
            config,
            clock,
            sui_asset_type,
            prices[0],
        );
        vault_oracle::set_current_price(
            config,
            clock,
            usdc_asset_type,
            prices[1],
        );
        vault_oracle::set_current_price(
            config,
            clock,
            btc_asset_type,
            prices[2],
        );
    }
}
