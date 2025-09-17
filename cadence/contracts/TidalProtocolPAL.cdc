import "DeFiActions"
import "MOET"

access(all) contract TidalProtocolPAL {
    
    /// The common unit of account for the PAL
    access(all) let commonUnitOfAccount: Type
    access(self) let oracles: {Type: {DeFiActions.PriceOracle}}
    access(self) let perAssetConfigs: {Type: {IPerAssetConfig}}

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
        access(all) let maxAgeSeconds: UInt64
        access(all) let minQuorum: UInt64
        access(all) let confidenceK_1e24: UInt128?
        access(all) let twapWindowSeconds: UInt64
        access(all) let deviationHardBps: UInt16
        access(all) let deviationSoftBps: UInt16
        access(all) let anchorEpsilonBps: UInt16
        access(all) let impactNotionalUSD: UInt128
        access(all) let impactBaseQty: UInt128?
        access(all) let bandGateBps: UInt16?
    }

    access(all) struct PerAssetConfig : IPerAssetConfig {
        access(all) let maxAgeSeconds: UInt64
        access(all) let minQuorum: UInt64
        access(all) let confidenceK_1e24: UInt128?
        access(all) let twapWindowSeconds: UInt64
        access(all) let deviationHardBps: UInt16
        access(all) let deviationSoftBps: UInt16
        access(all) let anchorEpsilonBps: UInt16
        access(all) let impactNotionalUSD: UInt128
        access(all) let impactBaseQty: UInt128?
        access(all) let bandGateBps: UInt16?

        init(
            maxAgeSeconds: UInt64,
            minQuorum: UInt64,
            confidenceK_1e24: UInt128?,
            twapWindowSeconds: UInt64,
            deviationHardBps: UInt16,
            deviationSoftBps: UInt16,
            anchorEpsilonBps: UInt16,
            impactNotionalUSD: UInt128,
            impactBaseQty: UInt128?,
            bandGateBps: UInt16?
        ) {
            post {
                self.maxAgeSeconds > 0: "maxAgeSeconds must be greater than 0 but was \(self.maxAgeSeconds)"
            }
            self.maxAgeSeconds = maxAgeSeconds
            self.minQuorum = minQuorum
            self.confidenceK_1e24 = confidenceK_1e24
            self.twapWindowSeconds = twapWindowSeconds
            self.deviationHardBps = deviationHardBps
            self.deviationSoftBps = deviationSoftBps
            self.anchorEpsilonBps = anchorEpsilonBps
            self.impactNotionalUSD = impactNotionalUSD
            self.impactBaseQty = impactBaseQty
            self.bandGateBps = bandGateBps
        }
    }

    /// PriceQuote
    ///
    /// A price quote for a specific asset. Internal price quote enabling time-based bounding and comparison
    ///
    access(all) struct PriceQuote {
        access(all) let price: UInt128     // in unit of account, common 24 decimals
        access(all) let updatedAt: UInt64  // unix seconds of the freshest input used
        access(all) let conf: UInt128?     // Pyth confidence (same scale as price)
        access(all) let status: Status     // overall health of this price
        access(all) let side: Side         // side of the market

        init(price: UInt128, updatedAt: UInt64, conf: UInt128?, status: Status, side: Side) {
            self.price = price
            self.updatedAt = updatedAt
            self.conf = conf
            self.status = status
            self.side = side
        }
    }

    /// PALPriceOracle
    ///
    /// A price oracle that returns the price of each token in terms of the default token.
    ///
    access(all) struct interface PALPriceOracle : DeFiActions.PriceOracle {
        access(all) let side: Side
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

        access(all) view fun unitOfAccount(): Type {
            return Type<@MOET.Vault>()
        }
        access(all) fun price(ofToken: Type): UFix64? {
            if ofToken == self.unitOfAccount() {
                return 1.0 // MOET/MOET
            }
            return 0.0 // TODO: Implement using PAL config
        }
        access(all) fun getComponentInfo(): DeFiActions.ComponentInfo {
            return DeFiActions.ComponentInfo(
                type: self.getType(),
                id: self.id(),
                innerComponents: []
            )
        }
        access(contract) view fun copyID(): DeFiActions.UniqueIdentifier? {
            return self.uniqueID
        }
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
        access(all) fun addOracle(_ oracle: {DeFiActions.PriceOracle}): Bool {
            let old = TidalProtocolPAL.oracles.remove(key: oracle.getType())
            TidalProtocolPAL.oracles[oracle.getType()] = oracle
            // TODO: Emit event
            return old != nil
        }
        /// Removes the specified oracle from the contract. Returns `true` if the oracle was removed, `false` if it was not found.
        access(all) fun removeOracle(oracle: {DeFiActions.PriceOracle}): Bool {
            let old = TidalProtocolPAL.oracles.remove(key: oracle.getType())
            // TODO: Emit event
            return old != nil
        }
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
        let config = TidalProtocolPAL.perAssetConfigs[ofToken]!
        return PriceQuote(
            price: 0,
            updatedAt: UInt64(getCurrentBlock().timestamp),
            conf: nil,
            status: Status.ERROR,
            side: side
        )
    }

    init(unitOfAccountIdentifier: String) {
        self.commonUnitOfAccount = CompositeType(unitOfAccountIdentifier) ?? panic("Invalid unitOfAccountIdentifier \(unitOfAccountIdentifier)")
        self.oracles = {}
        self.perAssetConfigs = {}

        self.PALConfigAdminStoragePath = /storage/PALConfigAdmin

        self.account.storage.save(<-create PALConfigAdmin(), to: self.PALConfigAdminStoragePath)
    }
}
