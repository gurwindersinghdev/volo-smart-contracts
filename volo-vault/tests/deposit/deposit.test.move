#[test_only]
module volo_vault::deposit_test;

use std::type_name;
use sui::clock;
use sui::coin::{Self, Coin};
use sui::test_scenario;
use volo_vault::init_vault;
use volo_vault::operation;
use volo_vault::receipt::{Self, Receipt};
use volo_vault::reward_manager::RewardManager;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::user_entry;
use volo_vault::vault::{Self, Vault, OperatorCap, Operation};
use volo_vault::vault_oracle::{Self, OracleConfig};

const OWNER: address = @0xa;
const ALICE: address = @0xb;
// const BOB: address = @0xc;

const MOCK_AGGREGATOR_SUI: address = @0xd;
// const MOCK_AGGREGATOR_USDC: address = @0xe;
// const MOCK_AGGREGATOR_BTC: address = @0xf;

const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000; // 18 decimals

#[test]
// [TEST-CASE: Should request deposit without receipt.] @test-case DEPOSIT-001
public fun test_request_deposit_without_receipt() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    // Request deposit 1 SUI, expected shares 2
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

        assert!(coin.value() == 0);

        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Check deposit request results
    s.next_tx(OWNER);
    {
        let request_id = 0;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.request_id() == request_id);
        assert!(deposit_request.vault_id() == vault.vault_id());
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        assert!(vault.deposit_id_count() == 1);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should request deposit with auto transfer.] @test-case DEPOSIT-002
public fun test_request_deposit_with_auto_transfer() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    // Request deposit 1 SUI, expected shares 2
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(2_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id) = user_entry::deposit_with_auto_transfer(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Check deposit request results
    s.next_tx(OWNER);
    {
        let request_id = 0;

        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        let remaining_coin = s.take_from_sender<Coin<SUI_TEST_COIN>>();
        assert!(remaining_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(remaining_coin);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_WRONG_RECEIPT_STATUS, location = vault)]
// [TEST-CASE: Should request deposit fail if receipt is pending deposit status.] @test-case DEPOSIT-003
public fun test_request_deposit_fail_receipt_is_pending_deposit_status() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    // Request deposit 1 SUI, expected shares 2
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

    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();

        let (_request_id, ret_receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::some(receipt),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(ret_receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should request deposit with multiple users.] @test-case DEPOSIT-004
public fun test_request_deposit_multiple_users() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

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

    // Request deposit
    s.next_tx(ALICE);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(2_000_000_000, s.ctx());
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

        assert!(coin.value() == 1_000_000_000);

        transfer::public_transfer(coin, ALICE);
        transfer::public_transfer(receipt, ALICE);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Check deposit request results
    s.next_tx(OWNER);
    {
        let request_id = 0;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    // Check deposit request results
    s.next_tx(ALICE);
    {
        let request_id = 1;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should request deposit with auto transfer with multiple users.] @test-case DEPOSIT-005
public fun test_request_deposit_with_auto_transfer_multiple_users() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id) = user_entry::deposit_with_auto_transfer(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Request deposit
    s.next_tx(ALICE);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(2_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id) = user_entry::deposit_with_auto_transfer(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Check deposit request results
    s.next_tx(OWNER);
    {
        let request_id = 0;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    // Check deposit request results
    s.next_tx(ALICE);
    {
        let request_id = 1;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should request deposit mixed with multiple users.] @test-case DEPOSIT-006
public fun test_request_deposit_mixed_multiple_users() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

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

    // Request deposit
    s.next_tx(ALICE);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(2_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id) = user_entry::deposit_with_auto_transfer(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Check deposit request results
    s.next_tx(OWNER);
    {
        let request_id = 0;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    // Check deposit request results
    s.next_tx(ALICE);
    {
        let request_id = 1;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should request deposit with receipt.] @test-case DEPOSIT-007
public fun test_request_deposit_with_receipt() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = receipt::create_receipt(
            vault.vault_id(),
            s.ctx(),
        );
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();

        let (_request_id, ret_receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::some(receipt),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(ret_receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Check deposit request results
    s.next_tx(OWNER);
    {
        let request_id = 0;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should request deposit with auto transfer with receipt.] @test-case DEPOSIT-008
public fun test_request_deposit_with_auto_transfer_with_receipt() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = receipt::create_receipt(
            vault.vault_id(),
            s.ctx(),
        );
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();

        let (_request_id) = user_entry::deposit_with_auto_transfer(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::some(receipt),
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Check deposit request results
    s.next_tx(OWNER);
    {
        let request_id = 0;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should request deposit with receipt with multiple users.] @test-case DEPOSIT-009
public fun test_request_deposit_with_receipt_multiple_users() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = receipt::create_receipt(
            vault.vault_id(),
            s.ctx(),
        );
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
    };

    s.next_tx(ALICE);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = receipt::create_receipt(
            vault.vault_id(),
            s.ctx(),
        );
        transfer::public_transfer(receipt, ALICE);

        test_scenario::return_shared(vault);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();

        let (_request_id, ret_receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::some(receipt),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(ret_receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Request deposit
    s.next_tx(ALICE);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();

        let (_request_id, ret_receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::some(receipt),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, ALICE);
        transfer::public_transfer(ret_receipt, ALICE);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Check deposit request results
    s.next_tx(OWNER);
    {
        let request_id = 0;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    // Check deposit request results
    s.next_tx(ALICE);
    {
        let request_id = 1;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should request deposit mixed with receipt with multiple users.] @test-case DEPOSIT-010
public fun test_request_deposit_mixed_with_receipt_multiple_users() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = receipt::create_receipt(
            vault.vault_id(),
            s.ctx(),
        );
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
    };

    s.next_tx(ALICE);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = receipt::create_receipt(
            vault.vault_id(),
            s.ctx(),
        );
        transfer::public_transfer(receipt, ALICE);

        test_scenario::return_shared(vault);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();

        let (_request_id, ret_receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::some(receipt),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(ret_receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Request deposit
    s.next_tx(ALICE);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();

        let (_request_id) = user_entry::deposit_with_auto_transfer(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::some(receipt),
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Check deposit request results
    s.next_tx(OWNER);
    {
        let request_id = 0;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    // Check deposit request results
    s.next_tx(ALICE);
    {
        let request_id = 1;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 1);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 1_000_000_000);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.receipt_id() == receipt.receipt_id());
        assert!(deposit_request.amount() == 1_000_000_000);
        assert!(deposit_request.expected_shares() == 2_000_000_000);

        let buffered_coin = vault.deposit_coin_buffer(request_id);
        assert!(buffered_coin.value() == 1_000_000_000);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_VAULT_NOT_NORMAL, location = vault)]
// [TEST-CASE: Should request deposit fail if vault is disabled.] @test-case DEPOSIT-011
public fun test_request_deposit_fail_vault_disabled() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault::set_enabled(&mut vault, false);
        test_scenario::return_shared(vault);
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

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_VAULT_NOT_NORMAL, location = vault)]
// [TEST-CASE: Should request deposit with auto transfer fail if vault is disabled.] @test-case DEPOSIT-012
public fun test_request_deposit_with_auto_transfer_fail_vault_disabled() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault::set_enabled(&mut vault, false);
        test_scenario::return_shared(vault);
    };

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id) = user_entry::deposit_with_auto_transfer(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_COIN_BUFFER_NOT_FOUND, location = vault)]
// [TEST-CASE: Should cancel deposit.] @test-case DEPOSIT-013
public fun test_cancel_deposit() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

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

    // Cancel deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let coin = user_entry::cancel_deposit(
            &mut vault,
            &mut receipt,
            0,
            &clock,
            s.ctx(),
        );

        assert!(coin.value() == 1_000_000_000);

        transfer::public_transfer(coin, OWNER);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    // Check the deposit request is cancelled
    s.next_tx(OWNER);
    {
        let request_id = 0;

        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        // let deposit_request = vault.deposit_request(request_id);
        // assert!(deposit_request.amount() == 1_000_000_000);
        // assert!(deposit_request.is_cancelled() == true);
        // assert!(deposit_request.is_executed() == false);

        // Fail: no buffered coin
        let _buffered_coin = vault.deposit_coin_buffer(request_id);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_REQUEST_NOT_FOUND, location = vault)]
// [TEST-CASE: Should cancel deposit fail if already cancelled.] @test-case DEPOSIT-014
public fun test_cancel_deposit_fail_already_cancelled() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

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

    // Cancel deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let coin = user_entry::cancel_deposit(
            &mut vault,
            &mut receipt,
            0,
            &clock,
            s.ctx(),
        );

        assert!(coin.value() == 1_000_000_000);

        transfer::public_transfer(coin, OWNER);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    // Cancel deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let coin = user_entry::cancel_deposit(
            &mut vault,
            &mut receipt,
            0,
            &clock,
            s.ctx(),
        );
        transfer::public_transfer(coin, OWNER);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_REQUEST_CANCEL_TIME_NOT_REACHED, location = vault)]
// [TEST-CASE: Should cancel deposit fail if not reach locking time.] @test-case DEPOSIT-015
public fun test_cancel_deposit_fail_not_reach_locking_time() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.set_locking_time_for_cancel_request(5000);

        test_scenario::return_shared(vault);
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

    // Cancel deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let coin = user_entry::cancel_deposit(
            &mut vault,
            &mut receipt,
            0,
            &clock,
            s.ctx(),
        );

        assert!(coin.value() == 1_000_000_000);

        transfer::public_transfer(coin, OWNER);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_COIN_BUFFER_NOT_FOUND, location = vault)]
// [TEST-CASE: Should cancel deposit with auto transfer.] @test-case DEPOSIT-016
public fun test_cancel_deposit_with_auto_transfer() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id) = user_entry::deposit_with_auto_transfer(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Cancel deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        user_entry::cancel_deposit_with_auto_transfer(
            &mut vault,
            &mut receipt,
            0,
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    // Check the deposit request is cancelled
    s.next_tx(OWNER);
    {
        let request_id = 0;

        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        // let deposit_request = vault.deposit_request(request_id);
        // assert!(deposit_request.amount() == 1_000_000_000);
        // assert!(deposit_request.is_cancelled() == true);
        // assert!(deposit_request.is_executed() == false);

        // Fail: no buffered coin
        let _buffered_coin = vault.deposit_coin_buffer(request_id);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_COIN_BUFFER_NOT_FOUND, location = vault)]
// [TEST-CASE: Should cancel deposit with multiple users.] @test-case DEPOSIT-017
public fun test_cancel_deposit_multiple_users() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

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
            1_000_000_000,
            2_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, ALICE);
        transfer::public_transfer(receipt, ALICE);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Cancel ALICE's deposit
    s.next_tx(ALICE);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let coin = user_entry::cancel_deposit(
            &mut vault,
            &mut receipt,
            1,
            &clock,
            s.ctx(),
        );

        assert!(coin.value() == 1_000_000_000);

        transfer::public_transfer(coin, ALICE);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    // Check the deposit request is cancelled
    s.next_tx(ALICE);
    {
        let request_id = 1;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        // let deposit_request = vault.deposit_request(request_id);
        // assert!(deposit_request.amount() == 1_000_000_000);
        // assert!(deposit_request.is_cancelled() == true);
        // assert!(deposit_request.is_executed() == false);

        // Fail: no buffered coin
        let _buffered_coin = vault.deposit_coin_buffer(request_id);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_COIN_BUFFER_NOT_FOUND, location = vault)]
// [TEST-CASE: Should cancel deposit with auto transfer with multiple users.] @test-case DEPOSIT-018
public fun test_cancel_deposit_with_auto_transfer_multiple_users() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    // Request deposit
    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id) = user_entry::deposit_with_auto_transfer(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Request deposit
    s.next_tx(ALICE);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id) = user_entry::deposit_with_auto_transfer(
            &mut vault,
            &mut reward_manager,
            coin,
            1_000_000_000,
            2_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Cancel ALICE's deposit
    s.next_tx(ALICE);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        user_entry::cancel_deposit_with_auto_transfer(
            &mut vault,
            &mut receipt,
            1,
            &clock,
            s.ctx(),
        );

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    // Check the deposit request is cancelled
    s.next_tx(ALICE);
    {
        let request_id = 1;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        // let deposit_request = vault.deposit_request(request_id);
        // assert!(deposit_request.amount() == 1_000_000_000);
        // assert!(deposit_request.is_cancelled() == true);
        // assert!(deposit_request.is_executed() == false);

        // Fail: no buffered coin
        let _buffered_coin = vault.deposit_coin_buffer(request_id);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_RECEIPT_ID_MISMATCH, location = vault)]
// [TEST-CASE: Should cancel deposit fail if wrong request id.] @test-case DEPOSIT-019
public fun test_cancel_deposit_fail_wrong_request_id() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

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
            1_000_000_000,
            2_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, ALICE);
        transfer::public_transfer(receipt, ALICE);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Cancel ALICE's deposit
    s.next_tx(ALICE);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let coin = user_entry::cancel_deposit(
            &mut vault,
            &mut receipt,
            0,
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, ALICE);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_REQUEST_NOT_FOUND, location = vault)]
// [TEST-CASE: Should execute deposit.] @test-case DEPOSIT-020
// Request deposit 1 SUI_TEST, then execute the deposit
// Initial share ratio = 1e9
// User shares = 2e9
public fun test_execute_deposit() {
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

    // Check total usd value before execute deposit
    s.next_tx(OWNER);
    {
        let config = s.take_shared<OracleConfig>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.update_free_principal_value( &config, &clock);

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
            2_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let request_id = 0;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() == 2_000_000_000);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let _deposit_request = vault.deposit_request(request_id);
        // assert!(deposit_request.amount() == 1_000_000_000);
        // assert!(deposit_request.is_cancelled() == false);
        // assert!(deposit_request.is_executed() == true);

        s.return_to_sender(receipt);
        test_scenario::return_shared(vault);
    };

    // Check deposit fee (0 fee)
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let deposit_fee = vault.deposit_withdraw_fee_collected();
        assert!(deposit_fee == 0);

        test_scenario::return_shared(vault);
    };

    // Check total usd value after execute deposit
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let config = s.take_shared<OracleConfig>();

        // vault.update_free_principal_value(&config, &clock);
        // Execute deposit will update free principal value
        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 2_000_000_000);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_REQUEST_NOT_FOUND, location = vault)]
// [TEST-CASE: Should execute deposit fail if already executed.] @test-case DEPOSIT-021
public fun test_execute_deposit_fail_already_executed() {
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

    // Check total usd value before execute deposit
    s.next_tx(OWNER);
    {
        let config = s.take_shared<OracleConfig>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.update_free_principal_value( &config, &clock);

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

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_UNEXPECTED_SLIPPAGE, location = vault)]
// [TEST-CASE: Should execute deposit fail with negative slippage.] @test-case DEPOSIT-022
public fun test_execute_deposit_fail_negative_slippage() {
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
            3_000_000_000,
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

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
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

    s.next_tx(OWNER);
    {
        let request_id = 0;
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() == 2_000_000_000);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let deposit_request = vault.deposit_request(request_id);
        assert!(deposit_request.amount() == 1_000_000_000);

        s.return_to_sender(receipt);
        test_scenario::return_shared(vault);
    };

    // Check deposit fee (0 fee)
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let deposit_fee = vault.deposit_withdraw_fee_collected();
        assert!(deposit_fee == 0);

        test_scenario::return_shared(vault);
    };

    // Check total usd value after execute deposit
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let config = s.take_shared<OracleConfig>();

        // vault.update_free_principal_value(&config, &clock);
        // Execute deposit will update free principal value
        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 2_000_000_000);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_UNEXPECTED_SLIPPAGE, location = vault)]
// [TEST-CASE: Should execute deposit fail with positive slippage.] @test-case DEPOSIT-023
public fun test_execute_deposit_fail_positive_slippage() {
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

    // Check total usd value before execute deposit
    s.next_tx(OWNER);
    {
        let config = s.take_shared<OracleConfig>();
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.update_free_principal_value(&config, &clock);

        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 0);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
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
            1_990_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should execute deposit with multiple users by request order.] @test-case DEPOSIT-024
// OWNER request deposit 1 SUI_TEST
// ALICE also request deposit 1 SUI_TEST
// OWNER executes requests by request order
public fun test_execute_deposit_multiple_users_by_request_order() {
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
            1_000_000_000,
            2_000_000_000,
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

    // Execute deposit
    s.next_tx(ALICE);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let config = s.take_shared<OracleConfig>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        vault.execute_deposit(
            &clock,
            &config,
            1,
            2_000_000_000,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
    };

    // Check receipt info
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() == 2_000_000_000);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        s.return_to_sender(receipt);
        test_scenario::return_shared(vault);
    };

    // Check receipt info
    s.next_tx(ALICE);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() == 2_000_000_000);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        s.return_to_sender(receipt);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should execute deposit with multiple users not by request order.] @test-case DEPOSIT-025
public fun test_execute_deposit_multiple_users_not_by_request_order() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    let sui_asset_type = type_name::with_defining_ids<SUI_TEST_COIN>().into_string();

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault.set_deposit_fee(0);
        vault.set_withdraw_fee(0);

        test_scenario::return_shared(vault);
    };

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
            1_000_000_000,
            2_000_000_000,
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
    s.next_tx(ALICE);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        vault.execute_deposit(
            &clock,
            &config,
            1,
            2_000_000_000,
        );

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

    // Check receipt info
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() == 2_000_000_000);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        s.return_to_sender(receipt);
        test_scenario::return_shared(vault);
    };

    // Check receipt info
    s.next_tx(ALICE);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() == 2_000_000_000);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        s.return_to_sender(receipt);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = user_entry::ERR_INSUFFICIENT_BALANCE, location = user_entry)]
// [TEST-CASE: Should request deposit fail if coin not enough.] @test-case DEPOSIT-026
public fun test_request_deposit_from_user_entry_fail_coin_not_enough() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            2_000_000_000,
            4_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_COIN_BUFFER_NOT_FOUND, location = vault)]
// [TEST-CASE: Should cancel deposit by operator.] @test-case DEPOSIT-027
public fun test_cancel_user_deposit_by_operator() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);
    init_vault::init_single_operator_config_for_owner<SUI_TEST_COIN>(&mut s, true);

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

    // Cancel deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();

        let operation = s.take_shared<Operation>();
        let operator_cap = s.take_from_sender<OperatorCap>();

        operation::cancel_user_deposit<SUI_TEST_COIN>(
            &operation,
            &operator_cap,
            &mut vault,
            0,
            receipt.receipt_id(),
            OWNER,
            &clock,
        );

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
        test_scenario::return_shared(operation);
        s.return_to_sender(operator_cap);
    };

    // Check the deposit request is cancelled
    s.next_tx(OWNER);
    {
        let request_id = 0;

        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        let coin = s.take_from_sender<Coin<SUI_TEST_COIN>>();
        assert!(coin.value() == 1_000_000_000);

        // Fail: no buffered coin
        let _buffered_coin = vault.deposit_coin_buffer(request_id);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
        s.return_to_sender(coin);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_VAULT_NOT_NORMAL, location = vault)]
// [TEST-CASE: Should request deposit fail if vault is during operation.] @test-case DEPOSIT-028
public fun test_request_deposit_fail_vault_during_operation() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault::set_status(&mut vault, 1);
        test_scenario::return_shared(vault);
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

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_VAULT_NOT_NORMAL, location = vault)]
// [TEST-CASE: Should cancel deposit fail if vault is disabled.] @test-case DEPOSIT-029
public fun test_cancel_deposit_fail_vault_disabled() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    // Request deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault::set_status(&mut vault, 2);
        test_scenario::return_shared(vault);
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

    // Cancel ALICE's deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let coin = user_entry::cancel_deposit(
            &mut vault,
            &mut receipt,
            0,
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, OWNER);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_VAULT_NOT_NORMAL, location = vault)]
// [TEST-CASE: Should cancel deposit fail if vault is during operation.] @test-case DEPOSIT-030
public fun test_cancel_deposit_fail_vault_during_operation() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    // Request deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        vault::set_status(&mut vault, 1);
        test_scenario::return_shared(vault);
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

    // Cancel ALICE's deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let coin = user_entry::cancel_deposit(
            &mut vault,
            &mut receipt,
            0,
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, OWNER);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should batch execute deposit.] @test-case DEPOSIT-031
public fun test_batch_execute_deposit() {
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
        let coin_1 = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let coin_2 = coin::mint_for_testing<SUI_TEST_COIN>(2_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id_1, receipt_1, return_coin_1) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin_1,
            1_000_000_000,
            2_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );
        transfer::public_transfer(return_coin_1, OWNER);
        transfer::public_transfer(receipt_1, OWNER);

        let (_request_id_2, receipt_2, return_coin_2) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin_2,
            2_000_000_000,
            4_000_000_000,
            option::none(),
            &clock,
            s.ctx(),
        );
        transfer::public_transfer(return_coin_2, OWNER);
        transfer::public_transfer(receipt_2, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    // Batch execute deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let config = s.take_shared<OracleConfig>();
        let operation = s.take_shared<Operation>();
        let cap = s.take_from_sender<OperatorCap>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        vault::update_free_principal_value(&mut vault, &config, &clock);

        let request_ids = vector<u64>[0, 1];
        let max_shares_received = vector<u256>[2_000_000_000, 4_000_000_000];

        operation::batch_execute_deposit(
            &operation,
            &cap,
            &mut vault,
            &mut reward_manager,
            &clock,
            &config,
            request_ids,
            max_shares_received,
        );

        test_scenario::return_shared(vault);
        test_scenario::return_shared(config);
        test_scenario::return_shared(operation);
        s.return_to_sender(cap);
        test_scenario::return_shared(reward_manager);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt_1 = s.take_from_sender<Receipt>();
        let vault_receipt_info_1 = vault.vault_receipt_info(receipt_1.receipt_id());

        assert!(vault_receipt_info_1.status() == 0);
        assert!(vault_receipt_info_1.shares() == 4_000_000_000);
        assert!(vault_receipt_info_1.pending_deposit_balance() == 0);
        assert!(vault_receipt_info_1.pending_withdraw_shares() == 0);

        let receipt_2 = s.take_from_sender<Receipt>();
        let vault_receipt_info_2 = vault.vault_receipt_info(receipt_2.receipt_id());

        assert!(vault_receipt_info_2.status() == 0);
        assert!(vault_receipt_info_2.shares() == 2_000_000_000);
        assert!(vault_receipt_info_2.pending_deposit_balance() == 0);
        assert!(vault_receipt_info_2.pending_withdraw_shares() == 0);

        s.return_to_sender(receipt_1);
        s.return_to_sender(receipt_2);
        test_scenario::return_shared(vault);
    };

    // Check total usd value after execute deposit
    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        let config = s.take_shared<OracleConfig>();

        // vault.update_free_principal_value(&config, &clock);
        // Execute deposit will update free principal value
        let total_usd_value = vault.get_total_usd_value(&clock);
        assert!(total_usd_value == 6_000_000_000);

        test_scenario::return_shared(config);
        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = vault::ERR_VAULT_NOT_NORMAL, location = vault)]
// [TEST-CASE: Should not cancel deposit if vault is disabled.] @test-case DEPOSIT-032
public fun test_cancel_deposit_success_vault_disabled() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

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

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        vault.set_enabled(false);
        test_scenario::return_shared(vault);
    };

    // Cancel deposit
    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut receipt = s.take_from_sender<Receipt>();

        let coin = user_entry::cancel_deposit(
            &mut vault,
            &mut receipt,
            0,
            &clock,
            s.ctx(),
        );

        assert!(coin.value() == 1_000_000_000);

        transfer::public_transfer(coin, OWNER);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    // Check the deposit request is cancelled
    s.next_tx(OWNER);
    {
        let request_id = 0;

        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let receipt = s.take_from_sender<Receipt>();
        let vault_receipt_info = vault.vault_receipt_info(receipt.receipt_id());

        assert!(vault_receipt_info.status() == 0);
        assert!(vault_receipt_info.shares() == 0);
        assert!(vault_receipt_info.pending_deposit_balance() == 0);
        assert!(vault_receipt_info.pending_withdraw_shares() == 0);

        // let deposit_request = vault.deposit_request(request_id);
        // assert!(deposit_request.amount() == 1_000_000_000);
        // assert!(deposit_request.is_cancelled() == true);
        // assert!(deposit_request.is_executed() == false);

        // Fail: no buffered coin
        let _buffered_coin = vault.deposit_coin_buffer(request_id);

        test_scenario::return_shared(vault);
        s.return_to_sender(receipt);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = user_entry::ERR_INVALID_AMOUNT, location = user_entry)]
// [TEST-CASE: Should request deposit fail if zero amount.] @test-case DEPOSIT-033
public fun test_request_deposit_fail_zero_amount() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    s.next_tx(OWNER);
    {
        let coin = coin::mint_for_testing<SUI_TEST_COIN>(1_000_000_000, s.ctx());
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        let mut reward_manager = s.take_shared<RewardManager<SUI_TEST_COIN>>();

        let (_request_id, receipt, coin) = user_entry::deposit(
            &mut vault,
            &mut reward_manager,
            coin,
            0,
            0,
            option::none(),
            &clock,
            s.ctx(),
        );

        transfer::public_transfer(coin, OWNER);
        transfer::public_transfer(receipt, OWNER);

        test_scenario::return_shared(vault);
        test_scenario::return_shared(reward_manager);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test, expected_failure(abort_code = user_entry::ERR_VAULT_ID_MISMATCH, location = user_entry)]
// [TEST-CASE: Should request deposit fail if reward manager mismatch.] @test-case DEPOSIT-034
public fun test_request_deposit_fail_reward_manager_mismatch() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);
    init_vault::init_create_reward_manager<SUI_TEST_COIN>(&mut s);

    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

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

    clock.destroy_for_testing();
    s.end();
}