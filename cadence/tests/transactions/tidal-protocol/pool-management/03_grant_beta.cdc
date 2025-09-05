import "ClosedBeta"

transaction() {

    prepare(
        // Must be the SAME account that deployed `ClosedBeta`
        admin: auth(Capabilities) &Account,
        // The target must allow storage writes
        tester: auth(Storage) &Account
    ) {
        // 1) Issue a capability to the stored AdminHandle with the Admin entitlement
        let adminCap: Capability<auth(ClosedBeta.Admin) &ClosedBeta.AdminHandle> =
            admin.capabilities.storage.issue<auth(ClosedBeta.Admin) &ClosedBeta.AdminHandle>(
                ClosedBeta.AdminHandleStoragePath
            )
        assert(adminCap.check(), message: "AdminHandle not found at AdminHandleStoragePath")

        // 2) Borrow the entitled AdminHandle reference
        let adminHandler: auth(ClosedBeta.Admin) &ClosedBeta.AdminHandle =
            adminCap.borrow()
            ?? panic("Failed to borrow entitled AdminHandle")

        // 3) Use the handler to perform the gated operation
        adminHandler.grantBeta(to: tester)
    }
}
