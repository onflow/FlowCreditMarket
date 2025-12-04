import "FlowCreditMarket"

/// Adds a token type with AdaptiveCurveIRM as supported to the stored pool
/// This enables dynamic interest rate adjustments based on market utilization
/// for non-MOET assets.
///
/// The AdaptiveCurveIRM automatically adjusts rates with:
/// - Target utilization: 90%
/// - Curve steepness: 4x
/// - Adjustment speed: 50/year
/// - Initial rate at target: 4% APR
/// - Min rate at target: 0.1% APR
/// - Max rate at target: 200% APR
///
transaction(
    tokenTypeIdentifier: String,
    collateralFactor: UFix64,
    borrowFactor: UFix64,
    depositRate: UFix64,
    depositCapacityCap: UFix64
) {
    let tokenType: Type
    let pool: auth(FlowCreditMarket.EGovernance) &FlowCreditMarket.Pool

    prepare(signer: auth(BorrowValue) &Account) {
        self.tokenType = CompositeType(tokenTypeIdentifier)
            ?? panic("Invalid tokenTypeIdentifier \(tokenTypeIdentifier)")
        self.pool = signer.storage.borrow<auth(FlowCreditMarket.EGovernance) &FlowCreditMarket.Pool>(from: FlowCreditMarket.PoolStoragePath)
            ?? panic("Could not borrow reference to Pool from \(FlowCreditMarket.PoolStoragePath) - ensure a Pool has been configured")
    }

    execute {
        self.pool.addSupportedToken(
            tokenType: self.tokenType,
            collateralFactor: collateralFactor,
            borrowFactor: borrowFactor,
            interestCurve: FlowCreditMarket.AdaptiveCurveIRM(),
            depositRate: depositRate,
            depositCapacityCap: depositCapacityCap
        )
    }
}
