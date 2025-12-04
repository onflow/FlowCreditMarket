import Test
import "FlowCreditMarket"
import "FlowCreditMarketMath"

/// Test suite for AdaptiveCurveIRM unit tests
/// Mirrors patterns from test/AdaptiveCurveIrmTest.sol
///
/// Tests:
/// - Initial rate calculations
/// - Curve function behavior
/// - Rate bounds verification
/// - Time-based adaptation
/// - Trapezoidal averaging
///
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

// ========== Initial Rate Tests ==========

/// Test that initial rate is set correctly (mirrors testFirstBorrowRateUtilizationZero)
access(all)
fun test_initial_rate_with_zero_utilization() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Test with zero utilization (no debit)
    let creditBalance: UFix128 = 0.0
    let debitBalance: UFix128 = 0.0
    let currentRateAtTarget: UFix128 = 0.0  // First interaction
    let lastUpdate: UFix64 = 0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRateAtTarget,
        lastUpdate: lastUpdate
    )

    // Initial rate should be INITIAL_RATE_AT_TARGET (4% APR = 0.04)
    Test.assertEqual(irm.INITIAL_RATE_AT_TARGET, result.newRateAtTarget)

    // With zero utilization and curve factor of 0.75, rate should be lower
    // rate = (0.75 * error + 1) * rateAtTarget
    // Since utilization = 0, error is negative (90% below target)
    // Expected: approximately INITIAL_RATE_AT_TARGET / 4
    let expectedRate = irm.INITIAL_RATE_AT_TARGET / 4.0
    Test.assert(
        result.rate >= expectedRate * (1.0 - tolerance) && result.rate <= expectedRate * (1.0 + tolerance),
        message: "Rate at zero utilization should be ~1% APR (INITIAL_RATE / 4), got ".concat(result.rate.toString())
    )
}

/// Test that rate at 100% utilization is higher (mirrors testFirstBorrowRateUtilizationOne)
access(all)
fun test_initial_rate_with_full_utilization() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Test with 100% utilization
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 1000.0
    let currentRateAtTarget: UFix128 = 0.0  // First interaction
    let lastUpdate: UFix64 = 0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRateAtTarget,
        lastUpdate: lastUpdate
    )

    // Initial rate at target should be set
    Test.assertEqual(irm.INITIAL_RATE_AT_TARGET, result.newRateAtTarget)

    // With 100% utilization (10% above target), curve multiplies by ~4
    // Expected: approximately INITIAL_RATE_AT_TARGET * 4
    let expectedRate = irm.INITIAL_RATE_AT_TARGET * 4.0
    Test.assert(
        result.rate >= expectedRate * (1.0 - tolerance) && result.rate <= expectedRate * (1.0 + tolerance),
        message: "Rate at 100% utilization should be ~16% APR (INITIAL_RATE * 4), got ".concat(result.rate.toString())
    )
}

// ========== Curve Function Tests ==========

/// Test curve function with negative error (below target utilization)
access(all)
fun test_curve_negative_error() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let rateAtTarget: UFix128 = 0.04  // 4% APR

    // Error of -0.5 (50% below target)
    let error = FlowCreditMarketMath.SignedUFix128(value: 0.5, isNegative: true)

    let result = irm.curve(rateAtTarget, error)

    // coeff = 1 - 1/4 = 0.75
    // rate = (0.75 * 0.5 + 1) * 0.04 = 1.375 * 0.04 = 0.055
    let expected = (0.75 * 0.5 + 1.0) * rateAtTarget

    Test.assert(
        result >= expected * (1.0 - tolerance) && result <= expected * (1.0 + tolerance),
        message: "Curve with negative error should apply 0.75 coefficient, expected ".concat(expected.toString()).concat(", got ").concat(result.toString())
    )
}

/// Test curve function with positive error (above target utilization)
access(all)
fun test_curve_positive_error() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let rateAtTarget: UFix128 = 0.04  // 4% APR

    // Error of +0.5 (50% above target)
    let error = FlowCreditMarketMath.SignedUFix128(value: 0.5, isNegative: false)

    let result = irm.curve(rateAtTarget, error)

    // coeff = 4 - 1 = 3
    // rate = (3 * 0.5 + 1) * 0.04 = 2.5 * 0.04 = 0.1
    let expected = (3.0 * 0.5 + 1.0) * rateAtTarget

    Test.assert(
        result >= expected * (1.0 - tolerance) && result <= expected * (1.0 + tolerance),
        message: "Curve with positive error should apply 3.0 coefficient, expected ".concat(expected.toString()).concat(", got ").concat(result.toString())
    )
}

/// Test curve function with zero error (at target)
access(all)
fun test_curve_zero_error() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let rateAtTarget: UFix128 = 0.04  // 4% APR

    // Error of 0 (exactly at target)
    let error = FlowCreditMarketMath.SignedUFix128(value: 0.0, isNegative: false)

    let result = irm.curve(rateAtTarget, error)

    // rate = (coeff * 0 + 1) * rateAtTarget = rateAtTarget
    Test.assertEqual(rateAtTarget, result)
}

// ========== Rate Bounds Tests ==========

/// Test that rate at target never goes below MIN_RATE_AT_TARGET
access(all)
fun test_rate_at_target_minimum_bound() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Simulate very low utilization for extended time to push rate down
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 100.0  // 10% utilization (well below 90% target)
    let currentRateAtTarget: UFix128 = irm.MIN_RATE_AT_TARGET * 2.0  // Start near minimum
    let lastUpdate: UFix64 = getCurrentBlock().timestamp - 86400  // 1 day ago

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRateAtTarget,
        lastUpdate: lastUpdate
    )

    // Rate at target should be bounded by MIN_RATE_AT_TARGET
    Test.assert(
        result.newRateAtTarget >= irm.MIN_RATE_AT_TARGET,
        message: "Rate at target should be >= MIN_RATE_AT_TARGET (0.1% APR), got ".concat(result.newRateAtTarget.toString())
    )
}

/// Test that rate at target never goes above MAX_RATE_AT_TARGET
access(all)
fun test_rate_at_target_maximum_bound() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Simulate very high utilization for extended time to push rate up
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 990.0  // 99% utilization (well above 90% target)
    let currentRateAtTarget: UFix128 = irm.MAX_RATE_AT_TARGET / 2.0  // Start near maximum
    let lastUpdate: UFix64 = getCurrentBlock().timestamp - 86400  // 1 day ago

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRateAtTarget,
        lastUpdate: lastUpdate
    )

    // Rate at target should be bounded by MAX_RATE_AT_TARGET
    Test.assert(
        result.newRateAtTarget <= irm.MAX_RATE_AT_TARGET,
        message: "Rate at target should be <= MAX_RATE_AT_TARGET (200% APR), got ".concat(result.newRateAtTarget.toString())
    )
}

// ========== Time Adaptation Tests ==========

/// Test that no time elapsed results in no rate change
access(all)
fun test_time_adaptation_no_time_elapsed() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 950.0  // 95% utilization
    let currentRateAtTarget: UFix128 = 0.05  // 5% APR
    let lastUpdate: UFix64 = getCurrentBlock().timestamp  // Just now

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRateAtTarget,
        lastUpdate: lastUpdate
    )

    // With no time elapsed, rateAtTarget should remain unchanged
    Test.assertEqual(currentRateAtTarget, result.newRateAtTarget)
}

/// Test that rate increases over time with high utilization
access(all)
fun test_time_adaptation_high_utilization_increases_rate() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 950.0  // 95% utilization (above target)
    let currentRateAtTarget: UFix128 = 0.04  // 4% APR
    let lastUpdate: UFix64 = getCurrentBlock().timestamp - 86400  // 1 day ago

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRateAtTarget,
        lastUpdate: lastUpdate
    )

    // Rate at target should increase
    Test.assert(
        result.newRateAtTarget > currentRateAtTarget,
        message: "Rate at target should increase with high utilization over time, was ".concat(currentRateAtTarget.toString()).concat(", now ").concat(result.newRateAtTarget.toString())
    )
}

/// Test that rate decreases over time with low utilization
access(all)
fun test_time_adaptation_low_utilization_decreases_rate() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 700.0  // 70% utilization (below target)
    let currentRateAtTarget: UFix128 = 0.04  // 4% APR
    let lastUpdate: UFix64 = getCurrentBlock().timestamp - 86400  // 1 day ago

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRateAtTarget,
        lastUpdate: lastUpdate
    )

    // Rate at target should decrease
    Test.assert(
        result.newRateAtTarget < currentRateAtTarget,
        message: "Rate at target should decrease with low utilization over time, was ".concat(currentRateAtTarget.toString()).concat(", now ").concat(result.newRateAtTarget.toString())
    )
}

/// Test rate stability at target utilization
access(all)
fun test_time_adaptation_at_target_utilization() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 900.0  // 90% utilization (exactly at target)
    let currentRateAtTarget: UFix128 = 0.04  // 4% APR
    let lastUpdate: UFix64 = getCurrentBlock().timestamp - 86400  // 1 day ago

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRateAtTarget,
        lastUpdate: lastUpdate
    )

    // Rate at target should remain approximately stable (within tolerance)
    Test.assert(
        result.newRateAtTarget >= currentRateAtTarget * (1.0 - tolerance) &&
        result.newRateAtTarget <= currentRateAtTarget * (1.0 + tolerance),
        message: "Rate at target should remain stable at target utilization, was ".concat(currentRateAtTarget.toString()).concat(", now ").concat(result.newRateAtTarget.toString())
    )
}

// ========== Trapezoidal Averaging Tests ==========

/// Test that trapezoidal averaging smooths rate changes
access(all)
fun test_trapezoidal_averaging_smoothing() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 1000.0  // 100% utilization
    let currentRateAtTarget: UFix128 = 0.04  // 4% APR
    let lastUpdate: UFix64 = getCurrentBlock().timestamp - 432000  // 5 days ago

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRateAtTarget,
        lastUpdate: lastUpdate
    )

    // The average rate should be between the start and end rates
    // Due to trapezoidal integration: avgRate = (start + end + 2*mid) / 4
    // This means the average is weighted toward the middle

    // Calculate what the end rate would be
    let endRate = result.newRateAtTarget

    // The returned rate should be less than what a simple curve application would give
    // because it's averaged over time
    let instantaneousCurveRate = irm.curve(
        endRate,
        FlowCreditMarketMath.SignedUFix128(value: 1.0, isNegative: false)  // 100% util = max positive error
    )

    Test.assert(
        result.rate < instantaneousCurveRate,
        message: "Averaged rate should be less than instantaneous curve rate due to smoothing"
    )
}

// ========== Parameter Tests ==========

/// Test that IRM parameters are set correctly
access(all)
fun test_irm_parameters() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Target utilization = 90%
    Test.assertEqual(0.9, irm.TARGET_UTILIZATION)

    // Curve steepness = 4
    Test.assertEqual(4.0, irm.CURVE_STEEPNESS)

    // Initial rate at target = 4% APR
    Test.assertEqual(0.04, irm.INITIAL_RATE_AT_TARGET)

    // Min rate at target = 0.1% APR
    Test.assertEqual(0.001, irm.MIN_RATE_AT_TARGET)

    // Max rate at target = 200% APR
    Test.assertEqual(2.0, irm.MAX_RATE_AT_TARGET)

    // Adjustment speed = 50/year (per second)
    let expectedSpeed = 50.0 / 365.0 / 24.0 / 3600.0
    Test.assert(
        irm.ADJUSTMENT_SPEED >= expectedSpeed * (1.0 - tolerance) &&
        irm.ADJUSTMENT_SPEED <= expectedSpeed * (1.0 + tolerance),
        message: "Adjustment speed should be ~50/year per second"
    )
}
