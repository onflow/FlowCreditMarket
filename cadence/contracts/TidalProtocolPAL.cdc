import "DeFiActions"
import "DeFiActionsMathUtils"

access(all) contract TidalProtocolPAL {

    /// The common unit of account for the PAL
    access(all) let commonUnitOfAccount: Type
    access(all) let cachedPrices: {Type: [PriceQuote]}              // TODO: Consolidate with approvedPrices
    access(all) let approvedPrices: {Type: [ApprovedPriceQuote]}    // TODO: Consolidate with cachedPrices
    access(self) let primaryOracles: {Type: {PALPriceOracle}}
    access(self) let gateOracles: {Type: {PALPriceOracle}}
    access(self) let perAssetConfigs: {Type: {IPerAssetConfig}}
    access(self) let dexAnchors: {Type: {DeFiActions.Swapper}}

    // PATHS
    //
    /// The canonical StoragePath where the PALConfigAdmin is stored
    access(all) let PALConfigAdminStoragePath: StoragePath

    /// Side
    ///
    /// A side for a price quote. Enables side-specific handling with differing levels of conservatism
    /// and price bounding
    ///
    access(all) enum Side : UInt8 {
        access(all) case LOW
        access(all) case HIGH
        access(all) case MEDIAN
    }

    /// Status
    ///
    /// A status for a price quote. Statuses used internally to indicate the health of a price quote
    ///
    access(all) enum Status : UInt8 {
        access(all) case OK
        access(all) case STALE
        access(all) case DEVIANT
        access(all) case ERROR
    }

    /// PerAssetConfig
    ///
    /// A configuration for a specific asset.
    ///
    access(all) struct interface IPerAssetConfig {
        access(all) let maxAgeSeconds: UFix64
        access(all) let minUpdateIntervalSeconds: UFix64
        access(all) let minPrimaryQuorum: UInt8
        access(all) let confidenceK_1e24: UInt128
        access(all) let twapWindowSeconds: UFix64
        access(all) let deviationHardBps: UInt16
        access(all) let deviationSoftBps: UInt16
        access(all) let anchorEpsilonBps: UInt16
        access(all) let impactNotionalUSD: UInt128
        access(all) let impactBaseQty: UInt128?
        access(all) let gateBps: UInt16?
    }

    /// PerAssetConfig
    ///
    /// A configuration for a specific asset. Used for the initial configuration of the PAL.
    ///
    access(all) struct PerAssetConfig : IPerAssetConfig {
        access(all) let maxAgeSeconds: UFix64
        access(all) let minUpdateIntervalSeconds: UFix64
        access(all) let minPrimaryQuorum: UInt8
        access(all) let twapWindowSeconds: UFix64
        access(all) let deviationHardBps: UInt16
        access(all) let deviationSoftBps: UInt16
        access(all) let anchorEpsilonBps: UInt16
        access(all) let impactNotionalUSD: UInt128
        access(all) let confidenceK_1e24: UInt128
        access(all) let impactBaseQty: UInt128?
        access(all) let gateBps: UInt16?

        init(
            maxAgeSeconds: UFix64,
            minUpdateIntervalSeconds: UFix64,
            minPrimaryQuorum: UInt8,
            twapWindowSeconds: UFix64,
            deviationHardBps: UInt16,
            deviationSoftBps: UInt16,
            anchorEpsilonBps: UInt16,
            impactNotionalUSD: UInt128,
            confidenceK_1e24: UInt128,
            impactBaseQty: UInt128?,
            gateBps: UInt16?
        ) {
            pre {
                maxAgeSeconds > 0.0: "maxAgeSeconds must be greater than 0 but was \(maxAgeSeconds)"
                minUpdateIntervalSeconds < maxAgeSeconds: "minUpdateIntervalSeconds must be less than maxAgeSeconds but was \(minUpdateIntervalSeconds)"
            }
            self.maxAgeSeconds = maxAgeSeconds
            self.minUpdateIntervalSeconds = minUpdateIntervalSeconds
            self.minPrimaryQuorum = minPrimaryQuorum
            self.twapWindowSeconds = twapWindowSeconds
            self.deviationHardBps = deviationHardBps
            self.deviationSoftBps = deviationSoftBps
            self.anchorEpsilonBps = anchorEpsilonBps
            self.impactNotionalUSD = impactNotionalUSD
            self.confidenceK_1e24 = confidenceK_1e24
            self.impactBaseQty = impactBaseQty
            self.gateBps = gateBps
        }
    }

    /// PriceQuote
    ///
    /// A price quote for a specific asset. Internal price quote enabling time-based bounding and comparison
    ///
    access(all) struct PriceQuote {
        access(all) let side: Side         // side of the market
        access(all) let price: UInt128     // in unit of account, common 24 decimals
        access(all) let updatedAt: UFix64  // unix seconds of the freshest input used
        access(all) let status: Status     // overall health of this price
        access(all) let conf: UInt128?     // Pyth confidence (same scale as price)

        view init(side: Side, price: UInt128, updatedAt: UFix64, status: Status, conf: UInt128?) {
            self.side = side
            self.price = price
            self.updatedAt = updatedAt
            self.status = status
            self.conf = conf
        }
    }

    /// ApprovedPriceQuote
    ///
    /// A price quote for a specific asset that has been approved and cached by the PAL.
    ///
    access(all) struct ApprovedPriceQuote {
        access(all) let medianizedPrimary: UInt128
        access(all) let twap: UInt128
        access(all) let conf: UInt128?
        access(all) let computedAt: UFix64
        access(all) let sellFloor: UInt128
        access(all) let buyCeiling: UInt128

        init(medianizedPrimary: UInt128, twap: UInt128, conf: UInt128?, computedAt: UFix64, sellFloor: UInt128, buyCeiling: UInt128) {
            self.medianizedPrimary = medianizedPrimary
            self.twap = twap
            self.conf = conf
            self.computedAt = computedAt
            self.sellFloor = sellFloor
            self.buyCeiling = buyCeiling
        }
    }

    /// PALPriceOracle
    ///
    /// A price oracle that returns the price of each token in terms of the default token.
    ///
    access(all) struct interface PALPriceOracle : DeFiActions.PriceOracle {
        access(all) let side: Side
        access(all) fun priceQuote(forToken: Type): PriceQuote?
    }

    /// PriceOracle
    ///
    /// A price oracle that returns the price of each token in terms of the default token.
    ///
    access(all) struct PriceOracle : PALPriceOracle {
        access(all) let side: Side
        access(contract) var uniqueID: DeFiActions.UniqueIdentifier?

        init(_ side: Side, _ uniqueID: DeFiActions.UniqueIdentifier?) {
            self.side = side
            self.uniqueID = uniqueID
        }

        /// Returns the unit of account for the PAL.
        access(all) view fun unitOfAccount(): Type {
            return TidalProtocolPAL.commonUnitOfAccount
        }
        /// Returns the latest price for the given token if a price quote is available and healthy, otherwise `nil`.
        access(all) fun price(ofToken: Type): UFix64? {
            if ofToken == self.unitOfAccount() {
                return 1.0 // UNIT/UNIT
            }
            let quote = self.priceQuote(forToken: ofToken)
            return quote != nil && quote!.status == Status.OK ? DeFiActionsMathUtils.toUFix64RoundDown(quote!.price) : nil
        }
        /// Returns the latest price quote for the given token if a price quote is available and healthy, otherwise `nil`.
        access(all) fun priceQuote(forToken: Type): PriceQuote? {
            return TidalProtocolPAL.price(ofToken: forToken, side: self.side)
        }
        /// Returns the component info for the PAL.
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: []
            )
        }
        /// Returns a copy of the struct's UniqueIdentifier, used in extending a stack to identify another connector in
        /// a DeFiActions stack. See DeFiActions.align() for more information.
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }
        /// Sets the UniqueIdentifier of this component to the provided UniqueIdentifier, used in extending a stack to
        /// identify another connector in a DeFiActions stack. See DeFiActions.align() for more information.
        access(contract) fun setID(_ id: DeFiActions.UniqueIdentifier?) {
            self.uniqueID = id
        }
    }

    /// PALConfigAdmin
    ///
    /// A resource contract for managing the PAL's configuration
    ///
    access(all) resource PALConfigAdmin {
        /// Sets the per-asset config for the specified asset. Returns `true` if the config was replaced, `false` if it was added.
        access(all) fun setAssetConfig(asset: Type, config: {IPerAssetConfig}): Bool {
            let old = TidalProtocolPAL.perAssetConfigs.remove(key: asset)
            TidalProtocolPAL.perAssetConfigs[asset] = config
            // TODO: Emit event
            return old != nil
        }
        /// Adds the specified oracle to the contract. Returns `true` if the oracle was replaced, `false` if it was added.
        access(all) fun addQuorumOracle(_ oracle: {PALPriceOracle}): Bool {
            let old: {TidalProtocolPAL.PALPriceOracle}? = TidalProtocolPAL.primaryOracles.remove(key: oracle.getType())
            TidalProtocolPAL.primaryOracles[oracle.getType()] = oracle
            // TODO: Emit event
            return old != nil
        }
        /// Removes the specified oracle from the contract. Returns `true` if the oracle was removed, `false` if it was not found.
        access(all) fun removeQuorumOracle(oracle: {PALPriceOracle}): Bool {
            let old = TidalProtocolPAL.primaryOracles.remove(key: oracle.getType())
            // TODO: Emit event
            return old != nil
        }
        /// Adds the specified oracle to the contract. Returns `true` if the oracle was replaced, `false` if it was added.
        access(all) fun addGateOracle(_ oracle: {PALPriceOracle}): Bool {
            let old = TidalProtocolPAL.gateOracles.remove(key: oracle.getType())
            TidalProtocolPAL.gateOracles[oracle.getType()] = oracle
            // TODO: Emit event
            return old != nil
        }
        /// Removes the specified oracle from the contract. Returns `true` if the oracle was removed, `false` if it was not found.
        access(all) fun removeGateOracle(oracle: {PALPriceOracle}): Bool {
            let old = TidalProtocolPAL.gateOracles.remove(key: oracle.getType())
            // TODO: Emit event
            return old != nil
        }
    }


    /* ---- PUBLIC METHODS ---- */
    //
    /// Processes the price for the given token if the latest approved price exceeds the min update interval, returning
    /// the status of the price. Returns `nil` if the asset config is not found.
    access(all) fun processPriceOnInterval(ofToken: Type): Status? {
        if TidalProtocolPAL.perAssetConfigs[ofToken] == nil {
            return nil
        }

        let now = getCurrentBlock().timestamp
        let latestApprovedPrice = self.borrowLatestApprovedPriceQuote(forToken: ofToken)
        let assetConfig = &TidalProtocolPAL.perAssetConfigs[ofToken] as &{IPerAssetConfig}?
        // check if the latest approved price is valid and the min update interval has been exceeded
        if assetConfig != nil
            && !self.isValidPriceCached(ofToken)
            && now - (latestApprovedPrice?.computedAt ?? 0.0) > assetConfig!.minUpdateIntervalSeconds {
            return self.processPrice(ofToken)
        }
        return Status.OK
    }

    /* ---- INTERNAL METHODS ---- */
    //
    /// Passthrough contract method enabling DFA oracles to call through and
    /// gate requrests through contract-level per-asset configs
    access(contract) fun price(ofToken: Type, side: Side): PriceQuote {
        pre {
            TidalProtocolPAL.perAssetConfigs[ofToken] != nil:
            "No per-asset config found for \(ofToken.identifier)"
        }
        if !self.isValidPriceCached(ofToken) {
            self.processPrice(ofToken)
        }
        let config = TidalProtocolPAL.perAssetConfigs[ofToken]!
        let latestQuote = self.borrowLatestPriceQuote(forToken: ofToken)

        // TODO: validate against gates and circuit breakers
        if latestQuote == nil || latestQuote!.status != Status.OK {
            return PriceQuote(
                side: side,
                price: 0,
                updatedAt: latestQuote?.updatedAt ?? getCurrentBlock().timestamp,
                status: Status.ERROR,
                conf: nil
            )
        }
        return PriceQuote(
            side: side,
            price: latestQuote!.price,
            updatedAt: latestQuote!.updatedAt,
            status: latestQuote!.status,
            conf: latestQuote!.conf
        )
    }

    /// Processes the price for the given token. Returns the status of the price.
    // TODO: Consider changing return type to PriceQuote
    // TODO: May need to store the processed price quote
    access(contract) fun processPrice(_ token: Type): Status {
        let sanitized = self.collectAndSanitize(forToken: token)
        let primaries = sanitized[0]
        let gates = sanitized[1]

        let assetConfig = TidalProtocolPAL.perAssetConfigs[token]!
        if UInt8(primaries.keys.length) < assetConfig.minPrimaryQuorum {
            return Status.ERROR
        }
        let medianPrimary = self.medianize(primaries)

        /* TODO: assess dex anchors

        - Compute **TWAP** `A` over `twapWindowSecs` from canonical pool(s).
        - Derive **impact trade sizes from anchor only** (no candidate price used):
            - Let `A_low = A * (1 − ε)`, where `ε = anchorEpsilonBps / 10_000`.
            - **Collateral (sell - `LOW`)**: `baseQtySell = ceil( impactNotionalUSD / A_low )`; simulate selling `baseQtySell` → **sell floor `F`**.
            - **Debt/Liq (buy - `HIGH`)**: simulate **spending exactly `impactNotionalUSD` of the quote** into the pool(s) → **buy ceiling `C`**.
            - *(Optional backstop)* If `impactBaseQty` is set, simulate the **max** of the USD-derived size and `impactBaseQty`.
        */

        /* TODO: check circuit breakers

        - **Deviation vs anchor (at mid):** if `|S_raw − A| / S_raw > deviationHardBps` → **reject** (no approval).
        - **Depth at size (executability):**
            1. **fully execute** the notional
            2. satisfy at-size drift:
                
                `|F − A| / A * 10_000 ≤ deviationHardBps`
                
                `|C − A| * 10_000 / A ≤ deviationHardBps`
                
                otherwise → **reject**
                
        - **Independence (optional):** if Band healthy and `|b − S_raw| * 10_000 / S_raw > bandGateBps` → **reject**.
        - **Anchor availability / domain health:** if anchor missing/unhealthy → **reject**.
         */
        let passCircuitBreakers = self.checkCircuitBreakers(forToken: token, medianizedPrimary: medianPrimary, rawGates: gates)
        if passCircuitBreakers != Status.OK {
            return passCircuitBreakers
        }

        // TODO: store the actual resulting price quote only if the status is OK
        self.storeLatestPriceQuote(forToken: token, quote: PriceQuote(
            side: Side.MEDIAN,
            price: medianPrimary.price,
            updatedAt: medianPrimary.updatedAt,
            status: Status.OK,
            conf: medianPrimary.conf
        ))
        self.storeLatestApprovedPriceQuote(forToken: token, quote: ApprovedPriceQuote(
            medianizedPrimary: medianPrimary.price,
            twap: 0,                                // TODO: Implement
            conf: medianPrimary.conf,
            computedAt: medianPrimary.updatedAt,
            sellFloor: 0,                           // TODO: Implement
            buyCeiling: 0                           // TODO: Implement
        ))

        return Status.OK
    }

    /// Collects and sanitizes the price quotes for the given token. Returns a tuple of the primary and gate price quotes.
    /// If the primary quorum is not met, an empty array is returned for the primaries.
    access(contract) fun collectAndSanitize(forToken: Type): [{Type: PriceQuote}; 2] {
        // aggregate & drop stale
        let primaryPrices = self.aggregateRawQuotes(forToken: forToken, primaries: true)
        let gatePrices = self.aggregateRawQuotes(forToken: forToken, primaries: false)
        self.dropStale(forToken, quotes: &primaryPrices as auth(Mutate) &{Type: PriceQuote})
        self.dropStale(forToken, quotes: &gatePrices as auth(Mutate) &{Type: PriceQuote})

        // require min quorum on primaries
        let primaryQuorum = TidalProtocolPAL.perAssetConfigs[forToken]!.minPrimaryQuorum
        let primaryCount = UInt8(primaryPrices.keys.length)
        if primaryCount < primaryQuorum {
            return [{}, {}]
        }
        return [primaryPrices, gatePrices]
    }

    /// Aggregates the raw price quotes for the given token. Returns a map of the price quotes.
    access(contract) fun aggregateRawQuotes(forToken: Type, primaries: Bool): {Type: PriceQuote} {
        let res: {Type: PriceQuote} = {}
        let now = getCurrentBlock().timestamp
        let maxAge = self.perAssetConfigs[forToken]!.maxAgeSeconds

        // determine which oracles to aggregate
        let oracles = primaries ? self.primaryOracles : self.gateOracles
        for type in oracles.keys {
            let oracle = oracles[type]!
            let priceQuote = oracle.priceQuote(forToken: forToken)
            // no price available
            if priceQuote == nil {
                res[type] = PriceQuote(
                    side: Side.MEDIAN,
                    price: 0,
                    updatedAt: now,
                    status: Status.ERROR,
                    conf: nil
                )
                continue
            }

            // assess time and compare against asset's max age
            var status = priceQuote!.status
            if now > priceQuote!.updatedAt + maxAge && status == Status.OK {
                status = Status.STALE
            }
            res[type] = PriceQuote(
                side: Side.MEDIAN,
                price: priceQuote!.price,
                updatedAt: priceQuote!.updatedAt,
                status: status,
                conf: priceQuote!.conf
            )
        }
        return res
    }

    /// Medianizes the given quotes. Returns the median price and the latest updatedAt timestamp.
    access(contract) fun medianize(_ quotes: {Type: PriceQuote}): PriceQuote {
        var sum: UInt128 = 0
        var latest: UFix64 = 0.0
        quotes.keys.map(fun(t: Type) {
            sum = quotes[t]!.price
            latest = latest < quotes[t]!.updatedAt ? quotes[t]!.updatedAt : latest
        })
        let median = sum / UInt128(quotes.keys.length)

        return PriceQuote(
            side: Side.MEDIAN,
            price: median,
            updatedAt: latest,
            status: Status.OK,
            conf: nil
        )
    }

    /// Drops stale quotes from the given map.
    access(contract) fun dropStale(_ token: Type, quotes: auth(Mutate) &{Type: PriceQuote}) {
        let now = getCurrentBlock().timestamp
        let maxAge = self.perAssetConfigs[token]!.maxAgeSeconds
        for type in quotes.keys {
            if now >= quotes[type]!.updatedAt + maxAge && quotes[type]!.status == Status.OK {
                quotes.remove(key: type)
            }
        }
    }

    access(contract) fun assessDexAnchors() {}

    /// Checks that the primary price is within the gateBps bounds of all gates
    access(contract) fun checkCircuitBreakers(forToken: Type, medianizedPrimary: PriceQuote, rawGates: {Type: PriceQuote}): Status {
        if rawGates.keys.length == 0 {
            return Status.OK
        }
        let config = TidalProtocolPAL.perAssetConfigs[forToken]!
        let anchorEpsilonBps = config.anchorEpsilonBps
        let impactNotionalUSD = config.impactNotionalUSD
        let impactBaseQty = config.impactBaseQty
        let gateBps = config.gateBps

        // absolute value should always be positive as distance from 0
        fun abs(_ val: Int): UInt128 {
            return val >= 0 ? UInt128(val) : UInt128(-1 * val)
        }
        let deviation = abs(Int(medianizedPrimary.price) - Int(rawGates[forToken]!.price)) / medianizedPrimary.price
        if gateBps != nil && deviation > UInt128(gateBps!) {
            return Status.ERROR
        }
        return Status.OK
    }

    /// Checks if the cached price for the given token is valid.
    access(contract) view fun isValidPriceCached(_ token: Type): Bool {
        // if let latestQuote = self.borrowLatestPriceQuote(forToken: token) {
        if let latestQuote = self.borrowLatestApprovedPriceQuote(forToken: token) {
            let now = getCurrentBlock().timestamp
            let maxAge = self.perAssetConfigs[token]!.maxAgeSeconds
            if now <= latestQuote.computedAt + maxAge { // TODO: Consider validating status if added to ApprovedPrice
                return true
            }
        }
        return false
    }

    /// Borrows the latest price quote for the given token.
    access(contract) view fun borrowLatestPriceQuote(forToken: Type): &PriceQuote? {
        let quotes = &self.cachedPrices[forToken] as &[PriceQuote]?
        if quotes == nil || quotes!.length == 0 {
            return nil
        }
        return quotes![quotes!.length - 1]
    }

    /// Borrows the latest approved price quote for the given token.
    access(contract) view fun borrowLatestApprovedPriceQuote(forToken: Type): &ApprovedPriceQuote? {
        let quotes = &self.approvedPrices[forToken] as &[ApprovedPriceQuote]?
        if quotes == nil || quotes!.length == 0 {
            return nil
        }
        return quotes![quotes!.length - 1]
    }

    /// Stores the latest price quote for the given token.
    access(contract) fun storeLatestPriceQuote(forToken: Type, quote: PriceQuote) {
        let cached = &self.cachedPrices as auth(Mutate) &{Type: [PriceQuote]}
        // first price quote record - init empty array
        if cached[forToken] == nil {
            cached[forToken] = []
        }
        // append new price quote at the end of the array
        cached[forToken]!.append(quote)
    }

    /// Stores the approved price quote for the given token.
    access(contract) fun storeLatestApprovedPriceQuote(forToken: Type, quote: ApprovedPriceQuote) {
        let approved = &self.approvedPrices as auth(Mutate) &{Type: [ApprovedPriceQuote]}
        // first price quote record - init empty array
        if approved[forToken] == nil {
            approved[forToken] = []
        }
        // append new price quote at the end of the array
        approved[forToken]!.append(quote)
    }

    access(contract) fun applySideClamping(_ side: Side) {}

    init(unitOfAccountIdentifier: String) {
        self.commonUnitOfAccount = CompositeType(unitOfAccountIdentifier) ?? panic("Invalid unitOfAccountIdentifier \(unitOfAccountIdentifier)")
        self.cachedPrices = {}
        self.approvedPrices = {}
        self.primaryOracles = {}
        self.gateOracles = {}
        self.perAssetConfigs = {}
        self.dexAnchors = {}

        self.PALConfigAdminStoragePath = /storage/PALConfigAdmin

        self.account.storage.save(<-create PALConfigAdmin(), to: self.PALConfigAdminStoragePath)
    }
}
