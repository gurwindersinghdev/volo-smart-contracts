#[test_only]
#[allow(deprecated_usage)]
module volo_vault::sui_test_coin {
    use sui::coin;

    public struct SUI_TEST_COIN has drop {}

    fun init(witness: SUI_TEST_COIN, ctx: &mut TxContext) {
        let decimals = 9;
        let name = b"Sui";
        let symbol = b"SUI";
        
        let (vault_cap, metadata) = coin::create_currency<SUI_TEST_COIN>(
            witness,         // witness
            decimals,        // decimals
            symbol,          // symbol
            name,            // name
            b"",             // description
            option::none(),  // icon_url
            ctx
        );

        transfer::public_freeze_object(metadata);
        transfer::public_transfer(vault_cap, tx_context::sender(ctx))
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(SUI_TEST_COIN {}, ctx)
    }
}

#[test_only]
#[allow(deprecated_usage)]
module volo_vault::usdc_test_coin {
    use sui::coin;

    public struct USDC_TEST_COIN has drop {}

    fun init(witness: USDC_TEST_COIN, ctx: &mut TxContext) {
        let decimals = 9;
        let name = b"USDC";
        let symbol = b"USDC";
        
        let (vault_cap, metadata) = coin::create_currency<USDC_TEST_COIN>(
            witness,         // witness
            decimals,        // decimals
            symbol,          // symbol
            name,            // name
            b"",             // description
            option::none(),  // icon_url
            ctx
        );

        transfer::public_freeze_object(metadata);
        transfer::public_transfer(vault_cap, tx_context::sender(ctx))
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(USDC_TEST_COIN {}, ctx)
    }
}

#[test_only]
#[allow(deprecated_usage)]
module volo_vault::btc_test_coin {
    use sui::coin;

    public struct BTC_TEST_COIN has drop {}

    fun init(witness: BTC_TEST_COIN, ctx: &mut TxContext) {
        let decimals = 6;
        let name = b"BTC_TEST";
        let symbol = b"BTC_TEST";
        
        let (treasury_cap, metadata) = coin::create_currency<BTC_TEST_COIN>(
            witness,         // witness
            decimals,        // decimals
            symbol,          // symbol
            name,            // name
            b"",             // description
            option::none(),  // icon_url
            ctx
        );

        transfer::public_freeze_object(metadata);
        transfer::public_transfer(treasury_cap, tx_context::sender(ctx))
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(BTC_TEST_COIN {}, ctx)
    }
}
