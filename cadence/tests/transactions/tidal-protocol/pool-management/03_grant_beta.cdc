import "TidalProtocol"

transaction() {
    prepare(
        // Admin needs Capabilities to issue an entitlement-bearing capability
        admin: auth(BorrowValue, Capabilities) &Account,
        tester: auth(Storage) &Account
    ) {
        // Issue a storage capability that carries the EGovernance entitlement
        let govCap: Capability<auth(TidalProtocol.EGovernance) &TidalProtocol.PoolFactory> =
            admin.capabilities.storage.issue<auth(TidalProtocol.EGovernance) &TidalProtocol.PoolFactory>(
                TidalProtocol.PoolFactoryPath
            )

        let govFactory = govCap.borrow()
            ?? panic("Failed to borrow governance-capability to PoolFactory")

        // Now you can call the entitlement-gated method
        govFactory.grantBeta(to: tester)
    }
}
