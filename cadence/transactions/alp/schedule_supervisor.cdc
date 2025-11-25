import "FlowALPLiquidationScheduler"
import "FlowTransactionScheduler"
import "FlowToken"
import "FungibleToken"

/// Schedules the global liquidation Supervisor for FlowALP.
///
/// Arguments:
/// - `timestamp`: first run timestamp (typically now + a small delta)
/// - `priorityRaw`: 0=High, 1=Medium, 2=Low
/// - `executionEffort`: typical 800
/// - `feeAmount`: FLOW to cover the scheduling fee
/// - `recurringInterval`: seconds between Supervisor runs (0 to disable recurrence)
/// - `maxPositionsPerMarket`: per-tick bound for positions processed per market
/// - `childRecurring`: whether per-position liquidations should be recurring
/// - `childInterval`: interval between recurring child liquidations
transaction(
    timestamp: UFix64,
    priorityRaw: UInt8,
    executionEffort: UInt64,
    feeAmount: UFix64,
    recurringInterval: UFix64,
    maxPositionsPerMarket: UInt64,
    childRecurring: Bool,
    childInterval: UFix64
) {
    let handlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    let payment: @FlowToken.Vault

    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, PublishCapability, SaveValue) &Account) {
        let supPath = FlowALPLiquidationScheduler.deriveSupervisorPath()
        assert(
            signer.storage.borrow<&FlowALPLiquidationScheduler.Supervisor>(from: supPath) != nil,
            message: "Liquidation Supervisor not set up; run setup_liquidation_supervisor first"
        )

        self.handlerCap = signer.capabilities.storage
            .issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(supPath)

        let vaultRef = signer.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("Could not borrow FlowToken Vault for supervisor scheduling fee")
        self.payment <- vaultRef.withdraw(amount: feeAmount) as! @FlowToken.Vault
    }

    execute {
        let priority: FlowTransactionScheduler.Priority =
            priorityRaw == 0
                ? FlowTransactionScheduler.Priority.High
                : (priorityRaw == 1
                    ? FlowTransactionScheduler.Priority.Medium
                    : FlowTransactionScheduler.Priority.Low)

        let isRecurring: Bool = recurringInterval > 0.0

        let cfg: {String: AnyStruct} = {
            "priority": priorityRaw,
            "executionEffort": executionEffort,
            "lookaheadSecs": 5.0,
            "maxPositionsPerMarket": maxPositionsPerMarket,
            "childRecurring": childRecurring,
            "childInterval": childInterval,
            "isRecurring": isRecurring,
            "recurringInterval": recurringInterval
        }

        let _scheduled <- FlowTransactionScheduler.schedule(
            handlerCap: self.handlerCap,
            data: cfg,
            timestamp: timestamp,
            priority: priority,
            executionEffort: executionEffort,
            fees: <-self.payment
        )
        destroy _scheduled
    }
}


