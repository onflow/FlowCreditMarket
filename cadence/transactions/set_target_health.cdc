import TidalProtocol from "../contracts/TidalProtocol.cdc"

transaction(poolAddress: Address, positionId: UInt64, targetHealth: UFix64) {
    prepare(signer: auth(BorrowValue) &Account) {
        // Get the pool reference
        let pool = getAccount(poolAddress).capabilities.borrow<auth(TidalProtocol.EPosition) &TidalProtocol.Pool>(
            /private/tidalPoolAuth
        ) ?? panic("Could not borrow pool reference")

        // Get the position
        let position = pool.borrowPosition(pid: positionId)
            ?? panic("Position not found")

        // Set the target health
        // Note: This is a no-op in the Position struct interface
        // The actual target health is stored in InternalPosition
        position.setTargetHealth(health: targetHealth)
    }
} 