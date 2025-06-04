import "MOET"
import "FungibleToken"

transaction {
    prepare(signer: auth(SaveValue, BorrowValue, IssueStorageCapabilityController, PublishCapability) &Account) {
        // Check if vault already exists
        if signer.storage.borrow<&MOET.Vault>(from: MOET.VaultStoragePath) != nil {
            return
        }
        
        // Create a new vault
        let vault <- MOET.createEmptyVault(vaultType: Type<@MOET.Vault>())
        
        // Save it to storage
        signer.storage.save(<-vault, to: MOET.VaultStoragePath)
        
        // Create capabilities
        let vaultCap = signer.capabilities.storage.issue<&MOET.Vault>(MOET.VaultStoragePath)
        
        // Publish receiver capability, unpublishing any that may exist to prevent collision
        signer.capabilities.unpublish(MOET.VaultPublicPath)
        signer.capabilities.publish(vaultCap, at: MOET.VaultPublicPath)
    }
} 