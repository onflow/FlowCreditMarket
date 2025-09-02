import "TidalProtocol"

transaction() {
    prepare(admin: auth(BorrowValue) &Account, tester: auth(Storage) &Account) {
        // Plain ref (NO entitlements):
        let plain: &TidalProtocol.PoolFactory =
            admin.storage.borrow<&TidalProtocol.PoolFactory>(from: TidalProtocol.PoolFactoryPath)
            ?? panic("No PoolFactory")

        // This line should FAIL AT COMPILE TIME (no EGovernance on `plain`)
        plain.grantBeta(to: tester)
    }
}
