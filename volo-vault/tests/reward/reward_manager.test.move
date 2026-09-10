#[test_only]
module volo_vault::reward_manager_test;

use lending_core::lending;
use std::type_name;
use sui::clock;
use sui::coin;
use sui::test_scenario;
use volo_vault::init_vault;
use volo_vault::operation;
use volo_vault::receipt::{Self, Receipt};
use volo_vault::reward_manager::{Self, RewardManager};
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::test_helpers;
use volo_vault::usdc_test_coin::USDC_TEST_COIN;
use volo_vault::user_entry;
use volo_vault::vault::{Self, Operation, OperatorCap, Vault, AdminCap};
use volo_vault::vault_manage;
use volo_vault::vault_oracle::OracleConfig;

const OWNER: address = @0xa;
const ALICE: address = @0xb;

const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000;
const WAD: u256 = 1_000_000_000_000_000_000;
const BASE_RATE: u256 = 1_000_000_000;

#[test]
// [TEST-CASE: Should create reward manager.] @test-case REWARD-001
public fun test_create_reward_manager() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(
            0,
            navi_account_cap,
        );
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let admin_cap = s.take_from_sender<AdminCap>();
        vault_manage::create_reward_manager<SUI_TEST_COIN>(&admin_cap, &mut vault, s.ctx());
        test_scenario::return_shared(vault);
        s.return_to_sender(admin_cap);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(reward_manager.vault_id() == vault.vault_id());
        assert!(vault.reward_manager_id() == object::id_address(&reward_manager));

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_REWARD_MANAGER_ALREADY_SET, location = vault)]
// [TEST-CASE: Should create reward manager fail if already exists.] @test-case REWARD-002
public fun test_create_reward_manager_fail_already_exists() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_account_cap = lending::create_account(s.ctx());
        vault.add_new_defi_asset(
            0,
            navi_account_cap,
        );
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        reward_manager::create_reward_manager<SUI_TEST_COIN>(&mut vault, s.ctx());
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        reward_manager::create_reward_manager<SUI_TEST_COIN>(&mut vault, s.ctx());
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = 0x1)]
// [TEST-CASE: Should add new reward type with buffer.] @test-case REWARD-003
public fun test_add_new_reward_type_without_buffer() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            false,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 0);
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);
        assert!(reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 0,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 0,
        );

        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should add new reward type with buffer.] @test-case REWARD-004
public fun test_add_new_reward_type_with_buffer() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 0);
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 0,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 0,
        );

        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should add new reward buffer distribution.] @test-case REWARD-005
public fun test_create_reward_buffer_distribution() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            false,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.create_reward_buffer_distribution<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 0,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 0,
        );

        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = reward_manager::ERR_REWARD_BUFFER_TYPE_EXISTS)]
// [TEST-CASE: Should add new reward buffer distribution fail if already exists.] @test-case REWARD-006
public fun test_create_reward_buffer_distribution_fail_already_exists() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.create_reward_buffer_distribution<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
        );

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should add reward balance.] @test-case REWARD-007
public fun test_add_reward_balance() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(
            reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 1_000_000_000 * BASE_RATE,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        // std::debug::print(&reward_indices);
        assert!(
            reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 1_000_000_000_000_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 2_000_000_000,
        );
        assert!(
            reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 2_000_000_000 * BASE_RATE,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(
            reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 2_000_000_000_000_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should add reward balance with big TVL.] @test-case REWARD-008
public fun test_add_reward_balance_with_big_tvl() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(
            reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 1_000_000_000 * BASE_RATE,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        // std::debug::print(&reward_indices);
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 1_000_000_000 * BASE_RATE);

        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 2_000_000_000,
        );
        assert!(
            reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 2_000_000_000 * BASE_RATE,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 2_000_000_000 * BASE_RATE);

        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = reward_manager::ERR_VAULT_HAS_NO_SHARES, location = reward_manager)]
// [TEST-CASE: Should add reward balance fail if vault has no shares.] @test-case REWARD-009
public fun test_add_reward_balance_fail_no_shares() {
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

        clock::set_for_testing(&mut clock, 1000);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should add reward balance bewteen two deposits.] @test-case REWARD-010
// OWNER deposit 0.5 SUI
// Add reward balance 1 SUI
// ALICE deposit 0.5 SUI
// Check receipt reward indices
public fun test_add_reward_balance_bewteen_two_deposits() {
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

        clock::set_for_testing(&mut clock, 1000);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
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
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            0,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(
            reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 1_000_000_000 * BASE_RATE,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(
            reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 1_000_000_000_000_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
    };

    // Request deposit
    s.next_tx(ALICE);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, ALICE);
        transfer::public_transfer(receipt, ALICE);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Execute deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            1,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(
            reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 1_000_000_000 * BASE_RATE,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(
            reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 1_000_000_000_000_000_000 * BASE_RATE,
        );

        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info_mut(receipt.receipt_id());
        let receipt_reward_indices = vault_receipt_info.reward_indices();
        assert!(receipt_reward_indices.borrow(type_name::with_defining_ids<SUI_TEST_COIN>()) == 0);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    s.next_tx(ALICE);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(
            reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 1_000_000_000 * BASE_RATE,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(
            reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 1_000_000_000_000_000_000 * BASE_RATE,
        );

        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info_mut(receipt.receipt_id());
        let receipt_reward_indices = vault_receipt_info.reward_indices();
        assert!(
            receipt_reward_indices.borrow(type_name::with_defining_ids<SUI_TEST_COIN>()) == 1_000_000_000_000_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );
        assert!(reward.value() == 1_000_000_000);
        reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    s.next_tx(ALICE);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );

        assert!(reward.value() == 0);
        reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should add reward to buffer.] @test-case REWARD-011
public fun test_add_reward_to_buffer() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 1_000_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 0,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 0,
        );

        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should set reward rate in buffer.] @test-case REWARD-012
public fun test_set_reward_rate_in_buffer() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 1_000_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 0,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 0,
        );

        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 1_000_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 0,
        );

        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = reward_manager::ERR_INVALID_REWARD_RATE, location = reward_manager)]
// [TEST-CASE: Should set reward rate in buffer fail if rate too high.] @test-case REWARD-013
public fun test_set_reward_rate_in_buffer_fail_rate_too_high() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            std::u256::max_value!() / 86_400_000,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = reward_manager::ERR_REWARD_MANAGER_VAULT_MISMATCH,
        location = reward_manager,
    ),
]
// [TEST-CASE: Should set reward rate in buffer fail if vault mismatch.] @test-case REWARD-014
public fun test_set_reward_rate_in_buffer_fail_vault_mismatch() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut sui_vault_2 = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut sui_vault_2,
            &operation,
            &cap,
            &clock,
            1_000_000_000,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(sui_vault_2);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should update reward buffer distribution.] @test-case REWARD-015
public fun test_update_reward_buffer() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 1_000_000_000_000_000_000,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 1,
        );

        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 2);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 900_000_000_000_000_000,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 2,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 100_000_000 * WAD);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 5);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 600_000_000_000_000_000,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 5,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 400_000_000 * WAD);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should update reward buffer with mock real distribution-1.] @test-case REWARD-016
// 10000 shares, 100SUI reward a day
public fun test_update_reward_buffer_mock_real_distribution_1() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    // 10000 shares, 100U reward
    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(10_000_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(100_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            1157 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    // 1 second later
    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 1001);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        // std::debug::print(&std::ascii::string(b"reward_buffer_amount"));
        // std::debug::print(&reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>());
        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 99_998_843_000 * BASE_RATE,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        // std::debug::print(&std::ascii::string(b"reward_indices"));
        // std::debug::print(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()));
        assert!(
            reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 115_700_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    // 1 hour later, 95.8348 SUI remained, 4.1652 SUI distributed
    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 3_600_000 + 1);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        // std::debug::print(&std::ascii::string(b"reward_buffer_amount"));
        // std::debug::print(&reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>());
        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 95_834_800_000 * BASE_RATE,
        );

        let _reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        // std::debug::print(&std::ascii::string(b"reward_indices"));
        // std::debug::print(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()));
        // assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 100_000_000_000_000_000);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    // 1 day later, 0.0352 SUI remained, 99.9648 SUI distributed
    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 86_400_000 + 1);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        // std::debug::print(&std::ascii::string(b"reward_buffer_amount"));
        // std::debug::print(&reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>());
        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 35_200_000 * BASE_RATE,
        );

        let _reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        // std::debug::print(&std::ascii::string(b"reward_indices"));
        // std::debug::print(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()));
        // assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 100_000_000_000_000_000);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should update reward buffer with mock real distribution-2.] @test-case REWARD-017
// 100M shares, 10k SUI a day
public fun test_update_reward_buffer_mock_real_distribution_2() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    // 10000 shares, 100U reward
    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(100_000_000_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(10_000_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            115700 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    // 1 second later
    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 1001);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        // std::debug::print(&std::ascii::string(b"reward_buffer_amount"));
        // std::debug::print(&reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>());
        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 9_999_884_300_000 * BASE_RATE,
        );

        let _reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        // std::debug::print(&std::ascii::string(b"reward_indices"));
        // std::debug::print(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()));
        // assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 115_700_000_000 * BASE_RATE);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    // 1 hour later, 9583.48 SUI remained, 416.52 SUI distributed
    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 3_600_000 + 1);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        // std::debug::print(&std::ascii::string(b"reward_buffer_amount"));
        // std::debug::print(&reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>());
        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 9_583_480_000_000 * BASE_RATE,
        );

        let _reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        // std::debug::print(&std::ascii::string(b"reward_indices"));
        // std::debug::print(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()));
        // assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 100_000_000_000_000_000);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    // 1 day later, 0.52 SUI remained, 9996.48 SUI distributed
    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 86_400_000 + 1);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        // std::debug::print(&std::ascii::string(b"reward_buffer_amount"));
        // std::debug::print(&reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>());
        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 3_520_000_000 * BASE_RATE,
        );

        let _reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        // std::debug::print(&std::ascii::string(b"reward_indices"));
        // std::debug::print(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()));
        // assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 100_000_000_000_000_000);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = reward_manager::ERR_REWARD_MANAGER_VAULT_MISMATCH,
        location = reward_manager,
    ),
]
// [TEST-CASE: Should update reward buffer fail if vault mismatch.] @test-case REWARD-018
public fun test_update_reward_buffer_fail_vault_mismatch() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut sui_vault_2 = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 2);
        reward_manager.update_reward_buffer(
            &mut sui_vault_2,
            &clock,
            type_name::with_defining_ids<SUI_TEST_COIN>(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(sui_vault_2);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should update reward buffer with no shares.] @test-case REWARD-019
public fun test_update_reward_buffer_with_no_shares() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 1_000_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 1,
        );

        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 2);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 900_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 2,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == WAD * BASE_RATE / 10);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.set_total_shares(0);
        clock::set_for_testing(&mut clock, 3);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 900_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 3,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == WAD * BASE_RATE / 10);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 5);
        vault.set_total_shares(1_000_000_000);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 700_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 5,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == WAD * BASE_RATE * 3 / 10);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = reward_manager::ERR_REWARD_BUFFER_TYPE_NOT_FOUND,
        location = reward_manager,
    ),
]
// [TEST-CASE: Should update reward buffer fail if asset type not added.] @test-case REWARD-020
public fun test_update_reward_buffer_fail_asset_type_not_added() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            false,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should remove reward buffer distribution.] @test-case REWARD-021
public fun test_remove_reward_buffer_distribution() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        reward_manager.remove_reward_buffer_distribution<SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            type_name::with_defining_ids<SUI_TEST_COIN>(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = reward_manager::ERR_REMAINING_REWARD_IN_BUFFER,
        location = reward_manager,
    ),
]
// [TEST-CASE: Should remove reward buffer distribution fail if still reward amount.] @test-case REWARD-022
public fun test_remove_reward_buffer_distribution_fail_still_reward_amount() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        reward_manager.remove_reward_buffer_distribution<SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            type_name::with_defining_ids<SUI_TEST_COIN>(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = reward_manager::ERR_REWARD_MANAGER_VAULT_MISMATCH,
        location = reward_manager,
    ),
]
// [TEST-CASE: Should remove reward buffer distribution fail if vault mismatch.] @test-case REWARD-023
public fun test_remove_reward_buffer_distribution_fail_vault_mismatch() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut sui_vault_2 = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        reward_manager.remove_reward_buffer_distribution<SUI_TEST_COIN>(
            &mut sui_vault_2,
            &operation,
            &cap,
            &clock,
            type_name::with_defining_ids<SUI_TEST_COIN>(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(sui_vault_2);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should retrieve undistributed reward.] @test-case REWARD-024
public fun test_retrieve_undistributed_reward() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 1_000_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 1,
        );

        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 2);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 900_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 2,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == WAD * BASE_RATE / 10);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 5);
        let retrieved_balance = reward_manager.retrieve_undistributed_reward<
            SUI_TEST_COIN,
            SUI_TEST_COIN,
        >(
            &mut vault,
            &operation,
            &cap,
            100_000_000,
            &clock,
        );
        assert!(retrieved_balance.value() == 100_000_000);
        retrieved_balance.destroy_for_testing();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 900_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 500_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 5,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == WAD * BASE_RATE * 4 / 10);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = reward_manager::ERR_REWARD_MANAGER_VAULT_MISMATCH,
        location = reward_manager,
    ),
]
// [TEST-CASE: Should retrieve undistributed reward fail if vault mismatch.] @test-case REWARD-025
public fun test_retrieve_undistributed_reward_fail_vault_mismatch() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 2);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut sui_vault_2 = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 5);
        let retrieved_balance = reward_manager.retrieve_undistributed_reward<
            SUI_TEST_COIN,
            SUI_TEST_COIN,
        >(
            &mut sui_vault_2,
            &operation,
            &cap,
            100_000_000,
            &clock,
        );
        assert!(retrieved_balance.value() == 100_000_000);
        retrieved_balance.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(sui_vault_2);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = reward_manager::ERR_INSUFFICIENT_REWARD_AMOUNT,
        location = reward_manager,
    ),
]
// [TEST-CASE: Should retrieve undistributed reward fail if not enough reward.] @test-case REWARD-026
public fun test_retrieve_undistributed_reward_fail_not_enough_reward() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 5);
        let retrieved_balance = reward_manager.retrieve_undistributed_reward<
            SUI_TEST_COIN,
            SUI_TEST_COIN,
        >(
            &mut vault,
            &operation,
            &cap,
            1_000_000_000,
            &clock,
        );
        retrieved_balance.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should update reward buffers.] @test-case REWARD-027
public fun test_update_reward_buffers() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, USDC_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<USDC_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, USDC_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000 * BASE_RATE,
        );

        reward_manager.set_reward_rate<SUI_TEST_COIN, USDC_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            200_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 1_000_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 1,
        );

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, USDC_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, USDC_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, USDC_TEST_COIN>() == 1_000_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, USDC_TEST_COIN>() == 200_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, USDC_TEST_COIN>() == 1,
        );

        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 2);
        // reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());
        // reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<USDC_TEST_COIN>());
        reward_manager.update_reward_buffers(&mut vault, &clock);

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 900_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 2,
        );

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, USDC_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, USDC_TEST_COIN>() == 0);
        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, USDC_TEST_COIN>() == 800_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, USDC_TEST_COIN>() == 200_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, USDC_TEST_COIN>() == 2,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == WAD * BASE_RATE / 10);
        assert!(reward_indices.get(&type_name::with_defining_ids<USDC_TEST_COIN>()) == WAD * BASE_RATE * 2 / 10);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 5);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<USDC_TEST_COIN>());

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 600_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 5,
        );

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, USDC_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, USDC_TEST_COIN>() == 0);

        assert!(
            reward_manager.reward_buffer_amount<SUI_TEST_COIN, USDC_TEST_COIN>() == 200_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, USDC_TEST_COIN>() == 200_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, USDC_TEST_COIN>() == 5,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == WAD * BASE_RATE * 4 / 10);
        assert!(reward_indices.get(&type_name::with_defining_ids<USDC_TEST_COIN>()) == WAD * BASE_RATE * 8 / 10);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = reward_manager::ERR_REWARD_MANAGER_VAULT_MISMATCH,
        location = reward_manager,
    ),
]
// [TEST-CASE: Should update reward buffers fail if vault mismatch.] @test-case REWARD-028
public fun test_update_reward_buffers_fail_vault_mismatch() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut sui_vault_2 = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 2);
        reward_manager.update_reward_buffers(&mut sui_vault_2, &clock);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(sui_vault_2);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should user claim reward.] @test-case REWARD-029
public fun test_user_claim_reward() {
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

        clock::set_for_testing(&mut clock, 1000);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
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
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);
        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            0,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );

        assert!(reward.value() == 1_000_000_000);
        reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = reward_manager::ERR_WRONG_RECEIPT_STATUS,
        location = reward_manager,
    ),
]
// [TEST-CASE: Should claim reward fail if receipt wrong status.] @test-case REWARD-030
public fun test_user_claim_reward_fail_receipt_wrong_status() {
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

        clock::set_for_testing(&mut clock, 1000);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
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
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            0,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    // Request withdraw
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut config = s.take_shared<OracleConfig>();
        let mut receipt = s.take_from_sender<Receipt>();

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

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );

        assert!(reward.value() == 1_000_000_000);
        reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = reward_manager::ERR_REWARD_MANAGER_VAULT_MISMATCH,
        location = reward_manager,
    ),
]
// [TEST-CASE: Should claim reward fail if vault & receipt mismatch.] @test-case REWARD-031
public fun test_user_claim_reward_fail_vault_receipt_mismatch() {
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

        clock::set_for_testing(&mut clock, 1000);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut sui_vault_2 = s.take_shared<Vault<SUI_TEST_COIN>>();

        let mut receipt = receipt::create_receipt(
            sui_vault_2.vault_id(),
            s.ctx(),
        );

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut sui_vault_2,
            &clock,
            &mut receipt,
        );

        assert!(reward.value() == 1_000_000_000);
        reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(sui_vault_2);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should add reward after already deposited.] @test-case REWARD-032
public fun test_add_reward_balance_after_already_deposited() {
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

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
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
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            0,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 2000);

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );

        assert!(reward.value() == 1_000_000_000);
        reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should distribute reward buffer after already deposited.] @test-case REWARD-033
// User will first deposit some funds and then start to distribute reward buffer.
public fun test_distribute_reward_buffer_after_already_deposited() {
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

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
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
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            0,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 2000);

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            500_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        clock::set_for_testing(&mut clock, 3000);

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );

        assert!(reward.value() == 500_000_000);
        reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should distribute reward buffer with other user execute deposit.] @test-case REWARD-034
public fun test_distribute_reward_buffer_with_other_user_execute_deposit() {
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

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
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
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            0,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 2000);

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(2_000_000_000, s.ctx());
        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            500_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        clock::set_for_testing(&mut clock, 3000);

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );

        assert!(reward.value() == 500_000_000);
        reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    s.next_tx(ALICE);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, ALICE);
        transfer::public_transfer(receipt, ALICE);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Execute deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 4000);

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            1,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );
        // std::debug::print(&reward);
        assert!(reward.value() == 500_000_000);
        reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    s.next_tx(OWNER);
    {
        clock::set_for_testing(&mut clock, 5000);

        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );
        // std::debug::print(&reward);
        assert!(reward.value() == 250_000_000);
        reward.destroy_for_testing();

        let mut alice_receipt = s.take_from_address<Receipt>(ALICE);
        let alice_reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut alice_receipt,
        );
        // std::debug::print(&alice_reward);
        assert!(alice_reward.value() == 250_000_000);
        alice_reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
        test_scenario::return_to_address(ALICE, alice_receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should distribute reward buffer with own execute deposit.] @test-case REWARD-035
public fun test_distribute_reward_buffer_with_own_execute_deposit() {
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

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
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
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            0,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(ALICE);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, ALICE);
        transfer::public_transfer(receipt, ALICE);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Execute deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            1,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 2000);

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            500_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let owner_receipt = s.take_from_address<Receipt>(OWNER);

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::some(owner_receipt),
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
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 3000);

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            2,
            2_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    // 2000 - 3000 50 50  25 25
    // 3000 - 4000 50 150 12.5 37.5
    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        clock::set_for_testing(&mut clock, 4000);

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );
        // std::debug::print(&reward);
        assert!(reward.value() == 625_000_000);
        reward.destroy_for_testing();

        let mut alice_receipt = s.take_from_address<Receipt>(ALICE);
        let alice_reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut alice_receipt,
        );
        // std::debug::print(&alice_reward);
        assert!(alice_reward.value() == 375_000_000);
        alice_reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
        test_scenario::return_to_address(ALICE, alice_receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should distribute reward buffer with own execute withdraw.] @test-case REWARD-036
public fun test_distribute_reward_buffer_with_own_execute_withdraw() {
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

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
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
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            0,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    // Request deposit
    s.next_tx(ALICE);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, ALICE);
        transfer::public_transfer(receipt, ALICE);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Execute deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            1,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 2000);

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(2_000_000_000, s.ctx());
        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            500_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    // Request withdraw
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();
        let mut receipt = s.take_from_sender<Receipt>();

        let admin_cap = s.take_from_sender<AdminCap>();
        vault_manage::set_locking_time_for_withdraw(&admin_cap, &mut vault, 100);

        clock::set_for_testing(&mut clock, 3000);

        vault.update_free_principal_value(&config, &clock);

        user_entry::withdraw(
            &mut vault,
            500_000_000,
            250_000_000,
            &mut receipt,
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        s.return_to_sender(receipt);
        s.return_to_sender(admin_cap);
    };

    // Execute withdraw
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        operation::execute_withdraw(
            &operation,
            &operator_cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            0,
            250_000_000,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    // 2000 - 3000 OWNER 50 ALICE 50   25 25
    // 3000 - 4000 OWNER 25 ALICE 50   16 33

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );
        // std::debug::print(&reward.value());
        assert!(reward.value() == 250_000_000);
        reward.destroy_for_testing();

        let mut alice_receipt = s.take_from_address<Receipt>(ALICE);
        let alice_reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut alice_receipt,
        );
        // std::debug::print(&alice_reward.value());
        assert!(alice_reward.value() == 250_000_000);
        alice_reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
        test_scenario::return_to_address(ALICE, alice_receipt);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        clock::set_for_testing(&mut clock, 4000);

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );
        // std::debug::print(&reward.value());
        assert!(reward.value() == 166_666_666);
        reward.destroy_for_testing();

        let mut alice_receipt = s.take_from_address<Receipt>(ALICE);
        let alice_reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut alice_receipt,
        );
        // std::debug::print(&alice_reward.value());
        assert!(alice_reward.value() == 333_333_333);
        alice_reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
        test_scenario::return_to_address(ALICE, alice_receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[
    expected_failure(
        abort_code = reward_manager::ERR_REWARD_TYPE_NOT_FOUND,
        location = reward_manager,
    ),
]
// [TEST-CASE: Should update reward indices fail if reward type not found.] @test-case REWARD-037
public fun test_update_reward_indices_fail_no_reward_type() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        reward_manager.update_reward_indices(
            &vault,
            type_name::with_defining_ids<SUI_TEST_COIN>(),
            100_000_000,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[
    test,
    expected_failure(
        abort_code = reward_manager::ERR_REWARD_EXCEED_LIMIT,
        location = reward_manager,
    ),
]
// [TEST-CASE: Should claim reward fail if not enough reward.] @test-case REWARD-038
public fun test_claim_reward_fail_not_enough_reward() {
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

        clock::set_for_testing(&mut clock, 1000);

        let prices = vector[2 * ORACLE_DECIMALS, 1 * ORACLE_DECIMALS, 100_000 * ORACLE_DECIMALS];
        test_helpers::set_prices(&mut s, &mut clock, &mut oracle_config, prices);

        test_scenario::return_shared(oracle_config);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            500_000_000,
            1_000_000_000,
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
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);
        operation::execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            0,
            1_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let balance = reward_manager.remove_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            type_name::with_defining_ids<SUI_TEST_COIN>(),
            500_000_000,
        );
        balance.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let reward = reward_manager.claim_reward<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &clock,
            &mut receipt,
        );

        assert!(reward.value() == 1_000_000_000);
        reward.destroy_for_testing();

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should update reward buffer when remaining reward buffer amount is zero.] @test-case REWARD-039
public fun test_update_reward_buffer_remaining_reward_buffer_amount_zero() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            100_000_000 * BASE_RATE,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 11);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 11,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 1_000_000_000 * WAD);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 12);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        assert!(
            reward_manager.reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>().value() == 1_000_000_000,
        );
        assert!(reward_manager.reward_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);

        assert!(reward_manager.reward_buffer_amount<SUI_TEST_COIN, SUI_TEST_COIN>() == 0);
        assert!(
            reward_manager.reward_buffer_distribution_rate<SUI_TEST_COIN, SUI_TEST_COIN>() == 100_000_000 * BASE_RATE,
        );
        assert!(
            reward_manager.reward_buffer_distribution_last_updated<SUI_TEST_COIN, SUI_TEST_COIN>() == 12,
        );

        let reward_indices = reward_manager.reward_indices<SUI_TEST_COIN>();
        assert!(reward_indices.get(&type_name::with_defining_ids<SUI_TEST_COIN>()) == 1_000_000_000 * WAD);

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
public fun test_add_reward_balance_fail_minimum_reward_amount() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(0, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
public fun test_update_reward_buffer_new_reward_less_than_minimum_reward_amount() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(2_000_000_000_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        clock::set_for_testing(&mut clock, 1);

        reward_manager.set_reward_rate<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            1,
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        clock::set_for_testing(&mut clock, 2);
        reward_manager.update_reward_buffer(&mut vault, &clock, type_name::with_defining_ids<SUI_TEST_COIN>());

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[
    test,
    expected_failure(
        abort_code = reward_manager::ERR_REWARD_MANAGER_VAULT_MISMATCH,
        location = reward_manager,
    ),
]
public fun test_add_reward_balance_fail_vault_id_mismatch() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = reward_manager::ERR_REWARD_AMOUNT_TOO_SMALL, location = reward_manager)]
public fun test_add_reward_balance_fail_new_reward_less_than_minimum_reward_amount() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(2_000_000_000_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(0, s.ctx());
        reward_manager.add_reward_balance<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[
    test,
    expected_failure(
        abort_code = reward_manager::ERR_REWARD_MANAGER_VAULT_MISMATCH,
        location = reward_manager,
    ),
]
public fun test_add_reward_to_buffer_fail_vault_id_mismatch() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        reward_manager.add_new_reward_type<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &clock,
            true,
        );

        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
        test_scenario::return_shared(reward_manager);
    };

    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        vault.set_total_shares(1_000_000_000);

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        reward_manager.add_reward_to_buffer<SUI_TEST_COIN, SUI_TEST_COIN>(
            &mut vault,
            &operation,
            &cap,
            &clock,
            coin.into_balance(),
        );

        test_scenario::return_shared(reward_manager);
        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}
