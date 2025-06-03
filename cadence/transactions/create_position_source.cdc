import TidalProtocol from "../contracts/TidalProtocol.cdc"

transaction(poolAddress: Address, positionId: UInt64, tokenType: String, maxAmount: UFix64) {
    prepare(signer: auth(BorrowValue, SaveValue) &Account) {
        // Get the pool reference
        let pool = getAccount(poolAddress).capabilities.borrow<auth(TidalProtocol.EPosition) &TidalProtocol.Pool>(
            /private/tidalPoolAuth
        ) ?? panic("Could not borrow pool reference")

        // Parse the token type
        let vaultType = CompositeType(tokenType) 
            ?? panic("Invalid token type identifier")

        // Create a position source
        let source <- pool.createSource(
            pid: positionId,
            tokenType: vaultType,
            max: maxAmount
        )

        // Save the source to storage
        let storagePath = StoragePath(identifier: "tidalPositionSource")!
        signer.storage.save(<-source, to: storagePath)

        // Create and publish capability
        let sourceCap = signer.capabilities.storage.issue<&{TidalProtocol.PositionSource}>(
            storagePath
        )
        let publicPath = PublicPath(identifier: "tidalPositionSource")!
        signer.capabilities.publish(sourceCap, at: publicPath)
    }
} 