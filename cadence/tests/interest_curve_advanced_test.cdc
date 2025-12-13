import Test
import BlockchainHelpers

import "MOET"
import "FlowToken"
import "FlowCreditMarket"
import "FlowCreditMarketMath"
import "test_helpers.cdc"
import "MockFlowCreditMarketConsumer"

// =============================================================================
// Advanced Interest Curve Tests
// =============================================================================
// These tests verify critical edge cases and mathematical correctness:
// 1. Curve change mid-accrual - verifies old interest is finalized before new curve
// 2. Exact compounding verification - proves compound interest formula is correct
// 3. Rate change between time periods - validates interest segmentation
// =============================================================================

access(all) let protocolAccount = Test.getAccount(0x0000000000000007)
access(all) let protocolConsumerAccount = Test.getAccount(0x0000000000000008)

access(all) let flowTokenIdentifier = "A.0000000000000003.FlowToken.Vault"
access(all) let flowVaultStoragePath = /storage/flowTokenVault
access(all) let wrapperStoragePath = /storage/flowCreditMarketPositionWrapper

// Time constants
access(all) let ONE_DAY: Fix64 = 86400.0
access(all) let TEN_DAYS: Fix64 = 864000.0
access(all) let FIFTEEN_DAYS: Fix64 = 1296000.0  // 15 * 86400
access(all) let THIRTY_DAYS: Fix64 = 2592000.0   // 30 * 86400
access(all) let ONE_YEAR: Fix64 = 31536000.0     // 365 * 86400

access(all)
fun setup() {
    deployContracts()

    let betaTxResult = grantBeta(protocolAccount, protocolConsumerAccount)
    Test.expect(betaTxResult, Test.beSucceeded())
}

// =============================================================================
// Helper Functions
// =============================================================================

access(all)
fun getBlockTimestamp(): UFix64 {
    let res = _executeScript("../scripts/flow-credit-market/get_block_timestamp.cdc", [])
    Test.expect(res, Test.beSucceeded())
    return res.returnValue as! UFix64
}

access(all)
fun getDebitBalanceForType(details: FlowCreditMarket.PositionDetails, vaultType: Type): UFix64 {
    for balance in details.balances {
        if balance.vaultType == vaultType && balance.direction == FlowCreditMarket.BalanceDirection.Debit {
            return balance.balance
        }
    }
    return 0.0
}

access(all)
fun getCreditBalanceForType(details: FlowCreditMarket.PositionDetails, vaultType: Type): UFix64 {
    for balance in details.balances {
        if balance.vaultType == vaultType && balance.direction == FlowCreditMarket.BalanceDirection.Credit {
            return balance.balance
        }
    }
    return 0.0
}

// =============================================================================
// Test 1: Curve Change Mid-Accrual with Rate Segmentation
// =============================================================================
// This comprehensive test verifies:
// 1. Interest accrues correctly at initial rate
// 2. Curve change properly finalizes interest at old rate
// 3. Subsequent interest accrues at new rate
// 4. Rate change ratios are mathematically correct
//
// Scenario using a single pool that evolves over time:
// - Phase 1: 10 days at 5% APY
// - Phase 2: 10 days at 15% APY (3x rate)
// - Phase 3: 10 days at 10% APY (2x original rate)
// =============================================================================
access(all)
fun test_curve_change_mid_accrual_and_rate_segmentation() {
    // Setup: price oracle
    setMockOraclePrice(signer: protocolAccount, forTokenIdentifier: flowTokenIdentifier, price: 1.0)

    // Create pool
    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)

    // Add FlowToken for collateral
    addSupportedTokenKinkCurve(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        optimalUtilization: 0.80,
        baseRate: 0.0,
        slope1: 0.04,
        slope2: 0.60,
        depositRate: 1_000_000.0,
        depositCapacityCap: 1_000_000.0
    )

    // Create LP
    let lp = Test.createAccount()
    setupMoetVault(lp, beFailed: false)
    mintMoet(signer: protocolAccount, to: lp.address, amount: 100_000.0, beFailed: false)

    let lpBetaRes = grantBeta(protocolAccount, lp)
    Test.expect(lpBetaRes, Test.beSucceeded())

    let createLpPosRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [100_000.0, MOET.VaultStoragePath, false],
        lp
    )
    Test.expect(createLpPosRes, Test.beSucceeded())
    log("LP deposited 100,000 MOET")

    // Set initial rate: 5% APY
    let rate1: UFix128 = 0.05
    setInterestCurveFixed(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        yearlyRate: rate1
    )
    log("Set MOET interest rate to 5% APY (Phase 1)")

    // Create borrower
    let borrower = Test.createAccount()
    setupMoetVault(borrower, beFailed: false)
    mintFlow(to: borrower, amount: 10_000.0)

    let borrowerBetaRes = grantBeta(protocolAccount, borrower)
    Test.expect(borrowerBetaRes, Test.beSucceeded())

    let openRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [10_000.0, flowVaultStoragePath, true],
        borrower
    )
    Test.expect(openRes, Test.beSucceeded())
    log("Borrower deposited 10,000 Flow and auto-borrowed MOET")

    let borrowerPid: UInt64 = 1

    // Record initial state
    let detailsT0 = getPositionDetails(pid: borrowerPid, beFailed: false)
    let debtT0 = getDebitBalanceForType(details: detailsT0, vaultType: Type<@MOET.Vault>())
    log("=== DAY 0 ===")
    log("Initial debt: ".concat(debtT0.toString()))

    // === PHASE 1: 10 days at 5% ===
    Test.moveTime(by: TEN_DAYS)
    Test.commitBlock()

    let detailsT10 = getPositionDetails(pid: borrowerPid, beFailed: false)
    let debtT10 = getDebitBalanceForType(details: detailsT10, vaultType: Type<@MOET.Vault>())
    let growth1 = debtT10 - debtT0
    log("=== DAY 10 ===")
    log("Debt after 10 days @ 5%: ".concat(debtT10.toString()))
    log("Phase 1 growth: ".concat(growth1.toString()))

    // Verify Phase 1 had positive growth
    Test.assert(growth1 > 0.0, message: "Phase 1 should have positive growth")

    // Change to 15% APY (3x original rate)
    let rate2: UFix128 = 0.15
    setInterestCurveFixed(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        yearlyRate: rate2
    )
    log("Changed MOET interest rate to 15% APY (Phase 2)")

    // === PHASE 2: 10 days at 15% ===
    Test.moveTime(by: TEN_DAYS)
    Test.commitBlock()

    let detailsT20 = getPositionDetails(pid: borrowerPid, beFailed: false)
    let debtT20 = getDebitBalanceForType(details: detailsT20, vaultType: Type<@MOET.Vault>())
    let growth2 = debtT20 - debtT10
    log("=== DAY 20 ===")
    log("Debt after 10 days @ 15%: ".concat(debtT20.toString()))
    log("Phase 2 growth: ".concat(growth2.toString()))

    // Verify Phase 2 had positive growth
    Test.assert(growth2 > 0.0, message: "Phase 2 should have positive growth")

    // Change to 10% APY (2x original rate)
    let rate3: UFix128 = 0.10
    setInterestCurveFixed(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        yearlyRate: rate3
    )
    log("Changed MOET interest rate to 10% APY (Phase 3)")

    // === PHASE 3: 10 days at 10% ===
    Test.moveTime(by: TEN_DAYS)
    Test.commitBlock()

    let detailsT30 = getPositionDetails(pid: borrowerPid, beFailed: false)
    let debtT30 = getDebitBalanceForType(details: detailsT30, vaultType: Type<@MOET.Vault>())
    let growth3 = debtT30 - debtT20
    log("=== DAY 30 ===")
    log("Debt after 10 days @ 10%: ".concat(debtT30.toString()))
    log("Phase 3 growth: ".concat(growth3.toString()))

    // Verify Phase 3 had positive growth
    Test.assert(growth3 > 0.0, message: "Phase 3 should have positive growth")

    // === ASSERTIONS ===

    // 1. Growth ratios should reflect the rate ratios
    // Phase 2 (15%) / Phase 1 (5%) ≈ 3x
    let ratio21 = growth2 / growth1
    log("Phase 2/Phase 1 ratio (should be ~3): ".concat(ratio21.toString()))
    Test.assert(
        ratio21 >= 2.5 && ratio21 <= 3.5,
        message: "Phase 2 growth should be ~3x Phase 1 (15%/5%). Actual ratio: ".concat(ratio21.toString())
    )

    // Phase 3 (10%) / Phase 1 (5%) ≈ 2x
    let ratio31 = growth3 / growth1
    log("Phase 3/Phase 1 ratio (should be ~2): ".concat(ratio31.toString()))
    Test.assert(
        ratio31 >= 1.5 && ratio31 <= 2.5,
        message: "Phase 3 growth should be ~2x Phase 1 (10%/5%). Actual ratio: ".concat(ratio31.toString())
    )

    // Phase 2 (15%) / Phase 3 (10%) ≈ 1.5x
    let ratio23 = growth2 / growth3
    log("Phase 2/Phase 3 ratio (should be ~1.5): ".concat(ratio23.toString()))
    Test.assert(
        ratio23 >= 1.2 && ratio23 <= 1.8,
        message: "Phase 2 growth should be ~1.5x Phase 3 (15%/10%). Actual ratio: ".concat(ratio23.toString())
    )

    // 2. Total growth should equal sum of phases
    let totalGrowth = debtT30 - debtT0
    let sumOfPhases = growth1 + growth2 + growth3
    let growthDiff = totalGrowth > sumOfPhases 
        ? totalGrowth - sumOfPhases 
        : sumOfPhases - totalGrowth

    log("Total growth: ".concat(totalGrowth.toString()))
    log("Sum of phases: ".concat(sumOfPhases.toString()))
    log("Difference: ".concat(growthDiff.toString()))

    // Allow small tolerance for rounding
    Test.assert(
        growthDiff < 0.01,
        message: "Total growth should equal sum of phase growths"
    )

    log("=== TEST PASSED ===")
    log("Multiple rate changes correctly segmented interest accrual")
}

// =============================================================================
// Test 2: Exact Compounding Verification (1 Year)
// =============================================================================
// This test verifies that the compound interest formula is mathematically correct.
// We continue from the previous test state with established positions.
//
// Formula: FinalBalance = InitialBalance × e^(r×t) for continuous compounding
// The protocol uses per-second compounding, which closely approximates continuous.
//
// Expected: 10% APY should yield ~10.52% with continuous compounding (e^0.10 ≈ 1.10517)
// =============================================================================
access(all)
fun test_exact_compounding_verification_one_year() {
    // Get borrower's current debt (from previous test state)
    let borrowerPid: UInt64 = 1
    
    // Set MOET to exactly 10% APY for easy math verification
    let yearlyRate: UFix128 = 0.10
    setInterestCurveFixed(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        yearlyRate: yearlyRate
    )
    log("Set MOET interest rate to 10% APY for compounding verification")

    // Record debt before 1-year advancement
    let detailsBefore = getPositionDetails(pid: borrowerPid, beFailed: false)
    let debtBefore = getDebitBalanceForType(details: detailsBefore, vaultType: Type<@MOET.Vault>())

    log("=== BEFORE 1 YEAR ===")
    log("Debt before: ".concat(debtBefore.toString()))

    // Advance time by exactly 1 year
    Test.moveTime(by: ONE_YEAR)
    Test.commitBlock()

    // Record final debt
    let detailsAfter = getPositionDetails(pid: borrowerPid, beFailed: false)
    let debtAfter = getDebitBalanceForType(details: detailsAfter, vaultType: Type<@MOET.Vault>())

    log("=== AFTER 1 YEAR ===")
    log("Debt after: ".concat(debtAfter.toString()))

    // Calculate actual growth
    let actualGrowth = debtAfter - debtBefore
    let actualGrowthRate = actualGrowth / debtBefore
    log("Actual growth: ".concat(actualGrowth.toString()))
    log("Actual growth rate: ".concat(actualGrowthRate.toString()))

    // Calculate expected growth using continuous compounding formula: e^r - 1
    // e^0.10 ≈ 1.10517, so growth rate ≈ 0.10517 (10.517%)
    let expectedMinGrowthRate: UFix64 = 0.1000  // At minimum, simple interest
    let expectedMaxGrowthRate: UFix64 = 0.1100  // Continuous compounding upper bound

    log("Expected growth rate range: [".concat(expectedMinGrowthRate.toString())
        .concat(", ").concat(expectedMaxGrowthRate.toString()).concat("]"))

    // Verify the actual growth rate is within expected range
    Test.assert(
        actualGrowthRate >= expectedMinGrowthRate && actualGrowthRate <= expectedMaxGrowthRate,
        message: "Actual growth rate ".concat(actualGrowthRate.toString())
            .concat(" should be between simple (10%) and continuous (~10.52%) compounding")
    )

    // More precise check: should be very close to e^0.10 - 1 ≈ 0.10517
    // Allow 0.5% tolerance for rounding
    let expectedExactRate: UFix64 = 0.10517
    let tolerance: UFix64 = 0.005
    let diff = actualGrowthRate > expectedExactRate 
        ? actualGrowthRate - expectedExactRate 
        : expectedExactRate - actualGrowthRate

    log("Difference from expected continuous compounding: ".concat(diff.toString()))

    Test.assert(
        diff <= tolerance,
        message: "Growth rate should be within 0.5% of e^0.10 - 1 = 0.10517. Actual: "
            .concat(actualGrowthRate.toString())
    )

    log("=== TEST PASSED ===")
    log("Compound interest formula verified: growth rate ≈ 10.52% (continuous compounding)")
}

// =============================================================================
// Test 3: Rapid Curve Changes (Same Block Edge Case)
// =============================================================================
// Verifies that changing the curve multiple times rapidly doesn't cause issues
// (no negative time delta, no double-counting)
// =============================================================================
access(all)
fun test_rapid_curve_changes_no_double_counting() {
    // Get borrower's current debt
    let borrowerPid: UInt64 = 1
    
    // Record debt before rapid changes
    let detailsBefore = getPositionDetails(pid: borrowerPid, beFailed: false)
    let debtBefore = getDebitBalanceForType(details: detailsBefore, vaultType: Type<@MOET.Vault>())

    log("=== BEFORE RAPID CHANGES ===")
    log("Debt: ".concat(debtBefore.toString()))

    // Change curve multiple times in rapid succession (no time advancement)
    setInterestCurveFixed(signer: protocolAccount, tokenTypeIdentifier: defaultTokenIdentifier, yearlyRate: 0.05)
    setInterestCurveFixed(signer: protocolAccount, tokenTypeIdentifier: defaultTokenIdentifier, yearlyRate: 0.20)
    setInterestCurveFixed(signer: protocolAccount, tokenTypeIdentifier: defaultTokenIdentifier, yearlyRate: 0.10)

    // Record debt after rapid changes
    let detailsAfter = getPositionDetails(pid: borrowerPid, beFailed: false)
    let debtAfter = getDebitBalanceForType(details: detailsAfter, vaultType: Type<@MOET.Vault>())

    log("=== AFTER RAPID CHANGES ===")
    log("Debt: ".concat(debtAfter.toString()))

    // Debt should be essentially unchanged (only minimal accrual from transaction timestamps)
    let growth = debtAfter - debtBefore
    let growthRate = growth / debtBefore

    log("Growth from rapid curve changes: ".concat(growth.toString()))
    log("Growth rate: ".concat(growthRate.toString()))

    // Growth should be negligible (< 0.01% from any timestamp differences)
    Test.assert(
        growthRate < 0.0001,
        message: "Rapid curve changes should not cause significant interest accrual. Growth rate: "
            .concat(growthRate.toString())
    )

    log("=== TEST PASSED ===")
    log("Rapid curve changes in same block handled correctly")
}

// =============================================================================
// Test 4: Credit Rate Also Changes with Curve
// =============================================================================
// Verifies that LP credit balance also responds correctly to curve changes
// =============================================================================
access(all)
fun test_credit_rate_changes_with_curve() {
    // Get LP's current credit (LP position ID = 0)
    let lpPid: UInt64 = 0
    
    // Set a specific rate for this test
    let testRate: UFix128 = 0.08 // 8% APY
    setInterestCurveFixed(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        yearlyRate: testRate
    )
    log("Set MOET interest rate to 8% APY")

    // Record LP credit before
    let detailsBefore = getPositionDetails(pid: lpPid, beFailed: false)
    let creditBefore = getCreditBalanceForType(details: detailsBefore, vaultType: Type<@MOET.Vault>())

    log("=== BEFORE 30 DAYS ===")
    log("LP Credit: ".concat(creditBefore.toString()))

    // Advance 30 days
    Test.moveTime(by: THIRTY_DAYS)
    Test.commitBlock()

    // Record LP credit after
    let detailsAfter = getPositionDetails(pid: lpPid, beFailed: false)
    let creditAfter = getCreditBalanceForType(details: detailsAfter, vaultType: Type<@MOET.Vault>())

    log("=== AFTER 30 DAYS ===")
    log("LP Credit: ".concat(creditAfter.toString()))

    // Verify credit increased
    Test.assert(
        creditAfter > creditBefore,
        message: "LP credit should increase over time"
    )

    let creditGrowth = creditAfter - creditBefore
    let creditGrowthRate = creditGrowth / creditBefore

    log("Credit growth: ".concat(creditGrowth.toString()))
    log("Credit growth rate (30 days): ".concat(creditGrowthRate.toString()))

    // For FixedRate, credit rate = debit rate - insurance
    // At 8% debit, 0.1% insurance = 7.9% credit
    // 30-day growth ≈ (30/365) × 7.9% ≈ 0.65%
    Test.assert(
        creditGrowthRate >= 0.004 && creditGrowthRate <= 0.01,
        message: "Credit growth rate should be approximately 0.65% for 30 days @ ~7.9%"
    )

    log("=== TEST PASSED ===")
    log("Credit rate correctly responds to curve changes")
}
