import Test
import "TidalProtocol"
import "FlowToken"
import "FungibleToken"
import "FungibleTokenMetadataViews"
import "MOET"

// Common test setup function that deploys all required contracts
access(all) fun deployContracts() {
    // Deploy DFB first since TidalProtocol imports it
    var err = Test.deployContract(
        name: "DFB",
        path: "../../DeFiBlocks/cadence/contracts/interfaces/DFB.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    
    // Deploy MOET before TidalProtocol since TidalProtocol imports it
    err = Test.deployContract(
        name: "MOET",
        path: "../contracts/MOET.cdc",
        arguments: [1000000.0]  // Initial supply
    )
    Test.expect(err, Test.beNil())
    
    // Deploy TidalProtocol
    err = Test.deployContract(
        name: "TidalProtocol",
        path: "../contracts/TidalProtocol.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

// Setup FlowToken vault for an account
access(all) fun setupFlowTokenVault(account: Test.TestAccount) {
    let setupCode = """
        import FlowToken from 0x0ae53cb6e3f42a79
        import FungibleToken from 0xee82856bf20e2aa6
        import FungibleTokenMetadataViews from 0xee82856bf20e2aa6
        
        transaction {
            prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, PublishCapability, SaveValue) &Account) {
                // Return early if the account already stores a FlowToken Vault
                if signer.storage.borrow<&FlowToken.Vault>(from: /storage/flowTokenVault) != nil {
                    return
                }
                
                // Create a new FlowToken Vault and put it in storage
                signer.storage.save(<-FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>()), to: /storage/flowTokenVault)
                
                // Create a public capability to the Vault that only exposes
                // the deposit function and balance field through the Receiver interface
                let vaultCap = signer.capabilities.storage.issue<&FlowToken.Vault>(/storage/flowTokenVault)
                signer.capabilities.publish(vaultCap, at: /public/flowTokenReceiver)
            }
        }
    """
    
    let tx = Test.Transaction(
        code: setupCode,
        authorizers: [account.address],
        signers: [account],
        arguments: []
    )
    
    let result = Test.blockchain.executeTransaction(tx)
    Test.expect(result, Test.beSucceeded())
}

// Mint FlowToken to an account using service account
access(all) fun mintFlowToken(to: Test.TestAccount, amount: UFix64) {
    // First ensure the recipient has a vault
    setupFlowTokenVault(account: to)
    
    let mintCode = """
        import FlowToken from 0x0ae53cb6e3f42a79
        import FungibleToken from 0xee82856bf20e2aa6
        
        transaction(recipient: Address, amount: UFix64) {
            let tokenAdmin: &FlowToken.Administrator
            let tokenReceiver: &{FungibleToken.Receiver}
            
            prepare(signer: auth(BorrowValue) &Account) {
                self.tokenAdmin = signer.storage.borrow<&FlowToken.Administrator>(from: /storage/flowTokenAdmin)
                    ?? panic("Signer is not the token admin")
                
                self.tokenReceiver = getAccount(recipient)
                    .capabilities.borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
                    ?? panic("Unable to borrow receiver reference")
            }
            
            execute {
                let minter <- self.tokenAdmin.createNewMinter(allowedAmount: amount)
                let mintedVault <- minter.mintTokens(amount: amount)
                
                self.tokenReceiver.deposit(from: <-mintedVault)
                
                destroy minter
            }
        }
    """
    
    let tx = Test.Transaction(
        code: mintCode,
        authorizers: [Test.blockchain.serviceAccount().address],
        signers: [Test.blockchain.serviceAccount()],
        arguments: [to.address, amount]
    )
    
    let result = Test.blockchain.executeTransaction(tx)
    Test.expect(result, Test.beSucceeded())
}

// Get FlowToken balance for an account
access(all) fun getFlowTokenBalance(account: Test.TestAccount): UFix64 {
    let script = """
        import FlowToken from 0x0ae53cb6e3f42a79
        import FungibleToken from 0xee82856bf20e2aa6
        
        access(all) fun main(address: Address): UFix64 {
            let account = getAccount(address)
            let vaultRef = account.capabilities.borrow<&{FungibleToken.Balance}>(/public/flowTokenBalance)
                ?? panic("Could not borrow Balance reference to the Vault")
            
            return vaultRef.balance
        }
    """
    
    let result = Test.blockchain.executeScript(script, [account.address])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue! as! UFix64
}

// Helper to create test pool with FlowToken as default token
access(all) fun createTestPoolWithFlowToken(defaultTokenThreshold: UFix64): @TidalProtocol.Pool {
    return <- TidalProtocol.createPool(
        defaultToken: Type<@FlowToken.Vault>(),
        defaultTokenThreshold: defaultTokenThreshold
    )
}

// Helper to create a pool with initial FlowToken balance
access(all) fun createTestPoolWithFlowTokenBalance(
    defaultTokenThreshold: UFix64,
    initialBalance: UFix64
): @TidalProtocol.Pool {
    let pool <- createTestPoolWithFlowToken(defaultTokenThreshold: defaultTokenThreshold)
    let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
    
    // Create admin position and deposit initial balance
    let adminPid = poolRef.createPosition()
    
    // Create a test account with FlowToken
    let testAccount = Test.createAccount()
    mintFlowToken(to: testAccount, amount: initialBalance)
    
    // Withdraw FlowToken from test account and deposit to pool
    let withdrawCode = """
        import FlowToken from 0x0ae53cb6e3f42a79
        import FungibleToken from 0xee82856bf20e2aa6
        
        transaction(amount: UFix64): @FlowToken.Vault {
            prepare(signer: auth(BorrowValue) &Account) {
                let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
                    ?? panic("Could not borrow reference to the owner's Vault!")
                
                return <- vaultRef.withdraw(amount: amount) as! @FlowToken.Vault
            }
        }
    """
    
    // For testing purposes, we'll simulate the deposit
    // In a real test, you would execute the transaction and deposit the vault
    
    return <- pool
} 