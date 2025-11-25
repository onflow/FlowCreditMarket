import "FlowALP"
import "FlowALPSchedulerRegistry"
import "FlowALPLiquidationScheduler"

/// Helper script for tests: returns all registered position IDs for a market
/// that are currently liquidatable according to FlowALP.
access(all) fun main(marketID: UInt64): [UInt64] {
    let allPositions = FlowALPSchedulerRegistry.getPositionIDsForMarket(marketID: marketID)
    let results: [UInt64] = []

    for pid in allPositions {
        if FlowALPLiquidationScheduler.isPositionLiquidatable(positionID: pid) {
            results.append(pid)
        }
    }
    return results
}


