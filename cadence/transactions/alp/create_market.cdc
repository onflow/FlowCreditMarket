import "FungibleToken"

import "DeFiActions"
import "FlowALP"
import "MockOracle"
import "FlowALPLiquidationScheduler"

/// Creates the FlowALP Pool (if not already created) and auto-registers a logical
/// market with the liquidation scheduler.
///
/// This transaction is intended as the single entrypoint for setting up a new
/// liquidation-enabled market in FlowALP environments.
///
/// - `defaultTokenIdentifier`: Type identifier of the Pool's default token,
///   e.g. `Type<@MOET.Vault>().identifier`.
/// - `marketID`: logical market identifier to register with the scheduler.
transaction(defaultTokenIdentifier: String, marketID: UInt64) {

    let factory: &FlowALP.PoolFactory
    let defaultToken: Type
    let oracle: {DeFiActions.PriceOracle}
    var shouldCreatePool: Bool

    prepare(signer: auth(BorrowValue) &Account) {
        self.factory = signer.storage.borrow<&FlowALP.PoolFactory>(from: FlowALP.PoolFactoryPath)
            ?? panic("create_market: Could not find FlowALP.PoolFactory in signer's account")

        self.defaultToken = CompositeType(defaultTokenIdentifier)
            ?? panic("create_market: Invalid defaultTokenIdentifier ".concat(defaultTokenIdentifier))

        self.oracle = MockOracle.PriceOracle()

        // Idempotent pool creation: only create if no Pool is currently stored.
        self.shouldCreatePool = signer.storage.type(at: FlowALP.PoolStoragePath) == nil
    }

    execute {
        if self.shouldCreatePool {
            self.factory.createPool(defaultToken: self.defaultToken, priceOracle: self.oracle)
        }

        // Auto-register market with scheduler (idempotent at scheduler level).
        FlowALPLiquidationScheduler.registerMarket(marketID: marketID)
    }
}


