module volo_vault::navi_adaptor;

use lending_core::account::AccountCap as NaviAccountCap;
use lending_core::dynamic_calculator;
use lending_core::storage::Storage;
use lending_core::ray_math;
use std::ascii::String;
use sui::clock::Clock;
use sui::dynamic_field;
use sui::event::emit;
use sui::table::{Self, Table};
use sui::vec_map::{Self, VecMap};
use volo_vault::vault::Vault;
use volo_vault::vault_oracle::{Self, OracleConfig};
use volo_vault::vault_utils;

// The supplied Storage's market is not whitelisted for this NAVI account-cap asset.
const ERR_NAVI_MARKET_NOT_WHITELISTED: u64 = 6_001;
// The market is already whitelisted for this NAVI account-cap asset.
const ERR_NAVI_MARKET_ALREADY_WHITELISTED: u64 = 6_002;
// A market can only be removed from the whitelist once its recorded value is 0.
const ERR_NAVI_MARKET_VALUE_NOT_ZERO: u64 = 6_003;
// A market can only be removed using a freshly-synced (current-timestamp) value, never a stale 0.
const ERR_NAVI_MARKET_VALUE_STALE: u64 = 6_004;
// A market can only be whitelisted while the NAVI account holds no assets (supply or debt) in it.
const ERR_NAVI_MARKET_NOT_EMPTY: u64 = 6_005;
// The one-off registry migration is past its deadline.
const ERR_MIGRATION_WINDOW_CLOSED: u64 = 6_006;
// The one-off registry migration was handed a Storage other than the NAVI main market.
const ERR_MIGRATION_MARKET_NOT_MAIN: u64 = 6_007;

// 2026-09-01T00:00:00Z — the one-off migration must be done by the end of 2026-08-31 UTC.
const MIGRATION_DEADLINE_MS: u64 = 1_788_220_800_000;

// The market every pre-registry NAVI position lives in.
const NAVI_MAIN_MARKET_ID: u64 = 0;

// A NAVI account (one account-cap under one `asset_type`) may hold positions across several markets,
// each a separate Storage. The registry records, per `asset_type`, the whitelisted markets and each
// market's latest value + update time. The aggregate commits to the vault only once every market is
// synced at the same timestamp; a partial update leaves the stored value/time untouched, so the
// value-update gate (MAX_UPDATE_INTERVAL == 0) stays closed until all markets refresh in one tx.
//
// The sync is consumed (every market's timestamp reset) on commit AND when the account cap is
// returned at end-op, so a market value recorded pre-op can never reach a commit — the clock is
// constant within a tx, so otherwise an operator could hide a loss behind a stale per-market value.

public struct NaviMarketRegistryKey has copy, drop, store {}

public struct NaviMarketState has copy, drop, store {
    value: u256,
    updated_at: u64,
}

public struct NaviMarketRegistry has store {
    // NAVI account-cap asset_type -> (market_id -> latest per-market state)
    markets: Table<String, VecMap<u64, NaviMarketState>>,
}

// ------------------------ Events ------------------------ //

public struct NaviMarketRegistryInitialized has copy, drop {
    vault_id: address,
    // Installed through the migration path, which also emits one NaviMarketAdded per account cap.
    migration: bool,
}

public struct NaviMarketAdded has copy, drop {
    vault_id: address,
    asset_type: String,
    market_id: u64,
}

public struct NaviMarketRemoved has copy, drop {
    vault_id: address,
    asset_type: String,
    market_id: u64,
}

// ------------------------ Registry management ------------------------ //

// One-time init of the NAVI multi-market registry on the vault. Cap-gated via vault_manage.
public(package) fun init_navi_market_registry<PrincipalCoinType>(
    vault: &mut Vault<PrincipalCoinType>,
    ctx: &mut TxContext,
) {
    install_registry(vault, ctx);

    emit(NaviMarketRegistryInitialized { vault_id: vault.vault_id(), migration: false });
}

// Aborts if the vault already has a registry: both init paths are one-shot and mutually exclusive.
fun install_registry<PrincipalCoinType>(
    vault: &mut Vault<PrincipalCoinType>,
    ctx: &mut TxContext,
) {
    vault.check_version();

    dynamic_field::add(
        vault.vault_id_mut(),
        NaviMarketRegistryKey {},
        NaviMarketRegistry {
            markets: table::new<String, VecMap<u64, NaviMarketState>>(ctx),
        },
    );
}

// MIGRATION ONLY, until MIGRATION_DEADLINE_MS — for vaults that predate the registry. Whitelists the
// main market for every NAVI account cap, skipping the empty check.
public(package) fun init_navi_market_registry_for_migration<PrincipalCoinType>(
    vault: &mut Vault<PrincipalCoinType>,
    storage: &Storage,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert!(clock.timestamp_ms() < MIGRATION_DEADLINE_MS, ERR_MIGRATION_WINDOW_CLOSED);
    assert!(storage.get_market_id() == NAVI_MAIN_MARKET_ID, ERR_MIGRATION_MARKET_NOT_MAIN);
    // A cap borrowed out mid-operation is absent from the bag and would be silently skipped.
    vault.assert_not_during_operation();

    install_registry(vault, ctx);

    emit(NaviMarketRegistryInitialized { vault_id: vault.vault_id(), migration: true });

    let asset_types = *vault.asset_types();
    asset_types.do_ref!(|asset_type| {
        if (vault.contains_defi_asset_of_type<PrincipalCoinType, NaviAccountCap>(*asset_type)) {
            add_navi_market_by_id(vault, *asset_type, NAVI_MAIN_MARKET_ID);
        };
    });
}

// Add a market to the whitelist of a NAVI account-cap asset. The market is identified by its live
// Storage object rather than a raw id: a whitelisted market must be synced on every value update,
// so whitelisting an id with no backing Storage would permanently block the asset's value from
// committing. The account must hold no assets in the new market yet: a pre-existing balance would
// be missing from the committed total until the next full sync. Cap-gated via vault_manage.
public(package) fun add_navi_market<PrincipalCoinType>(
    vault: &mut Vault<PrincipalCoinType>,
    asset_type: String,
    storage: &mut Storage,
) {
    let account_cap = vault.get_defi_asset_inner<PrincipalCoinType, NaviAccountCap>(asset_type);
    let owner = account_cap.account_owner();
    assert_navi_market_empty(owner, storage);

    add_navi_market_by_id(vault, asset_type, storage.get_market_id());
}

// Raw scaled balances suffice (indexes > 0, so scaled 0 <=> actual 0) — no oracle needed.
fun assert_navi_market_empty(account: address, storage: &mut Storage) {
    storage.get_reserves_count().do!(|i| {
        let (supply, borrow) = storage.get_user_balance(i, account);
        assert!(supply == 0 && borrow == 0, ERR_NAVI_MARKET_NOT_EMPTY);
    });
}

fun add_navi_market_by_id<PrincipalCoinType>(
    vault: &mut Vault<PrincipalCoinType>,
    asset_type: String,
    market_id: u64,
) {
    vault.check_version();
    vault.assert_enabled();
    vault.assert_not_during_operation();

    let registry = registry_mut(vault);
    if (!registry.markets.contains(asset_type)) {
        registry.markets.add(asset_type, vec_map::empty<u64, NaviMarketState>());
    };

    let market_states = registry.markets.borrow_mut(asset_type);
    assert!(!market_states.contains(&market_id), ERR_NAVI_MARKET_ALREADY_WHITELISTED);
    market_states.insert(market_id, NaviMarketState { value: 0, updated_at: 0 });

    emit(NaviMarketAdded { vault_id: vault.vault_id(), asset_type, market_id });
}

// Remove a market from the whitelist of a NAVI account-cap asset. Only permitted once the market's
// recorded value is 0 AND that 0 was just synced at the current timestamp (not a stale snapshot):
// because each market's value is clamped to 0 in isolation, a market carrying debt already
// contributes 0 to the aggregate, so removing a freshly-synced 0-value market cannot overstate the
// position. Cap-gated via vault_manage.
public(package) fun remove_navi_market<PrincipalCoinType>(
    vault: &mut Vault<PrincipalCoinType>,
    asset_type: String,
    market_id: u64,
    clock: &Clock,
) {
    vault.check_version();
    vault.assert_enabled();
    vault.assert_not_during_operation();

    let registry = registry_mut(vault);
    assert!(registry.markets.contains(asset_type), ERR_NAVI_MARKET_NOT_WHITELISTED);

    let market_states = registry.markets.borrow_mut(asset_type);
    assert!(market_states.contains(&market_id), ERR_NAVI_MARKET_NOT_WHITELISTED);
    let state = market_states.get(&market_id);
    assert!(state.value == 0, ERR_NAVI_MARKET_VALUE_NOT_ZERO);
    // Reject a stale 0: the market must have been re-synced this timestamp, so the 0 reflects the
    // live position rather than an outdated snapshot that has since accrued value.
    assert!(state.updated_at == clock.timestamp_ms(), ERR_NAVI_MARKET_VALUE_STALE);

    market_states.remove(&market_id);

    emit(NaviMarketRemoved { vault_id: vault.vault_id(), asset_type, market_id });
}

// ------------------------ Getters ------------------------ //

public fun has_navi_market_registry<PrincipalCoinType>(vault: &Vault<PrincipalCoinType>): bool {
    dynamic_field::exists_with_type<NaviMarketRegistryKey, NaviMarketRegistry>(
        vault.vault_uid(),
        NaviMarketRegistryKey {},
    )
}

// The markets that must all be synced before `asset_type`'s value can commit. Empty when the vault
// has no registry or the asset has no whitelisted market — such an asset can never commit.
public fun navi_market_ids<PrincipalCoinType>(
    vault: &Vault<PrincipalCoinType>,
    asset_type: String,
): vector<u64> {
    if (!has_navi_market_registry(vault)) {
        return vector[]
    };

    let registry = registry(vault);
    if (!registry.markets.contains(asset_type)) {
        return vector[]
    };
    registry.markets.borrow(asset_type).keys()
}

fun registry<PrincipalCoinType>(vault: &Vault<PrincipalCoinType>): &NaviMarketRegistry {
    dynamic_field::borrow<NaviMarketRegistryKey, NaviMarketRegistry>(
        vault.vault_uid(),
        NaviMarketRegistryKey {},
    )
}

fun registry_mut<PrincipalCoinType>(
    vault: &mut Vault<PrincipalCoinType>,
): &mut NaviMarketRegistry {
    dynamic_field::borrow_mut<NaviMarketRegistryKey, NaviMarketRegistry>(
        vault.vault_id_mut(),
        NaviMarketRegistryKey {},
    )
}

// ------------------------ Value update ------------------------ //

public fun update_navi_position_value<PrincipalCoinType>(
    vault: &mut Vault<PrincipalCoinType>,
    config: &OracleConfig,
    clock: &Clock,
    asset_type: String,
    storage: &mut Storage,
) {
    vault.check_version();
    vault.assert_enabled();

    let market_id = storage.get_market_id();

    let account_cap = vault.get_defi_asset_inner<PrincipalCoinType, NaviAccountCap>(asset_type);
    let owner = account_cap.account_owner();

    let market_value = calculate_navi_position_value(
        owner,
        storage,
        config,
        clock,
    );

    let now = clock.timestamp_ms();
    let (total_value, all_synced) = record_navi_market_value(
        vault,
        asset_type,
        market_id,
        market_value,
        now,
    );

    // Commit the aggregate to the vault ONLY once every whitelisted market has been synced at this
    // same timestamp. Until then the asset's stored value and update time are left untouched, so a
    // partial update never writes an incomplete aggregate and the value-update gate stays closed.
    if (all_synced) {
        vault.finish_update_asset_value(asset_type, total_value, now);
    };
}

// Refresh the per-market state for `market_id`, then recompute the asset's aggregate value and
// report whether every whitelisted market has been synced at `now`.
fun record_navi_market_value<PrincipalCoinType>(
    vault: &mut Vault<PrincipalCoinType>,
    asset_type: String,
    market_id: u64,
    market_value: u256,
    now: u64,
): (u256, bool) {
    let registry = registry_mut(vault);
    assert!(registry.markets.contains(asset_type), ERR_NAVI_MARKET_NOT_WHITELISTED);

    let market_states = registry.markets.borrow_mut(asset_type);
    assert!(market_states.contains(&market_id), ERR_NAVI_MARKET_NOT_WHITELISTED);

    let state = market_states.get_mut(&market_id);
    state.value = market_value;
    state.updated_at = now;

    let mut total_value: u256 = 0;
    let mut all_synced = true;
    let market_ids = market_states.keys();
    market_ids.do_ref!(|id| {
        let s = market_states.get(id);
        total_value = total_value + s.value;
        // Synced iff timestamp == this call's `now`. `updated_at == 0` is the unsynced sentinel; the
        // ambiguous case `now == 0` is unreachable on-chain (`now` is always > 0).
        if (s.updated_at != now) {
            all_synced = false;
        };
    });

    // On a full sync, consume it: reset every market's `updated_at` so the next commit must re-value
    // all markets from live Storage rather than reuse a value synced before this point. See the
    // module header for the operator loss-hiding attack this closes.
    if (all_synced) {
        reset_market_sync(market_states);
    };

    (total_value, all_synced)
}

// Consume any recorded sync: the aggregate can only commit once ALL markets are re-valued.
fun reset_market_sync(market_states: &mut VecMap<u64, NaviMarketState>) {
    market_states.keys().do_ref!(|id| {
        market_states.get_mut(id).updated_at = 0;
    });
}

// Called when the account cap is returned at end-op: consume any partial sync recorded pre-op so
// it can never combine with post-op syncs into a commit (see module header).
public(package) fun reset_navi_market_sync<PrincipalCoinType>(
    vault: &mut Vault<PrincipalCoinType>,
    asset_type: String,
) {
    reset_market_sync(registry_mut(vault).markets.borrow_mut(asset_type));
}

// Net USD value of a NAVI account within a single market (Storage). Markets are isolated, so the
// value is clamped to 0 per market before being aggregated by the caller.
public fun calculate_navi_position_value(
    account: address,
    storage: &mut Storage,
    config: &OracleConfig,
    clock: &Clock,
): u256 {

    let mut total_supply_usd_value: u256 = 0;
    let mut total_borrow_usd_value: u256 = 0;

    // i: asset id
    storage.get_reserves_count().do!(|i| {
        let (supply, borrow) = storage.get_user_balance(i, account);

        // let (supply_index, borrow_index) = storage.get_index(i - 1);
        let (supply_index, borrow_index) = dynamic_calculator::calculate_current_index(
            clock,
            storage,
            i,
        );
        let supply_scaled = ray_math::ray_mul(supply, supply_index);
        let borrow_scaled = ray_math::ray_mul(borrow, borrow_index);

        let coin_type = storage.get_coin_type(i);

        if (supply == 0 && borrow == 0) {
            return;
        };

        // Skip a supply-only reserve with no Volo feed. Anyone can donate collateral into the NAVI
        // account permissionlessly (NAVI's deposit-on-behalf, no account-cap), but has no borrow- or
        // withdraw-on-behalf, so donated exposure is always supply-only. Dropping it only undervalues
        // (never hides debt), which stops a dust donation of an unlisted coin from deadlocking every
        // value update. A reserve with debt is never dropped (`borrow != 0` falls through to abort);
        // an attacker cannot create debt here, so that only guards operator misconfiguration.
        if (borrow == 0 && !vault_oracle::has_aggregator(config, coin_type)) {
            return;
        };

        let price = vault_oracle::get_asset_price(config, clock, coin_type);

        let supply_usd_value = vault_utils::mul_with_oracle_price(supply_scaled as u256, price);
        let borrow_usd_value = vault_utils::mul_with_oracle_price(borrow_scaled as u256, price);

        total_supply_usd_value = total_supply_usd_value + supply_usd_value;
        total_borrow_usd_value = total_borrow_usd_value + borrow_usd_value;
    });

    if (total_supply_usd_value < total_borrow_usd_value) {
        return 0
    };

    total_supply_usd_value - total_borrow_usd_value
}

#[test_only]
public fun navi_market_value_for_testing<PrincipalCoinType>(
    vault: &Vault<PrincipalCoinType>,
    asset_type: String,
    market_id: u64,
): (u256, u64) {
    let state = registry(vault).markets.borrow(asset_type).get(&market_id);
    (state.value, state.updated_at)
}

#[test_only]
public fun registry_initialized_is_migration(e: &NaviMarketRegistryInitialized): bool {
    e.migration
}

// Whitelist a market by raw id, bypassing the Storage existence guarantee. Test-only: lets tests
// whitelist markets simulated via set_market_id_for_testing without a real second Storage.
#[test_only]
public fun add_navi_market_for_testing<PrincipalCoinType>(
    vault: &mut Vault<PrincipalCoinType>,
    asset_type: String,
    market_id: u64,
) {
    add_navi_market_by_id(vault, asset_type, market_id);
}

#[test_only]
public fun set_navi_market_value_for_testing<PrincipalCoinType>(
    vault: &mut Vault<PrincipalCoinType>,
    asset_type: String,
    market_id: u64,
    value: u256,
) {
    let registry = registry_mut(vault);
    let state = registry.markets.borrow_mut(asset_type).get_mut(&market_id);
    state.value = value;
}
