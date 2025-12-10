import "FlowCreditMarket"

/// Sets the deposit rate for a token type
///
transaction(tokenTypeIdentifier: String, rate: UFix64) {
    let tokenType: Type
    let pool: auth(FlowCreditMarket.EGovernance) &FlowCreditMarket.Pool

    prepare(signer: auth(BorrowValue) &Account) {
        self.tokenType = CompositeType(tokenTypeIdentifier)
            ?? panic("Invalid tokenTypeIdentifier \(tokenTypeIdentifier)")
        self.pool = signer.storage.borrow<auth(FlowCreditMarket.EGovernance) &FlowCreditMarket.Pool>(from: FlowCreditMarket.PoolStoragePath)
            ?? panic("Could not borrow reference to Pool from \(FlowCreditMarket.PoolStoragePath)")
    }

    execute {
        self.pool.setDepositRate(tokenType: self.tokenType, rate: rate)
    }
}

