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

// C-series: Position health & liquidation

access(all)
fun testHealthyPosition() {
    /* 
     * Test C-1: Healthy position
     * 
     * Create position with only credit balance
     * positionHealth() == 1.0 (no debt means healthy)
     */
    
    // Create pool
    let defaultThreshold: UFix64 = 1.0
    var pool <- AlpenFlow.createTestPool(defaultTokenThreshold: defaultThreshold)
    let poolRef = &pool as auth(AlpenFlow.EPosition) &AlpenFlow.Pool
    
    // Create position with only credit
    let pid = poolRef.createPosition()
    let depositVault <- AlpenFlow.createTestVault(balance: 100.0)
    poolRef.deposit(pid: pid, funds: <- depositVault)
    
    // Health should be 1.0 when no debt
    let health = poolRef.positionHealth(pid: pid)
    Test.assertEqual(1.0, health)
    
    // Clean up
    destroy pool
}

access(all)
fun testPositionHealthCalculation() {
    /* 
     * Test C-2: Position health calculation
     * 
     * Create position with credit and debit
     * Health = effectiveCollateral / totalDebt
     */
    
    // Create pool with 80% liquidation threshold
    let defaultThreshold: UFix64 = 0.8
    var pool <- AlpenFlow.createTestPoolWithBalance(
        defaultTokenThreshold: defaultThreshold,
        initialBalance: 1000.0
    )
    let poolRef = &pool as auth(AlpenFlow.EPosition) &AlpenFlow.Pool
    
    // Create test position
    let testPid = poolRef.createPosition()
    
    // Deposit 100 FLOW as collateral
    let collateralVault <- AlpenFlow.createTestVault(balance: 100.0)
    poolRef.deposit(pid: testPid, funds: <- collateralVault)
    
    // Borrow 50 FLOW (creating debt)
    let borrowed <- poolRef.withdraw(
        pid: testPid,
        amount: 50.0,
        type: Type<@AlpenFlow.FlowVault>()
    ) as! @AlpenFlow.FlowVault
    
    // Calculate expected health
    // effectiveCollateral = 100 * 0.8 = 80
    // totalDebt = 50
    // health = 80 / 50 = 1.6
    let health = poolRef.positionHealth(pid: testPid)
    Test.assert(health > 1.5 && health < 1.7, 
        message: "Health should be approximately 1.6")
    
    // Clean up
    destroy borrowed
    destroy pool
}

access(all)
fun testWithdrawalBlockedWhenUnhealthy() {
    /* 
     * Test C-3: Withdrawal blocked when unhealthy
     * 
     * Try to withdraw that would make position unhealthy
     * Transaction reverts with "Position is overdrawn"
     */
    
    // Create pool with 50% liquidation threshold
    let defaultThreshold: UFix64 = 0.5
    var pool <- AlpenFlow.createTestPoolWithBalance(
        defaultTokenThreshold: defaultThreshold,
        initialBalance: 1000.0
    )
    let poolRef = &pool as auth(AlpenFlow.EPosition) &AlpenFlow.Pool
    
    // Create test position
    let testPid = poolRef.createPosition()
    
    // Deposit 100 FLOW as collateral
    let collateralVault <- AlpenFlow.createTestVault(balance: 100.0)
    poolRef.deposit(pid: testPid, funds: <- collateralVault)
    
    // First, borrow 40 FLOW (within threshold: 40 < 100 * 0.5)
    let firstBorrow <- poolRef.withdraw(
        pid: testPid,
        amount: 40.0,
        type: Type<@AlpenFlow.FlowVault>()
    ) as! @AlpenFlow.FlowVault
    
    // Try to borrow another 20 FLOW (total would be 60, exceeding threshold)
    let withdrawResult = Test.expectFailure(fun(): Void {
        let secondBorrow <- poolRef.withdraw(
            pid: testPid,
            amount: 20.0,
            type: Type<@AlpenFlow.FlowVault>()
        )
        destroy secondBorrow
    }, errorMessageSubstring: "Position is overdrawn")
    
    // Clean up
    destroy firstBorrow
    destroy pool
} 