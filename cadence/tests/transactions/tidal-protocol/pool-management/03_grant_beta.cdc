import "TidalProtocolClosedBeta"

transaction() {

    prepare(
        // Must be the SAME account that deployed `TidalProtocolClosedBeta`
        admin: auth(Capabilities) &Account,
        // The target must allow storage writes
        tester: auth(Storage) &Account
    ) {
        // 1) Issue a capability to the stored AdminHandle with the Admin entitlement
        let adminCap: Capability<auth(TidalProtocolClosedBeta.Admin) &TidalProtocolClosedBeta.AdminHandle> =
        admin.capabilities.storage.issue<auth(TidalProtocolClosedBeta.Admin) &TidalProtocolClosedBeta.AdminHandle>(
            TidalProtocolClosedBeta.AdminHandleStoragePath
        )
        assert(adminCap.check(), message: "AdminHandle not found at AdminHandleStoragePath")

        // 2) Borrow the entitled AdminHandle reference
        let adminHandler: auth(TidalProtocolClosedBeta.Admin) &TidalProtocolClosedBeta.AdminHandle =
        adminCap.borrow()
        ?? panic("Failed to borrow entitled AdminHandle")

        // 3) Use the handler to perform the gated operation
        adminHandler.grantBeta(to: tester)
    }
}
