import "FlowALPLiquidationScheduler"

/// Returns schedule info for a liquidation associated with (marketID, positionID),
/// if a schedule currently exists.
access(all) fun main(marketID: UInt64, positionID: UInt64): FlowALPLiquidationScheduler.LiquidationScheduleInfo? {
    return FlowALPLiquidationScheduler.getScheduledLiquidation(
        marketID: marketID,
        positionID: positionID
    )
}


