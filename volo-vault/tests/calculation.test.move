#[test_only]
module volo_vault::calculation_test;

use volo_vault::vault_utils;

const DECIMALS: u256 = 1_000_000_000;
// const ORACLE_DECIMALS: u256 = 1_000_000_000_000_000_000;

#[test]
// [TEST-CASE: Should multiply with decimals.] @test-case CALCULATION-001
public fun test_mul_d() {
    let mut v1 = vault_utils::to_decimals(1);
    let mut v2 = vault_utils::to_decimals(1);
    assert!(vault_utils::mul_d(v1, v2) == vault_utils::to_decimals(1), 0);

    v1 = 1_000;
    v2 = 1_000;
    assert!(vault_utils::mul_d(v1, v2) == 0, 0);

    v1 = 1_000_000_000;
    v2 = 10_000_000_000;
    assert!(vault_utils::mul_d(v1, v2) == 10_000_000_000, 0);

    v1 = 1_000_000_000;
    v2 = 100_000_000_000;
    assert!(vault_utils::mul_d(v1, v2) == 100_000_000_000, 0);
}

#[test]
// [TEST-CASE: Should divide with decimals.] @test-case CALCULATION-002
public fun test_div_d() {
    let mut v1 = 1_000_000_000;
    let mut v2 = 1_000_000_000;
    assert!(vault_utils::div_d(v1, v2) == 1_000_000_000, 0);

    v1 = 1_000;
    v2 = 1_000;
    assert!(vault_utils::div_d(v1, v2) == 1_000_000_000, 0);

    v1 = 1_000_000_000;
    v2 = 10_000_000_000;
    assert!(vault_utils::div_d(v1, v2) == 100_000_000, 0);

    v1 = 1_000_000_000;
    v2 = 100_000_000_000;
    assert!(vault_utils::div_d(v1, v2) == 10_000_000, 0);
}

#[test]
// [TEST-CASE: Should multiply with oracle price.] @test-case CALCULATION-003
// Price is 10^18: 1U = 1e18
// Amount is 10^9: 1 coin = 1e9
// USD Value is 10^9: 1U = 1e9
public fun test_mul_with_oracle_price() {
    let mut amount = vault_utils::to_decimals(1);
    let mut price = vault_utils::to_oracle_price_decimals(1);

    assert!(vault_utils::from_oracle_price_decimals(price) == 1, 0);

    // 1 Coin * 1U/Coin = 1U
    assert!(vault_utils::mul_with_oracle_price(amount, price) == vault_utils::to_decimals(1), 0);

    amount = 10_000_000_000;
    price = 1_000_000_000_000_000_000;
    // 10 Coin * 1U/Coin = 10U
    assert!(vault_utils::mul_with_oracle_price(amount, price) == 10_000_000_000, 0);

    amount = 1_000_000_000;
    price = 10_000_000_000_000_000_000;
    // 1 Coin * 10U/Coin = 10U
    assert!(vault_utils::mul_with_oracle_price(amount, price) == 10_000_000_000, 0);
}

#[test]
// [TEST-CASE: Should divide with oracle price.] @test-case CALCULATION-004
// Price is 10^18: 1U = 1e18
// Amount is 10^9: 1 coin = 1e9
// USD Value is 10^9: 1U = 1e9
public fun test_div_with_oracle_price() {
    let mut usd_value = vault_utils::to_decimals(1);
    let mut price = vault_utils::to_oracle_price_decimals(1);

    assert!(vault_utils::from_oracle_price_decimals(price) == 1, 0);

    // 1 U / 1U/Coin = 1 Coin
    assert!(vault_utils::div_with_oracle_price(usd_value, price) == vault_utils::to_decimals(1), 0);

    usd_value = 10_000_000_000;
    price = 1_000_000_000_000_000_000;
    // 10 U / 1U/Coin = 10 Coin
    assert!(vault_utils::div_with_oracle_price(usd_value, price) == 10_000_000_000, 0);

    usd_value = 1_000_000_000;
    price = 10_000_000_000_000_000_000;
    // 1 U / 10U/Coin = 0.1 Coin
    assert!(vault_utils::div_with_oracle_price(usd_value, price) == 100_000_000, 0);
}

#[test]
// [TEST-CASE: Should get decimals.] @test-case CALCULATION-005
public fun test_decimal_getter() {
    assert!(vault_utils::decimals() == DECIMALS, 0);
}

#[test]
// [TEST-CASE: Should calculate correct min reward amount.] @test-case CALCULATION-006
public fun test_min_reward_amount_calculation() {
    // USDC reward to 1USD TVL
    let mut total_shares = 1_000_000_000;
    let mut min_reward_amount = vault_utils::mul_with_oracle_price(total_shares, 1);
    assert!(min_reward_amount == 0);

    // 1b USD TVL
    total_shares = 1_000_000_000 * DECIMALS;
    min_reward_amount = vault_utils::mul_with_oracle_price(total_shares, 1);
    std::debug::print(&std::ascii::string(b"min_reward_amount"));
    std::debug::print(&min_reward_amount);
    assert!(min_reward_amount == 1);

    // 1b USD TVL - 1
    total_shares = 1_000_000_000 * DECIMALS - 1;
    min_reward_amount = vault_utils::mul_with_oracle_price(total_shares, 1);
    std::debug::print(&std::ascii::string(b"min_reward_amount"));
    std::debug::print(&min_reward_amount);
    assert!(min_reward_amount == 0);

    // 1b USD TVL + 1
    total_shares = 1_000_000_000 * DECIMALS + 1;
    min_reward_amount = vault_utils::mul_with_oracle_price(total_shares, 1);
    std::debug::print(&std::ascii::string(b"min_reward_amount"));
    std::debug::print(&min_reward_amount);
    assert!(min_reward_amount == 1);

    let reward_amount = 1_000_000_000;
    total_shares = 1_000_000_000 * DECIMALS;
    let add_index = vault_utils::div_with_oracle_price(reward_amount, total_shares);
    std::debug::print(&std::ascii::string(b"add_index"));
    std::debug::print(&add_index);
    assert!(add_index == 1_000_000_000);
    std::debug::print(&std::ascii::string(b"User reward amount with 100USD shares"));
    std::debug::print(&vault_utils::mul_with_oracle_price(add_index, 100 * DECIMALS));
    std::debug::print(&std::ascii::string(b"User reward amount with 10_000USD shares"));
    std::debug::print(&vault_utils::mul_with_oracle_price(add_index, 10_000 * DECIMALS));
    std::debug::print(&std::ascii::string(b"User reward amount with 1_000_000USD shares"));
    std::debug::print(&vault_utils::mul_with_oracle_price(add_index, 1_000_000 * DECIMALS));
    std::debug::print(&std::ascii::string(b"User reward amount with 10_000_000USD shares"));
    std::debug::print(&vault_utils::mul_with_oracle_price(add_index, 10_000_000 * DECIMALS));
}

#[test]
// [TEST-CASE: Should rescale a pyth mantissa to the oracle 10^18 scale.] @test-case CALCULATION-007
public fun test_to_oracle_decimal() {
    // Pyth crypto feeds publish expo -8: 1.00000000 -> 1e18.
    assert!(vault_utils::to_oracle_decimal(100_000_000, 8) == 1_000_000_000_000_000_000);
    // 0.73698412 SUI/USD.
    assert!(vault_utils::to_oracle_decimal(73_698_412, 8) == 736_984_120_000_000_000);
    // 111_000 USD/BTC.
    assert!(
        vault_utils::to_oracle_decimal(11_100_000_000_000, 8) == 111_000_000_000_000_000_000_000,
    );

    // Already at 10^18: identity.
    assert!(
        vault_utils::to_oracle_decimal(1_234_567_890_123_456_789, 18) == 1_234_567_890_123_456_789,
    );

    // Zero exponent means the mantissa is the whole number.
    assert!(vault_utils::to_oracle_decimal(7, 0) == 7_000_000_000_000_000_000);

    // Finer than 10^18: the extra digits are truncated, not rounded.
    assert!(vault_utils::to_oracle_decimal(1_999_999_999, 27) == 1);
    assert!(vault_utils::to_oracle_decimal(999_999_999, 27) == 0);

    // The largest exponent the oracle accepts (MAX_PYTH_EXPO).
    assert!(vault_utils::to_oracle_decimal(1_000_000_000_000_000_000, 36) == 1);
}
