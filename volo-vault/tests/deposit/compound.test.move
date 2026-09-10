#[test_only]
module volo_vault::compound_test;

use std::type_name;
use sui::clock;
use sui::coin;
use sui::test_scenario;
use volo_vault::init_vault;
use volo_vault::operation;
use volo_vault::reward_manager::RewardManager;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::user_entry;
use volo_vault::vault::{Self, Vault, Operation, OperatorCap};
use volo_vault::vault_oracle::{Self, OracleConfig};

const OWNER: address = @0xa;
// const ALICE: address = @0xb;
// const BOB: address = @0xc;

const MOCK_AGGREGATOR_SUI: address = @0xd;

const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000; // 18 decimals

#[test]
// [TEST-CASE: Should compound deposit by operator.] @test-case COMPOUND-001
public fun test_compound_deposit_by_operator() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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
            1_000_000_000,
            2_000_000_000,
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

    // Compound deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());

        operation::deposit_by_operator(
            &operation,
            &cap,
            &mut vault,
            &clock,
            &config,
            coin,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    // Check vault info
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        // Free principal = 2 SUI = 4U
        // Share ratio = 4U / 2shares = 2
        assert!(vault.free_principal() == 2_000_000_000);
        assert!(vault.total_shares() == 2_000_000_000);
        assert!(vault.get_share_ratio( &clock) == 2_000_000_000);

        test_scenario::return_shared(vault);
    };

    // Compound deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        let coin = coin::mint_for_testing<SUI_TEST_COIN>(2_000_000_000, s.ctx());

        vault.deposit_by_operator(
            &clock,
            &config,
            coin,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Check vault info
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        // Free principal = 4 SUI = 8U
        // Share ratio = 8U / 2shares = 4
        assert!(vault.free_principal() == 4_000_000_000);
        assert!(vault.total_shares() == 2_000_000_000);
        assert!(vault.get_share_ratio( &clock) == 4_000_000_000);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}
