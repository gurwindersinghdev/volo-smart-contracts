#[test_only]
module volo_vault::assets_test;

use lending_core::account::AccountCap as NaviAccountCap;
use lending_core::lending;
use std::type_name;
use sui::clock;
use sui::test_scenario;
use volo_vault::btc_test_coin::BTC_TEST_COIN;
use volo_vault::init_vault;
use volo_vault::operation;
use volo_vault::receipt::{Self};
use volo_vault::receipt_cancellation;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::usdc_test_coin::USDC_TEST_COIN;
use volo_vault::vault::{Self, Vault, Operation, OperatorCap};
use volo_vault::vault_oracle::OracleConfig;
use volo_vault::vault_utils;

const OWNER: address = @0xa;

#[test]
// [TEST-CASE: Should add new defi asset.] @test-case ASSETS-001
public fun test_add_new_defi_asset() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let navi_account_cap = lending::create_account(s.ctx());
        operation::add_new_defi_asset(
            &operation,
            &cap,
            &mut vault,
            0,
            navi_account_cap,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        assert!(vault.contains_asset_type(navi_asset_type));

        let wrong_asset_type = vault_utils::parse_key<NaviAccountCap>(1);
        assert!(!vault.contains_asset_type(wrong_asset_type));

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should remove defi asset support.] @test-case ASSETS-002
public fun test_remove_defi_asset_support() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let navi_account_cap = lending::create_account(s.ctx());
        operation::add_new_defi_asset(
            &operation,
            &cap,
            &mut vault,
            0,
            navi_account_cap,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let navi_account_cap = operation::remove_defi_asset_support<SUI_TEST_COIN, NaviAccountCap>(
            &operation,
            &cap,
            &mut vault,
            0,
        );
        transfer::public_transfer(navi_account_cap, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        assert!(!vault.contains_asset_type(navi_asset_type));

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_ASSET_TYPE_NOT_FOUND, location = vault)]
// [TEST-CASE: Should remove defi asset support fail if not exist.] @test-case ASSETS-003
public fun test_remove_defi_asset_support_fail_not_exist() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let navi_account_cap = operation::remove_defi_asset_support<SUI_TEST_COIN, NaviAccountCap>(
            &operation,
            &cap,
            &mut vault,
            0,
        );
        transfer::public_transfer(navi_account_cap, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_ASSET_TYPE_NOT_FOUND, location = vault)]
// [TEST-CASE: Should remove defi asset support fail if value already updated.] @test-case ASSETS-004
public fun test_remove_defi_asset_support_fail_value_already_updated() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let navi_account_cap = lending::create_account(s.ctx());
        operation::add_new_defi_asset(
            &operation,
            &cap,
            &mut vault,
            0,
            navi_account_cap,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();
        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);

        vault.set_asset_value(navi_asset_type, 1_000_000_000, 1000);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let navi_account_cap = operation::remove_defi_asset_support<SUI_TEST_COIN, NaviAccountCap>(
            &operation,
            &cap,
            &mut vault,
            0,
        );
        transfer::public_transfer(navi_account_cap, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should add new coin type asset.] @test-case ASSETS-005
public fun test_add_new_coin_type_asset() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        operation::add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>(
            &operation,
            &cap,
            &mut vault,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin_asset_type = type_name::with_defining_ids<USDC_TEST_COIN>().into_string();
        assert!(vault.contains_asset_type(coin_asset_type));

        let wrong_asset_type = type_name::with_defining_ids<BTC_TEST_COIN>().into_string();
        assert!(!vault.contains_asset_type(wrong_asset_type));

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should borrow defi asset but not return.] @test-case ASSETS-006
public fun test_borrow_defi_asset_not_return() {
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
        let navi_account_cap_address = object::id_address(&navi_account_cap);
        vault.add_new_defi_asset(
            0,
            navi_account_cap,
        );

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        let navi_account_cap = vault.borrow_defi_asset<SUI_TEST_COIN, NaviAccountCap>(
            navi_asset_type,
        );
        assert!(navi_account_cap.account_owner() == navi_account_cap_address);

        transfer::public_transfer(navi_account_cap, OWNER);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        assert!(!vault.contains_asset_type(navi_asset_type));

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should borrow defi asset then return.] @test-case ASSETS-007
public fun test_borrow_defi_asset_then_return() {
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

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        let navi_account_cap = vault.borrow_defi_asset<SUI_TEST_COIN, NaviAccountCap>(
            navi_asset_type,
        );
        assert!(!vault.contains_asset_type(navi_asset_type));

        vault.return_defi_asset(navi_asset_type, navi_account_cap);
        assert!(vault.contains_asset_type(navi_asset_type));

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_ASSET_TYPE_NOT_FOUND, location = vault)]
// [TEST-CASE: Should borrow defi asset fail if not exist.] @test-case ASSETS-008
public fun test_borrow_defi_asset_fail_not_exist() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        let navi_account_cap = vault.borrow_defi_asset<SUI_TEST_COIN, NaviAccountCap>(
            navi_asset_type,
        );
        transfer::public_transfer(navi_account_cap, OWNER);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_ASSET_TYPE_NOT_FOUND, location = vault)]
// [TEST-CASE: Should borrow defi asset fail if already borrowed.] @test-case ASSETS-009
public fun test_borrow_defi_asset_fail_already_borrowed() {
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

        let navi_asset_type = vault_utils::parse_key<NaviAccountCap>(0);
        let navi_account_cap = vault.borrow_defi_asset<SUI_TEST_COIN, NaviAccountCap>(
            navi_asset_type,
        );
        transfer::public_transfer(navi_account_cap, OWNER);

        let navi_account_cap_2 = vault.borrow_defi_asset<SUI_TEST_COIN, NaviAccountCap>(
            navi_asset_type,
        );
        transfer::public_transfer(navi_account_cap_2, OWNER);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = vault::ERR_INVALID_COIN_ASSET_TYPE, location = vault)]
public fun test_add_coin_type_asset_fail_same_as_principal_asset() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        operation::add_new_coin_type_asset<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &cap,
            &mut vault,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
public fun test_remove_coin_type_asset() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        operation::add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>(
            &operation,
            &cap,
            &mut vault,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        operation::remove_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>(
            &operation,
            &cap,
            &mut vault,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let coin_asset_type = type_name::with_defining_ids<USDC_TEST_COIN>().into_string();
        assert!(!vault.contains_asset_type(coin_asset_type));

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = vault::ERR_ASSET_TYPE_NOT_FOUND, location = vault)]
public fun test_remove_coin_type_asset_fail_asset_type_not_exist() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        operation::add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>(
            &operation,
            &cap,
            &mut vault,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        operation::remove_coin_type_asset<SUI_TEST_COIN, BTC_TEST_COIN>(
            &operation,
            &cap,
            &mut vault,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = vault::ERR_INVALID_COIN_ASSET_TYPE, location = vault)]
public fun test_remove_coin_type_asset_fail_same_as_principal_asset() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        operation::add_new_coin_type_asset<SUI_TEST_COIN, USDC_TEST_COIN>(
            &operation,
            &cap,
            &mut vault,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        operation::remove_coin_type_asset<SUI_TEST_COIN, SUI_TEST_COIN>(
            &operation,
            &cap,
            &mut vault,
        );

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
        abort_code = receipt_cancellation::ERR_RECEIPT_CAN_BE_CANCELLED,
        location = receipt_cancellation,
    ),
]
public fun test_add_new_defi_asset_receipt_cancellation() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let mut receipt = receipt::create_receipt(vault.vault_id(), s.ctx());

        receipt_cancellation::add_dynamic_field_to_receipt(&mut receipt);
        receipt_cancellation::add_dynamic_field_to_vault(&mut vault, s.ctx());

        operation::add_receipt_as_defi_asset(
            &operation,
            &cap,
            &mut vault,
            0,
            receipt,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
public fun test_add_new_defi_asset_receipt_cancellation_2() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();

        let mut receipt = receipt::create_receipt(vault.vault_id(), s.ctx());

        receipt_cancellation::add_dynamic_field_to_receipt(&mut receipt);
        receipt_cancellation::add_dynamic_field_to_vault(&mut vault, s.ctx());

        receipt_cancellation::set_receipt_can_not_be_cancelled(&mut receipt, &mut vault);

        operation::add_receipt_as_defi_asset(
            &operation,
            &cap,
            &mut vault,
            0,
            receipt,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
    };

    clock.destroy_for_testing();
    s.end();
}
