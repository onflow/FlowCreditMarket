import "FlowCreditMarket"
import "FlowCreditMarketRegistry"

/// Schedules the RebalanceHandler's next internally-managed scheduled rebalancing
///
/// @param pid: The ID of the position to rebalance in the canonical Pool
transaction(pid: UInt64) {

    let handler: auth(FlowCreditMarket.Schedule) &FlowCreditMarketRegistry.RebalanceHandler
    
    prepare(signer: auth(BorrowValue) &Account) {
        let pool = signer.storage.borrow<auth(FlowCreditMarket.Register) &FlowCreditMarket.Pool>(from: FlowCreditMarket.PoolStoragePath)
            ?? panic("Could not borrow reference to Pool from \(FlowCreditMarket.PoolStoragePath) - ensure a Pool has been configured")
        let handlerPath = FlowCreditMarketRegistry.deriveRebalanceHandlerStoragePath(poolUUID: pool.uuid, positionID: pid)
        self.handler = signer.storage.borrow<auth(FlowCreditMarket.Schedule) &FlowCreditMarketRegistry.RebalanceHandler>(from: handlerPath)
            ?? panic("Could not borrow reference to RebalanceHandler from \(handlerPath) - ensure a RebalanceHandler has been configured")
    }

    execute {
        self.handler.scheduleNextRebalance(whileExecuting: nil, data: nil)
    }
}
