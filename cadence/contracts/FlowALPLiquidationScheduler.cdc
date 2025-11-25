import "FungibleToken"
import "FlowToken"
import "FlowTransactionScheduler"
import "FlowALP"
import "MOET"
import "FlowALPSchedulerRegistry"
import "FlowALPSchedulerProofs"

/// FlowALPLiquidationScheduler
///
/// Scheduler for automated, perpetual liquidations in FlowALP using FlowTransactionScheduler.
///
/// Architecture
///  - Global Supervisor (`Supervisor` resource) fans out across all registered markets.
///  - Per-market wrapper handler (`LiquidationHandler` resource) executes liquidations for individual positions.
///  - `FlowALPSchedulerRegistry` stores market/handler registration and supervisor capability.
///  - `FlowALPSchedulerProofs` records on-chain proofs for scheduled and executed liquidations.
///  - `LiquidationManager` resource tracks schedule metadata and prevents duplicate scheduling.
access(all) contract FlowALPLiquidationScheduler {

    /* --- PATHS --- */

    /// Storage path for the LiquidationManager resource
    access(all) let LiquidationManagerStoragePath: StoragePath
    /// Public path for the LiquidationManager (read-only helpers)
    access(all) let LiquidationManagerPublicPath: PublicPath

    /* --- EVENTS --- */

    /// Emitted when a child liquidation job is scheduled by the Supervisor or recurrence helper.
    access(all) event LiquidationChildScheduled(
        marketID: UInt64,
        positionID: UInt64,
        scheduledTransactionID: UInt64,
        timestamp: UFix64
    )

    /// Emitted when the Supervisor completes a fan-out tick.
    access(all) event SupervisorSeeded(
        timestamp: UFix64,
        childCount: UInt64
    )

    /* --- STRUCTS --- */

    /// Public view of a scheduled liquidation, exposed via scripts.
    access(all) struct LiquidationScheduleInfo {
        access(all) let marketID: UInt64
        access(all) let positionID: UInt64
        access(all) let scheduledTransactionID: UInt64
        access(all) let timestamp: UFix64
        access(all) let priority: FlowTransactionScheduler.Priority
        access(all) let isRecurring: Bool
        access(all) let recurringInterval: UFix64?
        access(all) let status: FlowTransactionScheduler.Status?

        init(
            marketID: UInt64,
            positionID: UInt64,
            scheduledTransactionID: UInt64,
            timestamp: UFix64,
            priority: FlowTransactionScheduler.Priority,
            isRecurring: Bool,
            recurringInterval: UFix64?,
            status: FlowTransactionScheduler.Status?
        ) {
            self.marketID = marketID
            self.positionID = positionID
            self.scheduledTransactionID = scheduledTransactionID
            self.timestamp = timestamp
            self.priority = priority
            self.isRecurring = isRecurring
            self.recurringInterval = recurringInterval
            self.status = status
        }
    }

    /// Internal schedule metadata tracked by the LiquidationManager.
    access(all) struct LiquidationScheduleData {
        access(all) let marketID: UInt64
        access(all) let positionID: UInt64
        access(all) let isRecurring: Bool
        access(all) let recurringInterval: UFix64?
        access(all) let priority: FlowTransactionScheduler.Priority
        access(all) let executionEffort: UInt64

        init(
            marketID: UInt64,
            positionID: UInt64,
            isRecurring: Bool,
            recurringInterval: UFix64?,
            priority: FlowTransactionScheduler.Priority,
            executionEffort: UInt64
        ) {
            self.marketID = marketID
            self.positionID = positionID
            self.isRecurring = isRecurring
            self.recurringInterval = recurringInterval
            self.priority = priority
            self.executionEffort = executionEffort
        }
    }

    /* --- RESOURCES --- */

    /// LiquidationManager tracks schedule metadata and prevents duplicate scheduling per (marketID, positionID).
    access(all) resource LiquidationManager {
        /// scheduledTransactionID -> schedule metadata
        access(self) var scheduleData: {UInt64: LiquidationScheduleData}

        /// marketID -> (positionID -> scheduledTransactionID)
        access(self) var scheduledByPosition: {UInt64: {UInt64: UInt64}}

        init() {
            self.scheduleData = {}
            self.scheduledByPosition = {}
        }

        /// Returns schedule metadata by scheduled transaction ID, if present.
        access(all) fun getScheduleData(id: UInt64): LiquidationScheduleData? {
            return self.scheduleData[id]
        }

        /// Returns the scheduledTransactionID for a given (marketID, positionID), if present.
        access(all) fun getScheduledID(marketID: UInt64, positionID: UInt64): UInt64? {
            let byMarket = self.scheduledByPosition[marketID] ?? {} as {UInt64: UInt64}
            return byMarket[positionID]
        }

        /// Returns true if a non-finalized schedule exists for the given (marketID, positionID).
        /// Performs cleanup for finalized or missing transactions.
        access(all) fun hasScheduled(marketID: UInt64, positionID: UInt64): Bool {
            let byMarket = self.scheduledByPosition[marketID] ?? {} as {UInt64: UInt64}
            let existingIDOpt = byMarket[positionID]
            if existingIDOpt == nil {
                return false
            }
            let existingID = existingIDOpt!
            let status = FlowTransactionScheduler.getStatus(id: existingID)
            if status == nil {
                self.clearScheduleInternal(marketID: marketID, positionID: positionID, scheduledID: existingID)
                return false
            }
            if status! == FlowTransactionScheduler.Status.Executed ||
               status! == FlowTransactionScheduler.Status.Canceled {
                self.clearScheduleInternal(marketID: marketID, positionID: positionID, scheduledID: existingID)
                return false
            }
            return true
        }

        /// Clears schedule mappings for a given (marketID, positionID, scheduledID) if they match.
        access(contract) fun clearScheduleInternal(marketID: UInt64, positionID: UInt64, scheduledID: UInt64) {
            let byMarket = self.scheduledByPosition[marketID] ?? {} as {UInt64: UInt64}
            let currentIDOpt = byMarket[positionID]
            if currentIDOpt == nil || currentIDOpt! != scheduledID {
                return
            }

            var updatedByMarket = byMarket
            let _removedPos = updatedByMarket.remove(key: positionID)
            if updatedByMarket.keys.length == 0 {
                let _removedMarket = self.scheduledByPosition.remove(key: marketID)
            } else {
                self.scheduledByPosition[marketID] = updatedByMarket
            }

            let _removedSchedule = self.scheduleData.remove(key: scheduledID)
        }

        /// Records new schedule metadata and indexes it by (marketID, positionID).
        access(contract) fun setSchedule(id: UInt64, data: LiquidationScheduleData) {
            self.scheduleData[id] = data
            let byMarket = self.scheduledByPosition[data.marketID] ?? {} as {UInt64: UInt64}
            var updatedByMarket = byMarket
            updatedByMarket[data.positionID] = id
            self.scheduledByPosition[data.marketID] = updatedByMarket
        }
    }

    /// Per-market handler that executes a liquidation for a specific position
    /// and optionally schedules the next child if recurring.
    access(all) resource LiquidationHandler: FlowTransactionScheduler.TransactionHandler {

        /// Market identifier this handler is associated with (for events & proofs).
        access(self) let marketID: UInt64

        /// Capability to withdraw FlowToken for scheduling fees or seized collateral.
        access(self) let feesCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>

        /// Capability to withdraw debt tokens (MOET) used to repay liquidations.
        access(self) let debtVaultCap: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>

        /// Debt token type used when repaying liquidations (e.g. MOET).
        access(self) let debtType: Type

        /// Collateral token type to seize (e.g. FlowToken).
        access(self) let seizeType: Type

        init(
            marketID: UInt64,
            feesCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>,
            debtVaultCap: Capability<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>,
            debtType: Type,
            seizeType: Type
        ) {
            self.marketID = marketID
            self.feesCap = feesCap
            self.debtVaultCap = debtVaultCap
            self.debtType = debtType
            self.seizeType = seizeType
        }

        /// Executes liquidation for a given position.
        ///
        /// `data` is expected to be:
        /// {
        ///   "marketID": UInt64,
        ///   "positionID": UInt64,
        ///   "isRecurring": Bool,
        ///   "recurringInterval": UFix64,
        ///   "priority": UInt8,
        ///   "executionEffort": UInt64
        /// }
        access(FlowTransactionScheduler.Execute) fun executeTransaction(id: UInt64, data: AnyStruct?) {
            let cfg = data as? {String: AnyStruct} ?? {}
            let positionID = cfg["positionID"] as! UInt64

            // Borrow FlowALP pool
            let poolAccount = Type<@FlowALP.Pool>().address!
            let pool = getAccount(poolAccount).capabilities
                .borrow<&FlowALP.Pool>(FlowALP.PoolPublicPath)
                ?? panic("LiquidationHandler: Could not borrow FlowALP.Pool at public path")

            // If position is no longer liquidatable, we still treat the scheduled tx as executed
            // but skip actual liquidation logic to avoid aborting the scheduler callback.
            if !FlowALPLiquidationScheduler.isPositionLiquidatable(positionID: positionID) {
                FlowALPSchedulerProofs.markExecuted(
                    marketID: self.marketID,
                    positionID: positionID,
                    scheduledTransactionID: id
                )
                FlowALPLiquidationScheduler.scheduleNextIfRecurring(
                    completedID: id,
                    marketID: self.marketID,
                    positionID: positionID
                )
                return
            }

            // Quote liquidation parameters
            let quote = pool.quoteLiquidation(
                pid: positionID,
                debtType: self.debtType,
                seizeType: self.seizeType
            )
            if quote.requiredRepay <= 0.0 {
                // Nothing to liquidate; record execution and bail out gracefully
                FlowALPSchedulerProofs.markExecuted(
                    marketID: self.marketID,
                    positionID: positionID,
                    scheduledTransactionID: id
                )
                FlowALPLiquidationScheduler.scheduleNextIfRecurring(
                    completedID: id,
                    marketID: self.marketID,
                    positionID: positionID
                )
                return
            }

            let repayAmount: UFix64 = quote.requiredRepay

            // Withdraw debt tokens (MOET) used to repay the borrower's debt.
            let debtVaultRef = self.debtVaultCap.borrow()
                ?? panic("LiquidationHandler: cannot borrow debt vault")
            assert(
                debtVaultRef.balance >= repayAmount,
                message: "LiquidationHandler: insufficient debt balance in keeper vault"
            )
            let repay <- debtVaultRef.withdraw(amount: repayAmount)

            // Execute liquidation via FlowALP pool
            let result <- pool.liquidateRepayForSeize(
                pid: positionID,
                debtType: self.debtType,
                maxRepayAmount: repayAmount,
                seizeType: self.seizeType,
                minSeizeAmount: 0.0,
                from: <-repay
            )

            let seized <- result.takeSeized()
            let remainder <- result.takeRemainder()
            destroy result

            // Deposit seized collateral into the FlowToken vault owned by the scheduler account.
            // This keeps accounting simple for tests while still providing observable asset movement.
            let flowVaultRef = self.feesCap.borrow()
                ?? panic("LiquidationHandler: cannot borrow FlowToken vault for seized collateral")
            flowVaultRef.deposit(from: <-seized)

            // Any unused debt tokens are returned to the keeper's debt vault.
            let debtVaultRef2 = self.debtVaultCap.borrow()
                ?? panic("LiquidationHandler: cannot borrow debt vault for remainder")
            debtVaultRef2.deposit(from: <-remainder)

            // Record proof that this scheduled transaction executed successfully.
            FlowALPSchedulerProofs.markExecuted(
                marketID: self.marketID,
                positionID: positionID,
                scheduledTransactionID: id
            )

            // If this schedule is recurring, schedule the next child
            FlowALPLiquidationScheduler.scheduleNextIfRecurring(
                completedID: id,
                marketID: self.marketID,
                positionID: positionID
            )
        }
    }

    /// Global Supervisor that fans out liquidation jobs across registered markets.
    access(all) resource Supervisor: FlowTransactionScheduler.TransactionHandler {

        /// Capability to the LiquidationManager for schedule bookkeeping.
        access(self) let managerCap: Capability<&FlowALPLiquidationScheduler.LiquidationManager>

        /// Capability to withdraw FlowToken used to pay scheduling fees.
        access(self) let feesCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>

        init(
            managerCap: Capability<&FlowALPLiquidationScheduler.LiquidationManager>,
            feesCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
        ) {
            self.managerCap = managerCap
            self.feesCap = feesCap
        }

        /// Supervisor configuration is passed via `data`:
        /// {
        ///   "priority": UInt8 (0=High,1=Medium,2=Low),
        ///   "executionEffort": UInt64,
        ///   "lookaheadSecs": UFix64,
        ///   "maxPositionsPerMarket": UInt64,
        ///   "childRecurring": Bool,
        ///   "childInterval": UFix64,
        ///   "isRecurring": Bool,
        ///   "recurringInterval": UFix64
        /// }
        access(FlowTransactionScheduler.Execute) fun executeTransaction(id: UInt64, data: AnyStruct?) {
            let cfg = data as? {String: AnyStruct} ?? {}

            let priorityRaw = cfg["priority"] as? UInt8 ?? 1
            let executionEffort = cfg["executionEffort"] as? UInt64 ?? 800
            let lookaheadSecs = cfg["lookaheadSecs"] as? UFix64 ?? 5.0
            let maxPositionsPerMarket = cfg["maxPositionsPerMarket"] as? UInt64 ?? 32
            let childRecurring = cfg["childRecurring"] as? Bool ?? true
            let childInterval = cfg["childInterval"] as? UFix64 ?? 60.0
            let isRecurring = cfg["isRecurring"] as? Bool ?? true
            let recurringInterval = cfg["recurringInterval"] as? UFix64 ?? 60.0

            let priority: FlowTransactionScheduler.Priority =
                priorityRaw == 0
                    ? FlowTransactionScheduler.Priority.High
                    : (priorityRaw == 1
                        ? FlowTransactionScheduler.Priority.Medium
                        : FlowTransactionScheduler.Priority.Low)

            let manager = self.managerCap.borrow()
                ?? panic("Supervisor: missing LiquidationManager")

            var totalChildren: UInt64 = 0

            // Iterate through registered markets and schedule liquidations for underwater positions.
            for marketID in FlowALPSchedulerRegistry.getRegisteredMarketIDs() {
                let wrapperCap = FlowALPSchedulerRegistry.getWrapperCap(marketID: marketID)
                    ?? panic("Supervisor: no wrapper capability for market ".concat(marketID.toString()))

                let positionIDs = FlowALPSchedulerRegistry.getPositionIDsForMarket(marketID: marketID)

                var processed: UInt64 = 0

                for positionID in positionIDs {
                    if processed >= maxPositionsPerMarket {
                        break
                    }
                    if manager.hasScheduled(marketID: marketID, positionID: positionID) {
                        continue
                    }
                    if !FlowALPLiquidationScheduler.isPositionLiquidatable(positionID: positionID) {
                        continue
                    }

                    let ts = getCurrentBlock().timestamp + lookaheadSecs
                    let est = FlowALPLiquidationScheduler.estimateSchedulingCost(
                        timestamp: ts,
                        priority: priority,
                        executionEffort: executionEffort
                    )

                    // Add a small safety buffer above the estimated fee to avoid "Insufficient fees"
                    // assertions if the on-chain estimate rounds slightly higher at schedule time.
                    if est.flowFee == nil || est.timestamp == nil {
                        continue
                    }
                    let baseFee: UFix64 = est.flowFee!
                    let required: UFix64 = baseFee + 0.00002

                    let vaultRef = self.feesCap.borrow()
                        ?? panic("Supervisor: cannot borrow FlowToken Vault for child fees")
                    let pay <- vaultRef.withdraw(amount: required) as! @FlowToken.Vault

                    let _scheduledID = FlowALPLiquidationScheduler.scheduleLiquidation(
                        handlerCap: wrapperCap,
                        marketID: marketID,
                        positionID: positionID,
                        timestamp: ts,
                        priority: priority,
                        executionEffort: executionEffort,
                        fees: <-pay,
                        isRecurring: childRecurring,
                        recurringInterval: childRecurring ? childInterval : nil
                    )

                    totalChildren = totalChildren + 1
                    processed = processed + 1
                }
            }

            emit SupervisorSeeded(
                timestamp: getCurrentBlock().timestamp,
                childCount: totalChildren
            )

            // Self-reschedule Supervisor for perpetual operation, if configured.
            if isRecurring {
                let nextTimestamp = getCurrentBlock().timestamp + recurringInterval
                let est = FlowALPLiquidationScheduler.estimateSchedulingCost(
                    timestamp: nextTimestamp,
                    priority: priority,
                    executionEffort: executionEffort
                )
                if est.flowFee == nil || est.timestamp == nil {
                    return
                }
                let baseFee: UFix64 = est.flowFee!
                let required: UFix64 = baseFee + 0.00002

                let vaultRef = self.feesCap.borrow()
                    ?? panic("Supervisor: cannot borrow FlowToken Vault for self-reschedule")
                let pay <- vaultRef.withdraw(amount: required) as! @FlowToken.Vault

                let supCap = FlowALPSchedulerRegistry.getSupervisorCap()
                    ?? panic("Supervisor: missing supervisor capability in registry")

                let _scheduled <- FlowTransactionScheduler.schedule(
                    handlerCap: supCap,
                    data: cfg,
                    timestamp: nextTimestamp,
                    priority: priority,
                    executionEffort: executionEffort,
                    fees: <-pay
                )
                destroy _scheduled
            }
        }
    }

    /* --- HELPER FUNCTIONS --- */

    /// Returns true if the given position is currently liquidatable according to FlowALP.
    access(all) fun isPositionLiquidatable(positionID: UInt64): Bool {
        let poolAccount = Type<@FlowALP.Pool>().address!
        let pool = getAccount(poolAccount).capabilities
            .borrow<&FlowALP.Pool>(FlowALP.PoolPublicPath)
            ?? panic("isPositionLiquidatable: Could not borrow FlowALP.Pool")
        return pool.isLiquidatable(pid: positionID)
    }

    /// Schedules the next liquidation for a position if the completed scheduled transaction
    /// was marked as recurring.
    access(all) fun scheduleNextIfRecurring(completedID: UInt64, marketID: UInt64, positionID: UInt64) {
        let manager = self.account.storage
            .borrow<&FlowALPLiquidationScheduler.LiquidationManager>(from: self.LiquidationManagerStoragePath)
            ?? panic("scheduleNextIfRecurring: missing LiquidationManager")

        let dataOpt = manager.getScheduleData(id: completedID)
        if dataOpt == nil {
            manager.clearScheduleInternal(marketID: marketID, positionID: positionID, scheduledID: completedID)
            return
        }
        let data = dataOpt!
        if !data.isRecurring {
            manager.clearScheduleInternal(marketID: marketID, positionID: positionID, scheduledID: completedID)
            return
        }

        let interval = data.recurringInterval ?? 60.0
        let priority = data.priority
        let executionEffort = data.executionEffort
        let ts = getCurrentBlock().timestamp + interval

        let wrapperCap = FlowALPSchedulerRegistry.getWrapperCap(marketID: marketID)
            ?? panic("scheduleNextIfRecurring: missing wrapper capability for market ".concat(marketID.toString()))

        let est = FlowALPLiquidationScheduler.estimateSchedulingCost(
            timestamp: ts,
            priority: priority,
            executionEffort: executionEffort
        )
        if est.flowFee == nil || est.timestamp == nil {
            manager.clearScheduleInternal(marketID: marketID, positionID: positionID, scheduledID: completedID)
            return
        }
        let baseFee: UFix64 = est.flowFee!
        let required: UFix64 = baseFee + 0.00002
        let vaultRef = self.account.storage
            .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
            ?? panic("scheduleNextIfRecurring: cannot borrow FlowToken Vault for recurrence fees")
        let pay <- vaultRef.withdraw(amount: required) as! @FlowToken.Vault

        // Replace old schedule entry with the new recurring one.
        manager.clearScheduleInternal(marketID: marketID, positionID: positionID, scheduledID: completedID)

        let _scheduledID = FlowALPLiquidationScheduler.scheduleLiquidation(
            handlerCap: wrapperCap,
            marketID: marketID,
            positionID: positionID,
            timestamp: ts,
            priority: priority,
            executionEffort: executionEffort,
            fees: <-pay,
            isRecurring: true,
            recurringInterval: interval
        )
    }

    /// Convenience helper to check if a schedule already exists for a given (marketID, positionID).
    access(all) fun isAlreadyScheduled(marketID: UInt64, positionID: UInt64): Bool {
        let manager = self.account.storage
            .borrow<&FlowALPLiquidationScheduler.LiquidationManager>(from: self.LiquidationManagerStoragePath)
        if manager == nil {
            return false
        }
        return manager!.hasScheduled(marketID: marketID, positionID: positionID)
    }

    /// Returns schedule info for a given (marketID, positionID), if present.
    access(all) fun getScheduledLiquidation(marketID: UInt64, positionID: UInt64): LiquidationScheduleInfo? {
        let manager = self.account.storage
            .borrow<&FlowALPLiquidationScheduler.LiquidationManager>(from: self.LiquidationManagerStoragePath)
        if manager == nil {
            return nil
        }
        let scheduledIDOpt = manager!.getScheduledID(marketID: marketID, positionID: positionID)
        if scheduledIDOpt == nil {
            return nil
        }
        let scheduledID = scheduledIDOpt!
        let dataOpt = manager!.getScheduleData(id: scheduledID)
        if dataOpt == nil {
            return nil
        }
        let data = dataOpt!

        let txData = FlowTransactionScheduler.getTransactionData(id: scheduledID)
        var ts: UFix64 = 0.0
        var prio: FlowTransactionScheduler.Priority = data.priority
        var status: FlowTransactionScheduler.Status? = nil
        if txData != nil {
            ts = txData!.scheduledTimestamp
            prio = txData!.priority
            status = txData!.status
        }

        return LiquidationScheduleInfo(
            marketID: data.marketID,
            positionID: data.positionID,
            scheduledTransactionID: scheduledID,
            timestamp: ts,
            priority: prio,
            isRecurring: data.isRecurring,
            recurringInterval: data.recurringInterval,
            status: status
        )
    }

    /* --- PUBLIC FUNCTIONS --- */

    /// Creates a global Supervisor handler resource.
    /// This function also ensures that a LiquidationManager is present in storage
    /// and that its public capability is published.
    access(all) fun createSupervisor(): @Supervisor {
        if self.account.storage.borrow<&FlowALPLiquidationScheduler.LiquidationManager>(
            from: self.LiquidationManagerStoragePath
        ) == nil {
            let mgr <- self.createLiquidationManager()
            self.account.storage.save(<-mgr, to: self.LiquidationManagerStoragePath)

            let cap = self.account.capabilities.storage
                .issue<&FlowALPLiquidationScheduler.LiquidationManager>(self.LiquidationManagerStoragePath)
            self.account.capabilities.unpublish(self.LiquidationManagerPublicPath)
            self.account.capabilities.publish(cap, at: self.LiquidationManagerPublicPath)
        }

        let managerCap = self.account.capabilities.storage
            .issue<&FlowALPLiquidationScheduler.LiquidationManager>(self.LiquidationManagerStoragePath)
        let feesCap = self.account.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(/storage/flowTokenVault)

        return <- create Supervisor(managerCap: managerCap, feesCap: feesCap)
    }

    /// Derives a storage path for the global Supervisor.
    access(all) fun deriveSupervisorPath(): StoragePath {
        let identifier = "FlowALPLiquidationScheduler_Supervisor_".concat(self.account.address.toString())
        return StoragePath(identifier: identifier)!
    }

    /// Creates a per-market LiquidationHandler wrapper.
    /// For now, this uses MOET as debt token and FlowToken as seized collateral token.
    access(all) fun createMarketWrapper(marketID: UInt64): @LiquidationHandler {
        let feesCap = self.account.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(/storage/flowTokenVault)
        let debtVaultCap = self.account.capabilities.storage
            .issue<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(MOET.VaultStoragePath)

        let debtType = Type<@MOET.Vault>()
        let seizeType = Type<@FlowToken.Vault>()

        return <- create LiquidationHandler(
            marketID: marketID,
            feesCap: feesCap,
            debtVaultCap: debtVaultCap,
            debtType: debtType,
            seizeType: seizeType
        )
    }

    /// Derives a storage path for a per-market LiquidationHandler wrapper.
    access(all) fun deriveMarketWrapperPath(marketID: UInt64): StoragePath {
        let identifier = "FlowALPLiquidationScheduler_LiquidationHandler_".concat(marketID.toString())
        return StoragePath(identifier: identifier)!
    }

    /// Creates a new LiquidationManager resource.
    access(all) fun createLiquidationManager(): @LiquidationManager {
        return <- create LiquidationManager()
    }

    /// Schedules a liquidation for a specific (marketID, positionID).
    /// Handles duplicate prevention, schedule metadata bookkeeping, and proof/events.
    /// Returns the scheduled transaction ID.
    access(all) fun scheduleLiquidation(
        handlerCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>,
        marketID: UInt64,
        positionID: UInt64,
        timestamp: UFix64,
        priority: FlowTransactionScheduler.Priority,
        executionEffort: UInt64,
        fees: @FlowToken.Vault,
        isRecurring: Bool,
        recurringInterval: UFix64?
    ): UInt64 {
        let managerOpt = self.account.storage
            .borrow<&FlowALPLiquidationScheduler.LiquidationManager>(from: self.LiquidationManagerStoragePath)
        if managerOpt == nil {
            panic("scheduleLiquidation: missing LiquidationManager - create Supervisor first")
        }
        let manager = managerOpt!

        if manager.hasScheduled(marketID: marketID, positionID: positionID) {
            panic("scheduleLiquidation: liquidation already scheduled for this market and position")
        }
        if isRecurring {
            if recurringInterval == nil || recurringInterval! <= 0.0 {
                panic("scheduleLiquidation: recurringInterval must be > 0 when isRecurring is true")
            }
        }
        if !handlerCap.check() {
            panic("scheduleLiquidation: invalid handler capability")
        }

        let priorityRaw = priority.rawValue
        let data: {String: AnyStruct} = {
            "marketID": marketID,
            "positionID": positionID,
            "isRecurring": isRecurring,
            "recurringInterval": recurringInterval ?? 0.0,
            "priority": priorityRaw,
            "executionEffort": executionEffort
        }

        let scheduled <- FlowTransactionScheduler.schedule(
            handlerCap: handlerCap,
            data: data,
            timestamp: timestamp,
            priority: priority,
            executionEffort: executionEffort,
            fees: <-fees
        )

        let scheduleData = LiquidationScheduleData(
            marketID: marketID,
            positionID: positionID,
            isRecurring: isRecurring,
            recurringInterval: recurringInterval,
            priority: priority,
            executionEffort: executionEffort
        )
        manager.setSchedule(id: scheduled.id, data: scheduleData)

        emit LiquidationChildScheduled(
            marketID: marketID,
            positionID: positionID,
            scheduledTransactionID: scheduled.id,
            timestamp: timestamp
        )

        let scheduledID = scheduled.id
        destroy scheduled
        return scheduledID
    }

    /// Registers a market with the scheduler (idempotent).
    ///  - Ensures a per-market LiquidationHandler exists in storage.
    ///  - Issues its TransactionHandler capability.
    ///  - Stores the capability in FlowALPSchedulerRegistry.
    access(all) fun registerMarket(marketID: UInt64) {
        let wrapperPath = self.deriveMarketWrapperPath(marketID: marketID)

        if self.account.storage.borrow<&FlowALPLiquidationScheduler.LiquidationHandler>(from: wrapperPath) == nil {
            let wrapper <- self.createMarketWrapper(marketID: marketID)
            self.account.storage.save(<-wrapper, to: wrapperPath)
        }

        let wrapperCap = self.account.capabilities.storage
            .issue<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>(wrapperPath)

        FlowALPSchedulerRegistry.registerMarket(
            marketID: marketID,
            wrapperCap: wrapperCap
        )
    }

    /// Unregisters a market (idempotent).
    access(all) fun unregisterMarket(marketID: UInt64) {
        FlowALPSchedulerRegistry.unregisterMarket(marketID: marketID)
    }

    /// Lists registered market IDs (proxy to registry).
    access(all) fun getRegisteredMarketIDs(): [UInt64] {
        return FlowALPSchedulerRegistry.getRegisteredMarketIDs()
    }

    /// Estimates the cost of scheduling a liquidation.
    access(all) fun estimateSchedulingCost(
        timestamp: UFix64,
        priority: FlowTransactionScheduler.Priority,
        executionEffort: UInt64
    ): FlowTransactionScheduler.EstimatedScheduledTransaction {
        return FlowTransactionScheduler.estimate(
            data: nil,
            timestamp: timestamp,
            priority: priority,
            executionEffort: executionEffort
        )
    }

    init() {
        let identifier = "FlowALPLiquidationScheduler_".concat(self.account.address.toString())
        self.LiquidationManagerStoragePath = StoragePath(identifier: identifier.concat("_Manager"))!
        self.LiquidationManagerPublicPath = PublicPath(identifier: identifier.concat("_Manager"))!
    }
}


