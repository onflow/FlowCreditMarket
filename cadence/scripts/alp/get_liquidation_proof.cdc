import "FlowALPSchedulerProofs"

/// Returns true if the given scheduled transaction ID has been marked executed
/// for the specified (marketID, positionID) pair.
access(all) fun main(
    marketID: UInt64,
    positionID: UInt64,
    scheduledTransactionID: UInt64
): Bool {
    return FlowALPSchedulerProofs.wasExecuted(
        marketID: marketID,
        positionID: positionID,
        scheduledTransactionID: scheduledTransactionID
    )
}


