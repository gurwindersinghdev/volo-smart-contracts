#[test_only]
module volo_vault::vault_oracle_test;

use std::ascii::String;
use std::type_name;
use sui::clock::{Self, Clock};
use sui::test_scenario::{Self, Scenario};
use switchboard::aggregator;
use volo_vault::btc_test_coin::BTC_TEST_COIN;
use volo_vault::init_vault;
use volo_vault::mock_aggregator;
use volo_vault::mock_pyth;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::test_helpers;
use volo_vault::usdc_test_coin::USDC_TEST_COIN;
use volo_vault::vault::{Vault, AdminCap};
use volo_vault::vault_manage;
use volo_vault::vault_oracle::{Self, OracleConfig};
use volo_vault::vault_utils;

const OWNER: address = @0xa;

const DECIMALS: u256 = 1_000_000_000;
const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000;

// A Pyth crypto feed quotes `magnitude * 10^-8`, so 1 USD is 100_000_000 at expo 8.
const PYTH_EXPO: u64 = 8;
const ONE_USD_PYTH: u64 = 100_000_000;
const TWO_USD_PYTH: u64 = 200_000_000;

// Real mainnet quotes, so the arithmetic below is the arithmetic prod will do.
// SUI/USD 0.73698412, VSUI/SUI.RR 1.06722037 -> vSUI 0.7865244652305244 USD.
const SUI_USD_PYTH: u64 = 73_698_412;
const VSUI_SUI_RATE_PYTH: u64 = 106_722_037;
const VSUI_USD_ORACLE: u256 = 786_524_465_230_524_400;

// ---------------------------------------------------------------- helpers

fun init_env(s: &mut Scenario, clock: &mut Clock) {
    init_vault::init_vault(s, clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(s);
}

fun sui_asset_type(): String {
    type_name::with_defining_ids<SUI_TEST_COIN>().into_string()
}

fun usdc_asset_type(): String {
    type_name::with_defining_ids<USDC_TEST_COIN>().into_string()
}

fun vsui_asset_type(): String {
    vault_oracle::vsui_asset_type()
}

// ---------------------------------------------------------------- registration

#[test]
// [TEST-CASE: Should add pyth aggregator.] @test-case ORACLE-001
public fun test_add_pyth_aggregator() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        let admin_cap = s.take_from_sender<AdminCap>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_manage::add_pyth_aggregator(
            &admin_cap,
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    s.next_tx(OWNER);
    {
        let oracle_config = s.take_shared<OracleConfig>();

        assert!(oracle_config.coin_decimals(sui_asset_type()) == 9);
        assert!(oracle_config.dex_slippage() == 100);
        assert!(oracle_config.has_aggregator(sui_asset_type()));
        assert!(oracle_config.get_asset_price(&clock, sui_asset_type()) == ORACLE_DECIMALS);

        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_AGGREGATOR_NOT_FOUND, location = vault_oracle)]
// [TEST-CASE: Should get asset price fail if not added.] @test-case ORACLE-002
public fun test_get_asset_price_fail_not_added() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let oracle_config = s.take_shared<OracleConfig>();

        assert!(!oracle_config.has_aggregator(sui_asset_type()));
        let _price = oracle_config.get_asset_price(&clock, sui_asset_type());

        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_PRICE_NOT_UPDATED, location = vault_oracle)]
// [TEST-CASE: Should add pyth aggregator fail if price not updated.] @test-case ORACLE-003
public fun test_add_pyth_aggregator_fail_price_not_updated() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        // update_interval is 60s; one millisecond past it the feed is stale.
        clock::set_for_testing(&mut clock, 1000 * 60);

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_AGGREGATOR_ALREADY_EXISTS,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should add pyth aggregator fail if already added.] @test-case ORACLE-004
public fun test_add_pyth_aggregator_fail_already_added() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );
        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// [TEST-CASE: Should remove pyth aggregator.] @test-case ORACLE-005
public fun test_remove_pyth_aggregator() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        let admin_cap = s.take_from_sender<AdminCap>();

        assert!(oracle_config.has_aggregator(sui_asset_type()));
        vault_manage::remove_pyth_aggregator(&admin_cap, &mut oracle_config, sui_asset_type());
        assert!(!oracle_config.has_aggregator(sui_asset_type()));

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_AGGREGATOR_NOT_FOUND, location = vault_oracle)]
// [TEST-CASE: Should remove pyth aggregator fail if already removed.] @test-case ORACLE-006
public fun test_remove_pyth_aggregator_fail_already_removed() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );
        vault_oracle::remove_pyth_aggregator(&mut oracle_config, sui_asset_type());
        vault_oracle::remove_pyth_aggregator(&mut oracle_config, sui_asset_type());

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

// ---------------------------------------------------------------- price update

#[test]
// [TEST-CASE: Should update price from pyth feed.] @test-case ORACLE-007
public fun test_update_price_v2_from_pyth() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        clock::set_for_testing(&mut clock, 1000 * 60);
        let fresh_price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            TWO_USD_PYTH,
            PYTH_EXPO,
            60,
            s.ctx(),
        );

        vault_oracle::update_price_v2(
            &mut oracle_config,
            &pyth_state,
            &fresh_price_info,
            &clock,
            sui_asset_type(),
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_price_info_object(fresh_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    s.next_tx(OWNER);
    {
        let oracle_config = s.take_shared<OracleConfig>();
        assert!(oracle_config.get_asset_price(&clock, sui_asset_type()) == 2 * ORACLE_DECIMALS);
        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// [TEST-CASE: Should change pyth aggregator.] @test-case ORACLE-008
public fun test_change_pyth_aggregator() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        let admin_cap = s.take_from_sender<AdminCap>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        // Repoint SUI at a different feed, priced differently.
        let new_price_info = mock_pyth::create_price_info_object(
            mock_pyth::usdc_usd_price_id(),
            TWO_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_manage::change_pyth_aggregator(
            &admin_cap,
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            &pyth_state,
            &new_price_info,
        );

        assert!(oracle_config.get_asset_price(&clock, sui_asset_type()) == 2 * ORACLE_DECIMALS);

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
        mock_pyth::destroy_price_info_object(new_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        // The old feed no longer matches the registered entry.
        let stale_feed = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let new_feed = mock_pyth::create_price_info_object(
            mock_pyth::usdc_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::update_price_v2(
            &mut oracle_config,
            &pyth_state,
            &new_feed,
            &clock,
            sui_asset_type(),
        );
        assert!(oracle_config.get_asset_price(&clock, sui_asset_type()) == ORACLE_DECIMALS);

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(stale_feed);
        mock_pyth::destroy_price_info_object(new_feed);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// [TEST-CASE: Should get normalized price for different decimals.] @test-case ORACLE-009
public fun test_get_normalized_price_for_different_decimals() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let sui_price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let usdc_price_info = mock_pyth::create_price_info_object(
            mock_pyth::usdc_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &sui_price_info,
        );
        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            usdc_asset_type(),
            6,
            &pyth_state,
            &usdc_price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(sui_price_info);
        mock_pyth::destroy_price_info_object(usdc_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    s.next_tx(OWNER);
    {
        let oracle_config = s.take_shared<OracleConfig>();

        assert!(
            oracle_config.get_normalized_asset_price(&clock, sui_asset_type()) == ORACLE_DECIMALS,
        );
        assert!(
            oracle_config.get_normalized_asset_price(&clock, usdc_asset_type()) == ORACLE_DECIMALS * 1_000,
        );

        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// [TEST-CASE: Should get correct usd value with normalized prices.] @test-case ORACLE-010
public fun test_get_correct_usd_value_with_oracle_price_with_different_decimals() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    let sui_asset_type = type_name::with_defining_ids<SUI_TEST_COIN>().into_string();
    let usdc_asset_type = type_name::with_defining_ids<USDC_TEST_COIN>().into_string();
    let btc_asset_type = type_name::with_defining_ids<BTC_TEST_COIN>().into_string();

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);
        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let config = s.take_shared<OracleConfig>();

        assert!(
            vault_oracle::get_asset_price(&config, &clock, sui_asset_type) == 2 * ORACLE_DECIMALS,
        );
        assert!(
            vault_oracle::get_asset_price(&config, &clock, usdc_asset_type) == 1 * ORACLE_DECIMALS,
        );
        assert!(
            vault_oracle::get_asset_price(&config, &clock, btc_asset_type) == 100_000 * ORACLE_DECIMALS,
        );

        assert!(
            vault_oracle::get_normalized_asset_price(&config, &clock, sui_asset_type) == 2 * ORACLE_DECIMALS,
        );
        assert!(
            vault_oracle::get_normalized_asset_price(&config, &clock, usdc_asset_type) == 1 * ORACLE_DECIMALS * 1_000,
        );
        assert!(
            vault_oracle::get_normalized_asset_price(&config, &clock, btc_asset_type) == 100_000 * ORACLE_DECIMALS * 10,
        );

        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let config = s.take_shared<OracleConfig>();

        let sui_usd_value_for_1_sui = vault_utils::mul_with_oracle_price(
            1_000_000_000,
            vault_oracle::get_normalized_asset_price(&config, &clock, sui_asset_type),
        );

        let usdc_usd_value_for_1_usdc = vault_utils::mul_with_oracle_price(
            1_000_000,
            vault_oracle::get_normalized_asset_price(&config, &clock, usdc_asset_type),
        );

        let btc_usd_value_for_1_btc = vault_utils::mul_with_oracle_price(
            100_000_000,
            vault_oracle::get_normalized_asset_price(&config, &clock, btc_asset_type),
        );

        assert!(sui_usd_value_for_1_sui == 2 * DECIMALS);
        assert!(usdc_usd_value_for_1_usdc == 1 * DECIMALS);
        assert!(btc_usd_value_for_1_btc == 100_000 * DECIMALS);

        test_scenario::return_shared(config);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_AGGREGATOR_NOT_FOUND, location = vault_oracle)]
// [TEST-CASE: Should change pyth aggregator fail if asset type not found.] @test-case ORACLE-011
public fun test_change_pyth_aggregator_fail_asset_type_not_found() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::change_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            &pyth_state,
            &price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_AGGREGATOR_ASSET_MISMATCH,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should update price fail if pyth feed id mismatch.] @test-case ORACLE-012
public fun test_update_price_v2_fail_feed_mismatch() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let wrong_price_info = mock_pyth::create_price_info_object(
            mock_pyth::btc_usd_price_id(),
            TWO_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        vault_oracle::update_price_v2(
            &mut oracle_config,
            &pyth_state,
            &wrong_price_info,
            &clock,
            sui_asset_type(),
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_price_info_object(wrong_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// [TEST-CASE: Should update price when pyth timestamp is slightly ahead of the clock.] @test-case ORACLE-013
public fun test_update_price_v2_when_timestamp_ahead_of_clock() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        // Publish time 60s while the clock reads 59.999s: inside FUTURE_TOLERANCE_MS.
        clock::set_for_testing(&mut clock, 1000 * 60 - 1);
        let ahead_price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            TWO_USD_PYTH,
            PYTH_EXPO,
            60,
            s.ctx(),
        );

        vault_oracle::update_price_v2(
            &mut oracle_config,
            &pyth_state,
            &ahead_price_info,
            &clock,
            sui_asset_type(),
        );

        assert!(oracle_config.get_asset_price(&clock, sui_asset_type()) == 2 * ORACLE_DECIMALS);

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_price_info_object(ahead_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_FUTURE_TOLERANCE_EXCEEDED,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should update price fail if pyth timestamp is too far ahead.] @test-case ORACLE-013b
public fun test_update_price_v2_fail_future_tolerance_exceeded() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        // 61s in the future, one second past FUTURE_TOLERANCE_MS.
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            61,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_INVALID_PRICE, location = vault_oracle)]
// [TEST-CASE: Should update price fail if pyth price is zero.] @test-case ORACLE-014
public fun test_update_price_v2_fail_zero_price() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            0,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_INVALID_PRICE, location = vault_oracle)]
// [TEST-CASE: Should update price fail if pyth price is negative.] @test-case ORACLE-015
public fun test_update_price_v2_fail_negative_price() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object_signed(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            true,
            PYTH_EXPO,
            true,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_INVALID_PRICE, location = vault_oracle)]
// [TEST-CASE: Should reject a pyth feed with a non-negative exponent.] @test-case ORACLE-015b
public fun test_update_price_v2_fail_non_negative_expo() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let price_info = mock_pyth::create_price_info_object_signed(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            false,
            PYTH_EXPO,
            false,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_INVALID_PRICE, location = vault_oracle)]
// [TEST-CASE: Should reject a pyth feed whose exponent is out of range.] @test-case ORACLE-015c
public fun test_update_price_v2_fail_expo_out_of_range() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        // MAX_PYTH_EXPO is 36.
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            37,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// Pyth's own staleness gate fires before ours; E_STALE_PRICE_UPDATE = 3 in pyth::pyth.
#[expected_failure(abort_code = 3, location = pyth_pro_compatible::pyth)]
// [TEST-CASE: Should surface pyth's own staleness gate.] @test-case ORACLE-019
public fun test_update_price_v2_fail_pyth_stale_gate() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state_with_threshold(60, s.ctx());
        let price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            ONE_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        clock::set_for_testing(&mut clock, 1000 * 60);

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

// ---------------------------------------------------------------- vSUI (rate feed)

#[test]
// [TEST-CASE: Should price vSUI as SUI * redemption rate.] @test-case ORACLE-VSUI-001
public fun test_set_and_update_pyth_aggregator_for_vsui() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    // Enabling vSUI only points the entry at the rate feed; it stores no price.
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        let admin_cap = s.take_from_sender<AdminCap>();

        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_manage::set_pyth_aggregator_for_vsui(
            &admin_cap,
            &mut oracle_config,
            &rate_price_info,
        );

        assert!(oracle_config.has_aggregator(vsui_asset_type()));
        assert!(
            oracle_config.asset_aggregator(vsui_asset_type()) == mock_pyth::vsui_sui_rate_price_id(),
        );
        assert!(oracle_config.coin_decimals(vsui_asset_type()) == 9);
        assert!(oracle_config.asset_price_last_updated(vsui_asset_type()) == 0);

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
        mock_pyth::destroy_price_info_object(rate_price_info);
    };

    // The first update is what makes it readable, at SUI/USD * rate.
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let sui_price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            SUI_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::update_price_v2_for_vsui(
            &mut oracle_config,
            &pyth_state,
            &sui_price_info,
            &rate_price_info,
            &clock,
            vsui_asset_type(),
        );

        assert!(oracle_config.get_asset_price(&clock, vsui_asset_type()) == VSUI_USD_ORACLE);

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(sui_price_info);
        mock_pyth::destroy_price_info_object(rate_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    // A later update moves the price with both legs.
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        clock::set_for_testing(&mut clock, 1000 * 60);
        let pyth_state = mock_pyth::create_state(s.ctx());
        let sui_price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            2 * ONE_USD_PYTH,
            PYTH_EXPO,
            60,
            s.ctx(),
        );
        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            150_000_000,
            PYTH_EXPO,
            60,
            s.ctx(),
        );

        vault_oracle::update_price_v2_for_vsui(
            &mut oracle_config,
            &pyth_state,
            &sui_price_info,
            &rate_price_info,
            &clock,
            vsui_asset_type(),
        );

        // 2 USD * 1.5 = 3 USD
        assert!(oracle_config.get_asset_price(&clock, vsui_asset_type()) == 3 * ORACLE_DECIMALS);

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(sui_price_info);
        mock_pyth::destroy_price_info_object(rate_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_PRICE_NOT_UPDATED, location = vault_oracle)]
// [TEST-CASE: vSUI should be unreadable until the first rate-based update.] @test-case ORACLE-VSUI-001b
public fun test_vsui_is_unpriced_until_first_update() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::set_pyth_aggregator_for_vsui(&mut oracle_config, &rate_price_info);

        // Anything past `update_interval` from the epoch is unreadable, which is every real
        // timestamp - the entry has no price until `update_price_v2_for_vsui` runs.
        clock::set_for_testing(&mut clock, 1000 * 60);
        let _price = oracle_config.get_asset_price(&clock, vsui_asset_type());

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(rate_price_info);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_RATE_FEED_NEEDS_DEDICATED_UPDATE,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should reject the rate feed on the plain update path.] @test-case ORACLE-VSUI-002
public fun test_update_price_v2_rejects_rate_feed() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let sui_price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            SUI_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::set_pyth_aggregator_for_vsui(&mut oracle_config, &rate_price_info);

        // Would otherwise store the bare 1.067 rate as vSUI's USD price.
        vault_oracle::update_price_v2(
            &mut oracle_config,
            &pyth_state,
            &rate_price_info,
            &clock,
            vsui_asset_type(),
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(sui_price_info);
        mock_pyth::destroy_price_info_object(rate_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_RATE_FEED_NEEDS_DEDICATED_UPDATE,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should refuse to register the rate feed as a plain price feed.] @test-case ORACLE-VSUI-003
public fun test_add_pyth_aggregator_rejects_rate_feed() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            vsui_asset_type(),
            9,
            &pyth_state,
            &rate_price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(rate_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_RATE_FEED_NEEDS_DEDICATED_UPDATE,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should refuse to repoint an entry at the rate feed.] @test-case ORACLE-VSUI-004
public fun test_change_pyth_aggregator_rejects_rate_feed() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let sui_price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            SUI_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &sui_price_info,
        );
        vault_oracle::change_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            &pyth_state,
            &rate_price_info,
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(sui_price_info);
        mock_pyth::destroy_price_info_object(rate_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_NOT_SUI_PRICE_FEED, location = vault_oracle)]
// [TEST-CASE: vSUI pricing should pin the SUI/USD feed.] @test-case ORACLE-VSUI-005
public fun test_vsui_price_fail_wrong_base_feed() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        // BTC/USD instead of SUI/USD would inflate vSUI by five orders of magnitude.
        let wrong_base = mock_pyth::create_price_info_object(
            mock_pyth::btc_usd_price_id(),
            SUI_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::set_pyth_aggregator_for_vsui(&mut oracle_config, &rate_price_info);
        vault_oracle::update_price_v2_for_vsui(
            &mut oracle_config,
            &pyth_state,
            &wrong_base,
            &rate_price_info,
            &clock,
            vsui_asset_type(),
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(wrong_base);
        mock_pyth::destroy_price_info_object(rate_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_NOT_RATE_FEED, location = vault_oracle)]
// [TEST-CASE: vSUI enablement should pin the redemption-rate feed.] @test-case ORACLE-VSUI-006
public fun test_set_pyth_aggregator_for_vsui_fail_not_a_rate_feed() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let not_a_rate = mock_pyth::create_price_info_object(
            mock_pyth::usdc_usd_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::set_pyth_aggregator_for_vsui(&mut oracle_config, &not_a_rate);

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(not_a_rate);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_NOT_RATE_FEED, location = vault_oracle)]
// [TEST-CASE: vSUI update should pin the redemption-rate feed.] @test-case ORACLE-VSUI-006b
public fun test_update_price_v2_for_vsui_fail_not_a_rate_feed() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let sui_price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            SUI_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let not_a_rate = mock_pyth::create_price_info_object(
            mock_pyth::usdc_usd_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::set_pyth_aggregator_for_vsui(&mut oracle_config, &rate_price_info);
        vault_oracle::update_price_v2_for_vsui(
            &mut oracle_config,
            &pyth_state,
            &sui_price_info,
            &not_a_rate,
            &clock,
            vsui_asset_type(),
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(sui_price_info);
        mock_pyth::destroy_price_info_object(rate_price_info);
        mock_pyth::destroy_price_info_object(not_a_rate);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_NOT_VSUI_ASSET_TYPE, location = vault_oracle)]
// [TEST-CASE: vSUI update should reject any asset type but vSUI.] @test-case ORACLE-VSUI-007
public fun test_update_price_v2_for_vsui_fail_wrong_asset_type() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let sui_price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            SUI_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::add_pyth_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &pyth_state,
            &sui_price_info,
        );

        // SUI is registered against SUI/USD, so the vsui path must not touch it.
        vault_oracle::update_price_v2_for_vsui(
            &mut oracle_config,
            &pyth_state,
            &sui_price_info,
            &rate_price_info,
            &clock,
            sui_asset_type(),
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(sui_price_info);
        mock_pyth::destroy_price_info_object(rate_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

// ---------------------------------------------------------------- update interval

#[test]
// [TEST-CASE: Should set update interval within bounds.] @test-case ORACLE-016
public fun test_set_update_interval() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        vault_oracle::set_update_interval(&mut oracle_config, 1000 * 60);
        assert!(oracle_config.update_interval() == 1000 * 60);

        vault_oracle::set_update_interval(&mut oracle_config, 1);
        assert!(oracle_config.update_interval() == 1);

        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_INVALID_UPDATE_INTERVAL,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should set update interval fail if zero.] @test-case ORACLE-017
public fun test_set_update_interval_fail_zero() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        vault_oracle::set_update_interval(&mut oracle_config, 0);
        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_INVALID_UPDATE_INTERVAL,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should set update interval fail if larger than max.] @test-case ORACLE-018
public fun test_set_update_interval_fail_exceeds_max() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        vault_oracle::set_update_interval(&mut oracle_config, 1000 * 60 + 1);
        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

// ---------------------------------------------------------------- retired switchboard path

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_SWITCHBOARD_DEPRECATED,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should abort on the retired switchboard add.] @test-case ORACLE-SB-001
public fun test_add_switchboard_aggregator_aborts() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        let admin_cap = s.take_from_sender<AdminCap>();

        let mut agg = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut agg, 1_000_000_000_000_000_000, 0);

        vault_manage::add_switchboard_aggregator(
            &admin_cap,
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            9,
            &agg,
        );

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
        aggregator::destroy_aggregator(agg);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_SWITCHBOARD_DEPRECATED,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should abort on the retired switchboard remove.] @test-case ORACLE-SB-002
public fun test_remove_switchboard_aggregator_aborts() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::remove_switchboard_aggregator(
            &admin_cap,
            &mut oracle_config,
            sui_asset_type(),
        );

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_SWITCHBOARD_DEPRECATED,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should abort on the retired switchboard change.] @test-case ORACLE-SB-003
public fun test_change_switchboard_aggregator_aborts() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        let admin_cap = s.take_from_sender<AdminCap>();

        let mut agg = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut agg, 1_000_000_000_000_000_000, 0);

        vault_manage::change_switchboard_aggregator(
            &admin_cap,
            &mut oracle_config,
            &clock,
            sui_asset_type(),
            &agg,
        );

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
        aggregator::destroy_aggregator(agg);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_SWITCHBOARD_DEPRECATED,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should abort on the retired switchboard price update.] @test-case ORACLE-SB-004
public fun test_update_price_aborts() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let mut agg = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut agg, 1_000_000_000_000_000_000, 0);

        vault_oracle::update_price(&mut oracle_config, &agg, &clock, sui_asset_type());

        test_scenario::return_shared(oracle_config);
        aggregator::destroy_aggregator(agg);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = vault_oracle::ERR_SWITCHBOARD_DEPRECATED,
        location = vault_oracle,
    ),
]
// [TEST-CASE: Should abort on the retired switchboard price read.] @test-case ORACLE-SB-005
public fun test_get_current_price_aborts() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let oracle_config = s.take_shared<OracleConfig>();

        let mut agg = mock_aggregator::create_mock_aggregator(s.ctx());
        mock_aggregator::set_current_result(&mut agg, 1_000_000_000_000_000_000, 0);

        let _price = vault_oracle::get_current_price(&oracle_config, &clock, &agg);

        test_scenario::return_shared(oracle_config);
        aggregator::destroy_aggregator(agg);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_RATE_OUT_OF_RANGE, location = vault_oracle)]
// [TEST-CASE: vSUI update should reject a redemption rate outside its band.] @test-case ORACLE-VSUI-008
public fun test_update_price_v2_for_vsui_fail_rate_out_of_range() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let sui_price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            SUI_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        // A garbled print: 10x the real redemption rate.
        let bad_rate = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            10 * VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::set_pyth_aggregator_for_vsui(&mut oracle_config, &rate_price_info);
        vault_oracle::update_price_v2_for_vsui(
            &mut oracle_config,
            &pyth_state,
            &sui_price_info,
            &bad_rate,
            &clock,
            vsui_asset_type(),
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(sui_price_info);
        mock_pyth::destroy_price_info_object(rate_price_info);
        mock_pyth::destroy_price_info_object(bad_rate);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_PRICE_NOT_UPDATED, location = vault_oracle)]
// [TEST-CASE: vSUI update should reject a stale rate leg even when SUI is fresh.] @test-case ORACLE-VSUI-009
public fun test_update_price_v2_for_vsui_fail_stale_rate_leg() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        vault_oracle::set_pyth_aggregator_for_vsui(&mut oracle_config, &rate_price_info);

        // The rate feed is what actually goes stale in production: nothing pushed it for a
        // minute while SUI/USD kept ticking.
        clock::set_for_testing(&mut clock, 1000 * 60);
        let fresh_sui = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            SUI_USD_PYTH,
            PYTH_EXPO,
            60,
            s.ctx(),
        );

        vault_oracle::update_price_v2_for_vsui(
            &mut oracle_config,
            &pyth_state,
            &fresh_sui,
            &rate_price_info,
            &clock,
            vsui_asset_type(),
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(rate_price_info);
        mock_pyth::destroy_price_info_object(fresh_sui);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_PRICE_NOT_UPDATED, location = vault_oracle)]
// [TEST-CASE: vSUI update should reject a stale SUI leg even when the rate is fresh.] @test-case ORACLE-VSUI-010
public fun test_update_price_v2_for_vsui_fail_stale_sui_leg() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        let pyth_state = mock_pyth::create_state(s.ctx());
        let stale_sui = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            SUI_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        vault_oracle::set_pyth_aggregator_for_vsui(&mut oracle_config, &rate_price_info);

        clock::set_for_testing(&mut clock, 1000 * 60);
        let fresh_rate = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            60,
            s.ctx(),
        );

        vault_oracle::update_price_v2_for_vsui(
            &mut oracle_config,
            &pyth_state,
            &stale_sui,
            &fresh_rate,
            &clock,
            vsui_asset_type(),
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(stale_sui);
        mock_pyth::destroy_price_info_object(rate_price_info);
        mock_pyth::destroy_price_info_object(fresh_rate);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
// [TEST-CASE: Enabling vSUI should keep the decimals already recorded for it.] @test-case ORACLE-VSUI-011
public fun test_set_pyth_aggregator_for_vsui_preserves_decimals() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        // A pre-existing entry, as the production cutover will find it.
        vault_oracle::set_aggregator(&mut oracle_config, &clock, vsui_asset_type(), 9, @0xabc);

        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        vault_oracle::set_pyth_aggregator_for_vsui(&mut oracle_config, &rate_price_info);

        assert!(oracle_config.coin_decimals(vsui_asset_type()) == 9);
        assert!(
            oracle_config.asset_aggregator(vsui_asset_type()) == mock_pyth::vsui_sui_rate_price_id(),
        );
        assert!(oracle_config.asset_price_last_updated(vsui_asset_type()) == 0);

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(rate_price_info);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_AGGREGATOR_NOT_FOUND, location = vault_oracle)]
// [TEST-CASE: Should fail to read the aggregator of an unregistered asset.] @test-case ORACLE-020
public fun test_asset_aggregator_fail_not_found() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let oracle_config = s.take_shared<OracleConfig>();
        let _agg = oracle_config.asset_aggregator(sui_asset_type());
        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_AGGREGATOR_NOT_FOUND, location = vault_oracle)]
// [TEST-CASE: Should fail to read the last update time of an unregistered asset.] @test-case ORACLE-021
public fun test_asset_price_last_updated_fail_not_found() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let oracle_config = s.take_shared<OracleConfig>();
        let _ts = oracle_config.asset_price_last_updated(sui_asset_type());
        test_scenario::return_shared(oracle_config);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_AGGREGATOR_NOT_FOUND, location = vault_oracle)]
// [TEST-CASE: Should fail to update the price of an unregistered asset.] @test-case ORACLE-022
public fun test_update_price_v2_fail_not_registered() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        let pyth_state = mock_pyth::create_state(s.ctx());
        let sui_price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            SUI_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        // Nothing was ever registered, so the keeper path must not create the entry.
        vault_oracle::update_price_v2(
            &mut oracle_config,
            &pyth_state,
            &sui_price_info,
            &clock,
            sui_asset_type(),
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(sui_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_AGGREGATOR_ASSET_MISMATCH, location = vault_oracle)]
// [TEST-CASE: Should reject a plain update on vsui even with a non-rate feed.] @test-case ORACLE-VSUI-002b
public fun test_update_price_v2_on_vsui_with_a_usd_feed() {
    let mut s = test_scenario::begin(OWNER);
    let mut clock = clock::create_for_testing(s.ctx());
    init_env(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        let pyth_state = mock_pyth::create_state(s.ctx());
        let sui_price_info = mock_pyth::create_price_info_object(
            mock_pyth::sui_usd_price_id(),
            SUI_USD_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );
        let rate_price_info = mock_pyth::create_price_info_object(
            mock_pyth::vsui_sui_rate_price_id(),
            VSUI_SUI_RATE_PYTH,
            PYTH_EXPO,
            0,
            s.ctx(),
        );

        vault_oracle::set_pyth_aggregator_for_vsui(&mut oracle_config, &rate_price_info);

        // The rate feed is caught by the 2010 guard (ORACLE-VSUI-002). Everything else is caught
        // here instead: vSUI's entry holds the rate feed id, so no other feed can ever match it.
        vault_oracle::update_price_v2(
            &mut oracle_config,
            &pyth_state,
            &sui_price_info,
            &clock,
            vsui_asset_type(),
        );

        test_scenario::return_shared(oracle_config);
        mock_pyth::destroy_price_info_object(sui_price_info);
        mock_pyth::destroy_price_info_object(rate_price_info);
        mock_pyth::destroy_state(pyth_state);
    };

    clock::destroy_for_testing(clock);
    s.end();
}
