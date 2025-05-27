import Test

// Common test setup function that deploys all required contracts
access(all) fun deployContracts() {
    // Deploy DFB first since AlpenFlow imports it
    var err = Test.deployContract(
        name: "DFB",
        path: "../../DeFiBlocks/cadence/contracts/interfaces/DFB.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    
    // Deploy AlpenFlow
    err = Test.deployContract(
        name: "AlpenFlow",
        path: "../contracts/AlpenFlow.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

// Helper to create a test account
access(all) fun createTestAccount(): Test.TestAccount {
    return Test.createAccount()
}

// Helper to get the deployed AlpenFlow address
access(all) fun getAlpenFlowAddress(): Address {
    return 0x0000000000000007
} 