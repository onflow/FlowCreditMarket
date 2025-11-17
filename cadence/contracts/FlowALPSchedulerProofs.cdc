/// FlowALPSchedulerProofs
///
/// Stores on-chain proofs for scheduled liquidations in FlowALP.
/// This contract is intentionally storage-only so that the main scheduler
/// logic in `FlowALPLiquidationScheduler` can be upgraded independently.
access(all) contract FlowALPSchedulerProofs {

    /// Emitted when a liquidation child job is scheduled for a specific (marketID, positionID).
    access(all) event LiquidationScheduled(
        marketID: UInt64,
        positionID: UInt64,
        scheduledTransactionID: UInt64,
        timestamp: UFix64
    )

    /// Emitted when a scheduled liquidation executes successfully.
    access(all) event LiquidationExecuted(
        marketID: UInt64,
        positionID: UInt64,
        scheduledTransactionID: UInt64,
        timestamp: UFix64
    )

    /// Proof map:
    /// marketID -> positionID -> scheduledTransactionID -> true
    access(self) var executedByPosition: {UInt64: {UInt64: {UInt64: Bool}}}

    /// Records that a scheduled liquidation transaction was executed.
    access(all) fun markExecuted(marketID: UInt64, positionID: UInt64, scheduledTransactionID: UInt64) {
        let byMarket = self.executedByPosition[marketID] ?? {} as {UInt64: {UInt64: Bool}}
        let byPosition = byMarket[positionID] ?? {} as {UInt64: Bool}

        var updatedByPosition = byPosition
        updatedByPosition[scheduledTransactionID] = true

        var updatedByMarket = byMarket
        updatedByMarket[positionID] = updatedByPosition
        self.executedByPosition[marketID] = updatedByMarket
    }

    /// Returns true if the given scheduled transaction was executed for (marketID, positionID).
    access(all) fun wasExecuted(
        marketID: UInt64,
        positionID: UInt64,
        scheduledTransactionID: UInt64
    ): Bool {
        let byMarket = self.executedByPosition[marketID] ?? {} as {UInt64: {UInt64: Bool}}
        let byPosition = byMarket[positionID] ?? {} as {UInt64: Bool}
        return byPosition[scheduledTransactionID] ?? false
    }

    /// Returns all executed scheduled transaction IDs for a given (marketID, positionID).
    access(all) fun getExecutedIDs(marketID: UInt64, positionID: UInt64): [UInt64] {
        let byMarket = self.executedByPosition[marketID] ?? {} as {UInt64: {UInt64: Bool}}
        let byPosition = byMarket[positionID] ?? {} as {UInt64: Bool}
        return byPosition.keys
    }

    init() {
        self.executedByPosition = {}
    }
}


