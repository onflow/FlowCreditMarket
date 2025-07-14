import Test
import BlockchainHelpers

import "test_helpers.cdc"

import "TidalProtocolUtils"

access(all) let protocolAccount = Test.getAccount(0x0000000000000007)

access(all)
fun setup() {
    deployContracts()
}

access(all)
fun testReducedPrecisionUInt256ToUFix64Succeeds() {
    let uintAmount: UInt256 = 24_244_814_054_591
    let ufixAmount: UFix64 = 24_244_814.05459100

    let actualUFixAmount = TidalProtocolUtils.uint256ToUFix64(uintAmount, decimals: 6)
    Test.assertEqual(ufixAmount, actualUFixAmount)
}

access(all)
fun testReducedPrecisionUInt256SmallChangeToUFix64Succeeds() {
    let uintAmount: UInt256 = 24_244_814_000_020
    let ufixAmount: UFix64 = 24_244_814.000020

    let actualUFixAmount = TidalProtocolUtils.uint256ToUFix64(uintAmount, decimals: 6)
    Test.assertEqual(ufixAmount, actualUFixAmount)
}

// Converting from UFix64 to UInt256 with reduced point precision (6 vs. 8) should round down
access(all)
fun testReducedPrecisionUFix64ToUInt256Succeeds() {
    let uintAmount: UInt256 = 24_244_814_054_591
    let ufixAmount: UFix64 = 24_244_814.05459154

    let actualUIntAmount = TidalProtocolUtils.ufix64ToUInt256(ufixAmount, decimals: 6)
    Test.assertEqual(uintAmount, actualUIntAmount)
}

access(all)
fun testDustUInt256ToUFix64Succeeds() {
    let dustUFixAmount: UFix64 = 0.00002547
    let dustUIntAmount: UInt256 = 25_470_000_000_000

    let actualUFixAmount = TidalProtocolUtils.uint256ToUFix64(dustUIntAmount, decimals: 18)
    Test.assertEqual(dustUFixAmount, actualUFixAmount)
    Test.assert(actualUFixAmount > 0.0)
}

access(all)
fun testDustUFix64ToUInt256Succeeds() {
    let dustUFixAmount: UFix64 = 0.00002547
    let dustUIntAmount: UInt256 = 25_470_000_000_000

    let actualUIntAmount = TidalProtocolUtils.ufix64ToUInt256(dustUFixAmount, decimals: 18)
    Test.assertEqual(dustUIntAmount, actualUIntAmount)
    Test.assert(actualUIntAmount > 0)
}

access(all)
fun testZeroUInt256ToUFix64Succeeds() {
    let zeroUFixAmount: UFix64 = 0.0
    let zeroUIntAmount: UInt256 = 0

    let actualUFixAmount = TidalProtocolUtils.uint256ToUFix64(zeroUIntAmount, decimals: 18)
    Test.assertEqual(zeroUFixAmount, actualUFixAmount)
}

access(all)
fun testZeroUFix64ToUInt256Succeeds() {
    let zeroUFixAmount: UFix64 = 0.0
    let zeroUIntAmount: UInt256 = 0

    let actualUIntAmount = TidalProtocolUtils.ufix64ToUInt256(zeroUFixAmount, decimals: 18)
    Test.assertEqual(zeroUIntAmount, actualUIntAmount)
}

access(all)
fun testNonFractionalUInt256ToUFix64Succeeds() {
    let nonFractionalUFixAmount: UFix64 = 100.0
    let nonFractionalUIntAmount: UInt256 = 100_000_000_000_000_000_000

    let actualUFixAmount = TidalProtocolUtils.uint256ToUFix64(nonFractionalUIntAmount, decimals: 18)
    Test.assertEqual(nonFractionalUFixAmount, actualUFixAmount)
}

access(all)
fun testNonFractionalUFix64ToUInt256Succeeds() {
    let nonFractionalUFixAmount: UFix64 = 100.0
    let nonFractionalUIntAmount: UInt256 = 100_000_000_000_000_000_000

    let actualUIntAmount = TidalProtocolUtils.ufix64ToUInt256(nonFractionalUFixAmount, decimals: 18)
    Test.assertEqual(nonFractionalUIntAmount, actualUIntAmount)
}

access(all)
fun testLargeFractionalUInt256ToUFix64Succeeds() {
    let largeFractionalUFixAmount: UFix64 = 1.99785982
    let largeFractionalUIntAmount: UInt256 = 1_997_859_829_999_999_999

    let actualUFixAmount = TidalProtocolUtils.uint256ToUFix64(largeFractionalUIntAmount, decimals: 18)
    Test.assertEqual(largeFractionalUFixAmount, actualUFixAmount)
}

access(all)
fun testLargeFractionalTrailingZerosUInt256ToUFix64Succeeds() {
    let largeFractionalUFixAmount: UFix64 = 1.99785982
    let largeFractionalUIntAmount: UInt256 = 1_997_859_829_999_000_000

    let actualUFixAmount = TidalProtocolUtils.uint256ToUFix64(largeFractionalUIntAmount, decimals: 18)
    Test.assertEqual(largeFractionalUFixAmount, actualUFixAmount)
}

access(all)
fun testLargeFractionalUFix64ToUInt256Succeeds() {
    let largeFractionalUFixAmount: UFix64 = 1.99785982
    let largeFractionalUIntAmount: UInt256 = 1_997_859_820_000_000_000

    let actualUIntAmount = TidalProtocolUtils.ufix64ToUInt256(largeFractionalUFixAmount, decimals: 18)
    Test.assertEqual(largeFractionalUIntAmount, actualUIntAmount)
}

access(all)
fun testIntegerAndLeadingZeroFractionalUInt256ToUFix64Succeeds() {
    let ufixAmount: UFix64 = 100.00000500
    let uintAmount: UInt256 = 100_000_005_000_000_888_999

    let actualUFixAmount = TidalProtocolUtils.uint256ToUFix64(uintAmount, decimals: 18)
    Test.assertEqual(ufixAmount, actualUFixAmount)
}

access(all)
fun testIntegerAndLeadingZeroFractionalUFix64ToUInt256Succeeds() {
    let ufixAmount: UFix64 = 100.00000500
    let uintAmount: UInt256 = 100_000_005_000_000_000_000

    let actualUIntAmount = TidalProtocolUtils.ufix64ToUInt256(ufixAmount, decimals: 18)
    Test.assertEqual(uintAmount, actualUIntAmount)
}

access(all)
fun testMaxUFix64ToUInt256Succeeds() {
    let ufixAmount: UFix64 = UFix64.max
    let uintAmount: UInt256 = 184467440737_095516150000000000

    let actualUIntAmount = TidalProtocolUtils.ufix64ToUInt256(ufixAmount, decimals: 18)

    Test.assertEqual(uintAmount, actualUIntAmount)
}

access(all)
fun testMaxUFix64AsUInt256ToUFix64Succeds() {
    let ufixAmount: UFix64 = UFix64.max
    var uintAmount: UInt256 = 184467440737_095516150000000000

    let actualUFixAmount = TidalProtocolUtils.uint256ToUFix64(uintAmount, decimals: 18)

    Test.assertEqual(ufixAmount, actualUFixAmount)
}

access(all)
fun testFractionalPartMaxUFix64AsUInt256ToUFix64Fails() {
    let ufixAmount: UFix64 = UFix64.max
    var uintAmount: UInt256 = 184467440737_095_516_150_000_000_000 + 10_000_000_000

    let convertedResult = executeScript(
        "./scripts/uint256_to_ufix64.cdc",
        [uintAmount, UInt8(18)]
    )
    Test.expect(convertedResult, Test.beFailed())
}

access(all)
fun testIntegerPartMaxUFix64AsUInt256ToUFix64Fails() {
    let ufixAmount: UFix64 = UFix64.max
    var uintAmount: UInt256 = 184467440737_095_516_150_000_000_000 + 100_000_000_000_000_000_000_000

    let convertedResult = executeScript(
        "./scripts/uint256_to_ufix64.cdc",
        [uintAmount, UInt8(18)]
    )
    Test.expect(convertedResult, Test.beFailed())
}

access(all)
fun testInterestIndexScalingWithDecimals16() {
    // Test: Interest index with 1e16 scale (decimals=16) conversions
    
    // Example 1: An interest index of 1.061538461538461538 (16 decimals) represented as UInt256
    let interestIndexUInt: UInt256 = 10_615_384_615_384_615 // 1.061538461538461538 * 1e16
    let expectedInterestIndex: UFix64 = 1.06153846 // UFix64 max precision is 8 decimals
    
    let actualInterestIndex = TidalProtocolUtils.uint256ToUFix64(interestIndexUInt, decimals: 16)
    Test.assertEqual(expectedInterestIndex, actualInterestIndex)
    
    // Convert back to verify round trip
    let roundTripUInt = TidalProtocolUtils.ufix64ToUInt256(actualInterestIndex, decimals: 16)
    let expectedRoundTrip: UInt256 = 10_615_384_600_000_000 // Loses precision beyond 8 decimals
    Test.assertEqual(expectedRoundTrip, roundTripUInt)
}

access(all)
fun testBalanceScalingWithInterestIndex() {
    // Test: Applying interest index to a balance
    
    // Starting balance: 1000.0 FLOW
    let balanceUFix: UFix64 = 1000.0
    let balanceUInt: UInt256 = TidalProtocolUtils.ufix64ToUInt256(balanceUFix, decimals: 16)
    Test.assertEqual(10_000_000_000_000_000_000 as UInt256, balanceUInt) // 1000 * 1e16
    
    // Interest index: 1.061538461538461538 (representing 6.15% interest)
    let interestIndexUInt: UInt256 = 10_615_384_615_384_615
    
    // Apply interest: balance * interestIndex / 1e16
    let divisor: UInt256 = 10_000_000_000_000_000
    let scaledBalanceUInt = (balanceUInt * interestIndexUInt) / divisor
    
    // Convert back to UFix64
    let scaledBalanceUFix = TidalProtocolUtils.uint256ToUFix64(scaledBalanceUInt, decimals: 16)
    let expectedScaledBalance: UFix64 = 1061.53846153 // 1000 * 1.061538461538
    
    // Due to UFix64 precision limits, we only get 8 decimal places
    Test.assertEqual(1061.53846153, scaledBalanceUFix)
}

access(all) 
fun testScaledBalanceToTrueBalanceConversion() {
    // Test the pattern used in TidalProtocol.cdc for scaled balance conversion
    
    // Scenario: User has a scaled balance that represents 1061.53846151 true tokens
    // This tests the specific conversion that's failing in the rebalance tests
    
    // True balance we expect: 1061.53846151
    let expectedTrueBalance: UFix64 = 1061.53846151
    
    // Interest index at time of calculation
    let interestIndex: UFix64 = 1.06153846 // Typical interest index after some accrual
    
    // Calculate scaled balance: trueBalance / interestIndex
    // In the protocol, this would be stored as the user's position
    let scaledBalance = expectedTrueBalance / interestIndex
    Test.assertEqual(1000.0, scaledBalance) // Should be approximately the original deposit
    
    // Now convert back (this is what getTideBalance does)
    let calculatedTrueBalance = scaledBalance * interestIndex
    
    // Due to UFix64 precision, we might lose some precision
    let tolerance = 0.00000001
    Test.assert(
        (calculatedTrueBalance > expectedTrueBalance - tolerance) &&
        (calculatedTrueBalance < expectedTrueBalance + tolerance),
        message: "True balance calculation is off. Expected: \(expectedTrueBalance), Got: \(calculatedTrueBalance)"
    )
}

access(all)
fun testRebalanceScenario2ExpectedValues() {
    // Test the specific values from rebalance_scenario2_test.cdc
    // These are the expected flow balances after yield price increases
    
    let testCases: [{String: UFix64}] = [
        {"yieldPrice": 1.1, "expectedBalance": 1061.53846151},
        {"yieldPrice": 1.2, "expectedBalance": 1120.92522857},
        {"yieldPrice": 1.3, "expectedBalance": 1178.40857358}
    ]
    
    // Starting values
    let initialDeposit: UFix64 = 1000.0
    let collateralFactor: UFix64 = 0.8
    let targetHealthFactor: UFix64 = 1.3
    
    for testCase in testCases {
        // Calculate expected balance based on yield price increase
        // This mimics what the rebalance logic should produce
        
        let yieldPrice = testCase["yieldPrice"]!
        let expectedBalance = testCase["expectedBalance"]!
        
        // Initial loan amount
        let loanAmount = initialDeposit * (collateralFactor / targetHealthFactor)
        
        // Profit from yield increase
        let yieldProfit = loanAmount * (yieldPrice - 1.0)
        
        // Total expected balance
        let calculatedBalance = initialDeposit + yieldProfit
        
        // Check if our calculation matches the expected values
        let tolerance = 0.01
        Test.assert(
            (calculatedBalance > expectedBalance - tolerance) &&
            (calculatedBalance < expectedBalance + tolerance),
            message: "Balance calculation mismatch for yield price \(yieldPrice). Expected: \(expectedBalance), Calculated: \(calculatedBalance)"
        )
    }
}

access(all)
fun testInterestIndexPrecisionLoss() {
    // Test to demonstrate precision loss when converting interest indices
    
    // High precision interest index (16 decimals)
    let preciseIndexUInt: UInt256 = 11_234_567_891_234_567 // 1.123456789123456789 * 1e16 (actually 17 digits for the full number)
    
    // Convert to UFix64 (loses precision beyond 8 decimals)
    let indexUFix = TidalProtocolUtils.uint256ToUFix64(preciseIndexUInt, decimals: 16)
    Test.assertEqual(1.12345678, indexUFix) // Only 8 decimal places retained
    
    // Convert back to UInt256
    let backToUInt = TidalProtocolUtils.ufix64ToUInt256(indexUFix, decimals: 16)
    Test.assertEqual(11_234_567_800_000_000 as UInt256, backToUInt) // Lost precision in lower digits
    
    // Calculate precision loss
    let precisionLoss = preciseIndexUInt - backToUInt
    Test.assertEqual(91_234_567 as UInt256, precisionLoss)
}
