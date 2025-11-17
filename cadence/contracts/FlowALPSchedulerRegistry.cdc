import "FlowTransactionScheduler"

/// FlowALPSchedulerRegistry
///
/// Lightweight on-chain registry for FlowALP liquidation scheduling.
/// - Tracks which markets are registered with the global Supervisor
/// - Stores a per-market wrapper capability for scheduling per-position liquidations
/// - Stores the Supervisor capability for self-rescheduling
/// - Optionally tracks positions per market to support bounded supervisor fan-out
access(all) contract FlowALPSchedulerRegistry {

    /// Set of registered market IDs
    access(self) var registeredMarkets: {UInt64: Bool}

    /// Per-market wrapper capabilities for `FlowTransactionScheduler.TransactionHandler`
    access(self) var wrapperCaps: {
        UInt64: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    }

    /// Global Supervisor capability (used for self-rescheduling)
    access(self) var supervisorCap: Capability<
        auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}
    >?

    /// Optional: positions registered per market.
    /// This enables the Supervisor to enumerate candidate positions in a gas-safe way
    /// without requiring FlowALP to expose its internal storage layout.
    ///
    /// Shape: marketID -> (positionID -> true)
    access(self) var positionsByMarket: {UInt64: {UInt64: Bool}}

    /// Registers a market and stores its wrapper capability (idempotent).
    access(all) fun registerMarket(
        marketID: UInt64,
        wrapperCap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    ) {
        self.registeredMarkets[marketID] = true
        self.wrapperCaps[marketID] = wrapperCap
    }

    /// Unregisters a market (idempotent).
    /// Any existing wrapper capability entry is removed and the positions set is cleared.
    access(all) fun unregisterMarket(marketID: UInt64) {
        self.registeredMarkets.remove(key: marketID)
        self.wrapperCaps.remove(key: marketID)
        self.positionsByMarket.remove(key: marketID)
    }

    /// Returns all registered market IDs.
    access(all) fun getRegisteredMarketIDs(): [UInt64] {
        return self.registeredMarkets.keys
    }

    /// Returns the wrapper capability for a given market, if present.
    access(all) fun getWrapperCap(
        marketID: UInt64
    ): Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>? {
        return self.wrapperCaps[marketID]
    }

    /// Sets the global Supervisor capability (used for Supervisor self-rescheduling).
    access(all) fun setSupervisorCap(
        cap: Capability<auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}>
    ) {
        self.supervisorCap = cap
    }

    /// Returns the global Supervisor capability, if configured.
    access(all) fun getSupervisorCap(): Capability<
        auth(FlowTransactionScheduler.Execute) &{FlowTransactionScheduler.TransactionHandler}
    >? {
        return self.supervisorCap
    }

    /// Registers a position under a given market (idempotent).
    /// This is the primary hook used by transactions when a position is opened.
    access(all) fun registerPosition(marketID: UInt64, positionID: UInt64) {
        let current = self.positionsByMarket[marketID] ?? {} as {UInt64: Bool}
        var updated = current
        updated[positionID] = true
        self.positionsByMarket[marketID] = updated
    }

    /// Unregisters a position from a given market (idempotent).
    /// This hook can be called when a position is permanently closed.
    access(all) fun unregisterPosition(marketID: UInt64, positionID: UInt64) {
        let current = self.positionsByMarket[marketID] ?? {} as {UInt64: Bool}
        if current[positionID] == nil {
            return
        }
        var updated = current
        let _ = updated.remove(key: positionID)
        if updated.keys.length == 0 {
            let _ = self.positionsByMarket.remove(key: marketID)
        } else {
            self.positionsByMarket[marketID] = updated
        }
    }

    /// Returns the registered position IDs for a given market.
    /// The Supervisor is responsible for applying any per-tick bounds on iteration.
    access(all) fun getPositionIDsForMarket(marketID: UInt64): [UInt64] {
        let byMarket = self.positionsByMarket[marketID] ?? {} as {UInt64: Bool}
        return byMarket.keys
    }

    init() {
        self.registeredMarkets = {}
        self.wrapperCaps = {}
        self.supervisorCap = nil
        self.positionsByMarket = {}
    }
}


