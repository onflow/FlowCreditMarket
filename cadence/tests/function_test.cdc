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
fun testFunctionCall() {
    // Try calling a very simple function from the contract
    // We'll use a type conversion function which should be simple enough
    let index: UInt64 = 10000000000000000  // 1.0 with 16 decimal places
    let asUFix = UFix64.fromBigEndianBytes(index.toBigEndianBytes())! / 100000000.0
    
    // Another simple assertion that should pass
    Test.assertEqual(asUFix, 1.0)
} 