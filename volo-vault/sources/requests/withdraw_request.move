module volo_vault::withdraw_request;

// ------------- Structs ------------- //

public struct WithdrawRequest has copy, drop, store {
    request_id: u64, // Self incremented id (start from 0)
    // ---- Receipt Info ---- //
    receipt_id: address, // Receipt object address
    recipient: address, // Recipient address (only used for check when "with_lock" is true)
    // ---- Vault Info ---- //
    vault_id: address, // Vault address
    // ---- Withdraw Info ---- //
    shares: u256, // Shares to withdraw
    expected_amount: u64, // Expected amount to get after withdraw
    // ---- Request Status ---- //
    request_time: u64, // Time when the request is created
}

// ------------- Functions ------------- //

public(package) fun new(
    request_id: u64,
    receipt_id: address,
    recipient: address,
    vault_id: address,
    shares: u256,
    expected_amount: u64,
    timestamp: u64,
): WithdrawRequest {
    WithdrawRequest {
        request_id,
        receipt_id,
        recipient,
        vault_id,
        shares,
        expected_amount,
        request_time: timestamp,
    }
}

// ------------- Getters ------------- //

// Get the request id
public fun request_id(self: &WithdrawRequest): u64 {
    self.request_id
}

// Get the receipt id
public fun receipt_id(self: &WithdrawRequest): address {
    self.receipt_id
}

// Get the recipient address
public fun recipient(self: &WithdrawRequest): address {
    self.recipient
}

// Get the vault id
public fun vault_id(self: &WithdrawRequest): address {
    self.vault_id
}

// Get the shares to withdraw
public fun shares(self: &WithdrawRequest): u256 {
    self.shares
}

// Get the expected amount to get after withdraw
public fun expected_amount(self: &WithdrawRequest): u64 {
    self.expected_amount
}

// Get the request time
public fun request_time(self: &WithdrawRequest): u64 {
    self.request_time
}