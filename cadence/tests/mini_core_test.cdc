import Test
import BlockchainHelpers

import "AlpenFlow"

access(all)
fun setup() {
    var err = Test.deployContract(
        name: "AlpenFlow",
        path: "../contracts/AlpenFlow.cdc",
        arguments: [],
    )
    Test.expect(err, Test.beNil())
}

access(all)
fun testMiniCore() {
    /* 
     * This test verifies that we can create a FlowVault with a specified 
     * balance using the createTestVault helper function
     */
     
    // 1. Create a FlowVault with a balance of 10.0
    let vault <- AlpenFlow.createTestVault(balance: 10.0)
    
    // 2. Verify the balance is 10.0
    Test.assertEqual(10.0, vault.balance)
    
    // 3. Clean up
    destroy vault
} 