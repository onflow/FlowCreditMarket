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
fun testDepositWithdrawSymmetry() {
    /* 
     * Test A-1: Deposit → Withdraw symmetry
     * 
     * This test verifies that depositing funds into a position and then
     * immediately withdrawing the same amount returns the expected funds,
     * leaves reserves unchanged, and maintains a health factor of 1.0.
     */
    
    // 1. Create a fresh Pool with default token threshold 1.0
    let defaultThreshold: UFix64 = 1.0
    var pool <- AlpenFlow.createTestPool(defaultTokenThreshold: defaultThreshold)

    // 2. Obtain an auth reference that grants EPosition access so we can call deposit/withdraw
    let poolRef = &pool as auth(AlpenFlow.EPosition) &AlpenFlow.Pool

    // 3. Open a new empty position inside the pool
    let pid = poolRef.createPosition()
    
    // 4. Create a vault with 10.0 FLOW for the deposit
    let depositVault <- AlpenFlow.createTestVault(balance: 10.0)
    
    // 5. Perform the deposit
    poolRef.deposit(pid: pid, funds: <- depositVault)

    // 6. Immediately withdraw the exact same amount
    let withdrawn <- poolRef.withdraw(
        pid: pid,
        amount: 10.0,
        type: Type<@AlpenFlow.FlowVault>()
    ) as! @AlpenFlow.FlowVault

    // 7. Assertions
    Test.assertEqual(10.0, withdrawn.balance)                                // withdraw returns 10 FLOW
    Test.assertEqual(0.0, poolRef.reserveBalance(type: Type<@AlpenFlow.FlowVault>())) // reserves unchanged (back to 0)
    Test.assertEqual(1.0, poolRef.positionHealth(pid: pid))                  // health == 1

    // 8. Clean-up resources to avoid leaks
    destroy withdrawn
    destroy pool
} 