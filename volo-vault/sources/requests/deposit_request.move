module volo_vault::deposit_request;

// ------------- Structs ------------- //

public struct DepositRequest has copy, drop, store {
    request_id: u64, // Self incremented id (start from 0)
    // ---- Receipt Info ---- //
    receipt_id: address, // Receipt object address
    recipient: address, // Address that created the deposit (ctx.sender()); the buffered coin is refunded here if the request is cancelled
    // ---- Vault Info ---- //
    vault_id: address, // Vault address
    // ---- Deposit Info ---- //
    amount: u64, // Amount (of principal) to deposit
    expected_shares: u256, // Expected shares to get after deposit
    // ---- Request Status ---- //
    request_time: u64, // Time when the request is created
}

// ------------- Functions ------------- //

public(package) fun new(
    request_id: u64,
    receipt_id: address,
    recipient: address,
    vault_id: address,
    amount: u64,
    expected_shares: u256,
    timestamp: u64,
): DepositRequest {
    DepositRequest {
        request_id,
        receipt_id,
        recipient,
        vault_id,
        amount,
        expected_shares,
        request_time: timestamp,
    }
}

// ------------- Getters ------------- //

// Get the request id
public fun request_id(self: &DepositRequest): u64 {
    self.request_id
}

// Get the receipt id
public fun receipt_id(self: &DepositRequest): address {
    self.receipt_id
}

// Get the recipient address
public fun recipient(self: &DepositRequest): address {
    self.recipient
}

// Get the vault id
public fun vault_id(self: &DepositRequest): address {
    self.vault_id
}

// Get the deposit amount
public fun amount(self: &DepositRequest): u64 {
    self.amount
}

// Get the expected shares
public fun expected_shares(self: &DepositRequest): u256 {
    self.expected_shares
}

// Get the request time
public fun request_time(self: &DepositRequest): u64 {
    self.request_time
}