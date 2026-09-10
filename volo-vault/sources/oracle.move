module volo_vault::vault_oracle;

use std::ascii::String;
use std::u64::pow;
use sui::clock::Clock;
use sui::event::emit;
use sui::table::{Self, Table};
use sui::address::{Self};
use volo_vault::vault_utils;

use switchboard::aggregator::Aggregator;
use pyth_pro_compatible::i64::{Self as pro_i64};
use pyth_pro_compatible::pyth::{Self as pro_pyth};
use pyth_pro_compatible::price::{Self as pro_price};
use pyth_pro_compatible::state::{Self as pro_state, State as ProState};
use pyth_pro_compatible::price_info::{Self as pro_price_info, PriceInfoObject as ProPriceInfoObject};
use pyth_pro_compatible::price_identifier::{Self as pro_price_identifier};


// ---------------------  Constants  ---------------------//
// const VERSION: u64 = 2;
// ^(v1.4 upgrade - new)
// const VERSION: u64 = 4;
// ^(pyth migration - new) bumped to version-gate the pre-migration package, whose switchboard
// entrypoints still work, out of this OracleConfig.
const VERSION: u64 = 5;

const MAX_UPDATE_INTERVAL: u64 = 1000 * 60; // 1 minute
const FUTURE_TOLERANCE_MS: u64 = 1000 * 60; // 60 seconds

const DEFAULT_DEX_SLIPPAGE: u256 = 100; // 1%

// Pyth has no VSUI/USD feed, only the redemption rate, so vSUI = SUI/USD * VSUI/SUI.RR.
// These are Pyth feed ids (the value inside a PriceInfoObject), not Sui object ids.
const PYTH_SUI_USD_PRICE_ID: address =
    @0x23d7315113f5b1d3ba7a83604c44b94d79f4fd69af77f804fc7f920a6dc65744;
const PYTH_VSUI_SUI_RATE_PRICE_ID: address =
    @0x77a89fd7818905d056d1ba2a841868ad932fd32260a98a2205c5db28e02ea736;
const VSUI_ASSET_TYPE: vector<u8> =
    b"549e8b69270defbfafd4f94e17ec44cdbdd99820b33bda2278dea3b9a32d3f55::cert::CERT";
const VSUI_DECIMALS: u8 = 9;

// A redemption rate only accrues, so >= 1 by construction; the ceiling bounds a bad print.
const MIN_VSUI_SUI_RATE: u256 = 1_000_000_000_000_000_000;
const MAX_VSUI_SUI_RATE: u256 = 2_000_000_000_000_000_000;

const MAX_PYTH_EXPO: u64 = 36;

// ---------------------  Errors  ---------------------//
const ERR_AGGREGATOR_NOT_FOUND: u64 = 2_001;
const ERR_PRICE_NOT_UPDATED: u64 = 2_002;
const ERR_AGGREGATOR_ALREADY_EXISTS: u64 = 2_003;
const ERR_AGGREGATOR_ASSET_MISMATCH: u64 = 2_004;
const ERR_INVALID_VERSION: u64 = 2_005;
const ERR_FUTURE_TOLERANCE_EXCEEDED: u64 = 2_006;
const ERR_INVALID_PRICE: u64 = 2_007;
const ERR_INVALID_UPDATE_INTERVAL: u64 = 2_008;
// ^(pyth migration - new)
const ERR_SWITCHBOARD_DEPRECATED: u64 = 2_009;
const ERR_RATE_FEED_NEEDS_DEDICATED_UPDATE: u64 = 2_010;
const ERR_NOT_RATE_FEED: u64 = 2_011;
const ERR_NOT_SUI_PRICE_FEED: u64 = 2_012;
const ERR_RATE_OUT_OF_RANGE: u64 = 2_013;
const ERR_NOT_VSUI_ASSET_TYPE: u64 = 2_014;

// ---------------------  Structs  ---------------------//
public struct PriceInfo has drop, store {
    aggregator: address,
    decimals: u8,
    price: u256,
    last_updated: u64,
}

public struct OracleConfig has key, store {
    id: UID,
    version: u64,
    aggregators: Table<String, PriceInfo>,
    update_interval: u64,
    dex_slippage: u256, // Pool price and oracle price slippage parameter (used in adaptors related to DEX)
}

// ---------------------  Events  ---------------------//

public struct UpdateIntervalSet has copy, drop {
    update_interval: u64,
}

public struct DexSlippageSet has copy, drop {
    dex_slippage: u256,
}

// deprecated
#[allow(unused_field)]
public struct PriceUpdated has copy, drop {
    price: u256,
    timestamp: u64,
}

public struct SwitchboardAggregatorAdded has copy, drop {
    asset_type: String,
    aggregator: address,
}

public struct PythAggregatorAdded has copy, drop {
    asset_type: String,
    aggregator: address,
}

public struct SwitchboardAggregatorRemoved has copy, drop {
    asset_type: String,
    aggregator: address,
}

public struct PythAggregatorRemoved has copy, drop {
    asset_type: String,
    aggregator: address,
}

public struct SwitchboardAggregatorChanged has copy, drop {
    asset_type: String,
    old_aggregator: address,
    new_aggregator: address,
}

public struct PythAggregatorChanged has copy, drop {
    asset_type: String,
    old_aggregator: address,
    new_aggregator: address,
}

public struct OracleConfigUpgraded has copy, drop {
    oracle_config_id: address,
    version: u64,
}

public struct AssetPriceUpdated has copy, drop {
    asset_type: String,
    price: u256,
    timestamp: u64,
}

// ---------------------  Initialization  ---------------------//
fun init(ctx: &mut TxContext) {
    let config = OracleConfig {
        id: object::new(ctx),
        version: VERSION,
        aggregators: table::new(ctx),
        update_interval: MAX_UPDATE_INTERVAL,
        dex_slippage: DEFAULT_DEX_SLIPPAGE,
    };

    transfer::share_object(config);
}

public(package) fun check_version(self: &OracleConfig) {
    assert!(self.version == VERSION, ERR_INVALID_VERSION);
}

public(package) fun upgrade_oracle_config(self: &mut OracleConfig) {
    assert!(self.version < VERSION, ERR_INVALID_VERSION);
    self.version = VERSION;

    emit(OracleConfigUpgraded {
        oracle_config_id: self.id.to_address(),
        version: VERSION,
    });
}

public(package) fun set_update_interval(config: &mut OracleConfig, update_interval: u64) {
    config.check_version();

    assert!(
        update_interval > 0 && update_interval <= MAX_UPDATE_INTERVAL,
        ERR_INVALID_UPDATE_INTERVAL,
    );

    config.update_interval = update_interval;
    emit(UpdateIntervalSet { update_interval })
}

public(package) fun set_dex_slippage(config: &mut OracleConfig, dex_slippage: u256) {
    config.check_version();

    config.dex_slippage = dex_slippage;
    emit(DexSlippageSet { dex_slippage })
}

// ---------------------  Public Functions  ---------------------//

public fun get_asset_price(config: &OracleConfig, clock: &Clock, asset_type: String): u256 {
    config.check_version();

    assert!(table::contains(&config.aggregators, asset_type), ERR_AGGREGATOR_NOT_FOUND);

    let price_info = &config.aggregators[asset_type];
    let now = clock.timestamp_ms();

    // Price must be updated within update_interval
    assert!(price_info.last_updated.diff(now) < config.update_interval, ERR_PRICE_NOT_UPDATED);

    price_info.price
}

public fun get_normalized_asset_price(
    config: &OracleConfig,
    clock: &Clock,
    asset_type: String,
): u256 {
    let price = get_asset_price(config, clock, asset_type);
    let decimals = config.aggregators[asset_type].decimals;

    // Normalize price to 9 decimals
    if (decimals < 9) {
        price * (pow(10, 9 - decimals) as u256)
    } else {
        price / (pow(10, decimals - 9) as u256)
    }
}

// ------------------ Aggregator Management ------------------//

// !(pyth migration - deprecated) Use `add_pyth_aggregator`. Signature kept for upgrade compat.
#[allow(unused_variable, unused_mut_parameter)]
public(package) fun add_switchboard_aggregator(
    config: &mut OracleConfig,
    clock: &Clock,
    asset_type: String,
    decimals: u8,
    aggregator: &Aggregator,
) {
    abort ERR_SWITCHBOARD_DEPRECATED
}

// ^(pyth migration - new)
// Register a plain USD feed. Rate feeds are rejected: only the vsui entrypoints take those.
public(package) fun add_pyth_aggregator(
    config: &mut OracleConfig,
    clock: &Clock,
    asset_type: String,
    decimals: u8,
    pyth_state: &ProState,
    pyth_price_info: &ProPriceInfoObject,
) {
    config.check_version();

    assert!(!config.aggregators.contains(asset_type), ERR_AGGREGATOR_ALREADY_EXISTS);
    let now = clock.timestamp_ms();

    let pyth_info_id = get_pyth_object_identifier(pyth_price_info);
    assert!(!is_rate_feed(pyth_info_id), ERR_RATE_FEED_NEEDS_DEDICATED_UPDATE);

    let init_price = get_current_price_v2(config, clock, pyth_state, pyth_price_info);

    let price_info = PriceInfo {
        aggregator: pyth_info_id,
        decimals,
        price: init_price,
        last_updated: now,
    };
    config.aggregators.add(asset_type, price_info);

    emit(PythAggregatorAdded {
        asset_type,
        aggregator: pyth_info_id,
    });
}

// ^(pyth migration - new)
// Point vSUI at the redemption-rate feed. Seeds no price, so it stays unreadable (and a
// forgotten follow-up fails closed) until the first `update_price_v2_for_vsui`.
public(package) fun set_pyth_aggregator_for_vsui(
    config: &mut OracleConfig,
    pyth_vsui_rr_price_info: &ProPriceInfoObject,
) {
    config.check_version();

    let rate_feed_id = get_pyth_object_identifier(pyth_vsui_rr_price_info);
    assert!(is_rate_feed(rate_feed_id), ERR_NOT_RATE_FEED);

    let asset_type = vsui_asset_type();

    if (config.aggregators.contains(asset_type)) {
        let price_info = &mut config.aggregators[asset_type];

        emit(PythAggregatorChanged {
            asset_type,
            old_aggregator: price_info.aggregator,
            new_aggregator: rate_feed_id,
        });

        price_info.aggregator = rate_feed_id;
        price_info.price = 0;
        price_info.last_updated = 0;
    } else {
        config
            .aggregators
            .add(
                asset_type,
                PriceInfo {
                    aggregator: rate_feed_id,
                    decimals: VSUI_DECIMALS,
                    price: 0,
                    last_updated: 0,
                },
            );

        emit(PythAggregatorAdded {
            asset_type,
            aggregator: rate_feed_id,
        });
    }
}

// !(pyth migration - deprecated) Use `remove_pyth_aggregator`.
#[allow(unused_variable, unused_mut_parameter)]
public(package) fun remove_switchboard_aggregator(config: &mut OracleConfig, asset_type: String) {
    abort ERR_SWITCHBOARD_DEPRECATED
}

// ^(pyth migration - new)
// Drops the feed entirely; for assets Pyth does not price at all (SLP).
public(package) fun remove_pyth_aggregator(config: &mut OracleConfig, asset_type: String) {
    config.check_version();
    assert!(config.aggregators.contains(asset_type), ERR_AGGREGATOR_NOT_FOUND);

    emit(PythAggregatorRemoved {
        asset_type,
        aggregator: config.aggregators[asset_type].aggregator,
    });

    config.aggregators.remove(asset_type);
}


// !(pyth migration - deprecated) Use `change_pyth_aggregator`.
#[allow(unused_variable, unused_mut_parameter)]
public(package) fun change_switchboard_aggregator(
    config: &mut OracleConfig,
    clock: &Clock,
    asset_type: String,
    aggregator: &Aggregator,
) {
    abort ERR_SWITCHBOARD_DEPRECATED
}

// ^(pyth migration - new)
// The cutover path: repoint an entry onto a Pyth feed id and reseed the price. Atomic on
// purpose - a remove/add pair leaves a window where NAVI positions in that asset value at 0.
public(package) fun change_pyth_aggregator(
    config: &mut OracleConfig,
    clock: &Clock,
    asset_type: String,
    pyth_state: &ProState,
    pyth_price_info: &ProPriceInfoObject,
) {
    config.check_version();
    assert!(config.aggregators.contains(asset_type), ERR_AGGREGATOR_NOT_FOUND);

    let pyth_info_id = get_pyth_object_identifier(pyth_price_info);
    assert!(!is_rate_feed(pyth_info_id), ERR_RATE_FEED_NEEDS_DEDICATED_UPDATE);

    let init_price = get_current_price_v2(config, clock, pyth_state, pyth_price_info);

    let price_info = &mut config.aggregators[asset_type];

    emit(PythAggregatorChanged {
        asset_type,
        old_aggregator: price_info.aggregator,
        new_aggregator: pyth_info_id,
    });

    price_info.aggregator = pyth_info_id;
    price_info.price = init_price;
    price_info.last_updated = clock.timestamp_ms();
}


// ------------------ Price Update ------------------//

// !(pyth migration - deprecated) Use `update_price_v2` / `update_price_v2_for_vsui`.
#[allow(unused_variable, unused_mut_parameter)]
public fun update_price(
    config: &mut OracleConfig,
    aggregator: &Aggregator,
    clock: &Clock,
    asset_type: String,
) {
    abort ERR_SWITCHBOARD_DEPRECATED
}

// ^(pyth migration - new)
// Copy a Pyth price in (the PriceInfoObject must be pushed first). Permissionless: only a price
// Pyth signed, only for the asset whose registered feed matches.
public fun update_price_v2(
    config: &mut OracleConfig,
    pyth_state: &ProState,
    pyth_price_info: &ProPriceInfoObject,
    clock: &Clock,
    asset_type: String,
) {
    config.check_version();
    assert!(config.aggregators.contains(asset_type), ERR_AGGREGATOR_NOT_FOUND);

    let now = clock.timestamp_ms();
    let pyth_info_id = get_pyth_object_identifier(pyth_price_info);
    // A rate is not a USD price - vSUI must go through `update_price_v2_for_vsui`.
    assert!(!is_rate_feed(pyth_info_id), ERR_RATE_FEED_NEEDS_DEDICATED_UPDATE);

    let current_price = get_current_price_v2(config, clock, pyth_state, pyth_price_info);

    let price_info = &mut config.aggregators[asset_type];
    assert!(price_info.aggregator == pyth_info_id, ERR_AGGREGATOR_ASSET_MISMATCH);

    price_info.price = current_price;
    price_info.last_updated = now;

    emit(AssetPriceUpdated {
        asset_type,
        price: current_price,
        timestamp: now,
    })
}

// ^(pyth migration - new)
// vSUI price = SUI/USD * VSUI/SUI redemption rate. Permissionless like `update_price_v2`;
// asset type and both feeds are pinned by constant.
public fun update_price_v2_for_vsui(
    config: &mut OracleConfig,
    pyth_state: &ProState,
    pyth_sui_price_info: &ProPriceInfoObject,
    pyth_vsui_rr_price_info: &ProPriceInfoObject,
    clock: &Clock,
    asset_type: String,
) {
    config.check_version();
    assert!(asset_type == vsui_asset_type(), ERR_NOT_VSUI_ASSET_TYPE);
    assert!(config.aggregators.contains(asset_type), ERR_AGGREGATOR_NOT_FOUND);

    let now = clock.timestamp_ms();

    assert!(
        get_pyth_object_identifier(pyth_sui_price_info) == PYTH_SUI_USD_PRICE_ID,
        ERR_NOT_SUI_PRICE_FEED,
    );
    let rate_feed_id = get_pyth_object_identifier(pyth_vsui_rr_price_info);
    assert!(is_rate_feed(rate_feed_id), ERR_NOT_RATE_FEED);

    // Each leg carries its own freshness and sanity checks.
    let sui_price = get_current_price_v2(config, clock, pyth_state, pyth_sui_price_info);
    let vsui_sui_rate = get_current_price_v2(config, clock, pyth_state, pyth_vsui_rr_price_info);
    assert!(
        vsui_sui_rate >= MIN_VSUI_SUI_RATE && vsui_sui_rate <= MAX_VSUI_SUI_RATE,
        ERR_RATE_OUT_OF_RANGE,
    );

    // Both operands are 10^18 fixed point, and so is the product.
    let current_price = vault_utils::mul_with_oracle_price(sui_price, vsui_sui_rate);
    assert!(current_price > 0, ERR_INVALID_PRICE);

    let price_info = &mut config.aggregators[asset_type];
    assert!(price_info.aggregator == rate_feed_id, ERR_AGGREGATOR_ASSET_MISMATCH);

    price_info.price = current_price;
    price_info.last_updated = now;

    emit(AssetPriceUpdated {
        asset_type,
        price: current_price,
        timestamp: now,
    })
}

// !(pyth migration - deprecated) Use `get_current_price_v2`.
#[allow(unused_variable, unused_mut_parameter)]
public fun get_current_price(config: &OracleConfig, clock: &Clock, aggregator: &Aggregator): u256 {
    abort ERR_SWITCHBOARD_DEPRECATED
}

// ^(pyth migration - new)
// A Pyth feed normalised to the oracle's 10^18 fixed point. `pro_pyth::get_price` applies Pyth's
// staleness threshold; we hold it to `update_interval` on top.
public fun get_current_price_v2(
    config: &OracleConfig,
    clock: &Clock,
    pyth_state: &ProState,
    pyth_price_info: &ProPriceInfoObject,
): u256 {
    config.check_version();

    let now = clock.timestamp_ms();

    let pyth_price = pro_pyth::get_price(pyth_state, pyth_price_info, clock);

    let i64_price = pro_price::get_price(&pyth_price);
    let i64_expo = pro_price::get_expo(&pyth_price);
    // timestamp from pyth is in seconds, should be multiplied by 1000
    let timestamp = pro_price::get_timestamp(&pyth_price) * 1000;

    // Check the signs before unwrapping so we abort with our own error, not pyth's bare 0.
    assert!(!pro_i64::get_is_negative(&i64_price), ERR_INVALID_PRICE);
    assert!(pro_i64::get_is_negative(&i64_expo), ERR_INVALID_PRICE);

    let price = pro_i64::get_magnitude_if_positive(&i64_price);
    let expo = pro_i64::get_magnitude_if_negative(&i64_expo);
    assert!(expo <= MAX_PYTH_EXPO, ERR_INVALID_PRICE);

    assert!(timestamp <= now + FUTURE_TOLERANCE_MS, ERR_FUTURE_TOLERANCE_EXCEEDED);

    if (now >= timestamp) {
        assert!(now - timestamp < config.update_interval, ERR_PRICE_NOT_UPDATED);
    };

    let price = vault_utils::to_oracle_decimal(price as u256, expo);

    // A zero result signals a malfunctioning aggregator
    assert!(price > 0, ERR_INVALID_PRICE);

    price
}

// ^(pyth migration - new)
// Feeds that quote a ratio rather than a USD price, and must never be stored as one.
fun is_rate_feed(pyth_price_id: address): bool {
    pyth_price_id == PYTH_VSUI_SUI_RATE_PRICE_ID
}

// ^(pyth migration - new)
public fun vsui_asset_type(): String {
    std::ascii::string(VSUI_ASSET_TYPE)
}

// ------------------ Getters ------------------//

public fun update_interval(config: &OracleConfig): u64 {
    config.update_interval
}

public fun coin_decimals(config: &OracleConfig, asset_type: String): u8 {
    config.aggregators[asset_type].decimals
}

// Whether a price feed is registered for `asset_type` (membership only, no freshness check), so
// callers can test priceability without the abort in `get_asset_price`. Stale-but-registered feeds
// still report true, keeping callers fail-closed on staleness for assets Volo tracks.
public fun has_aggregator(config: &OracleConfig, asset_type: String): bool {
    config.aggregators.contains(asset_type)
}

// ^(pyth migration - new)
// The feed an asset is registered against, so operators can verify the cutover.
public fun asset_aggregator(config: &OracleConfig, asset_type: String): address {
    assert!(config.aggregators.contains(asset_type), ERR_AGGREGATOR_NOT_FOUND);
    config.aggregators[asset_type].aggregator
}

// ^(pyth migration - new)
public fun asset_price_last_updated(config: &OracleConfig, asset_type: String): u64 {
    assert!(config.aggregators.contains(asset_type), ERR_AGGREGATOR_NOT_FOUND);
    config.aggregators[asset_type].last_updated
}

public fun dex_slippage(config: &OracleConfig): u256 {
    config.dex_slippage
}

public fun get_pyth_object_identifier(price_info_object: &ProPriceInfoObject): address {
    let info = price_info_object.get_price_info_from_price_info_object();
    let identifier = info.get_price_identifier();
    address::from_bytes(identifier.get_bytes())
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun set_version_for_testing(config: &mut OracleConfig, version: u64) {
    config.version = version;
}

#[test_only]
public fun set_current_price(
    config: &mut OracleConfig,
    clock: &Clock,
    asset_type: String,
    price: u256,
) {
    let price_info = &mut config.aggregators[asset_type];

    price_info.price = price;
    price_info.last_updated = clock.timestamp_ms();
}

#[test_only]
public fun set_aggregator(
    config: &mut OracleConfig,
    clock: &Clock,
    asset_type: String,
    decimals: u8,
    aggregator: address,
) {
    let price_info = PriceInfo {
        aggregator: aggregator,
        decimals,
        price: 0,
        last_updated: clock.timestamp_ms(),
    };

    config.aggregators.add(asset_type, price_info);
}
