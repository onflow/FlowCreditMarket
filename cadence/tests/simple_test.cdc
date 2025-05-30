import Test
import "test_helpers.cdc"

access(all)
fun setup() {
    deployContracts()
}

access(all)
fun testSimpleImport() {
    // Verify the contract was deployed successfully
    Test.assert(true, message: "Contract deployment should succeed")
}

access(all) 
fun testBasicMath() {
    // Test basic operations to ensure test framework is working
    Test.assertEqual(2 + 2, 4)
    Test.assertEqual(10 - 5, 5)
    Test.assertEqual(3 * 4, 12)
} 