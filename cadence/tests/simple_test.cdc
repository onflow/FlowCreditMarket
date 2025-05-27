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
fun testSimpleImport() {
    // This is a minimal test that just checks if the contract can be imported
    Test.assert(true)
} 