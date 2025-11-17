import "FlowALPLiquidationScheduler"
import "FlowALPSchedulerRegistry"
import "FlowTransactionScheduler"

/// Creates and stores the global liquidation Supervisor handler in the FlowALP account,
/// and publishes its TransactionHandler capability into FlowALPSchedulerRegistry so that
/// the Supervisor can self-reschedule.
transaction() {
    prepare(signer: auth(BorrowValue, SaveValue, IssueStorageCapabilityController, PublishCapability) &Account) {
        let path = FlowALPLiquidationScheduler.deriveSupervisorPath()

        if signer.storage.borrow<&FlowALPLiquidationScheduler.Supervisor>(from: path) == nil {
            let sup <- FlowALPLiquidationScheduler.createSupervisor()
            signer.storage.save(<-sup, to: path)
        }

        let supCap = signer.capabilities.storage
            .issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(path)

        FlowALPSchedulerRegistry.setSupervisorCap(cap: supCap)
    }
}


