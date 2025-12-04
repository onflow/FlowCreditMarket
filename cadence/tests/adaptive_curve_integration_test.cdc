import Test
import "FlowCreditMarket"
import "FlowCreditMarketMath"
import "test_helpers"

/// Test suite for AdaptiveCurveIRM integration with TokenState
/// Tests the full integration path through updateInterestRates()
///
/// Tests:
/// - TokenState initialization with AdaptiveCurveIRM
/// - updateInterestRates() type detection and adaptive logic
/// - State persistence across multiple updates
/// - Mixed IRM types in same pool

access(all) let tolerance: UFix128 = 0.001  // 0.1% tolerance

access(all)
fun setup() {
    // Deploy FlowCreditMarketMath first (dependency)
    var err = Test.deployContract(
        name: "FlowCreditMarketMath",
        path: "../lib/FlowCreditMarketMath.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())

    // Deploy FlowCreditMarket contract
    err = Test.deployContract(
        name: "FlowCreditMarket",
        path: "../contracts/FlowCreditMarket.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

// ========== TokenState Initialization Tests ==========

/// Test that TokenState can be created with AdaptiveCurveIRM
access(all)
fun test_tokenState_initialization_with_adaptive_irm() {
    let adaptiveIRM = FlowCreditMarket.AdaptiveCurveIRM()

    let tokenState = FlowCreditMarket.TokenState(
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        interestCurve: adaptiveIRM,
        depositRate: 100.0,
        depositCapacityCap: 1000000.0
    )

    // Verify IRM type is correct
    Test.assertEqual(
        Type<FlowCreditMarket.AdaptiveCurveIRM>(),
        tokenState.interestCurve.getType()
    )

    // Verify adaptive state initialized to zero
    Test.assertEqual(0.0, tokenState.adaptiveRateAtTarget)
    Test.assertEqual(UInt64(0), tokenState.adaptiveLastUpdate)
}

/// Test that TokenState can be created with SimpleInterestCurve (non-adaptive)
access(all)
fun test_tokenState_initialization_with_simple_curve() {
    let simpleIRM = FlowCreditMarket.SimpleInterestCurve(
        baseRate: 0.02,
        rate1: 0.04,
        rate2: 1.0,
        utilization1: 0.8,
        utilization2: 0.9
    )

    let tokenState = FlowCreditMarket.TokenState(
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        interestCurve: simpleIRM,
        depositRate: 100.0,
        depositCapacityCap: 1000000.0
    )

    // Verify IRM type is SimpleInterestCurve
    Test.assertEqual(
        Type<FlowCreditMarket.SimpleInterestCurve>(),
        tokenState.interestCurve.getType()
    )

    // Adaptive state should still be initialized to zero (unused)
    Test.assertEqual(0.0, tokenState.adaptiveRateAtTarget)
    Test.assertEqual(UInt64(0), tokenState.adaptiveLastUpdate)
}

// ========== updateInterestRates() Integration Tests ==========

/// Test that updateInterestRates() detects AdaptiveCurveIRM and updates adaptive state
access(all)
fun test_updateInterestRates_detects_adaptive_irm() {
    let adaptiveIRM = FlowCreditMarket.AdaptiveCurveIRM()

    let tokenState = FlowCreditMarket.TokenState(
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        interestCurve: adaptiveIRM,
        depositRate: 100.0,
        depositCapacityCap: 1000000.0
    )

    // Simulate some balances
    tokenState.totalCreditBalance = 1000.0
    tokenState.totalDebitBalance = 900.0  // 90% utilization (at target)

    // First update (no previous state)
    tokenState.updateInterestRates()

    // Verify adaptive state was initialized
    Test.assert(
        tokenState.adaptiveRateAtTarget > 0.0,
        message: "adaptiveRateAtTarget should be initialized, got ".concat(tokenState.adaptiveRateAtTarget.toString())
    )

    // Should be initialized to INITIAL_RATE_AT_TARGET (4% APR)
    Test.assertEqual(adaptiveIRM.INITIAL_RATE_AT_TARGET, tokenState.adaptiveRateAtTarget)

    // lastUpdate should be set to current block timestamp
    Test.assert(
        tokenState.adaptiveLastUpdate > 0,
        message: "adaptiveLastUpdate should be set"
    )

    // Debit rate should be set
    Test.assert(
        tokenState.currentDebitRate > FlowCreditMarketMath.one,
        message: "currentDebitRate should be set and > 1.0"
    )
}

/// Test that updateInterestRates() with SimpleInterestCurve doesn't use adaptive logic
access(all)
fun test_updateInterestRates_simple_curve_unchanged() {
    let simpleIRM = FlowCreditMarket.SimpleInterestCurve(
        baseRate: 0.02,
        rate1: 0.04,
        rate2: 1.0,
        utilization1: 0.8,
        utilization2: 0.9
    )

    let tokenState = FlowCreditMarket.TokenState(
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        interestCurve: simpleIRM,
        depositRate: 100.0,
        depositCapacityCap: 1000000.0
    )

    tokenState.totalCreditBalance = 1000.0
    tokenState.totalDebitBalance = 850.0  // 85% utilization

    tokenState.updateInterestRates()

    // Adaptive state should remain at zero (not used)
    Test.assertEqual(0.0, tokenState.adaptiveRateAtTarget)
    Test.assertEqual(UInt64(0), tokenState.adaptiveLastUpdate)

    // Debit rate should still be calculated (via SimpleInterestCurve)
    Test.assert(
        tokenState.currentDebitRate > FlowCreditMarketMath.one,
        message: "currentDebitRate should be calculated via SimpleInterestCurve"
    )
}

/// Test that updateInterestRates() handles zero credit balance
access(all)
fun test_updateInterestRates_zero_credit_balance() {
    let adaptiveIRM = FlowCreditMarket.AdaptiveCurveIRM()

    let tokenState = FlowCreditMarket.TokenState(
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        interestCurve: adaptiveIRM,
        depositRate: 100.0,
        depositCapacityCap: 1000000.0
    )

    // Zero balances
    tokenState.totalCreditBalance = 0.0
    tokenState.totalDebitBalance = 0.0

    tokenState.updateInterestRates()

    // Should return early with rates set to 1.0
    Test.assertEqual(FlowCreditMarketMath.one, tokenState.currentCreditRate)
    Test.assertEqual(FlowCreditMarketMath.one, tokenState.currentDebitRate)

    // Adaptive state should remain at zero (not initialized)
    Test.assertEqual(0.0, tokenState.adaptiveRateAtTarget)
}

// ========== State Persistence Tests ==========

/// Test that rateAtTarget persists across multiple updates
access(all)
fun test_rateAtTarget_persists_across_updates() {
    let adaptiveIRM = FlowCreditMarket.AdaptiveCurveIRM()

    let tokenState = FlowCreditMarket.TokenState(
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        interestCurve: adaptiveIRM,
        depositRate: 100.0,
        depositCapacityCap: 1000000.0
    )

    tokenState.totalCreditBalance = 1000.0
    tokenState.totalDebitBalance = 950.0  // 95% utilization (above target)

    // First update
    tokenState.updateInterestRates()
    let firstRateAtTarget = tokenState.adaptiveRateAtTarget
    let firstUpdate = tokenState.adaptiveLastUpdate

    Test.assert(
        firstRateAtTarget > 0.0,
        message: "First rateAtTarget should be set"
    )

    // Simulate time passing (manually set lastUpdate to past)
    // Note: In real scenario, this would happen via block progression
    // For testing, we can't manipulate block timestamp, so we test the logic

    // Second update with same balances
    tokenState.updateInterestRates()
    let secondRateAtTarget = tokenState.adaptiveRateAtTarget

    // With high utilization and time elapsed, rate should increase or stay same
    // (In this test, if no time actually elapsed, it should stay the same)
    Test.assert(
        secondRateAtTarget >= firstRateAtTarget,
        message: "Rate at target should persist or increase with high utilization"
    )
}

/// Test state persistence with utilization changes
access(all)
fun test_state_persistence_with_utilization_changes() {
    let adaptiveIRM = FlowCreditMarket.AdaptiveCurveIRM()

    let tokenState = FlowCreditMarket.TokenState(
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        interestCurve: adaptiveIRM,
        depositRate: 100.0,
        depositCapacityCap: 1000000.0
    )

    // Start with high utilization
    tokenState.totalCreditBalance = 1000.0
    tokenState.totalDebitBalance = 950.0  // 95%

    tokenState.updateInterestRates()
    let highUtilRate = tokenState.adaptiveRateAtTarget

    // Change to low utilization
    tokenState.totalDebitBalance = 700.0  // 70%

    tokenState.updateInterestRates()
    let lowUtilRate = tokenState.adaptiveRateAtTarget

    // Rate should persist from previous state
    // (actual change depends on time elapsed, but state should be maintained)
    Test.assert(
        lowUtilRate > 0.0,
        message: "Rate at target should remain > 0 after utilization change"
    )
}

// ========== First Interaction Tests ==========

/// Test first interaction sets initial rate (mirrors testFirstBorrowRateUtilizationZero)
access(all)
fun test_first_interaction_zero_utilization() {
    let adaptiveIRM = FlowCreditMarket.AdaptiveCurveIRM()

    let tokenState = FlowCreditMarket.TokenState(
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        interestCurve: adaptiveIRM,
        depositRate: 100.0,
        depositCapacityCap: 1000000.0
    )

    tokenState.totalCreditBalance = 1000.0
    tokenState.totalDebitBalance = 0.0  // 0% utilization

    tokenState.updateInterestRates()

    // First interaction should set INITIAL_RATE_AT_TARGET
    Test.assertEqual(adaptiveIRM.INITIAL_RATE_AT_TARGET, tokenState.adaptiveRateAtTarget)

    // Rate should be lower than INITIAL_RATE due to curve with negative error
    let expectedRate = adaptiveIRM.INITIAL_RATE_AT_TARGET / 4.0
    Test.assert(
        tokenState.currentDebitRate >= FlowCreditMarketMath.one + expectedRate * (1.0 - tolerance) &&
        tokenState.currentDebitRate <= FlowCreditMarketMath.one + expectedRate * (1.0 + tolerance),
        message: "Debit rate should be ~1% APR above 1.0, got ".concat(tokenState.currentDebitRate.toString())
    )
}

/// Test first interaction with full utilization (mirrors testFirstBorrowRateUtilizationOne)
access(all)
fun test_first_interaction_full_utilization() {
    let adaptiveIRM = FlowCreditMarket.AdaptiveCurveIRM()

    let tokenState = FlowCreditMarket.TokenState(
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        interestCurve: adaptiveIRM,
        depositRate: 100.0,
        depositCapacityCap: 1000000.0
    )

    tokenState.totalCreditBalance = 1000.0
    tokenState.totalDebitBalance = 1000.0  // 100% utilization

    tokenState.updateInterestRates()

    // First interaction should set INITIAL_RATE_AT_TARGET
    Test.assertEqual(adaptiveIRM.INITIAL_RATE_AT_TARGET, tokenState.adaptiveRateAtTarget)

    // Rate should be higher than INITIAL_RATE due to curve with positive error
    let expectedRate = adaptiveIRM.INITIAL_RATE_AT_TARGET * 4.0
    Test.assert(
        tokenState.currentDebitRate >= FlowCreditMarketMath.one + expectedRate * (1.0 - tolerance) &&
        tokenState.currentDebitRate <= FlowCreditMarketMath.one + expectedRate * (1.0 + tolerance),
        message: "Debit rate should be ~16% APR above 1.0, got ".concat(tokenState.currentDebitRate.toString())
    )
}

// ========== Credit Rate Calculation Tests ==========

/// Test that credit rate is calculated correctly with adaptive IRM
access(all)
fun test_credit_rate_calculation_with_adaptive_irm() {
    let adaptiveIRM = FlowCreditMarket.AdaptiveCurveIRM()

    let tokenState = FlowCreditMarket.TokenState(
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        interestCurve: adaptiveIRM,
        depositRate: 100.0,
        depositCapacityCap: 1000000.0
    )

    tokenState.totalCreditBalance = 1000.0
    tokenState.totalDebitBalance = 800.0  // 80% utilization

    tokenState.updateInterestRates()

    // Credit rate should be based on debit rate and utilization
    // creditRate = 1 + (debitRate - 1) * utilization
    let utilization = tokenState.totalDebitBalance / tokenState.totalCreditBalance
    let borrowAPR = tokenState.currentDebitRate - FlowCreditMarketMath.one
    let expectedCreditRate = FlowCreditMarketMath.one + (borrowAPR * utilization)

    Test.assert(
        tokenState.currentCreditRate >= expectedCreditRate * (1.0 - tolerance) &&
        tokenState.currentCreditRate <= expectedCreditRate * (1.0 + tolerance),
        message: "Credit rate should be calculated correctly, expected ~".concat(expectedCreditRate.toString()).concat(", got ").concat(tokenState.currentCreditRate.toString())
    )
}

// ========== Type Detection Tests ==========

/// Test that getType() correctly identifies AdaptiveCurveIRM
access(all)
fun test_type_detection_adaptive_curve_irm() {
    let adaptiveIRM = FlowCreditMarket.AdaptiveCurveIRM()

    let actualType = adaptiveIRM.getType()
    let expectedType = Type<FlowCreditMarket.AdaptiveCurveIRM>()

    Test.assertEqual(expectedType, actualType)
}

/// Test that getType() correctly identifies SimpleInterestCurve
access(all)
fun test_type_detection_simple_interest_curve() {
    let simpleIRM = FlowCreditMarket.SimpleInterestCurve(
        baseRate: 0.02,
        rate1: 0.04,
        rate2: 1.0,
        utilization1: 0.8,
        utilization2: 0.9
    )

    let actualType = simpleIRM.getType()
    let expectedType = Type<FlowCreditMarket.SimpleInterestCurve>()

    Test.assertEqual(expectedType, actualType)
}

// ========== Rate Bounds Integration Tests ==========

/// Test that updateInterestRates() respects MIN_RATE_AT_TARGET bound
access(all)
fun test_updateInterestRates_respects_min_bound() {
    let adaptiveIRM = FlowCreditMarket.AdaptiveCurveIRM()

    let tokenState = FlowCreditMarket.TokenState(
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        interestCurve: adaptiveIRM,
        depositRate: 100.0,
        depositCapacityCap: 1000000.0
    )

    // Very low utilization to push rate down
    tokenState.totalCreditBalance = 1000.0
    tokenState.totalDebitBalance = 100.0  // 10% utilization

    // Multiple updates to potentially reach minimum
    tokenState.updateInterestRates()
    tokenState.updateInterestRates()
    tokenState.updateInterestRates()

    // Rate at target should not go below MIN_RATE_AT_TARGET
    Test.assert(
        tokenState.adaptiveRateAtTarget >= adaptiveIRM.MIN_RATE_AT_TARGET,
        message: "adaptiveRateAtTarget should be >= MIN_RATE_AT_TARGET"
    )
}

/// Test that updateInterestRates() respects MAX_RATE_AT_TARGET bound
access(all)
fun test_updateInterestRates_respects_max_bound() {
    let adaptiveIRM = FlowCreditMarket.AdaptiveCurveIRM()

    let tokenState = FlowCreditMarket.TokenState(
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        interestCurve: adaptiveIRM,
        depositRate: 100.0,
        depositCapacityCap: 1000000.0
    )

    // Very high utilization to push rate up
    tokenState.totalCreditBalance = 1000.0
    tokenState.totalDebitBalance = 999.0  // 99.9% utilization

    // Multiple updates to potentially reach maximum
    tokenState.updateInterestRates()
    tokenState.updateInterestRates()
    tokenState.updateInterestRates()

    // Rate at target should not go above MAX_RATE_AT_TARGET
    Test.assert(
        tokenState.adaptiveRateAtTarget <= adaptiveIRM.MAX_RATE_AT_TARGET,
        message: "adaptiveRateAtTarget should be <= MAX_RATE_AT_TARGET"
    )
}
