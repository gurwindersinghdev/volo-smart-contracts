// SPDX-License-Identifier: Apache 2

/// This module implements a container that collects fees in SUI denomination.
/// The `FeeCollector` requires that the fee deposited is exactly equal to the
/// `fee_amount` configured.
module wormhole_simple_majority::fee_collector {
    use sui::balance::{Self, Balance};
    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::tx_context::{TxContext};

    /// Amount deposited is not exactly the amount configured.
    const E_INCORRECT_FEE: u64 = 0;

    /// Container for configured `fee_amount` and `balance` of SUI collected.
    struct FeeCollector has store {
        fee_amount: u64,
        balance: Balance<SUI>
    }

    /// Create new `FeeCollector` with specified amount to collect.
    public fun new(fee_amount: u64): FeeCollector {
        FeeCollector { fee_amount, balance: balance::zero() }
    }

    /// Retrieve configured amount to collect.
    public fun fee_amount(self: &FeeCollector): u64 {
        self.fee_amount
    }

    /// Retrieve current SUI balance.
    public fun balance_value(self: &FeeCollector): u64 {
        balance::value(&self.balance)
    }

    /// Take `Balance<SUI>` and add it to current collected balance.
    public fun deposit_balance(self: &mut FeeCollector, fee: Balance<SUI>) {
        assert!(balance::value(&fee) == self.fee_amount, E_INCORRECT_FEE);
        balance::join(&mut self.balance, fee);
    }

    /// Take `Coin<SUI>` and add it to current collected balance.
    public fun deposit(self: &mut FeeCollector, fee: Coin<SUI>) {
        deposit_balance(self, coin::into_balance(fee))
    }

    /// Create `Balance<SUI>` of some `amount` by taking from collected balance.
    public fun withdraw_balance(
        self: &mut FeeCollector,
        amount: u64
    ): Balance<SUI> {
        // This will trigger `sui::balance::ENotEnough` if amount > balance.
        balance::split(&mut self.balance, amount)
    }

    /// Create `Coin<SUI>` of some `amount` by taking from collected balance.
    public fun withdraw(
        self: &mut FeeCollector,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<SUI> {
        coin::from_balance(withdraw_balance(self, amount), ctx)
    }

    /// Re-configure current `fee_amount`.
    public fun change_fee(self: &mut FeeCollector, new_amount: u64) {
        self.fee_amount = new_amount;
    }

    #[test_only]
    public fun destroy(collector: FeeCollector) {
        let FeeCollector { fee_amount: _, balance: bal } = collector;
        balance::destroy_for_testing(bal);
    }
}
