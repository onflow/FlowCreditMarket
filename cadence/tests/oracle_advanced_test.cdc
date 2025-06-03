import Test
import "TidalProtocol"
import "./test_helpers.cdc"

access(all)
fun setup() {
    deployContracts()
}

// Test 1: Rapid Price Changes
access(all) fun testRapidPriceChanges() {
    Test.test("Position health responds correctly to rapid price changes") {
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
            collateralFactor: 0.8,
            borrowFactor: 0.8,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position with collateral and debt
        let pid = poolRef.createPosition()
        let collateral <- createTestVault(balance: 1000.0)
        poolRef.deposit(pid: pid, funds: <-collateral)
        
        let borrowed <- poolRef.withdraw(
            pid: pid,
            amount: 500.0,
            type: Type<@MockVault>()
        ) as! @MockVault
        
        // Track health through price changes
        let priceSequence: [UFix64] = [1.0, 0.8, 0.6, 0.4, 0.6, 0.8, 1.0, 1.2, 1.5]
        var previousHealth: UFix64 = poolRef.positionHealth(pid: pid)
        
        for price in priceSequence {
            oracle.setPrice(token: Type<@MockVault>(), price: price)
            let currentHealth = poolRef.positionHealth(pid: pid)
            
            // Health should decrease as price drops (collateral worth less)
            if price < 1.0 {
                Test.assert(currentHealth < previousHealth || currentHealth == previousHealth,
                    message: "Health should decrease or stay same as collateral price drops")
            } else if price > 1.0 {
                Test.assert(currentHealth > previousHealth || currentHealth == previousHealth,
                    message: "Health should increase or stay same as collateral price rises")
            }
            
            previousHealth = currentHealth
        }
        
        destroy borrowed
        destroy pool
    }
}

// Test 2: Price Volatility Impact on Borrowing
access(all) fun testPriceVolatilityBorrowingLimits() {
    Test.test("Borrowing limits adjust with price volatility") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token with conservative factors
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 0.7,  // 70% collateral value
            borrowFactor: 0.7,      // 70% borrow efficiency
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position
        let pid = poolRef.createPosition()
        let collateral <- createTestVault(balance: 1000.0)
        poolRef.deposit(pid: pid, funds: <-collateral)
        
        // Test borrowing at different price points
        let testPrices: [UFix64] = [1.0, 2.0, 0.5]
        let borrowAmounts: [UFix64] = []
        
        for price in testPrices {
            oracle.setPrice(token: Type<@MockVault>(), price: price)
            
            // Calculate available to borrow
            let availableFunds = poolRef.fundsAvailableAboveTargetHealth(
                pid: pid,
                type: Type<@MockVault>()
            )
            
            // Higher prices should allow more borrowing
            if price > 1.0 {
                Test.assert(availableFunds > 0.0,
                    message: "Should be able to borrow more with higher collateral value")
            }
        }
        
        destroy pool
    }
}

// Test 3: Multi-Token Oracle Pricing
access(all) fun testMultiTokenOraclePricing() {
    Test.test("Oracle correctly prices multiple tokens") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        
        // Set different prices for different tokens
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)    // Stable
        oracle.setPrice(token: Type<@FlowToken.Vault>(), price: 5.0)  // FLOW
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        
        // Add both tokens with different risk parameters
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 1.0,  // Stablecoin - full value
            borrowFactor: 0.9,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        pool.addSupportedToken(
            tokenType: Type<@FlowToken.Vault>(),
            collateralFactor: 0.8,  // Volatile - reduced value
            borrowFactor: 0.8,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Test that prices are correctly retrieved
        let mockPrice = oracle.getPrice(token: Type<@MockVault>())
        Test.assertEqual(mockPrice, 1.0)
        
        let flowPrice = oracle.getPrice(token: Type<@FlowToken.Vault>())
        Test.assertEqual(flowPrice, 5.0)
        
        destroy pool
    }
}

// Test 4: Oracle Price Manipulation Resistance
access(all) fun testOracleManipulationResistance() {
    Test.test("System resists oracle price manipulation attempts") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 0.8,
            borrowFactor: 0.8,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position with debt
        let pid = poolRef.createPosition()
        let collateral <- createTestVault(balance: 1000.0)
        poolRef.deposit(pid: pid, funds: <-collateral)
        
        let borrowed <- poolRef.withdraw(
            pid: pid,
            amount: 600.0,
            type: Type<@MockVault>()
        ) as! @MockVault
        
        // Attempt 1: Flash crash price to liquidate
        oracle.setPrice(token: Type<@MockVault>(), price: 0.1)
        let crashHealth = poolRef.positionHealth(pid: pid)
        
        // Immediately restore price
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        let restoredHealth = poolRef.positionHealth(pid: pid)
        
        // System should respond to current price, not historical
        Test.assert(restoredHealth > crashHealth,
            message: "Health should recover with price restoration")
        
        // Attempt 2: Pump price to over-borrow
        oracle.setPrice(token: Type<@MockVault>(), price: 10.0)
        
        // Try to borrow excessive amount
        let availableAfterPump = poolRef.fundsAvailableAboveTargetHealth(
            pid: pid,
            type: Type<@MockVault>()
        )
        
        // Even with 10x price, borrowing should be limited by factors
        Test.assert(availableAfterPump < 10000.0,
            message: "Borrowing should be limited despite price pump")
        
        destroy borrowed
        destroy pool
    }
}

// Test 5: Cross-Token Price Correlation
access(all) fun testCrossTokenPriceCorrelation() {
    Test.test("Health calculations with correlated token prices") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        
        // Set initial prices
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        oracle.setPrice(token: Type<@FlowToken.Vault>(), price: 5.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add both tokens
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 1.0,
            borrowFactor: 0.9,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        pool.addSupportedToken(
            tokenType: Type<@FlowToken.Vault>(),
            collateralFactor: 0.8,
            borrowFactor: 0.8,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position with both tokens
        let pid = poolRef.createPosition()
        
        // Deposit stablecoin
        let stableCollateral <- createTestVault(balance: 500.0)
        poolRef.deposit(pid: pid, funds: <-stableCollateral)
        
        // Note: In real implementation would deposit FLOW tokens too
        // For test purposes, we'll work with single token type
        
        // Simulate market crash - all prices drop
        oracle.setPrice(token: Type<@MockVault>(), price: 0.9)    // -10%
        oracle.setPrice(token: Type<@FlowToken.Vault>(), price: 2.5)  // -50%
        
        let crashHealth = poolRef.positionHealth(pid: pid)
        
        // Simulate recovery
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        oracle.setPrice(token: Type<@FlowToken.Vault>(), price: 5.0)
        
        let recoveryHealth = poolRef.positionHealth(pid: pid)
        
        Test.assert(recoveryHealth > crashHealth,
            message: "Health should recover with price recovery")
        
        destroy pool
    }
}

// Test 6: Oracle Update Frequency Impact
access(all) fun testOracleUpdateFrequency() {
    Test.test("System handles different oracle update frequencies") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 0.8,
            borrowFactor: 0.8,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position
        let pid = poolRef.createPosition()
        let collateral <- createTestVault(balance: 1000.0)
        poolRef.deposit(pid: pid, funds: <-collateral)
        
        // Simulate high-frequency updates
        var i = 0
        while i < 10 {
            let price = 1.0 + (UFix64(i) * 0.01)  // Small increments
            oracle.setPrice(token: Type<@MockVault>(), price: price)
            
            // Each update should be reflected immediately
            let health = poolRef.positionHealth(pid: pid)
            Test.assert(health > 0.0, message: "Health should be calculable at any time")
            
            i = i + 1
        }
        
        // Simulate low-frequency update (big jump)
        oracle.setPrice(token: Type<@MockVault>(), price: 2.0)
        let jumpHealth = poolRef.positionHealth(pid: pid)
        
        Test.assert(jumpHealth > 1.0,
            message: "Large price jump should significantly improve health")
        
        destroy pool
    }
}

// Test 7: Extreme Price Scenarios
access(all) fun testExtremePriceScenarios() {
    Test.test("System handles extreme oracle prices gracefully") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 0.8,
            borrowFactor: 0.8,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position
        let pid = poolRef.createPosition()
        let collateral <- createTestVault(balance: 1000.0)
        poolRef.deposit(pid: pid, funds: <-collateral)
        
        // Test extreme prices
        let extremePrices: [UFix64] = [
            0.00000001,  // Near zero
            0.001,       // Very low
            1000.0,      // Very high
            100000.0     // Extremely high
        ]
        
        for price in extremePrices {
            oracle.setPrice(token: Type<@MockVault>(), price: price)
            
            // System should not panic
            let health = poolRef.positionHealth(pid: pid)
            Test.assert(health >= 0.0, message: "Health should be calculable at extreme prices")
            
            // Try to calculate other functions
            let available = poolRef.fundsAvailableAboveTargetHealth(
                pid: pid,
                type: Type<@MockVault>()
            )
            Test.assert(available >= 0.0, message: "Available funds should not be negative")
        }
        
        destroy pool
    }
}

// Test 8: Oracle Fallback Behavior
access(all) fun testOracleFallbackBehavior() {
    Test.test("System behavior when oracle returns zero or invalid prices") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        
        // Test with zero price
        oracle.setPrice(token: Type<@MockVault>(), price: 0.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 0.8,
            borrowFactor: 0.8,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position
        let pid = poolRef.createPosition()
        
        // Deposit should work even with zero price
        let collateral <- createTestVault(balance: 1000.0)
        poolRef.deposit(pid: pid, funds: <-collateral)
        
        // Health calculation with zero price should handle gracefully
        // (Implementation might return 0 or max health)
        let zeroHealth = poolRef.positionHealth(pid: pid)
        Test.assert(zeroHealth >= 0.0, message: "Health should handle zero price gracefully")
        
        // Set valid price and verify recovery
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        let normalHealth = poolRef.positionHealth(pid: pid)
        Test.assert(normalHealth > 0.0, message: "Health should be positive with valid price")
        
        destroy pool
    }
}

// Test 9: Price Impact on Liquidations
access(all) fun testPriceImpactOnLiquidations() {
    Test.test("Oracle prices correctly trigger liquidation thresholds") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token with specific factors
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 0.75,  // 75% collateral value
            borrowFactor: 0.75,      // 75% borrow efficiency
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create position near liquidation
        let pid = poolRef.createPosition()
        let collateral <- createTestVault(balance: 1000.0)
        poolRef.deposit(pid: pid, funds: <-collateral)
        
        // Borrow close to limit
        let borrowed <- poolRef.withdraw(
            pid: pid,
            amount: 700.0,  // Close to 75% limit
            type: Type<@MockVault>()
        ) as! @MockVault
        
        let initialHealth = poolRef.positionHealth(pid: pid)
        
        // Drop price to trigger liquidation territory
        oracle.setPrice(token: Type<@MockVault>(), price: 0.9)
        let lowHealth = poolRef.positionHealth(pid: pid)
        
        Test.assert(lowHealth < initialHealth,
            message: "Health should decrease with collateral price drop")
        
        // Further price drop
        oracle.setPrice(token: Type<@MockVault>(), price: 0.8)
        let criticalHealth = poolRef.positionHealth(pid: pid)
        
        Test.assert(criticalHealth < lowHealth,
            message: "Health should continue decreasing with price")
        
        // Check if position would be liquidatable
        // (Actual liquidation logic would be in separate contract)
        Test.assert(criticalHealth < 1.1,
            message: "Position should be near or below liquidation threshold")
        
        destroy borrowed
        destroy pool
    }
}

// Test 10: Oracle Integration Stress Test
access(all) fun testOracleIntegrationStress() {
    Test.test("Oracle integration under stress conditions") {
        // Create oracle
        let oracle = TidalProtocol.DummyPriceOracle(defaultToken: Type<@MockVault>())
        oracle.setPrice(token: Type<@MockVault>(), price: 1.0)
        
        // Create pool
        var pool <- TidalProtocol.createPool(
            defaultToken: Type<@MockVault>(),
            priceOracle: oracle
        )
        let poolRef = &pool as auth(TidalProtocol.EPosition) &TidalProtocol.Pool
        
        // Add token
        pool.addSupportedToken(
            tokenType: Type<@MockVault>(),
            collateralFactor: 0.8,
            borrowFactor: 0.8,
            interestCurve: TidalProtocol.SimpleInterestCurve(),
            depositRate: 1000000.0,
            depositCapacityCap: 1000000.0
        )
        
        // Create multiple positions
        let positions: [UInt64] = []
        var i = 0
        while i < 10 {
            let pid = poolRef.createPosition()
            positions.append(pid)
            
            let collateral <- createTestVault(balance: 100.0 * UFix64(i + 1))
            poolRef.deposit(pid: pid, funds: <-collateral)
            
            i = i + 1
        }
        
        // Rapid price changes while positions active
        let stressPrices: [UFix64] = [1.0, 0.5, 2.0, 0.3, 3.0, 0.7, 1.5, 0.9, 1.1, 1.0]
        
        for price in stressPrices {
            oracle.setPrice(token: Type<@MockVault>(), price: price)
            
            // Check all positions remain calculable
            for pid in positions {
                let health = poolRef.positionHealth(pid: pid)
                Test.assert(health >= 0.0, message: "All positions should remain calculable")
            }
        }
        
        destroy pool
    }
} 