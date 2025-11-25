import "FlowALPSchedulerRegistry"

/// Returns all market IDs registered with the FlowALP liquidation scheduler.
access(all) fun main(): [UInt64] {
    return FlowALPSchedulerRegistry.getRegisteredMarketIDs()
}


