#[test_only]
module volo_vault::update_test;

use lending_core::account::AccountCap as NaviAccountCap;
use lending_core::lending;
use lending_core::storage::Storage;
use std::type_name;
use sui::clock;
use sui::coin;
use sui::test_scenario;
use volo_vault::init_vault;
use volo_vault::mock_cetus::{Self, MockCetusPosition};
use volo_vault::mock_suilend::{Self, MockSuilendObligation};
use volo_vault::navi_adaptor;
use volo_vault::reward_manager::RewardManager;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::test_helpers;
use volo_vault::usdc_test_coin::USDC_TEST_COIN;
use volo_vault::user_entry;
use volo_vault::vault::{Self, Vault, OperatorCap};
use volo_vault::vault_oracle::{Self, OracleConfig};
use volo_vault::vault_utils;

const OWNER: address = @0xa;
// const ALICE: address = @0xb;
// const BOB: address = @0xc;

const MOCK_AGGREGATOR_SUI: address = @0xd;
// const MOCK_AGGREGATOR_USDC: address = @0xe;
// const MOCK_AGGREGATOR_BTC: address = @0xf;

const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000; // 18 decimals
const DECIMALS: u256 = 1_000_000_000;

const MAX_UPDATE_INTERVAL: u64 = 1000 * 60; // 1 minute

// Navi Account Cap (asset type) exists by default
// "only principal" means the assets to be updated are principal + navi account cap

#[test]
// [TEST-CASE: Should update total usd value with only principal.] @test-case UPDATE-001
// Update total usd value when there is only principal in the vault
// Test the total usd value result with different price of principal
public fun test_update_total_usd_value_only_principal() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    let sui_asset_type = type_name::with_defining_ids<SUI_TEST_COIN>().into_string();

    // Set mock aggregator and price (1SUI = 2U)
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    // Add 1 SUI to the vault and update principal value
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let oracle_config = s.take_shared<OracleConfig>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        // Add 1 SUI to the vault
        vault.return_free_principal(coin.into_balance());

        // Update principal value
        vault.update_free_principal_value(&oracle_config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    // Check total usd value at T = 0
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 2 * DECIMALS);

        let (principal_asset_value, last_update_time) = vault.get_asset_value(type_name::with_defining_ids<
            SUI_TEST_COIN,
        >().into_string());
        assert!(principal_asset_value == 2 * DECIMALS);
        assert!(last_update_time == 0);

        test_scenario::return_shared(vault);
    };

    // Change price (1SUI = 5U) at T = 1000
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        clock::set_for_testing(&mut clock, 1000);
        vault_oracle::set_current_price(
            &mut oracle_config,
            &clock,
            sui_asset_type,
            5 * ORACLE_DECIMALS,
        );

        test_scenario::return_shared(oracle_config);
    };

    // Update principal value
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Check total usd value has changed with the new price
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 5 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    // Add 1 more SUI to the vault
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let oracle_config = s.take_shared<OracleConfig>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        // Add 1 SUI to the vault
        vault.return_free_principal(coin.into_balance());

        vault.update_free_principal_value(&oracle_config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    // Check total usd value has changed with the new price and new amount
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 10 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_USD_VALUE_NOT_UPDATED, location = vault)]
// [TEST-CASE: Should update total usd value fail with only principal if not updated.] @test-case UPDATE-002
// Update total usd value when there is only principal in the vault
// Try to get total usd value when the update interval has already passed
public fun test_update_total_usd_value_only_principal_fail_not_updated() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    let sui_asset_type = type_name::with_defining_ids<SUI_TEST_COIN>().into_string();

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(
            0,
            navi_account_cap,
        );
        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, vault_utils::parse_key<NaviAccountCap>(0), 0);
        test_scenario::return_shared(vault);
    };

    // Set mock aggregator and price (1SUI = 2U)
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
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        // Add 1 SUI to the vault
        vault.return_free_principal(coin.into_balance());
        vault.update_free_principal_value(&config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 2 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    // Set price (1SUI = 5U)
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        clock::set_for_testing(&mut clock, 1000);
        vault_oracle::set_current_price(
            &mut oracle_config,
            &clock,
            sui_asset_type,
            5 * ORACLE_DECIMALS,
        );

        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.update_free_principal_value(&config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 5 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.validate_total_usd_value_updated(&clock);

        test_scenario::return_shared(vault);
    };

    // T = 1000 + MAX_UPDATE_INTERVAL + 1
    // Last update time is 1000
    // The update interval has already passed, should fail
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        clock::set_for_testing(&mut clock, 1000 + MAX_UPDATE_INTERVAL + 1);

        // Will fail here
        let _total_usd_value = vault.get_total_usd_value(&clock);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_USD_VALUE_NOT_UPDATED, location = vault)]
// [TEST-CASE: Should validate total usd value fail if not updated.] @test-case UPDATE-003
// Validate total usd value when there is only principal in the vault
// Try to validate again when the update interval has already passed
public fun test_validate_total_usd_value_only_principal_fail_not_updated() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    let sui_asset_type = type_name::with_defining_ids<SUI_TEST_COIN>().into_string();

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(
            0,
            navi_account_cap,
        );
        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, vault_utils::parse_key<NaviAccountCap>(0), 0);
        test_scenario::return_shared(vault);
    };

    // Set mock aggregator and price (1SUI = 2U)
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
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        // Add 1 SUI to the vault
        vault.return_free_principal(coin.into_balance());
        vault.update_free_principal_value(&config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 2 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    // Set price (1SUI = 5U)
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        clock::set_for_testing(&mut clock, 1000);
        vault_oracle::set_current_price(
            &mut oracle_config,
            &clock,
            sui_asset_type,
            5 * ORACLE_DECIMALS,
        );

        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.update_free_principal_value(&config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 5 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.validate_total_usd_value_updated(&clock);

        test_scenario::return_shared(vault);
    };

    // T = 1000 + MAX_UPDATE_INTERVAL + 1
    // Last update time is 1000
    // The update interval has already passed, should fail
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 1000 + MAX_UPDATE_INTERVAL + 1);
        vault.validate_total_usd_value_updated(&clock);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should update total usd value with principal & coin type asset.] @test-case UPDATE-004
// SUI(principal) + USDC(coin_type_asset)
public fun test_update_total_usd_value_with_coin_type_asset() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    // Set mock aggregator and price (1SUI = 2U)
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
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        // Add 1 SUI to the vault
        vault.return_free_principal(coin.into_balance());

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        test_scenario::return_shared(vault);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // T = 0 Validate total usd value
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.validate_total_usd_value_updated(&clock);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 102 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    // Change price (1SUI = 5U) at T = 1000
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();
        let sui_asset_type = type_name::with_defining_ids<SUI_TEST_COIN>().into_string();

        clock::set_for_testing(&mut clock, 1000);
        vault_oracle::set_current_price(
            &mut oracle_config,
            &clock,
            sui_asset_type,
            5 * ORACLE_DECIMALS,
        );

        test_scenario::return_shared(oracle_config);
    };

    // Update assets values with new price
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 105 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault_oracle::ERR_PRICE_NOT_UPDATED, location = vault_oracle)]
// [TEST-CASE: Should update total usd value fail if oracle price not updated.] @test-case UPDATE-005
// Set oracle price at T = 0
// Try to update the free principal value at T = 1000 (succeed)
// Try to update the free principal value at T = 1000000 (fail)
// Maximum price update interval is 1 minute
// 1000000 - 1000 = 999000 > 1 minute
public fun test_update_usd_value_fail_oracle_price_not_latest_updated() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(
            0,
            navi_account_cap,
        );
        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, vault_utils::parse_key<NaviAccountCap>(0), 0);
        test_scenario::return_shared(vault);
    };

    // Set mock aggregator and price (1SUI = 2U)
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    // Try to update the free principal value (but the price is not updated)
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let config = s.take_shared<OracleConfig>();

        clock::set_for_testing(&mut clock, 1000);
        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Try to update the free principal value (but the price is not updated)
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let config = s.take_shared<OracleConfig>();

        clock::set_for_testing(&mut clock, 1_000_000);
        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_USD_VALUE_NOT_UPDATED, location = vault)]
// [TEST-CASE: Should update total usd value fail if not updated.] @test-case UPDATE-006
// Set oracle price at T = 0
// Update the free principal value at T = 1000 (succeed)
// Try to get total usd value at T = 1000 + MAX_UPDATE_INTERVAL + 1 (fail)
public fun test_update_usd_value_fail_not_updated() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    let sui_asset_type = type_name::with_defining_ids<SUI_TEST_COIN>().into_string();

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(
            0,
            navi_account_cap,
        );
        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, vault_utils::parse_key<NaviAccountCap>(0), 0);
        test_scenario::return_shared(vault);
    };

    // Set mock aggregator and price (1SUI = 2U)
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        vault_oracle::set_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type,
            9,
            MOCK_AGGREGATOR_SUI,
        );

        vault_oracle::set_current_price(
            &mut oracle_config,
            &clock,
            sui_asset_type,
            2 * ORACLE_DECIMALS,
        );

        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        clock::set_for_testing(&mut clock, 1000);
        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 1000 + MAX_UPDATE_INTERVAL + 1);
        let _total_usd_value = vault.get_total_usd_value(&clock);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should update total usd value with mock cetus position.] @test-case UPDATE-007
public fun test_update_cetus_position_value() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

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
        let cetus_position = mock_cetus::create_mock_position<
            SUI_TEST_COIN,
            USDC_TEST_COIN,
        >(s.ctx());

        transfer::public_transfer(cetus_position, OWNER);
    };

    s.next_tx(OWNER);
    {
        let mut cetus_position = s.take_from_sender<
            MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
        >();

        mock_cetus::set_token_amount(&mut cetus_position, 1_000_000_000, 1_000_000);

        s.return_to_sender(cetus_position);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cetus_position = s.take_from_sender<MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>>();

        vault.add_new_defi_asset(0, cetus_position);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let cetus_position_type = vault_utils::parse_key<
            MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
        >(0);

        mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
            &mut vault,
            &config,
            &clock,
            cetus_position_type,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 3 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should update total usd value with mock suilend obligation.] @test-case UPDATE-008
public fun test_update_suilend_obligation_value() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

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
        // Create a mock suilend obligation with 100 USD value
        let suilend_obligation = mock_suilend::create_mock_obligation<SUI_TEST_COIN>(
            s.ctx(),
            100_000_000_000,
        );

        transfer::public_transfer(suilend_obligation, OWNER);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let suilend_obligation = s.take_from_sender<MockSuilendObligation<SUI_TEST_COIN>>();

        vault.add_new_defi_asset(0, suilend_obligation);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let suilend_obligation_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
            0,
        );

        mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            suilend_obligation_type,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 100 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should update total usd value with all types of assets.] @test-case UPDATE-009
// Deposit 1 SUI to Navi Account Cap
// Add 1 SUI to free principal
// Add 100 USDC to coin type asset
// Add 1 SUI + 100 USDC to cetus position
// Add 100 USD to suilend obligation
// Update total usd value
public fun test_update_usd_value_with_all_types_of_assets() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(
            0,
            navi_account_cap,
        );
        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, vault_utils::parse_key<NaviAccountCap>(0), 0);
        test_scenario::return_shared(vault);
    };

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
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.set_deposit_fee(0);

        test_scenario::return_shared(vault);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        // deposit 1 SUI, (2U)
        // expected shares = 2e18
        let expected_shares = 2_000_000_000;
        let (_request_id, receipt, remaining_coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            expected_shares,
            option::none(),
            &clock,
            s.ctx(),
        );
        transfer::public_transfer(remaining_coin, OWNER);
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Execute deposit
    // Navi account position 1 SUI
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        let mut storage = s.take_shared<Storage>();
        let config = s.take_shared<OracleConfig>();

        vault::update_free_principal_value(&mut vault, &config, &clock);
        navi_adaptor::update_navi_position_value<SUI_TEST_COIN>(
            &mut vault,
            &config,
            &clock,
            vault_utils::parse_key<NaviAccountCap>(0),
            &mut storage,
        );

        vault.execute_deposit(
            &clock,
            &config,
            0,
            2_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(storage);
        test_scenario::return_shared(config);
        s.return_to_sender(operator_cap);
    };

    // Mock cetus position with 1 SUI and 100 USDC
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let mut cetus_position = mock_cetus::create_mock_position<
            SUI_TEST_COIN,
            USDC_TEST_COIN,
        >(s.ctx());

        mock_cetus::set_token_amount(&mut cetus_position, 1_000_000_000, 100_000_000);

        vault.add_new_defi_asset(0, cetus_position);

        test_scenario::return_shared(vault);
    };

    // Mock suilend obligation with 100 USD value
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        // Create a mock suilend obligation with 100 USD value
        let suilend_obligation = mock_suilend::create_mock_obligation<SUI_TEST_COIN>(
            s.ctx(),
            100_000_000_000,
        );

        vault.add_new_defi_asset(0, suilend_obligation);

        test_scenario::return_shared(vault);
    };

    // 1 SUI free principal
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        // Add 1 SUI to the vault
        vault.return_free_principal(coin.into_balance());

        test_scenario::return_shared(vault);
    };

    // 100 USDC coin type asset
    s.next_tx(OWNER);
    {
        let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        test_scenario::return_shared(vault);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut storage = s.take_shared<Storage>();
        let config = s.take_shared<OracleConfig>();

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        let cetus_asset_type = vault_utils::parse_key<
            MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
        >(0);
        let suilend_obligation_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
            0,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );
        mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
            &mut vault,
            &config,
            &clock,
            cetus_asset_type,
        );
        mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            suilend_obligation_type,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 306 * DECIMALS, 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should get vault share ratio.] @test-case UPDATE-010
public fun test_get_vault_share_ratio() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    // Set mock aggregator and price (1SUI = 2U)
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    // Add 1 SUI to the vault and update principal value
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let oracle_config = s.take_shared<OracleConfig>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        // Add 1 SUI to the vault
        vault.return_free_principal(coin.into_balance());

        // Update principal value
        vault.update_free_principal_value(&oracle_config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(oracle_config);
    };

    // Check total usd value at T = 0
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 2 * DECIMALS);

        let share_ratio = vault.get_share_ratio_without_update();
        assert!(share_ratio == 1 * DECIMALS);

        test_scenario::return_shared(vault);
    };

    // Set total shares to 1_000_000_000
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.set_total_shares(1_000_000_000);

        let share_ratio = vault.get_share_ratio_without_update();
        assert!(share_ratio == 2 * DECIMALS);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = vault::ERR_INVALID_COIN_ASSET_TYPE, location = vault)]
// [TEST-CASE: Should update coin type asset fail if asset type same as principal.] @test-case UPDATE-011
public fun test_update_coin_type_asset_fail_asset_type_same_as_principal() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    // Set mock aggregator and price (1SUI = 2U)
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
        let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        test_scenario::return_shared(vault);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.update_coin_type_asset_value<SUI_TEST_COIN, SUI_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_USD_VALUE_NOT_UPDATED, location = vault)]
// [TEST-CASE: Should validate total usd value updated fail if not updated.] @test-case UPDATE-012
public fun test_validate_total_usd_value_updated_fail_not_updated() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(
            0,
            navi_account_cap,
        );
        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, vault_utils::parse_key<NaviAccountCap>(0), 0);
        test_scenario::return_shared(vault);
    };

    // Set mock aggregator and price (1SUI = 2U)
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
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        // Add 1 SUI to the vault
        vault.return_free_principal(coin.into_balance());
        vault.update_free_principal_value(&config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.validate_total_usd_value_updated(&clock);

        test_scenario::return_shared(vault);
    };

    // T = 1000 + MAX_UPDATE_INTERVAL + 1
    // Last update time is 1000
    // The update interval has already passed, should fail
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        clock::set_for_testing(&mut clock, 1000 + MAX_UPDATE_INTERVAL + 1);

        // Will fail here
        vault.validate_total_usd_value_updated(&clock);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should value a single whitelisted market = 0 for a fresh account, recorded at that market's time.] @test-case NAVI-001
// With only market 0 whitelisted, a freshly created NAVI account has no balance, so the position
// should value to 0 and the aggregate should be recorded with that market's update time.
public fun test_update_navi_position_value_single_market() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(0, navi_account_cap);

        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, vault_utils::parse_key<NaviAccountCap>(0), 0);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut storage = s.take_shared<Storage>();
        let config = s.take_shared<OracleConfig>();

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);

        // Main market by default.
        assert!(storage.get_market_id() == 0);

        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        let (navi_value, last_update_time) = vault.get_asset_value(navi_asset_type);
        assert!(navi_value == 0);
        assert!(last_update_time == 0);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(storage);
        test_scenario::return_shared(config);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = navi_adaptor::ERR_NAVI_MARKET_NOT_WHITELISTED, location = navi_adaptor)]
// [TEST-CASE: Should abort update_navi_position_value on a non-whitelisted market.] @test-case NAVI-002
// Only market 0 is whitelisted; a Storage from a market that is not on the whitelist should be
// rejected, otherwise the position could be valued against an untracked market.
public fun test_update_navi_position_value_fail_not_whitelisted() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(0, navi_account_cap);

        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, vault_utils::parse_key<NaviAccountCap>(0), 0);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut storage = s.take_shared<Storage>();
        let config = s.take_shared<OracleConfig>();

        // Simulate a market that has not been whitelisted.
        storage.set_market_id_for_testing(1);

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);

        // Aborts here with ERR_NAVI_MARKET_NOT_WHITELISTED.
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(storage);
        test_scenario::return_shared(config);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should commit aggregate only when all whitelisted markets synced in one tx.] @test-case NAVI-003
public fun test_update_navi_position_value_multi_market_requires_all_synced() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(0, navi_account_cap);

        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, vault_utils::parse_key<NaviAccountCap>(0), 0);
        navi_adaptor::add_navi_market_for_testing(&mut vault, vault_utils::parse_key<NaviAccountCap>(0), 1);

        test_scenario::return_shared(vault);
    };

    clock::set_for_testing(&mut clock, 1000);

    let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);

    // Sync only market 0. Market 1 is still stale, so the aggregate is NOT committed: the registry
    // records market 0 at t == 1000, but the vault's asset value/timestamp stay at their initial 0.
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut storage = s.take_shared<Storage>();
        let config = s.take_shared<OracleConfig>();

        assert!(storage.get_market_id() == 0);

        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        // Registry recorded market 0 at the current time...
        let (m0_value, m0_updated_at) = navi_adaptor::navi_market_value_for_testing(
            &vault,
            navi_asset_type,
            0,
        );
        assert!(m0_value == 0);
        assert!(m0_updated_at == 1000);

        // ...but market 1 is untouched, so nothing is committed to the vault yet.
        let (m1_value, m1_updated_at) = navi_adaptor::navi_market_value_for_testing(
            &vault,
            navi_asset_type,
            1,
        );
        assert!(m1_value == 0);
        assert!(m1_updated_at == 0);

        let (navi_value, last_update_time) = vault.get_asset_value(navi_asset_type);
        assert!(navi_value == 0);
        assert!(last_update_time == 0);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(storage);
        test_scenario::return_shared(config);
    };

    // Now sync market 1 (the same Storage retagged as market 1). Both markets are updated at
    // t == 1000, so the aggregate timestamp advances to 1000.
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut storage = s.take_shared<Storage>();
        let config = s.take_shared<OracleConfig>();

        storage.set_market_id_for_testing(1);

        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        let (navi_value, last_update_time) = vault.get_asset_value(navi_asset_type);
        assert!(navi_value == 0);
        assert!(last_update_time == 1000);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(storage);
        test_scenario::return_shared(config);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = navi_adaptor::ERR_NAVI_MARKET_ALREADY_WHITELISTED, location = navi_adaptor)]
// [TEST-CASE: Should abort whitelisting the same market twice.] @test-case NAVI-004
public fun test_navi_add_market_fail_duplicate() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(0, navi_account_cap);

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, navi_asset_type, 0);
        // Aborts: market 0 is already whitelisted.
        navi_adaptor::add_navi_market_for_testing(&mut vault, navi_asset_type, 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should remove a 0-value market, then re-add it.] @test-case NAVI-005
public fun test_navi_remove_market_zero_value() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(0, navi_account_cap);

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, navi_asset_type, 0);
        navi_adaptor::add_navi_market_for_testing(&mut vault, navi_asset_type, 1);

        // Market 1 has 0 recorded value, so it can be removed.
        navi_adaptor::remove_navi_market(&mut vault, navi_asset_type, 1, &clock);

        // Re-adding the removed market succeeds and starts fresh (value 0, updated_at 0).
        navi_adaptor::add_navi_market_for_testing(&mut vault, navi_asset_type, 1);
        let (value, updated_at) = navi_adaptor::navi_market_value_for_testing(
            &vault,
            navi_asset_type,
            1,
        );
        assert!(value == 0);
        assert!(updated_at == 0);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = navi_adaptor::ERR_NAVI_MARKET_VALUE_NOT_ZERO, location = navi_adaptor)]
// [TEST-CASE: Should abort removing a market with non-zero value.] @test-case NAVI-006
public fun test_navi_remove_market_fail_value_not_zero() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(0, navi_account_cap);

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, navi_asset_type, 0);

        // Force a non-zero recorded value for market 0.
        navi_adaptor::set_navi_market_value_for_testing(&mut vault, navi_asset_type, 0, 1);

        // Aborts: market 0 still carries value.
        navi_adaptor::remove_navi_market(&mut vault, navi_asset_type, 0, &clock);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = navi_adaptor::ERR_NAVI_MARKET_NOT_WHITELISTED, location = navi_adaptor)]
// [TEST-CASE: Should abort removing a never-whitelisted market.] @test-case NAVI-007
public fun test_navi_remove_market_fail_not_whitelisted() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(0, navi_account_cap);

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, navi_asset_type, 0);

        // Aborts: market 5 was never whitelisted.
        navi_adaptor::remove_navi_market(&mut vault, navi_asset_type, 5, &clock);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}