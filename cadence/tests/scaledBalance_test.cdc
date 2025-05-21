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
fun testScaledBalance() {
    /* 
     * This test verifies that the scaledBalanceToTrueBalance function 
     * correctly converts scaled balances to true balances based on the interest index
     */
    
    // 1. Set up test values
    let scaledBalance: UFix64 = 100.0
    let interestIndex: UInt64 = 10000000000000000 // 1.0 as a fixed point with 16 decimals
    
    // 2. Call the conversion function
    let trueBalance = AlpenFlow.scaledBalanceToTrueBalance(
        scaledBalance: scaledBalance, 
        interestIndex: interestIndex
    )
    
    // 3. If the interest index is 1.0, the true balance should equal the scaled balance
    Test.assertEqual(100.0, trueBalance)
    
    // 4. Test with a different interest index (1.05 = 5% interest accrued)
    let higherIndex: UInt64 = 10500000000000000 // 1.05 as a fixed point
    let adjustedBalance = AlpenFlow.scaledBalanceToTrueBalance(
        scaledBalance: scaledBalance,
        interestIndex: higherIndex
    )
    
    // 5. The true balance should now be 5% higher than the scaled balance
    Test.assert(adjustedBalance > scaledBalance)
    Test.assertEqual(105.0, adjustedBalance)
} 