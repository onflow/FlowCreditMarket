import Test
import BlockchainHelpers

import "AlpenFlow"

access(all)
fun setup() {
    var err = Test.deployContract(
        name: "AlpenFlow",
        path: "../contracts/AlpenFlow.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

// H-series: Edge-cases & precision

access(all)
fun testZeroAmountValidation() {
    /* 
     * Test H-1: Zero amount validation
     * 
     * Try to deposit or withdraw 0
     * Reverts with "amount must be positive"
     */
    
    // Create pool
    let defaultThreshold: UFix64 = 1.0
    var pool <- AlpenFlow.createTestPool(defaultTokenThreshold: defaultThreshold)
    let poolRef = &pool as auth(AlpenFlow.EPosition) &AlpenFlow.Pool
    
    // Create position
    let pid = poolRef.createPosition()
    
    // First deposit some funds so we can test withdrawal
    let initialDeposit <- AlpenFlow.createTestVault(balance: 10.0)
    poolRef.deposit(pid: pid, funds: <- initialDeposit)
    
    // Test zero deposit - should fail
    let testZeroDeposit = Test.expectFailure(fun(): Void {
        let zeroVault <- AlpenFlow.createTestVault(balance: 0.0)
        poolRef.deposit(pid: pid, funds: <- zeroVault)
    }, errorMessageSubstring: "Deposit amount must be positive")
    
    // Test zero withdrawal - should fail
    let testZeroWithdraw = Test.expectFailure(fun(): Void {
        let withdrawn <- poolRef.withdraw(
            pid: pid,
            amount: 0.0,
            type: Type<@AlpenFlow.FlowVault>()
        )
        destroy withdrawn
    }, errorMessageSubstring: "Withdrawal amount must be positive")
    
    // Clean up
    destroy pool
}

access(all)
fun testSmallAmountPrecision() {
    /* 
     * Test H-2: Small amount precision
     * 
     * Deposit very small amounts (0.00000001)
     * Handle precision limits gracefully
     */
    
    // Create pool
    let defaultThreshold: UFix64 = 1.0
    var pool <- AlpenFlow.createTestPool(defaultTokenThreshold: defaultThreshold)
    let poolRef = &pool as auth(AlpenFlow.EPosition) &AlpenFlow.Pool
    
    // Create position
    let pid = poolRef.createPosition()
    
    // Test with various small amounts
    let smallAmounts: [UFix64] = [
        0.00000001,  // 1 satoshi
        0.00000010,  // 10 satoshi
        0.00000100,  // 100 satoshi
        0.00001000   // 1000 satoshi
    ]
    
    var totalDeposited: UFix64 = 0.0
    
    // Deposit small amounts
    for amount in smallAmounts {
        let smallVault <- AlpenFlow.createTestVault(balance: amount)
        poolRef.deposit(pid: pid, funds: <- smallVault)
        totalDeposited = totalDeposited + amount
    }
    
    // Verify total deposited
    let reserveBalance = poolRef.reserveBalance(type: Type<@AlpenFlow.FlowVault>())
    Test.assert(
        reserveBalance >= totalDeposited - 0.00000001 && 
        reserveBalance <= totalDeposited + 0.00000001,
        message: "Reserve balance should match total deposited within precision limits"
    )
    
    // Test withdrawing a small amount
    let smallWithdraw <- poolRef.withdraw(
        pid: pid,
        amount: 0.00000050,
        type: Type<@AlpenFlow.FlowVault>()
    ) as! @AlpenFlow.FlowVault
    
    Test.assertEqual(smallWithdraw.balance, 0.00000050)
    
    // Clean up
    destroy smallWithdraw
    destroy pool
}

access(all)
fun testEmptyPositionOperations() {
    /* 
     * Test H-3: Empty position operations
     * 
     * Withdraw from position with no balance
     * Appropriate error handling
     */
    
    // Create pool with funding
    let defaultThreshold: UFix64 = 1.0
    var pool <- AlpenFlow.createTestPoolWithBalance(
        defaultTokenThreshold: defaultThreshold,
        initialBalance: 100.0
    )
    let poolRef = &pool as auth(AlpenFlow.EPosition) &AlpenFlow.Pool
    
    // Create empty position (no deposits)
    let emptyPid = poolRef.createPosition()
    
    // Try to withdraw from empty position - should fail
    let testEmptyWithdraw = Test.expectFailure(fun(): Void {
        let withdrawn <- poolRef.withdraw(
            pid: emptyPid,
            amount: 1.0,
            type: Type<@AlpenFlow.FlowVault>()
        )
        destroy withdrawn
    }, errorMessageSubstring: "Position is overdrawn")
    
    // Verify position health is 1.0 (no debt, no collateral)
    Test.assertEqual(1.0, poolRef.positionHealth(pid: emptyPid))
    
    // Now deposit and withdraw everything
    let deposit <- AlpenFlow.createTestVault(balance: 10.0)
    poolRef.deposit(pid: emptyPid, funds: <- deposit)
    
    let fullWithdraw <- poolRef.withdraw(
        pid: emptyPid,
        amount: 10.0,
        type: Type<@AlpenFlow.FlowVault>()
    ) as! @AlpenFlow.FlowVault
    
    // Position should be empty again
    Test.assertEqual(1.0, poolRef.positionHealth(pid: emptyPid))
    
    // Try to withdraw again - should fail
    let testSecondEmptyWithdraw = Test.expectFailure(fun(): Void {
        let withdrawn <- poolRef.withdraw(
            pid: emptyPid,
            amount: 1.0,
            type: Type<@AlpenFlow.FlowVault>()
        )
        destroy withdrawn
    }, errorMessageSubstring: "Position is overdrawn")
    
    // Clean up
    destroy fullWithdraw
    destroy pool
} 