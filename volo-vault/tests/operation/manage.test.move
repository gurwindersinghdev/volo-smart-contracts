#[test_only]
module volo_vault::vault_manage_test;

use std::type_name;
use sui::clock;
use sui::coin;
use sui::test_scenario;
use volo_vault::curator_position::{Self, CuratorConfig};
use volo_vault::init_vault;
use volo_vault::manager_cap::ManagerCap;
use volo_vault::receipt::Receipt;
use volo_vault::reward_manager::RewardManager;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::test_helpers;
use volo_vault::user_entry;
use volo_vault::vault::{Self, Vault, OperatorCap, AdminCap, Operation};
use volo_vault::vault_manage;
use volo_vault::vault_oracle::{Self, OracleConfig};
use volo_vault::curator_position::CuratorCap;

const OWNER: address = @0xa;
const ALICE: address = @0xb;
// const BOB: address = @0xc;

const MOCK_AGGREGATOR_SUI: address = @0xd;
// const MOCK_AGGREGATOR_USDC: address = @0xe;
// const MOCK_AGGREGATOR_BTC: address = @0xf;

const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000; // 18 decimals

const VAULT_NORMAL_STATUS: u8 = 0;
// const VAULT_DURING_OPERATION_STATUS: u8 = 1;
const VAULT_DISABLED_STATUS: u8 = 2;

#[test]
// [TEST-CASE: Should enable/disable vault.] @test-case MANAGE-001
public fun test_set_vault_enabled() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        assert!(vault.status() == VAULT_NORMAL_STATUS);

        vault_manage::set_vault_enabled(&admin_cap, &mut vault, false);
        assert!(vault.status() == VAULT_DISABLED_STATUS);

        vault_manage::set_vault_enabled(&admin_cap, &mut vault, true);
        assert!(vault.status() == VAULT_NORMAL_STATUS);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should retrieve deposit fee from vault.] @test-case MANAGE-002
public fun test_set_and_retrieve_deposit_fee_from_manage() {
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

        // Set SUI price to 2
        vault_oracle::set_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type,
            9,
            MOCK_AGGREGATOR_SUI,
        );

        clock::set_for_testing(&mut clock, 1000);
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
        let admin_cap = s.take_from_sender<AdminCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault_manage::set_deposit_fee(&admin_cap, &mut vault, 100);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        // deposit 1 SUI, (2U)
        // expected shares = 2e18
        let expected_shares = 1_980_000_000;

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            expected_shares,
            option::none(),
            &clock,
            s.ctx(),
        );
        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Check total usd value before execute deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.update_free_principal_value(&config, &clock);

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 0);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Execute deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        vault.execute_deposit(
            &clock,
            &config,
            0,
            2_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Check deposit fee (0.001 SUI)
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let deposit_fee = vault.deposit_withdraw_fee_collected();
        assert!(deposit_fee == 10_000_000);
        test_scenario::return_shared(vault);
    };

    // Check total usd value after execute deposit
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 1_980_000_000);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();
        // let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let fee_retrieved = vault_manage::retrieve_deposit_withdraw_fee(
            &admin_cap,
            &mut vault,
            2_000_000,
        );
        assert!(fee_retrieved.value() == 2_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
        fee_retrieved.destroy_for_testing();
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let deposit_fee = vault.deposit_withdraw_fee_collected();
        assert!(deposit_fee == 8_000_000);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();
        // let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let fee_retrieved = vault_manage::retrieve_deposit_withdraw_fee(
            &admin_cap,
            &mut vault,
            8_000_000,
        );
        assert!(fee_retrieved.value() == 8_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
        fee_retrieved.destroy_for_testing();
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let deposit_fee = vault.deposit_withdraw_fee_collected();
        assert!(deposit_fee == 0);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
public fun test_set_and_retrieve_deposit_fee_from_manage_operator() {
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

        // Set SUI price to 2
        vault_oracle::set_aggregator(
            &mut oracle_config,
            &clock,
            sui_asset_type,
            9,
            MOCK_AGGREGATOR_SUI,
        );

        clock::set_for_testing(&mut clock, 1000);
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
        let admin_cap = s.take_from_sender<AdminCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault_manage::set_deposit_fee(&admin_cap, &mut vault, 100);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        // deposit 1 SUI, (2U)
        // expected shares = 2e18
        let expected_shares = 1_980_000_000;

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            expected_shares,
            option::none(),
            &clock,
            s.ctx(),
        );
        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Check total usd value before execute deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault.update_free_principal_value(&config, &clock);

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 0);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Execute deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        vault.execute_deposit(
            &clock,
            &config,
            0,
            2_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Check deposit fee (0.001 SUI)
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let deposit_fee = vault.deposit_withdraw_fee_collected();
        assert!(deposit_fee == 10_000_000);
        test_scenario::return_shared(vault);
    };

    // Check total usd value after execute deposit
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 1_980_000_000);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        // let admin_cap = s.take_from_sender<AdminCap>();
        let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let fee_retrieved = vault_manage::retrieve_deposit_withdraw_fee_operator(
            &operator_cap,
            &mut vault,
            2_000_000,
        );
        // ! (v1.1 upgrade - this function is deprecated)
        // assert!(fee_retrieved.value() == 2_000_000);
        assert!(fee_retrieved.value() == 0);

        test_scenario::return_shared(vault);
        s.return_to_sender(operator_cap);
        fee_retrieved.destroy_for_testing();
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let deposit_fee = vault.deposit_withdraw_fee_collected();
        assert!(deposit_fee == 10_000_000);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        // let admin_cap = s.take_from_sender<AdminCap>();
        let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let fee_retrieved = vault_manage::retrieve_deposit_withdraw_fee_operator(
            &operator_cap,
            &mut vault,
            8_000_000,
        );
        assert!(fee_retrieved.value() == 0);

        test_scenario::return_shared(vault);
        s.return_to_sender(operator_cap);
        fee_retrieved.destroy_for_testing();
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let deposit_fee = vault.deposit_withdraw_fee_collected();
        assert!(deposit_fee == 10_000_000);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}
#[test]
// [TEST-CASE: Should retrieve withdraw fee from vault.] @test-case MANAGE-003
public fun test_set_and_retrieve_withdraw_fee_from_manage() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::set_withdraw_fee(&admin_cap, &mut vault, 100);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    // Set mock aggregator and price
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);

        clock::set_for_testing(&mut clock, 1000);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        // deposit 1 SUI, (2U)
        // expected shares = 2e18
        let expected_shares = 2_000_000_000;

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            expected_shares,
            option::none(),
            &clock,
            s.ctx(),
        );
        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Execute deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let config = s.take_shared<OracleConfig>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        vault.execute_deposit(
            &clock,
            &config,
            0,
            2_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Request withdraw
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();
        let mut config = s.take_shared<OracleConfig>();

        clock::set_for_testing(&mut clock, 1000 + 12 * 3600_000);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut config, prices);

        vault.update_free_principal_value(&config, &clock);

        user_entry::withdraw(
            &mut vault,
            1_000_000_000,
            500_000_000,
            &mut receipt,
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        s.return_to_sender(receipt);
    };

    // Execute withdraw
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let (withdraw_balance, _recipient) = vault.execute_withdraw(
            &clock,
            &config,
            0,
            500_000_000,
        );
        transfer::public_transfer(withdraw_balance.into_coin(s.ctx()), _recipient);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Check total usd value after execute withdraw
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 1_000_000_000);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Check withdraw fee (0.0005 SUI)
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let withdraw_fee = vault.deposit_withdraw_fee_collected();
        assert!(withdraw_fee == 5_000_000);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();
        // let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let fee_retrieved = vault_manage::retrieve_deposit_withdraw_fee(
            &admin_cap,
            &mut vault,
            5_000_000,
        );
        assert!(fee_retrieved.value() == 5_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
        fee_retrieved.destroy_for_testing();
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let withdraw_fee = vault.deposit_withdraw_fee_collected();
        assert!(withdraw_fee == 0);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();
        // let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let fee_retrieved = vault_manage::retrieve_deposit_withdraw_fee(
            &admin_cap,
            &mut vault,
            0,
        );
        assert!(fee_retrieved.value() == 0);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
        fee_retrieved.destroy_for_testing();
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should retrieve withdraw fee from vault.] @test-case MANAGE-003
public fun test_set_and_retrieve_withdraw_fee_from_manage_operator() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::set_withdraw_fee(&admin_cap, &mut vault, 100);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    // Set mock aggregator and price
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);

        clock::set_for_testing(&mut clock, 1000);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        // deposit 1 SUI, (2U)
        // expected shares = 2e18
        let expected_shares = 2_000_000_000;

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            expected_shares,
            option::none(),
            &clock,
            s.ctx(),
        );
        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Execute deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let config = s.take_shared<OracleConfig>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        vault.execute_deposit(
            &clock,
            &config,
            0,
            2_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Request withdraw
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();
        let mut config = s.take_shared<OracleConfig>();

        clock::set_for_testing(&mut clock, 1000 + 12 * 3600_000);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut config, prices);

        vault.update_free_principal_value(&config, &clock);

        user_entry::withdraw(
            &mut vault,
            1_000_000_000,
            500_000_000,
            &mut receipt,
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        s.return_to_sender(receipt);
    };

    // Execute withdraw
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let (withdraw_balance, _recipient) = vault.execute_withdraw(
            &clock,
            &config,
            0,
            500_000_000,
        );
        transfer::public_transfer(withdraw_balance.into_coin(s.ctx()), _recipient);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Check total usd value after execute withdraw
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 1_000_000_000);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Check withdraw fee (0.0005 SUI)
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let withdraw_fee = vault.deposit_withdraw_fee_collected();
        assert!(withdraw_fee == 5_000_000);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        // let admin_cap = s.take_from_sender<AdminCap>();
        let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let fee_retrieved = vault_manage::retrieve_deposit_withdraw_fee_operator(
            &operator_cap,
            &mut vault,
            5_000_000,
        );
        // ! (v1.1 upgrade - this function is deprecated)
        // assert!(fee_retrieved.value() == 5_000_000);
        assert!(fee_retrieved.value() == 0);

        test_scenario::return_shared(vault);
        s.return_to_sender(operator_cap);
        fee_retrieved.destroy_for_testing();
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let withdraw_fee = vault.deposit_withdraw_fee_collected();
        assert!(withdraw_fee == 5_000_000);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let fee_retrieved = vault_manage::retrieve_deposit_withdraw_fee_operator(
            &operator_cap,
            &mut vault,
            0,
        );
        assert!(fee_retrieved.value() == 0);

        test_scenario::return_shared(vault);
        s.return_to_sender(operator_cap);
        fee_retrieved.destroy_for_testing();
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should create operator cap.] @test-case MANAGE-004
public fun test_create_operator_cap_from_manage() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();

        let operator_cap = vault_manage::create_operator_cap(&admin_cap, s.ctx());

        transfer::public_transfer(operator_cap, OWNER);
        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should freeze/unfreeze operator cap.] @test-case MANAGE-005
public fun test_set_operator_cap_freezed_from_manage() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();
        let operator_cap = vault_manage::create_operator_cap(&admin_cap, s.ctx());

        transfer::public_transfer(operator_cap, OWNER);
        s.return_to_sender(admin_cap);
    };

    s.next_tx(OWNER);
    {
        let mut operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::set_operator_freezed(
            &admin_cap,
            &mut operation,
            operator_cap.operator_id(),
            true,
        );

        assert!(vault::operator_freezed(&operation, operator_cap.operator_id()));

        vault_manage::set_operator_freezed(
            &admin_cap,
            &mut operation,
            operator_cap.operator_id(),
            false,
        );

        assert!(!vault::operator_freezed(&operation, operator_cap.operator_id()));

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should set loss tolerance.] @test-case MANAGE-006
public fun test_set_loss_tolerance_from_manage() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::set_loss_tolerance(&admin_cap, &mut vault, 100);

        assert!(vault.loss_tolerance() == 100);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should set deposit fee.] @test-case MANAGE-007
public fun test_set_deposit_fee_from_manage() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::set_deposit_fee(&admin_cap, &mut vault, 100);
        assert!(vault.deposit_fee_rate() == 100);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_EXCEED_LIMIT, location = vault)]
// [TEST-CASE: Should set deposit fee fail if deposit fee too high.] @test-case MANAGE-008
public fun test_set_deposit_fee_fail_exceed_limit() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::set_deposit_fee(&admin_cap, &mut vault, 500);
        assert!(vault.deposit_fee_rate() == 500);

        vault_manage::set_deposit_fee(&admin_cap, &mut vault, 600);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should set withdraw fee.] @test-case MANAGE-009
public fun test_set_withdraw_fee_from_manage() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::set_withdraw_fee(&admin_cap, &mut vault, 100);
        assert!(vault.withdraw_fee_rate() == 100);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_EXCEED_LIMIT, location = vault)]
// [TEST-CASE: Should set withdraw fee fail if withdraw fee too high.] @test-case MANAGE-010
public fun test_set_withdraw_fee_fail_exceed_limit() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::set_withdraw_fee(&admin_cap, &mut vault, 500);
        assert!(vault.withdraw_fee_rate() == 500);

        vault_manage::set_withdraw_fee(&admin_cap, &mut vault, 600);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should set oracle update interval.] @test-case MANAGE-011
public fun test_set_oracle_update_interval() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        vault_manage::set_update_interval(&admin_cap, &mut oracle_config, 6000);
        assert!(oracle_config.update_interval() == 6000);

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
public fun test_set_dex_slippage() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();
        let mut oracle_config = s.take_shared<OracleConfig>();

        vault_manage::set_dex_slippage(&admin_cap, &mut oracle_config, 200);
        assert!(oracle_config.dex_slippage() == 200);

        test_scenario::return_shared(oracle_config);
        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
public fun test_set_and_retrieve_withdraw_fee_by_single_operator() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let admin_cap = s.take_from_sender<AdminCap>();

        vault_manage::set_withdraw_fee(&admin_cap, &mut vault, 100);

        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    // Set mock aggregator and price
    s.next_tx(OWNER);
    {
        let mut oracle_config = s.take_shared<OracleConfig>();

        test_helpers::set_aggregators(&mut s, &mut clock, &mut oracle_config);

        clock::set_for_testing(&mut clock, 1000);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        // deposit 1 SUI, (2U)
        // expected shares = 2e18
        let expected_shares = 2_000_000_000;

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            expected_shares,
            option::none(),
            &clock,
            s.ctx(),
        );
        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Execute deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let config = s.take_shared<OracleConfig>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        vault.execute_deposit(
            &clock,
            &config,
            0,
            2_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Request withdraw
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();
        let mut config = s.take_shared<OracleConfig>();

        clock::set_for_testing(&mut clock, 1000 + 12 * 3600_000);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut config, prices);

        vault.update_free_principal_value(&config, &clock);

        user_entry::withdraw(
            &mut vault,
            1_000_000_000,
            500_000_000,
            &mut receipt,
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        s.return_to_sender(receipt);
    };

    // Execute withdraw
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let (withdraw_balance, _recipient) = vault.execute_withdraw(
            &clock,
            &config,
            0,
            500_000_000,
        );
        transfer::public_transfer(withdraw_balance.into_coin(s.ctx()), _recipient);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Check total usd value after execute withdraw
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 1_000_000_000);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Check withdraw fee (0.0005 SUI)
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let withdraw_fee = vault.deposit_withdraw_fee_collected();
        assert!(withdraw_fee == 5_000_000);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let fee_retrieved = vault_manage::retrieve_deposit_withdraw_fee_by_operator(
            &operation,
            &operator_cap,
            &mut vault,
            5_000_000,
        );
        assert!(fee_retrieved.value() == 5_000_000);

        test_scenario::return_shared(operation);
        test_scenario::return_shared(vault);
        s.return_to_sender(operator_cap);
        fee_retrieved.destroy_for_testing();
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let withdraw_fee = vault.deposit_withdraw_fee_collected();
        assert!(withdraw_fee == 0);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let fee_retrieved = vault_manage::retrieve_deposit_withdraw_fee_by_operator(
            &operation,
            &operator_cap,
            &mut vault,
            0,
        );
        assert!(fee_retrieved.value() == 0);

        test_scenario::return_shared(operation);
        test_scenario::return_shared(vault);
        s.return_to_sender(operator_cap);
        fee_retrieved.destroy_for_testing();
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
public fun test_add_curator_from_manage() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    curator_position::init_for_testing(s.ctx());
    init_vault::init_create_curator_cap(ALICE, &mut s);

    s.next_tx(OWNER);
    {
        let mut curator_config = s.take_shared<CuratorConfig>();
        let admin_cap = s.take_from_sender<AdminCap>();

        let curator_cap = s.take_from_sender<CuratorCap>();

        vault_manage::add_curator_cap(
            &admin_cap,
            &mut curator_config,
            curator_cap.curator_cap_id(),
        );

        transfer::public_transfer(curator_cap, ALICE);

        test_scenario::return_shared(curator_config);
        s.return_to_sender(admin_cap);
    };

    s.next_tx(ALICE);
    {
        let curator_config = s.take_shared<CuratorConfig>();
        let curator_cap = s.take_from_sender<CuratorCap>();
        let curator_cap_id = curator_cap.curator_cap_id();

        let is_valid_curator = curator_config.is_valid_curator_cap(
            curator_cap_id,
        );
        assert!(is_valid_curator);

        test_scenario::return_shared(curator_config);
        s.return_to_sender(curator_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
public fun test_remove_curator_from_manage() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    curator_position::init_for_testing(s.ctx());
    init_vault::init_create_curator_cap(ALICE, &mut s);

    s.next_tx(OWNER);
    {
        let mut curator_config = s.take_shared<CuratorConfig>();
        let admin_cap = s.take_from_sender<AdminCap>();
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let curator_cap = s.take_from_sender<CuratorCap>();
        let curator_cap_id = curator_cap.curator_cap_id();

        curator_config.create_curator_position_with_auto_transfer(
            &admin_cap,
            curator_cap,
            &vault,
            s.ctx(),
        );

        curator_config.add_curator_cap(
            curator_cap_id
        );

        test_scenario::return_shared(curator_config);
        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    s.next_tx(ALICE);
    {
        let curator_config = s.take_shared<CuratorConfig>();
        let curator_cap = s.take_from_sender<CuratorCap>();
        let curator_cap_id = curator_cap.curator_cap_id();

        let is_valid_curator = curator_config.is_valid_curator_cap (
            curator_cap_id,
        );
        assert!(is_valid_curator);

        test_scenario::return_shared(curator_config);
        s.return_to_sender(curator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut curator_config = s.take_shared<CuratorConfig>();
        let admin_cap = s.take_from_sender<AdminCap>();

        let alice_curator_cap = s.take_from_address<CuratorCap>(ALICE);
        let alice_curator_cap_id = alice_curator_cap.curator_cap_id();

        vault_manage::remove_curator_cap(
            &admin_cap,
            &mut curator_config,
            alice_curator_cap_id,
        );

        test_scenario::return_shared(curator_config);
        s.return_to_sender(admin_cap);
        test_scenario::return_to_address(ALICE, alice_curator_cap);
    };

    s.next_tx(ALICE);
    {
        let curator_config = s.take_shared<CuratorConfig>();
        let is_valid_curator = curator_config.is_valid_curator_cap(
            ALICE,
        );
        assert!(!is_valid_curator);

        test_scenario::return_shared(curator_config);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
public fun test_add_manager_cap() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();

        let manager_cap = vault_manage::create_manager_cap(&admin_cap, s.ctx());
        transfer::public_transfer(manager_cap, OWNER);

        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
public fun test_set_parameters_by_manager_cap() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();

        let manager_cap = vault_manage::create_manager_cap(&admin_cap, s.ctx());
        transfer::public_transfer(manager_cap, OWNER);

        s.return_to_sender(admin_cap);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let manager_cap = s.take_from_sender<ManagerCap>();

        vault_manage::set_parameters_by_manager(&manager_cap, &mut vault, 0, 0, 0, 0, 0);

        test_scenario::return_shared(vault);
        s.return_to_sender(manager_cap);
    };

    clock.destroy_for_testing();
    s.end();
}
