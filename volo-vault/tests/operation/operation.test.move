#[test_only]
module volo_vault::operation_test;

use lending_core::account::AccountCap as NaviAccountCap;
use lending_core::incentive_v2::Incentive as IncentiveV2;
use lending_core::incentive_v3::{Self, Incentive as IncentiveV3};
use lending_core::lending;
use lending_core::pool::Pool;
use lending_core::storage::Storage;
use std::ascii::String;
use std::type_name;
use sui::clock;
use sui::coin;
use sui::table;
use sui::test_scenario;
use volo_vault::init_vault;
use volo_vault::mock_cetus::{Self, MockCetusPosition};
use volo_vault::mock_suilend::{Self, MockSuilendObligation};
use volo_vault::navi_adaptor;
use volo_vault::operation;
use volo_vault::receipt::{Self, Receipt};
use volo_vault::receipt_adaptor;
use volo_vault::reward_manager::RewardManager;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::test_helpers;
use volo_vault::usdc_test_coin::USDC_TEST_COIN;
use volo_vault::user_entry;
use volo_vault::vault::{Self, Vault, OperatorCap, Operation, AdminCap};
use volo_vault::vault_manage;
use volo_vault::vault_oracle::OracleConfig;
use volo_vault::vault_receipt_info;
use volo_vault::vault_utils;

const OWNER: address = @0xa;

const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000; // 18 decimals

#[test]
// [TEST-CASE: Should do op without coin type asset.] @test-case OPERATION-001
// Start op with coin type asset = 0
public fun test_start_op_with_no_coin_type_asset() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        let op_value_update_record = vault.op_value_update_record();
        assert!(op_value_update_record.op_value_update_record_value_update_enabled());

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should do op without defi assets.] @test-case OPERATION-002
// Start op with no defi assets
public fun test_start_op_with_no_defi_assets() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();

        let defi_asset_ids = vector[];
        let defi_asset_types = vector[];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should do op without principal.] @test-case OPERATION-003
// Start op with principal amount = 0
public fun test_start_op_with_no_principal() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            0,
            0,
            s.ctx(),
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should do op with value loss.] @test-case OPERATION-004
// Total usd value has some loss but not exceed loss limit
public fun test_start_op_with_value_loss() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_epoch(OWNER);
    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            mut principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        let split_balance = principal_balance.split(1_000);
        split_balance.destroy_for_testing();

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should do op with value gain.] @test-case OPERATION-005
// Total usd value has increased
public fun test_start_op_with_value_gain() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            mut principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        let new_coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        principal_balance.join(new_coin.into_balance());

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_USD_VALUE_NOT_UPDATED, location = vault)]
// [TEST-CASE: Should start op fail if not update value first.] @test-case OPERATION-006
// Start op with coin type asset = 0
public fun test_start_op_fail_not_update_value() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        // let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        // navi_adaptor::update_navi_position_value(
        //     &mut vault,
        //     &config,
        //     &clock,
        //     navi_asset_type,
        //     &mut storage,
        // );

        // vault.update_free_principal_value(&config, &clock);
        // vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_ASSET_TYPE_NOT_FOUND, location = vault)]
// [TEST-CASE: Should start op fail if borrow wrong defi assets.] @test-case OPERATION-007
public fun test_start_op_fail_borrow_wrong_defi_assets() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[1];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = operation::ERR_ASSETS_LENGTH_MISMATCH, location = operation)]
// [TEST-CASE: Should start op fail if defi assets length mismatch.] @test-case OPERATION-008
public fun test_start_op_fail_defi_assets_length_mismatch() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0, 1];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_EXCEED_LOSS_LIMIT, location = vault)]
// [TEST-CASE: Should do op fail with value loss exceed loss limit.] @test-case OPERATION-009
public fun test_start_op_fail_with_value_loss() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            mut principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        let split_balance = principal_balance.split(500_000_000);
        split_balance.destroy_for_testing();

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = operation::ERR_ASSETS_NOT_RETURNED, location = operation)]
// [TEST-CASE: Should do op fail if not return borrowed assets.] @test-case OPERATION-010
public fun test_start_op_fail_not_return_assets() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        // let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        // navi_adaptor::update_navi_position_value(
        //     &mut vault,
        //     &config,
        //     &clock,
        //     navi_asset_type,
        //     &mut storage,
        // );

        // vault.update_free_principal_value(&config, &clock);
        // vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = 0x1)]
// [TEST-CASE: Should do op fail if assets bag lose asset.] @test-case OPERATION-011
public fun test_start_op_fail_assets_bag_lose_asset() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            mut asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        let navi_account_cap = asset_bag.remove<String, NaviAccountCap>(
            vault_utils::parse_key<NaviAccountCap>(0),
        );
        transfer::public_transfer(navi_account_cap, OWNER);

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        // let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        // navi_adaptor::update_navi_position_value(
        //     &mut vault,
        //     &config,
        //     &clock,
        //     navi_asset_type,
        //     &mut storage,
        // );

        // vault.update_free_principal_value(&config, &clock);
        // vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_OPERATOR_FREEZED, location = vault)]
// [TEST-CASE: Should do op fail if operator is freezed.] @test-case OPERATION-012
public fun test_start_op_fail_op_freezed() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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
        let admin_cap = s.take_from_sender<AdminCap>();
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        vault_manage::set_operator_freezed(
            &admin_cap,
            &mut operation,
            operator_cap.operator_id(),
            true,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(admin_cap);
        s.return_to_sender(operator_cap);
    };

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

// #[test]
// // [TEST-CASE: Should do op with 2 navi account caps.] @test-case OPERATION-013
// // Start op with 2 account caps, 0 cetus position, 0 suilend obligation
// public fun test_start_op_2() {
//     let mut s = test_scenario::begin(OWNER);

//     let mut clock = clock::create_for_testing(s.ctx());

//     init_vault::init_vault(&mut s, &mut clock);
//     init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
//     init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
//     init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

//         let navi_account_cap = lending::create_account(s.ctx());
//         vault.add_new_defi_asset(
//             0,
//             navi_account_cap,
//         );

//         let navi_account_cap_2 = lending::create_account(s.ctx());
//         vault.add_new_defi_asset(
//             1,
//             navi_account_cap_2,
//         );

//         test_scenario::return_shared(vault);
//     };

//     // Set mock aggregator and price
//     s.next_tx(OWNER);
//     {
//         let mut oracle_config = s.take_shared<OracleConfig>();

//         test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);

//         let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
//         test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

//         test_scenario::return_shared(oracle_config);
//     };

//     s.next_tx(OWNER);
//     {
//         let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

//         vault.return_free_principal(coin.into_balance());

//         test_scenario::return_shared(vault);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         vault::update_free_principal_value(&mut vault, &config, &clock);

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let operator_cap = s.take_from_sender<OperatorCap>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

//         let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
//         // Add 100 USDC to the vault
//         vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
//         vault.return_coin_type_asset(coin.into_balance());

//         test_scenario::return_shared(vault);
//         s.return_to_sender(operator_cap);
//     };

//     s.next_tx(OWNER);
//     {
//         let operation = s.take_shared<Operation>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let cap = s.take_from_sender<OperatorCap>();
//         let config = s.take_shared<OracleConfig>();
//         let mut storage = s.take_shared<Storage>();

//         let defi_asset_ids = vector[0, 1];
//         let defi_asset_types = vector[
//             type_name::with_defining_ids<NaviAccountCap>(),
//             type_name::with_defining_ids<NaviAccountCap>(),
//         ];

//         let (
//             asset_bag,
//             tx_bag,
//             tx_bag_for_check_value_update,
//             principal_balance,
//             coin_type_asset_balance,
//         ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             &clock,
//             defi_asset_ids,
//             defi_asset_types,
//             1_000_000_000,
//             0,
//             s.ctx(),
//         );

//         // Step 2
//         operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             asset_bag,
//             tx_bag,
//             principal_balance,
//             coin_type_asset_balance,
//         );

//         let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
//         navi_adaptor::update_navi_position_value(
//             &mut vault,
//             &config,
//             &clock,
//             navi_asset_type,
//             &mut storage,
//         );

//         let navi_asset_type_2 = vault_utils::parse_key<NaviAccountCap>(1);
//         navi_adaptor::update_navi_position_value(
//             &mut vault,
//             &config,
//             &clock,
//             navi_asset_type_2,
//             &mut storage,
//         );

//         vault.update_free_principal_value(&config, &clock);
//         vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

//         // Step 3
//         operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             &clock,
//             tx_bag_for_check_value_update,
//         );

//         s.return_to_sender(cap);
//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(operation);
//         test_scenario::return_shared(config);
//         test_scenario::return_shared(storage);
//     };

//     s.next_tx(OWNER);
//     {
//         let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

//         let record = vault.op_value_update_record();
//         let _assets_updated = record.op_value_update_record_assets_updated();
//         let _assets_borrowed = record.op_value_update_record_assets_borrowed();

//         test_scenario::return_shared(vault);
//     };

//     clock.destroy_for_testing();
//     s.end();
// }

#[test]
// [TEST-CASE: Should do op with cetus position & principal.] @test-case OPERATION-014
// Start op with cetus position and principal
public fun test_start_op_cetus() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());
        vault.update_free_principal_value(&config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let mut mock_cetus_position = mock_cetus::create_mock_position<
            SUI_TEST_COIN,
            USDC_TEST_COIN,
        >(s.ctx());
        mock_cetus::set_token_amount(&mut mock_cetus_position, 1_000_000_000, 1_000_000_000);

        vault.add_new_defi_asset(
            0,
            mock_cetus_position,
        );

        let mock_cetus_asset_type = vault_utils::parse_key<
            MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
        >(0);
        mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
            &mut vault,
            &config,
            &clock,
            mock_cetus_asset_type,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[
            type_name::with_defining_ids<MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>>(),
        ];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let mock_cetus_asset_type = vault_utils::parse_key<
            MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
        >(0);
        mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
            &mut vault,
            &config,
            &clock,
            mock_cetus_asset_type,
        );

        vault.update_free_principal_value(&config, &clock);
        // vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should do op with suilend position & principal.] @test-case OPERATION-015
public fun test_start_op_suilend() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());
        vault.update_free_principal_value(&config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let mock_suilend_position = mock_suilend::create_mock_obligation<SUI_TEST_COIN>(
            s.ctx(),
            1_000_000_000,
        );

        vault.add_new_defi_asset(
            0,
            mock_suilend_position,
        );

        let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
            0,
        );
        mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            mock_suilend_asset_type,
        );

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[
            type_name::with_defining_ids<MockSuilendObligation<SUI_TEST_COIN>>(),
        ];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, MockSuilendObligation<SUI_TEST_COIN>>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, MockSuilendObligation<SUI_TEST_COIN>>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
            0,
        );
        mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            mock_suilend_asset_type,
        );

        vault.update_free_principal_value(&config, &clock);
        // vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, MockSuilendObligation<SUI_TEST_COIN>>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
    };

    clock.destroy_for_testing();
    s.end();
}

// #[test]
// // [TEST-CASE: Should do op with all assets.] @test-case OPERATION-016
// public fun test_start_op_with_all_assets() {
//     let mut s = test_scenario::begin(OWNER);

//     let mut clock = clock::create_for_testing(s.ctx());

//     init_vault::init_vault(&mut s, &mut clock);
//     init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
//     init_vault::init_create_vault<USDC_TEST_COIN>(&mut s);
//     init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
//     init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

//     s.next_tx(OWNER);
//     {
//         let mut oracle_config = s.take_shared<OracleConfig>();

//         test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);
//         let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
//         test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

//         test_scenario::return_shared(oracle_config);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<USDC_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();
//         let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000, s.ctx());
//         vault.return_free_principal(coin.into_balance());
//         vault.update_free_principal_value(&config, &clock);

//         vault.set_total_shares(1_000_000_000);
//         let receipt = receipt::create_receipt(vault.vault_id(), s.ctx());
//         let mut vault_receipt_info = vault_receipt_info::new_vault_receipt_info(
//             table::new(s.ctx()),
//             table::new(s.ctx()),
//         );
//         vault_receipt_info.add_share(1_000_000_000);
//         vault.set_vault_receipt_info(receipt.receipt_id(), vault_receipt_info);

//         transfer::public_transfer(receipt, OWNER);

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let receipt = s.take_from_sender<Receipt>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let usdc_vault = s.take_shared<Vault<USDC_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         let receipt_asset_type = vault_utils::parse_key<Receipt>(0);
//         vault.add_new_defi_asset(
//             0,
//             receipt,
//         );
//         receipt_adaptor::update_receipt_value<SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &usdc_vault,
//             &config,
//             &clock,
//             receipt_asset_type,
//         );

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(usdc_vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         vault.return_free_principal(coin.into_balance());
//         vault.update_free_principal_value(&config, &clock);

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let operator_cap = s.take_from_sender<OperatorCap>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
//         // Add 100 USDC to the vault
//         vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
//         vault.return_coin_type_asset(coin.into_balance());
//         vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//         s.return_to_sender(operator_cap);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();
//         let mut storage = s.take_shared<Storage>();

//         let navi_account_cap = lending::create_account(s.ctx());
//         vault.add_new_defi_asset(
//             0,
//             navi_account_cap,
//         );

//         let navi_account_cap_type = vault_utils::parse_key<NaviAccountCap>(0);
//         navi_adaptor::update_navi_position_value<SUI_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             navi_account_cap_type,
//             &mut storage,
//         );

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//         test_scenario::return_shared(storage);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         let mut mock_cetus_position = mock_cetus::create_mock_position<
//             SUI_TEST_COIN,
//             USDC_TEST_COIN,
//         >(s.ctx());
//         mock_cetus::set_token_amount(&mut mock_cetus_position, 1_000_000_000, 1_000_000_000);

//         vault.add_new_defi_asset(
//             0,
//             mock_cetus_position,
//         );

//         let mock_cetus_asset_type = vault_utils::parse_key<
//             MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
//         >(0);
//         mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             mock_cetus_asset_type,
//         );

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

//         let mock_suilend_position = mock_suilend::create_mock_obligation<SUI_TEST_COIN>(
//             s.ctx(),
//             1_000_000_000,
//         );

//         vault.add_new_defi_asset(
//             0,
//             mock_suilend_position,
//         );

//         let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
//             0,
//         );
//         mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &clock,
//             mock_suilend_asset_type,
//         );

//         test_scenario::return_shared(vault);
//     };

//     s.next_tx(OWNER);
//     {
//         let operation = s.take_shared<Operation>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let usdc_vault = s.take_shared<Vault<USDC_TEST_COIN>>();
//         let cap = s.take_from_sender<OperatorCap>();
//         let config = s.take_shared<OracleConfig>();
//         let mut storage = s.take_shared<Storage>();

//         let defi_asset_ids = vector[0, 0, 0, 0];
//         let defi_asset_types = vector[
//             type_name::with_defining_ids<NaviAccountCap>(),
//             type_name::with_defining_ids<MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>>(),
//             type_name::with_defining_ids<MockSuilendObligation<SUI_TEST_COIN>>(),
//             type_name::with_defining_ids<Receipt>(),
//         ];

//         let (
//             asset_bag,
//             tx_bag,
//             tx_bag_for_check_value_update,
//             principal_balance,
//             coin_type_asset_balance,
//         ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             &clock,
//             defi_asset_ids,
//             defi_asset_types,
//             1_000_000_000,
//             1_000_000_000,
//             s.ctx(),
//         );

//         // Step 2
//         operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             asset_bag,
//             tx_bag,
//             principal_balance,
//             coin_type_asset_balance,
//         );

//         let navi_account_cap_type = vault_utils::parse_key<NaviAccountCap>(0);
//         navi_adaptor::update_navi_position_value<SUI_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             navi_account_cap_type,
//             &mut storage,
//         );

//         let mock_cetus_asset_type = vault_utils::parse_key<
//             MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
//         >(0);
//         mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             mock_cetus_asset_type,
//         );

//         let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
//             0,
//         );
//         mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &clock,
//             mock_suilend_asset_type,
//         );

//         let receipt_asset_type = vault_utils::parse_key<Receipt>(0);
//         receipt_adaptor::update_receipt_value<SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &usdc_vault,
//             &config,
//             &clock,
//             receipt_asset_type,
//         );

//         vault.update_free_principal_value(&config, &clock);
//         vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

//         // Step 3
//         operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             &clock,
//             tx_bag_for_check_value_update,
//         );

//         s.return_to_sender(cap);
//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(operation);
//         test_scenario::return_shared(config);
//         test_scenario::return_shared(storage);
//         test_scenario::return_shared(usdc_vault);
//     };

//     clock.destroy_for_testing();
//     s.end();
// }

// #[test]
// // [TEST-CASE: Should do op with all assets multiple ops.] @test-case OPERATION-017
// public fun test_start_op_with_all_assets_multiple_ops() {
//     let mut s = test_scenario::begin(OWNER);

//     let mut clock = clock::create_for_testing(s.ctx());

//     init_vault::init_vault(&mut s, &mut clock);
//     init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
//     init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
//     init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

//     s.next_tx(OWNER);
//     {
//         let mut oracle_config = s.take_shared<OracleConfig>();

//         test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);
//         let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
//         test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

//         test_scenario::return_shared(oracle_config);
//     };

//     s.next_tx(OWNER);
//     {
//         let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         vault.return_free_principal(coin.into_balance());
//         vault.update_free_principal_value(&config, &clock);

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let operator_cap = s.take_from_sender<OperatorCap>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
//         // Add 100 USDC to the vault
//         vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
//         vault.return_coin_type_asset(coin.into_balance());
//         vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//         s.return_to_sender(operator_cap);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();
//         let mut storage = s.take_shared<Storage>();

//         let navi_account_cap = lending::create_account(s.ctx());
//         vault.add_new_defi_asset(
//             0,
//             navi_account_cap,
//         );

//         let navi_account_cap_type = vault_utils::parse_key<NaviAccountCap>(0);
//         navi_adaptor::update_navi_position_value<SUI_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             navi_account_cap_type,
//             &mut storage,
//         );

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//         test_scenario::return_shared(storage);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         let mut mock_cetus_position = mock_cetus::create_mock_position<
//             SUI_TEST_COIN,
//             USDC_TEST_COIN,
//         >(s.ctx());
//         mock_cetus::set_token_amount(&mut mock_cetus_position, 1_000_000_000, 1_000_000_000);

//         vault.add_new_defi_asset(
//             0,
//             mock_cetus_position,
//         );

//         let mock_cetus_asset_type = vault_utils::parse_key<
//             MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
//         >(0);
//         mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             mock_cetus_asset_type,
//         );

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

//         let mock_suilend_position = mock_suilend::create_mock_obligation<SUI_TEST_COIN>(
//             s.ctx(),
//             1_000_000_000,
//         );

//         vault.add_new_defi_asset(
//             0,
//             mock_suilend_position,
//         );

//         let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
//             0,
//         );
//         mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &clock,
//             mock_suilend_asset_type,
//         );

//         test_scenario::return_shared(vault);
//     };

//     s.next_tx(OWNER);
//     {
//         let operation = s.take_shared<Operation>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let cap = s.take_from_sender<OperatorCap>();
//         let config = s.take_shared<OracleConfig>();
//         let mut storage = s.take_shared<Storage>();

//         let defi_asset_ids = vector[0, 0, 0];
//         let defi_asset_types = vector[
//             type_name::with_defining_ids<NaviAccountCap>(),
//             type_name::with_defining_ids<MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>>(),
//             type_name::with_defining_ids<MockSuilendObligation<SUI_TEST_COIN>>(),
//         ];

//         let (
//             asset_bag,
//             tx_bag,
//             tx_bag_for_check_value_update,
//             principal_balance,
//             coin_type_asset_balance,
//         ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             &clock,
//             defi_asset_ids,
//             defi_asset_types,
//             1_000_000_000,
//             1_000_000_000,
//             s.ctx(),
//         );

//         // Step 2
//         operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             asset_bag,
//             tx_bag,
//             principal_balance,
//             coin_type_asset_balance,
//         );

//         let navi_account_cap_type = vault_utils::parse_key<NaviAccountCap>(0);
//         navi_adaptor::update_navi_position_value<SUI_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             navi_account_cap_type,
//             &mut storage,
//         );

//         let mock_cetus_asset_type = vault_utils::parse_key<
//             MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
//         >(0);
//         mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             mock_cetus_asset_type,
//         );

//         let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
//             0,
//         );
//         mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &clock,
//             mock_suilend_asset_type,
//         );

//         vault.update_free_principal_value(&config, &clock);
//         vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

//         // Step 3
//         operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             &clock,
//             tx_bag_for_check_value_update,
//         );

//         s.return_to_sender(cap);
//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(operation);
//         test_scenario::return_shared(config);
//         test_scenario::return_shared(storage);
//     };

//     s.next_tx(OWNER);
//     {
//         let operation = s.take_shared<Operation>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let cap = s.take_from_sender<OperatorCap>();
//         let config = s.take_shared<OracleConfig>();
//         let mut storage = s.take_shared<Storage>();

//         let defi_asset_ids = vector[0, 0, 0];
//         let defi_asset_types = vector[
//             type_name::with_defining_ids<NaviAccountCap>(),
//             type_name::with_defining_ids<MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>>(),
//             type_name::with_defining_ids<MockSuilendObligation<SUI_TEST_COIN>>(),
//         ];

//         let (
//             asset_bag,
//             tx_bag,
//             tx_bag_for_check_value_update,
//             principal_balance,
//             coin_type_asset_balance,
//         ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             &clock,
//             defi_asset_ids,
//             defi_asset_types,
//             500_000_000,
//             500_000_000,
//             s.ctx(),
//         );

//         // Step 2
//         operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             asset_bag,
//             tx_bag,
//             principal_balance,
//             coin_type_asset_balance,
//         );

//         let navi_account_cap_type = vault_utils::parse_key<NaviAccountCap>(0);
//         navi_adaptor::update_navi_position_value<SUI_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             navi_account_cap_type,
//             &mut storage,
//         );

//         let mock_cetus_asset_type = vault_utils::parse_key<
//             MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
//         >(0);
//         mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             mock_cetus_asset_type,
//         );

//         let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
//             0,
//         );
//         mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &clock,
//             mock_suilend_asset_type,
//         );

//         vault.update_free_principal_value(&config, &clock);
//         vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

//         // Step 3
//         operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             &clock,
//             tx_bag_for_check_value_update,
//         );

//         s.return_to_sender(cap);
//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(operation);
//         test_scenario::return_shared(config);
//         test_scenario::return_shared(storage);
//     };

//     clock.destroy_for_testing();
//     s.end();
// }

#[test]
// [TEST-CASE: Should do op with other vault receipt.] @test-case OPERATION-018
public fun test_start_op_with_other_vault_receipt() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());
        vault.update_free_principal_value(&config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(
            0,
            navi_account_cap,
        );
        navi_adaptor::init_navi_market_registry(&mut vault, s.ctx());
        navi_adaptor::add_navi_market_for_testing(&mut vault, vault_utils::parse_key<NaviAccountCap>(0), 0);

        let navi_account_cap_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value<SUI_TEST_COIN>(
            &mut vault,
            &config,
            &clock,
            navi_account_cap_type,
            &mut storage,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let mut mock_cetus_position = mock_cetus::create_mock_position<
            SUI_TEST_COIN,
            USDC_TEST_COIN,
        >(s.ctx());
        mock_cetus::set_token_amount(&mut mock_cetus_position, 1_000_000_000, 1_000_000_000);

        vault.add_new_defi_asset(
            0,
            mock_cetus_position,
        );

        let mock_cetus_asset_type = vault_utils::parse_key<
            MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
        >(0);
        mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
            &mut vault,
            &config,
            &clock,
            mock_cetus_asset_type,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let mock_suilend_position = mock_suilend::create_mock_obligation<SUI_TEST_COIN>(
            s.ctx(),
            1_000_000_000,
        );

        vault.add_new_defi_asset(
            0,
            mock_suilend_position,
        );

        let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
            0,
        );
        mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            mock_suilend_asset_type,
        );

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[
            type_name::with_defining_ids<NaviAccountCap>(),
        ];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            1_000_000_000,
            s.ctx(),
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

// #[test]
// // [TEST-CASE: Should do op with all assets deposit into navi with borrow mut.] @test-case OPERATION-019
// public fun test_start_op_with_all_assets_deposit_into_navi() {
//     let mut s = test_scenario::begin(OWNER);

//     let mut clock = clock::create_for_testing(s.ctx());

//     init_vault::init_vault(&mut s, &mut clock);
//     init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
//     init_vault::init_create_vault<USDC_TEST_COIN>(&mut s);
//     init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
//     init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

//     s.next_tx(OWNER);
//     {
//         let mut oracle_config = s.take_shared<OracleConfig>();

//         test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);
//         let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
//         test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

//         test_scenario::return_shared(oracle_config);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<USDC_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();
//         let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000, s.ctx());
//         vault.return_free_principal(coin.into_balance());
//         vault.update_free_principal_value(&config, &clock);

//         vault.set_total_shares(1_000_000_000);
//         let receipt = receipt::create_receipt(vault.vault_id(), s.ctx());
//         let mut vault_receipt_info = vault_receipt_info::new_vault_receipt_info(
//             table::new(s.ctx()),
//             table::new(s.ctx()),
//         );
//         vault_receipt_info.add_share(1_000_000_000);
//         vault.set_vault_receipt_info(receipt.receipt_id(), vault_receipt_info);

//         transfer::public_transfer(receipt, OWNER);

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let receipt = s.take_from_sender<Receipt>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let usdc_vault = s.take_shared<Vault<USDC_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         let receipt_asset_type = vault_utils::parse_key<Receipt>(0);
//         vault.add_new_defi_asset(
//             0,
//             receipt,
//         );
//         receipt_adaptor::update_receipt_value<SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &usdc_vault,
//             &config,
//             &clock,
//             receipt_asset_type,
//         );

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(usdc_vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         vault.return_free_principal(coin.into_balance());
//         vault.update_free_principal_value(&config, &clock);

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let operator_cap = s.take_from_sender<OperatorCap>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
//         // Add 100 USDC to the vault
//         vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
//         vault.return_coin_type_asset(coin.into_balance());
//         vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//         s.return_to_sender(operator_cap);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();
//         let mut storage = s.take_shared<Storage>();

//         let navi_account_cap = lending::create_account(s.ctx());
//         vault.add_new_defi_asset(
//             0,
//             navi_account_cap,
//         );

//         let navi_account_cap_type = vault_utils::parse_key<NaviAccountCap>(0);
//         navi_adaptor::update_navi_position_value<SUI_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             navi_account_cap_type,
//             &mut storage,
//         );

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//         test_scenario::return_shared(storage);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         let mut mock_cetus_position = mock_cetus::create_mock_position<
//             SUI_TEST_COIN,
//             USDC_TEST_COIN,
//         >(s.ctx());
//         mock_cetus::set_token_amount(&mut mock_cetus_position, 1_000_000_000, 1_000_000_000);

//         vault.add_new_defi_asset(
//             0,
//             mock_cetus_position,
//         );

//         let mock_cetus_asset_type = vault_utils::parse_key<
//             MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
//         >(0);
//         mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             mock_cetus_asset_type,
//         );

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

//         let mock_suilend_position = mock_suilend::create_mock_obligation<SUI_TEST_COIN>(
//             s.ctx(),
//             1_000_000_000,
//         );

//         vault.add_new_defi_asset(
//             0,
//             mock_suilend_position,
//         );

//         let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
//             0,
//         );
//         mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &clock,
//             mock_suilend_asset_type,
//         );

//         test_scenario::return_shared(vault);
//     };

//     s.next_tx(OWNER);
//     {
//         let operation = s.take_shared<Operation>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let usdc_vault = s.take_shared<Vault<USDC_TEST_COIN>>();
//         let cap = s.take_from_sender<OperatorCap>();
//         let config = s.take_shared<OracleConfig>();
//         let mut storage = s.take_shared<Storage>();

//         let defi_asset_ids = vector[0, 0, 0, 0];
//         let defi_asset_types = vector[
//             type_name::with_defining_ids<NaviAccountCap>(),
//             type_name::with_defining_ids<MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>>(),
//             type_name::with_defining_ids<MockSuilendObligation<SUI_TEST_COIN>>(),
//             type_name::with_defining_ids<Receipt>(),
//         ];

//         // std::debug::print(&std::ascii::string(b"usd value before op"));
//         // std::debug::print(&vault.get_total_usd_value_without_update());

//         let (
//             mut asset_bag,
//             tx_bag,
//             tx_bag_for_check_value_update,
//             mut principal_balance,
//             coin_type_asset_balance,
//         ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             &clock,
//             defi_asset_ids,
//             defi_asset_types,
//             1_000_000_000,
//             1_000_000_000,
//             s.ctx(),
//         );

//         let navi_account_cap = asset_bag.borrow_mut<String, NaviAccountCap>(
//             vault_utils::parse_key<NaviAccountCap>(0),
//         );
//         let split_to_deposit_balance = principal_balance.split(500_000_000);
//         let mut sui_pool = s.take_shared<Pool<SUI_TEST_COIN>>();
//         let mut incentive_v2 = s.take_shared<IncentiveV2>();
//         let mut incentive_v3 = s.take_shared<IncentiveV3>();
//         incentive_v3::deposit_with_account_cap<SUI_TEST_COIN>(
//             &clock,
//             &mut storage,
//             &mut sui_pool,
//             0,
//             split_to_deposit_balance.into_coin(s.ctx()),
//             &mut incentive_v2,
//             &mut incentive_v3,
//             navi_account_cap,
//         );

//         operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             asset_bag,
//             tx_bag,
//             principal_balance,
//             coin_type_asset_balance,
//         );

//         let navi_account_cap_type = vault_utils::parse_key<NaviAccountCap>(0);
//         navi_adaptor::update_navi_position_value<SUI_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             navi_account_cap_type,
//             &mut storage,
//         );

//         let mock_cetus_asset_type = vault_utils::parse_key<
//             MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
//         >(0);
//         mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             mock_cetus_asset_type,
//         );

//         let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
//             0,
//         );
//         mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &clock,
//             mock_suilend_asset_type,
//         );

//         let receipt_asset_type = vault_utils::parse_key<Receipt>(0);
//         receipt_adaptor::update_receipt_value<SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &usdc_vault,
//             &config,
//             &clock,
//             receipt_asset_type,
//         );

//         vault.update_free_principal_value(&config, &clock);
//         vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

//         // Step 3
//         operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             &clock,
//             tx_bag_for_check_value_update,
//         );

//         // std::debug::print(&std::ascii::string(b"usd value after op"));
//         // std::debug::print(&vault.get_total_usd_value_without_update());

//         s.return_to_sender(cap);
//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(operation);
//         test_scenario::return_shared(config);
//         test_scenario::return_shared(storage);
//         test_scenario::return_shared(usdc_vault);
//         test_scenario::return_shared(sui_pool);
//         test_scenario::return_shared(incentive_v2);
//         test_scenario::return_shared(incentive_v3);
//     };

//     clock.destroy_for_testing();
//     s.end();
// }

// #[test]
// // [TEST-CASE: Should do op with all assets deposit into navi with remove.] @test-case OPERATION-020
// public fun test_start_op_with_all_assets_deposit_into_navi_remove_not_borrow() {
//     let mut s = test_scenario::begin(OWNER);

//     let mut clock = clock::create_for_testing(s.ctx());

//     init_vault::init_vault(&mut s, &mut clock);
//     init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
//     init_vault::init_create_vault<USDC_TEST_COIN>(&mut s);
//     init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
//     init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

//     s.next_tx(OWNER);
//     {
//         let mut oracle_config = s.take_shared<OracleConfig>();

//         test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);
//         let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
//         test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

//         test_scenario::return_shared(oracle_config);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<USDC_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();
//         let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000, s.ctx());
//         vault.return_free_principal(coin.into_balance());
//         vault.update_free_principal_value(&config, &clock);

//         vault.set_total_shares(1_000_000_000);
//         let receipt = receipt::create_receipt(vault.vault_id(), s.ctx());
//         let mut vault_receipt_info = vault_receipt_info::new_vault_receipt_info(
//             table::new(s.ctx()),
//             table::new(s.ctx()),
//         );
//         vault_receipt_info.add_share(1_000_000_000);
//         vault.set_vault_receipt_info(receipt.receipt_id(), vault_receipt_info);

//         transfer::public_transfer(receipt, OWNER);

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let receipt = s.take_from_sender<Receipt>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let usdc_vault = s.take_shared<Vault<USDC_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         let receipt_asset_type = vault_utils::parse_key<Receipt>(0);
//         vault.add_new_defi_asset(
//             0,
//             receipt,
//         );
//         receipt_adaptor::update_receipt_value<SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &usdc_vault,
//             &config,
//             &clock,
//             receipt_asset_type,
//         );

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(usdc_vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         vault.return_free_principal(coin.into_balance());
//         vault.update_free_principal_value(&config, &clock);

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let operator_cap = s.take_from_sender<OperatorCap>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
//         // Add 100 USDC to the vault
//         vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
//         vault.return_coin_type_asset(coin.into_balance());
//         vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//         s.return_to_sender(operator_cap);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();
//         let mut storage = s.take_shared<Storage>();

//         let navi_account_cap = lending::create_account(s.ctx());
//         vault.add_new_defi_asset(
//             0,
//             navi_account_cap,
//         );

//         let navi_account_cap_type = vault_utils::parse_key<NaviAccountCap>(0);
//         navi_adaptor::update_navi_position_value<SUI_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             navi_account_cap_type,
//             &mut storage,
//         );

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//         test_scenario::return_shared(storage);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let config = s.take_shared<OracleConfig>();

//         let mut mock_cetus_position = mock_cetus::create_mock_position<
//             SUI_TEST_COIN,
//             USDC_TEST_COIN,
//         >(s.ctx());
//         mock_cetus::set_token_amount(&mut mock_cetus_position, 1_000_000_000, 1_000_000_000);

//         vault.add_new_defi_asset(
//             0,
//             mock_cetus_position,
//         );

//         let mock_cetus_asset_type = vault_utils::parse_key<
//             MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
//         >(0);
//         mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             mock_cetus_asset_type,
//         );

//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(config);
//     };

//     s.next_tx(OWNER);
//     {
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

//         let mock_suilend_position = mock_suilend::create_mock_obligation<SUI_TEST_COIN>(
//             s.ctx(),
//             1_000_000_000,
//         );

//         vault.add_new_defi_asset(
//             0,
//             mock_suilend_position,
//         );

//         let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
//             0,
//         );
//         mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &clock,
//             mock_suilend_asset_type,
//         );

//         test_scenario::return_shared(vault);
//     };

//     s.next_tx(OWNER);
//     {
//         let operation = s.take_shared<Operation>();
//         let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
//         let usdc_vault = s.take_shared<Vault<USDC_TEST_COIN>>();
//         let cap = s.take_from_sender<OperatorCap>();
//         let config = s.take_shared<OracleConfig>();
//         let mut storage = s.take_shared<Storage>();

//         let defi_asset_ids = vector[0, 0, 0, 0];
//         let defi_asset_types = vector[
//             type_name::with_defining_ids<NaviAccountCap>(),
//             type_name::with_defining_ids<MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>>(),
//             type_name::with_defining_ids<MockSuilendObligation<SUI_TEST_COIN>>(),
//             type_name::with_defining_ids<Receipt>(),
//         ];

//         let (
//             mut asset_bag,
//             tx_bag,
//             tx_bag_for_check_value_update,
//             mut principal_balance,
//             coin_type_asset_balance,
//         ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             &clock,
//             defi_asset_ids,
//             defi_asset_types,
//             1_000_000_000,
//             1_000_000_000,
//             s.ctx(),
//         );

//         let navi_account_cap = asset_bag.remove<String, NaviAccountCap>(
//             vault_utils::parse_key<NaviAccountCap>(0),
//         );
//         let split_to_deposit_balance = principal_balance.split(500_000_000);
//         let mut sui_pool = s.take_shared<Pool<SUI_TEST_COIN>>();
//         let mut incentive_v2 = s.take_shared<IncentiveV2>();
//         let mut incentive_v3 = s.take_shared<IncentiveV3>();
//         incentive_v3::deposit_with_account_cap<SUI_TEST_COIN>(
//             &clock,
//             &mut storage,
//             &mut sui_pool,
//             0,
//             split_to_deposit_balance.into_coin(s.ctx()),
//             &mut incentive_v2,
//             &mut incentive_v3,
//             &navi_account_cap,
//         );

//         asset_bag.add<String, NaviAccountCap>(
//             vault_utils::parse_key<NaviAccountCap>(0),
//             navi_account_cap,
//         );

//         operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             asset_bag,
//             tx_bag,
//             principal_balance,
//             coin_type_asset_balance,
//         );

//         let navi_account_cap_type = vault_utils::parse_key<NaviAccountCap>(0);
//         navi_adaptor::update_navi_position_value<SUI_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             navi_account_cap_type,
//             &mut storage,
//         );

//         let mock_cetus_asset_type = vault_utils::parse_key<
//             MockCetusPosition<SUI_TEST_COIN, USDC_TEST_COIN>,
//         >(0);
//         mock_cetus::update_mock_cetus_position_value<SUI_TEST_COIN, SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &config,
//             &clock,
//             mock_cetus_asset_type,
//         );

//         let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
//             0,
//         );
//         mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &clock,
//             mock_suilend_asset_type,
//         );

//         let receipt_asset_type = vault_utils::parse_key<Receipt>(0);
//         receipt_adaptor::update_receipt_value<SUI_TEST_COIN, USDC_TEST_COIN>(
//             &mut vault,
//             &usdc_vault,
//             &config,
//             &clock,
//             receipt_asset_type,
//         );

//         vault.update_free_principal_value(&config, &clock);
//         vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

//         // Step 3
//         operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, SUI_TEST_COIN>(
//             &mut vault,
//             &operation,
//             &cap,
//             &clock,
//             tx_bag_for_check_value_update,
//         );

//         // std::debug::print(&std::ascii::string(b"usd value after op"));
//         // std::debug::print(&vault.get_total_usd_value_without_update());

//         s.return_to_sender(cap);
//         test_scenario::return_shared(vault);
//         test_scenario::return_shared(operation);
//         test_scenario::return_shared(config);
//         test_scenario::return_shared(storage);
//         test_scenario::return_shared(usdc_vault);
//         test_scenario::return_shared(sui_pool);
//         test_scenario::return_shared(incentive_v2);
//         test_scenario::return_shared(incentive_v3);
//     };

//     clock.destroy_for_testing();
//     s.end();
// }

#[test]
// [TEST-CASE: Should do op and add new defi asset during operation.] @test-case OPERATION-021
public fun test_start_op_with_add_new_defi_asset_during_operation() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        let mock_suilend_position = mock_suilend::create_mock_obligation<SUI_TEST_COIN>(
            s.ctx(),
            1_000_000_000,
        );

        vault.add_new_defi_asset(
            0,
            mock_suilend_position,
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        let mock_suilend_asset_type = vault_utils::parse_key<MockSuilendObligation<SUI_TEST_COIN>>(
            0,
        );
        mock_suilend::update_mock_suilend_position_value<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            mock_suilend_asset_type,
        );

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_VAULT_DURING_OPERATION, location = vault)]
// [TEST-CASE: Should set vault disabled fail if vault is during operation.] @test-case OPERATION-022
public fun test_start_op_and_set_vault_enabled_fail_vault_during_operation() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        let admin_cap = s.take_from_sender<AdminCap>();
        vault_manage::set_vault_enabled(&admin_cap, &mut vault, false);

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = vault::ERR_OP_VALUE_UPDATE_NOT_ENABLED, location = vault)]
// [TEST-CASE: Should check op value update fail before end op.] @test-case OPERATION-023
public fun test_start_op_check_op_value_update_fail_before_end_op() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        vault.check_op_value_update_record();

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        let op_value_update_record = vault.op_value_update_record();
        assert!(op_value_update_record.op_value_update_record_value_update_enabled());

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = operation::ERR_VAULT_ID_MISMATCH, location = operation)]
public fun test_end_op_fail_with_wrong_vault() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_vault<USDC_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);
    init_vault::init_single_operator_config_for_owner<USDC_TEST_COIN>(&mut s, false);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        principal_balance.destroy_for_testing();

        // Step 2
        let mut usdc_vault = s.take_shared<Vault<USDC_TEST_COIN>>();
        usdc_vault.set_status(1);
        let wrong_principal_coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        operation::end_op_with_bag_v2<USDC_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut usdc_vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            wrong_principal_coin.into_balance(),
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        operation::end_op_value_update_with_bag_v2<SUI_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
        test_scenario::return_shared(usdc_vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = operation::ERR_VAULT_ID_MISMATCH, location = operation)]
public fun test_end_op_value_update_fail_with_wrong_vault() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_vault<USDC_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);
    init_vault::init_single_operator_config_for_owner<USDC_TEST_COIN>(&mut s, false);

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

    // Set mock aggregator and price
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
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.return_free_principal(coin.into_balance());

        vault::update_free_principal_value(&mut vault, &config, &clock);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(100_000_000_000, s.ctx());
        // Add 100 USDC to the vault
        vault.add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>();
        vault.return_coin_type_asset(coin.into_balance());

        let config = s.take_shared<OracleConfig>();
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let cap = s.take_from_sender<OperatorCap>();
        let config = s.take_shared<OracleConfig>();
        let mut storage = s.take_shared<Storage>();

        let defi_asset_ids = vector[0];
        let defi_asset_types = vector[type_name::with_defining_ids<NaviAccountCap>()];

        let (
            asset_bag,
            tx_bag,
            tx_bag_for_check_value_update,
            principal_balance,
            coin_type_asset_balance,
        ) = operation::start_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            defi_asset_ids,
            defi_asset_types,
            1_000_000_000,
            0,
            s.ctx(),
        );

        // Step 2
        operation::end_op_with_bag_v2<SUI_TEST_COIN, USDC_TEST_COIN, NaviAccountCap>(
            &mut vault,
            &operation,
            &cap,
            asset_bag,
            tx_bag,
            principal_balance,
            coin_type_asset_balance,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        navi_adaptor::update_navi_position_value(
            &mut vault,
            &config,
            &clock,
            navi_asset_type,
            &mut storage,
        );

        vault.update_free_principal_value(&config, &clock);
        vault.update_coin_type_asset_value<SUI_TEST_COIN, USDC_TEST_COIN>(&config, &clock);

        // Step 3
        let mut usdc_vault = s.take_shared<Vault<USDC_TEST_COIN>>();
        usdc_vault.set_status(1);
        operation::end_op_value_update_with_bag_v2<USDC_TEST_COIN, NaviAccountCap>(
            &mut usdc_vault,
            &operation,
            &cap,
            &clock,
            tx_bag_for_check_value_update,
        );

        s.return_to_sender(cap);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        test_scenario::return_shared(config);
        test_scenario::return_shared(storage);
        test_scenario::return_shared(usdc_vault);
    };

    clock.destroy_for_testing();
    s.end();
}
