import Test
import "TidalProtocol"
import "./test_helpers.cdc"

access(all)
fun setup() {
    deployContracts()
}

// Test 1: Basic Sink Creation and Usage
access(all) fun testBasicSinkCreation() {
    Test.test("Basic sink creation and deposit") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token support
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 1.0,
            borrowFactor: 1.0,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position
        let pid = poolRef.createPosition()
        
        // Create sink
        let sink <- poolRef.createSink(pid: pid, tokenType: Type<@MockVault>())
        
        // Deposit through sink
        let depositVault <- createTestVault(balance: 100.0)
        sink.deposit(vault: <-depositVault)
        
        // Verify deposit
        let details = poolRef.getPositionDetails(pid: pid)
        Test.assertEqual(details.balances[0].balance, 100.0)
        
        destroy sink
        destroy pool
    }
}

// Test 2: Basic Source Creation and Usage
access(all) fun testBasicSourceCreation() {
    Test.test("Basic source creation and withdrawal") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token support
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 1.0,
            borrowFactor: 1.0,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position with collateral
        let pid = poolRef.createPosition()
        let collateral <- createTestVault(balance: 1000.0)
        poolRef.deposit(pid: pid, funds: <-collateral)
        
        // Create source with limit
        let source <- poolRef.createSource(
            pid: pid,
            tokenType: Type<@MockVault>(),
            max: 200.0
        )
        
        // Withdraw through source
        let withdrawn <- source.withdraw(amount: 100.0) as! @MockVault
        Test.assertEqual(withdrawn.balance, 100.0)
        
        // Verify balance reduced
        let details = poolRef.getPositionDetails(pid: pid)
        Test.assertEqual(details.balances[0].balance, 900.0)
        
        destroy withdrawn
        destroy source
        destroy pool
    }
}

// Test 3: Sink with Draw-Down Source Option
access(all) fun testSinkWithDrawDownSource() {
    Test.test("Sink with draw-down source integration") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token support
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 1.0,
            borrowFactor: 1.0,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position with initial balance
        let pid = poolRef.createPosition()
        let initial <- createTestVault(balance: 500.0)
        poolRef.deposit(pid: pid, funds: <-initial)
        
        // Create draw-down source (simulating external source)
        let drawDownSource <- poolRef.createSource(
            pid: pid,
            tokenType: Type<@MockVault>(),
            max: 1000.0  // Can draw up to 1000
        )
        
        // Create sink with draw-down source option
        let sink <- poolRef.createSinkWithOptions(
            pid: pid,
            tokenType: Type<@MockVault>(),
            pushToDrawDownSink: false  // For this test, not using push
        )
        
        // Deposit small amount through sink
        let smallDeposit <- createTestVault(balance: 50.0)
        sink.deposit(vault: <-smallDeposit)
        
        // Draw from source to simulate external funding
        let externalFunds <- drawDownSource.withdraw(amount: 200.0) as! @MockVault
        sink.deposit(vault: <-externalFunds)
        
        // Verify total balance
        let details = poolRef.getPositionDetails(pid: pid)
        // 500 (initial) + 50 (small) + 200 (drawn) - 200 (source) = 550
        Test.assertEqual(details.balances[0].balance, 550.0)
        
        destroy sink
        destroy drawDownSource
        destroy pool
    }
}

// Test 4: Source with Top-Up Sink Option
access(all) fun testSourceWithTopUpSink() {
    Test.test("Source with top-up sink integration") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token support
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 1.0,
            borrowFactor: 1.0,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position with large balance
        let pid = poolRef.createPosition()
        let initial <- createTestVault(balance: 2000.0)
        poolRef.deposit(pid: pid, funds: <-initial)
        
        // Create top-up sink (for automatic refills)
        let topUpSink <- poolRef.createSink(pid: pid, tokenType: Type<@MockVault>())
        
        // Create source with top-up option
        let source <- poolRef.createSourceWithOptions(
            pid: pid,
            tokenType: Type<@MockVault>(),
            max: 500.0,
            pullFromTopUpSource: false  // For this test, not using pull
        )
        
        // Withdraw from source
        let withdrawn <- source.withdraw(amount: 300.0) as! @MockVault
        Test.assertEqual(withdrawn.balance, 300.0)
        
        // Simulate top-up by depositing back through sink
        let topUp <- createTestVault(balance: 100.0)
        topUpSink.deposit(vault: <-topUp)
        
        // Verify balance reflects both operations
        let details = poolRef.getPositionDetails(pid: pid)
        // 2000 - 300 + 100 = 1800
        Test.assertEqual(details.balances[0].balance, 1800.0)
        
        destroy withdrawn
        destroy source
        destroy topUpSink
        destroy pool
    }
}

// Test 5: Multiple Sinks and Sources
access(all) fun testMultipleSinksAndSources() {
    Test.test("Multiple sinks and sources for same position") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token support
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 1.0,
            borrowFactor: 1.0,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position
        let pid = poolRef.createPosition()
        let initial <- createTestVault(balance: 1000.0)
        poolRef.deposit(pid: pid, funds: <-initial)
        
        // Create multiple sinks
        let sink1 <- poolRef.createSink(pid: pid, tokenType: Type<@MockVault>())
        let sink2 <- poolRef.createSink(pid: pid, tokenType: Type<@MockVault>())
        
        // Create multiple sources with different limits
        let source1 <- poolRef.createSource(
            pid: pid,
            tokenType: Type<@MockVault>(),
            max: 200.0
        )
        let source2 <- poolRef.createSource(
            pid: pid,
            tokenType: Type<@MockVault>(),
            max: 300.0
        )
        
        // Use sinks
        let deposit1 <- createTestVault(balance: 100.0)
        sink1.deposit(vault: <-deposit1)
        
        let deposit2 <- createTestVault(balance: 150.0)
        sink2.deposit(vault: <-deposit2)
        
        // Use sources
        let withdraw1 <- source1.withdraw(amount: 100.0) as! @MockVault
        let withdraw2 <- source2.withdraw(amount: 200.0) as! @MockVault
        
        // Verify final balance
        let details = poolRef.getPositionDetails(pid: pid)
        // 1000 + 100 + 150 - 100 - 200 = 950
        Test.assertEqual(details.balances[0].balance, 950.0)
        
        destroy withdraw1
        destroy withdraw2
        destroy sink1
        destroy sink2
        destroy source1
        destroy source2
        destroy pool
    }
}

// Test 6: Source Limit Enforcement
access(all) fun testSourceLimitEnforcement() {
    Test.test("Source enforces maximum withdrawal limit") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token support
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 1.0,
            borrowFactor: 1.0,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position with balance
        let pid = poolRef.createPosition()
        let initial <- createTestVault(balance: 1000.0)
        poolRef.deposit(pid: pid, funds: <-initial)
        
        // Create source with 200 limit
        let source <- poolRef.createSource(
            pid: pid,
            tokenType: Type<@MockVault>(),
            max: 200.0
        )
        
        // Withdraw up to limit
        let withdraw1 <- source.withdraw(amount: 150.0) as! @MockVault
        Test.assertEqual(withdraw1.balance, 150.0)
        
        // Try to withdraw more than remaining (should fail or return less)
        // This depends on implementation - may panic or return available amount
        let withdraw2 <- source.withdraw(amount: 100.0) as! @MockVault
        // Should only get 50.0 (200 - 150 = 50)
        Test.assert(withdraw2.balance <= 50.0, 
            message: "Source should enforce maximum limit")
        
        destroy withdraw1
        destroy withdraw2
        destroy source
        destroy pool
    }
}

// Test 7: DFB Interface Compliance
access(all) fun testDFBInterfaceCompliance() {
    Test.test("Sink and Source implement DFB interfaces correctly") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token support
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 1.0,
            borrowFactor: 1.0,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position
        let pid = poolRef.createPosition()
        let initial <- createTestVault(balance: 500.0)
        poolRef.deposit(pid: pid, funds: <-initial)
        
        // Create sink and verify interface
        let sink <- poolRef.createSink(pid: pid, tokenType: Type<@MockVault>())
        // Sink should accept any FungibleToken vault
        let testDeposit <- createTestVault(balance: 50.0)
        sink.deposit(vault: <-testDeposit)
        
        // Create source and verify interface
        let source <- poolRef.createSource(
            pid: pid,
            tokenType: Type<@MockVault>(),
            max: 100.0
        )
        // Source should return FungibleToken vault
        let withdrawn <- source.withdraw(amount: 50.0)
        Test.assertEqual(withdrawn.balance, 50.0)
        
        destroy withdrawn
        destroy sink
        destroy source
        destroy pool
    }
}

// Test 8: Sink/Source with Rate Limiting
access(all) fun testSinkSourceWithRateLimiting() {
    Test.test("Sink respects deposit rate limiting") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token with rate limiting
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 1.0,
            borrowFactor: 1.0,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 50.0,           // 50 tokens/second
            depositCapacityCap: 100.0    // Max 100 tokens immediate
        )
        
        // Create position
        let pid = poolRef.createPosition()
        
        // Create sink
        let sink <- poolRef.createSink(pid: pid, tokenType: Type<@MockVault>())
        
        // Large deposit through sink
        let largeDeposit <- createTestVault(balance: 1000.0)
        sink.deposit(vault: <-largeDeposit)
        
        // Check that rate limiting was applied
        let details = poolRef.getPositionDetails(pid: pid)
        Test.assert(details.balances[0].balance <= 100.0,
            message: "Sink deposits should be rate limited")
        
        destroy sink
        destroy pool
    }
}

// Test 9: Complex DeFi Integration Scenario
access(all) fun testComplexDeFiIntegration() {
    Test.test("Complex DeFi integration with multiple pools") {
        // Create two pools to simulate cross-protocol interaction
        let oracle1 = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle1.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        var pool1 <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle1
        )
        let pool1Ref = &pool1 as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        pool1.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 1.0,
            borrowFactor: 1.0,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create positions in pool1
        let pid1 = pool1Ref.createPosition()
        let collateral1 <- createTestVault(balance: 1000.0)
        pool1Ref.deposit(pid: pid1, funds: <-collateral1)
        
        // Create source from pool1
        let source1 <- pool1Ref.createSource(
            pid: pid1,
            tokenType: Type<@MockVault>(),
            max: 500.0
        )
        
        // Simulate using funds in another protocol
        let borrowedFunds <- source1.withdraw(amount: 300.0) as! @MockVault
        
        // In real scenario, these funds might go through:
        // 1. DEX swap
        // 2. Yield farming
        // 3. Another lending protocol
        
        // For test, just return with profit
        let profit <- createTestVault(balance: 50.0)
        borrowedFunds.deposit(from: <-profit)
        
        // Create sink to return funds
        let sink1 <- pool1Ref.createSink(pid: pid1, tokenType: Type<@MockVault>())
        sink1.deposit(vault: <-borrowedFunds)
        
        // Verify profit was captured
        let finalDetails = pool1Ref.getPositionDetails(pid: pid1)
        // 1000 - 300 + 350 = 1050
        Test.assertEqual(finalDetails.balances[0].balance, 1050.0)
        
        destroy source1
        destroy sink1
        destroy pool1
    }
}

// Test 10: Error Handling and Edge Cases
access(all) fun testSinkSourceErrorHandling() {
    Test.test("Sink/Source error handling and edge cases") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token support
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 1.0,
            borrowFactor: 1.0,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position with minimal balance
        let pid = poolRef.createPosition()
        let minimal <- createTestVault(balance: 0.00000001)
        poolRef.deposit(pid: pid, funds: <-minimal)
        
        // Test 1: Source with zero max
        let zeroSource <- poolRef.createSource(
            pid: pid,
            tokenType: Type<@MockVault>(),
            max: 0.0
        )
        
        // Should not be able to withdraw anything
        let zeroWithdraw <- zeroSource.withdraw(amount: 0.0) as! @MockVault
        Test.assertEqual(zeroWithdraw.balance, 0.0)
        
        // Test 2: Sink with empty vault
        let sink <- poolRef.createSink(pid: pid, tokenType: Type<@MockVault>())
        let emptyVault <- createTestVault(balance: 0.0)
        sink.deposit(vault: <-emptyVault)
        
        // Balance should remain unchanged
        let details = poolRef.getPositionDetails(pid: pid)
        Test.assertEqual(details.balances[0].balance, 0.00000001)
        
        destroy zeroWithdraw
        destroy zeroSource
        destroy sink
        destroy pool
    }
} 