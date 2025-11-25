import "FlowALPSchedulerProofs"

/// Returns the executed scheduled transaction IDs for a given (marketID, positionID).
access(all) fun main(marketID: UInt64, positionID: UInt64): [UInt64] {
    return FlowALPSchedulerProofs.getExecutedIDs(
        marketID: marketID,
        positionID: positionID
    )
}


