import Test

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

// Helper to create a test account
access(all) fun createTestAccount(): Test.TestAccount {
    let account = Test.createAccount()
    
    // TODO: Set up FlowToken vault in the account
    // This will be needed when we fully integrate with FlowToken
    
    return account
}

// Helper to get the deployed TidalProtocol address
access(all) fun getTidalProtocolAddress(): Address {
    return 0x0000000000000007
}

// ADDED: Helper to create a dummy oracle for testing
// Returns the oracle as AnyStruct since we can't use contract types directly
access(all) fun createDummyOracle(defaultToken: Type): AnyStruct {
    // Use a script to create the oracle
    let code = "import TidalProtocol from ".concat(getTidalProtocolAddress().toString()).concat("\n")
        .concat("access(all) fun main(defaultToken: Type): TidalProtocol.DummyPriceOracle {\n")
        .concat("    let oracle = TidalProtocol.DummyPriceOracle(defaultToken: defaultToken)\n")
        .concat("    oracle.setPrice(token: defaultToken, price: 1.0)\n")
        .concat("    return oracle\n")
        .concat("}")
    
    let result = Test.executeScript(code, [defaultToken])
    Test.expect(result, Test.beSucceeded())
    return result.returnValue!
}

// ADDED: Function to mint FLOW tokens from the service account
// This replaces createTestVault() to use real FLOW tokens
access(all) fun mintFlow(_ amount: UFix64): @AnyResource {
    // Get the service account which has minting capability
    let serviceAccount = Test.serviceAccount()
    
    // TODO: Implement proper FLOW minting from service account
    // For now, we'll use MockVault for testing
    panic("Real FLOW minting not implemented yet - use createTestVault for now")
}

// CHANGE: Create a mock vault for testing since we can't create FlowToken vaults directly
// Using a simplified structure for test context
access(all) resource MockVault {
    access(all) var balance: UFix64
    
    access(all) fun deposit(from: @MockVault) {
        self.balance = self.balance + from.balance
        from.balance = 0.0
        destroy from
    }
    
    access(all) fun withdraw(amount: UFix64): @MockVault {
        self.balance = self.balance - amount
        return <- create MockVault(balance: amount)
    }
    
    access(all) view fun isAvailableToWithdraw(amount: UFix64): Bool {
        return self.balance >= amount
    }
    
    access(all) fun createEmptyVault(): @MockVault {
        return <- create MockVault(balance: 0.0)
    }
    
    init(balance: UFix64) {
        self.balance = balance
    }
}

// CHANGE: Helper to create test vaults
access(all) fun createTestVault(balance: UFix64): @MockVault {
    return <- create MockVault(balance: balance)
}

// NOTE: The following functions need to be updated in each test file that uses them
// Since we cannot directly access contract types in test files, tests must:
// 1. Use Test.executeScript() to create oracles
// 2. Use Test.Transaction() to create pools with oracles
// 3. Handle the oracle parameter when calling TidalProtocol.createPool()

// DEPRECATED: These functions are placeholders - update your tests to use the new patterns
access(all) fun createTestPool(): @AnyResource {
    panic("Update test to use TidalProtocol.createTestPoolWithOracle() or create pool with oracle parameter")
}

access(all) fun createTestPoolWithOracle(): @AnyResource {
    panic("Update test to create pool with oracle using Test.Transaction")
}

access(all) fun createTestPoolWithBalance(initialBalance: UFix64): @AnyResource {
    panic("Update test to create pool with oracle and then add balance")
}

access(all) fun createMultiTokenTestPool(): @AnyResource {
    panic("Update test to create pool with oracle and add multiple tokens with risk parameters")
} 