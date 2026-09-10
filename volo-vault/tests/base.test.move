#[test_only]
module volo_vault::base_test;

use std::type_name;
use sui::clock;
use sui::test_scenario;
use volo_vault::init_vault;
use volo_vault::sui_test_coin::SUI_TEST_COIN;
use volo_vault::vault::{Self, Vault, AdminCap};

const DEPOSIT_FEE_RATE: u64 = 10; // default 10bp (0.1%)
const WITHDRAW_FEE_RATE: u64 = 10; // default 10bp (0.1%)

const DEFAULT_LOCKING_TIME_FOR_WITHDRAW: u64 = 12 * 3600 * 1_000; // 12 hours to withdraw after a deposit
const DEFAULT_LOCKING_TIME_FOR_CANCEL_REQUEST: u64 = 5 * 60 * 1_000; // 5 minutes to cancel a submitted request

const DEFAULT_TOLERANCE: u256 = 10; // principal loss tolerance at every epoch (0.1%)

const OWNER: address = @0xa;
// const ALICE: address = @0xb;
// const BOB: address = @0xc;

#[test]
// [TEST-CASE: Should init vault.] @test-case BASE-001
public fun test_init() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    s.next_tx(OWNER);
    {
        init_vault::init_vault(&mut s, &mut clock);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should create vault with init status.] @test-case BASE-002
public fun test_create_vault_init_status() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();
        vault::create_vault<SUI_TEST_COIN>(&admin_cap, s.ctx());
        s.return_to_sender(admin_cap);
    };

    s.next_tx(OWNER);
    {
        let vault = s.take_shared<Vault<SUI_TEST_COIN>>();

        assert!(vault.withdraw_fee_rate() == WITHDRAW_FEE_RATE);
        assert!(vault.deposit_fee_rate() == DEPOSIT_FEE_RATE);
        assert!(vault.loss_tolerance() == DEFAULT_TOLERANCE);

        assert!(vault.status() == 0);
        assert!(vault.locking_time_for_withdraw() == DEFAULT_LOCKING_TIME_FOR_WITHDRAW);
        assert!(vault.locking_time_for_cancel_request() == DEFAULT_LOCKING_TIME_FOR_CANCEL_REQUEST);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
// [TEST-CASE: Should create vault with admin cap.] @test-case BASE-003
public fun test_create_vault_with_admin_cap() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());

    init_vault::init_vault(&mut s, &mut clock);

    s.next_tx(OWNER);
    {
        let admin_cap = s.take_from_sender<AdminCap>();
        vault::create_vault<SUI_TEST_COIN>(&admin_cap, s.ctx());
        s.return_to_sender(admin_cap);
    };

    clock.destroy_for_testing();
    s.end();
}

#[test]
#[expected_failure(abort_code = vault::ERR_ASSET_TYPE_ALREADY_EXISTS, location = vault)]
public fun test_set_new_asset_type_failed_already_exists() {
    let mut s = test_scenario::begin(OWNER);

    let mut clock = clock::create_for_testing(s.ctx());
    init_vault::init_vault(&mut s, &mut clock);
    init_vault::init_create_vault<SUI_TEST_COIN>(&mut s);

    let sui_asset_type = type_name::with_defining_ids<SUI_TEST_COIN>().into_string();

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        vault.set_new_asset_type(sui_asset_type);

        test_scenario::return_shared(vault);
    };

    s.next_tx(OWNER);
    {
        let mut vault = s.take_shared<Vault<SUI_TEST_COIN>>();
        vault.set_new_asset_type(sui_asset_type);

        test_scenario::return_shared(vault);
    };

    clock.destroy_for_testing();
    s.end();
}
