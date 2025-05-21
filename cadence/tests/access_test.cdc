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
fun testTypeAccess() {
    // This test doesn't call any functions, just verifies we can access type information
    let vaultType = Type<@AlpenFlow.FlowVault>()
    let poolType = Type<@AlpenFlow.Pool>()
    
    // Simple assertion that should pass
    Test.assert(true)
} 