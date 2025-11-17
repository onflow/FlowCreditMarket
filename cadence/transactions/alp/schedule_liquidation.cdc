import "FlowALPLiquidationScheduler"
import "FlowALPSchedulerRegistry"
import "FlowTransactionScheduler"
import "FlowToken"
import "FungibleToken"

/// Manually schedules a liquidation job for a specific (marketID, positionID).
/// Useful for tests, backfills, or as a fallback when Supervisor-based fan-out
/// is not yet configured.
///
/// Arguments:
/// - `marketID`: logical market identifier registered in FlowALPSchedulerRegistry
/// - `positionID`: FlowALP position ID to liquidate
/// - `timestamp`: desired execution time
/// - `priorityRaw`: 0=High,1=Medium,2=Low
/// - `executionEffort`: execution effort hint for the scheduler
/// - `feeAmount`: FLOW to cover scheduling
/// - `isRecurring`: whether this liquidation should self-reschedule
/// - `recurringInterval`: interval in seconds between recurring executions
transaction(
    marketID: UInt64,
    positionID: UInt64,
    timestamp: UFix64,
    priorityRaw: UInt8,
    executionEffort: UInt64,
    feeAmount: UFix64,
    isRecurring: Bool,
    recurringInterval: UFix64
) {
    let handlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    let payment: @FlowToken.Vault

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, PublishCapability, SaveValue) &Account) {
        let wrapperCapOpt = FlowALPSchedulerRegistry.getWrapperCap(marketID: marketID)
        assert(wrapperCapOpt != nil, message: "schedule_liquidation: market is not registered")
        self.handlerCap = wrapperCapOpt!

        let vaultRef = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("schedule_liquidation: could not borrow FlowToken Vault")
        self.payment <- vaultRef.withdraw(amount: feeAmount) as! @FlowToken.Vault
    }

    execute {
        let priority: FlowTransactionScheduler.Priority =
            priorityRaw == 0
                ? FlowTransactionScheduler.Priority.High
                : (priorityRaw == 1
                    ? FlowTransactionScheduler.Priority.Medium
                    : FlowTransactionScheduler.Priority.Low)

        let intervalOpt: UFix64? = isRecurring ? recurringInterval : nil

        let _scheduledID = FlowALPLiquidationScheduler.scheduleLiquidation(
            handlerCap: self.handlerCap,
            marketID: marketID,
            positionID: positionID,
            timestamp: timestamp,
            priority: priority,
            executionEffort: executionEffort,
            fees: <-self.payment,
            isRecurring: isRecurring,
            recurringInterval: intervalOpt
        )
    }
}


