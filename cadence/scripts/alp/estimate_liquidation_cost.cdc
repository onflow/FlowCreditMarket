import "FlowTransactionScheduler"
import "FlowALPLiquidationScheduler"

/// Estimates the cost of scheduling a liquidation transaction via FlowALPLiquidationScheduler.
///
/// - `timestamp`: desired execution timestamp
/// - `priorityRaw`: 0=High,1=Medium,2=Low
/// - `executionEffort`: expected execution effort
access(all) fun main(
    timestamp: UFix64,
    priorityRaw: UInt8,
    executionEffort: UInt64
): FlowTransactionScheduler.EstimatedScheduledTransaction {
    let priority: FlowTransactionScheduler.Priority =
        priorityRaw == 0
            ? FlowTransactionScheduler.Priority.High
            : (priorityRaw == 1
                ? FlowTransactionScheduler.Priority.Medium
                : FlowTransactionScheduler.Priority.Low)

    return FlowALPLiquidationScheduler.estimateSchedulingCost(
        timestamp: timestamp,
        priority: priority,
        executionEffort: executionEffort
    )
}


