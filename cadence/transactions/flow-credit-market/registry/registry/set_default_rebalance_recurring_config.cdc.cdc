import "FlowCreditMarket"
import "FlowCreditMarketRegistry"

/// This transaction will set the default rebalance recurring configuration for the Registry, defining the default 
/// scheduled transaction configuration for all registered positions.
///
/// @param interval: The interval at which to rebalance (in seconds)
/// @param priority: The priority of the rebalance (0: High, 1: Medium, 2: Low)
/// @param executionEffort: The execution effort of the rebalance
/// @param force: The force rebalance flag
transaction(
    interval: UFix64,
    priority: UInt8,
    executionEffort: UInt64,
    force: Bool
) {

    let registry: auth(FlowCreditMarket.Register) &FlowCreditMarketRegistry.Registry
    let config: {String: AnyStruct}
    
    prepare(signer: auth(BorrowValue) &Account) {
        let pool = signer.storage.borrow<auth(FlowCreditMarket.Register) &FlowCreditMarket.Pool>(from: FlowCreditMarket.PoolStoragePath)
            ?? panic("Could not borrow reference to Pool from \(FlowCreditMarket.PoolStoragePath) - ensure a Pool has been configured")
        let registryPath = FlowCreditMarket.deriveRegistryStoragePath(forPool: pool.uuid)
        self.registry = signer.storage.borrow<auth(FlowCreditMarket.Register) &FlowCreditMarketRegistry.Registry>(from: registryPath)
            ?? panic("Could not borrow reference to Registry from \(registryPath) - ensure a Registry has been configured")
        self.config = {
            "interval": interval,
            "priority": priority,
            "executionEffort": executionEffort,
            "force": force
        }
    }

    execute {
        self.registry.setDefaultRebalanceRecurringConfig(config: self.config)
    }
}
