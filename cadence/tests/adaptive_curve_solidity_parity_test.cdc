import Test
import "FlowCreditMarket"
import "FlowCreditMarketMath"
import "test_helpers"

/// Test suite for verifying numerical parity with Solidity AdaptiveCurveIRM
/// These tests match specific scenarios from AdaptiveCurveIrmTest.sol
///
/// Key test cases from Solidity:
/// - testFirstBorrowRateUtilizationZero: rate = INITIAL_RATE / 4
/// - testFirstBorrowRateUtilizationOne: rate = INITIAL_RATE * 4
/// - testRateAfterUtilizationOne (5 days): rate ≈ 0.22976 APR
/// - testRateAfterUtilizationZero (5 days): rate ≈ 0.00724 APR

access(all) let tolerance: UFix128 = 0.1  // 10% tolerance for numerical comparisons

access(all)
fun setup() {
    deployContracts()
}

// ========== First Borrow Rate Tests (Solidity parity) ==========

/// Test: testFirstBorrowRateUtilizationZero
/// Expected: avgBorrowRate ≈ INITIAL_RATE_AT_TARGET / 4
access(all)
fun test_solidity_first_borrow_rate_utilization_zero() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Market with 0% utilization (totalBorrow = 0)
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 0.0
    let currentRateAtTarget: UFix128 = 0.0  // First interaction
    let lastUpdate: UFix64 = 0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRateAtTarget,
        lastUpdate: lastUpdate
    )

    // rateAtTarget should be set to INITIAL_RATE_AT_TARGET
    Test.assertEqual(irm.INITIAL_RATE_AT_TARGET, result.newRateAtTarget)

    // With 0% utilization, error = -1.0 (fully negative)
    // Curve: (0.75 * -1.0 + 1) * rateAtTarget = 0.25 * rateAtTarget
    // So rate = INITIAL_RATE_AT_TARGET / 4
    let expectedRate = irm.INITIAL_RATE_AT_TARGET / 4.0

    Test.assert(
        result.rate >= expectedRate * (1.0 - tolerance) &&
        result.rate <= expectedRate * (1.0 + tolerance),
        message: "Rate should be INITIAL_RATE / 4 at 0% utilization, expected "
            .concat(expectedRate.toString())
            .concat(", got ")
            .concat(result.rate.toString())
    )
}

/// Test: testFirstBorrowRateUtilizationOne
/// Expected: avgBorrowRate = INITIAL_RATE_AT_TARGET * 4
access(all)
fun test_solidity_first_borrow_rate_utilization_one() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Market with 100% utilization
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

    // rateAtTarget should be set to INITIAL_RATE_AT_TARGET
    Test.assertEqual(irm.INITIAL_RATE_AT_TARGET, result.newRateAtTarget)

    // With 100% utilization, error = (1.0 - 0.9) / (1.0 - 0.9) = 1.0
    // Curve: (3.0 * 1.0 + 1) * rateAtTarget = 4.0 * rateAtTarget
    // So rate = INITIAL_RATE_AT_TARGET * 4
    let expectedRate = irm.INITIAL_RATE_AT_TARGET * 4.0

    Test.assert(
        result.rate >= expectedRate * (1.0 - tolerance) &&
        result.rate <= expectedRate * (1.0 + tolerance),
        message: "Rate should be INITIAL_RATE * 4 at 100% utilization, expected "
            .concat(expectedRate.toString())
            .concat(", got ")
            .concat(result.rate.toString())
    )
}

// ========== Time-Based Adaptation Tests (Solidity parity) ==========

/// Test: testRateAfterUtilizationOne (5 days)
/// Expected: rate ≈ 0.22976 APR (per year) = 0.22976 / 365 days (per second)
/// Solidity test shows exp((50/365)*5) ≈ 1.4361 average multiplier
access(all)
fun test_solidity_rate_after_5_days_utilization_one() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Initialize with first interaction at 0% utilization
    let initResult = irm.calculateAdaptiveRate(
        creditBalance: 1000.0,
        debitBalance: 0.0,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Now simulate 5 days later at 100% utilization
    let fiveDaysInSeconds: UFix64 = 5 * 24 * 3600
    let currentTime = getCurrentBlock().timestamp
    let lastUpdate = currentTime - fiveDaysInSeconds

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 1000.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: initResult.newRateAtTarget,
        lastUpdate: lastUpdate
    )

    // Expected annual rate: ~0.22976 or 22.976%
    // Convert to per-second: 0.22976 / (365 * 24 * 3600)
    let expectedAnnualRate = 0.22976
    let expectedPerSecondRate = expectedAnnualRate / 365.0 / 24.0 / 3600.0

    Test.assert(
        result.rate >= expectedPerSecondRate * (1.0 - tolerance) &&
        result.rate <= expectedPerSecondRate * (1.0 + tolerance),
        message: "Rate after 5 days at 100% util should be ~0.22976 APR, expected "
            .concat(expectedPerSecondRate.toString())
            .concat(" per-second, got ")
            .concat(result.rate.toString())
    )
}

/// Test: testRateAfterUtilizationZero (5 days)
/// Expected: rate ≈ 0.00724 APR (per year) = 0.00724 / 365 days (per second)
/// Solidity test shows exp((-50/365)*5) ≈ 0.724 average multiplier
access(all)
fun test_solidity_rate_after_5_days_utilization_zero() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Initialize with first interaction at 0% utilization
    let initResult = irm.calculateAdaptiveRate(
        creditBalance: 1000.0,
        debitBalance: 0.0,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Now simulate 5 days later, still at 0% utilization
    let fiveDaysInSeconds: UFix64 = 5 * 24 * 3600
    let currentTime = getCurrentBlock().timestamp
    let lastUpdate = currentTime - fiveDaysInSeconds

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 0.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: initResult.newRateAtTarget,
        lastUpdate: lastUpdate
    )

    // Expected annual rate: ~0.00724 or 0.724%
    // Convert to per-second: 0.00724 / (365 * 24 * 3600)
    let expectedAnnualRate = 0.00724
    let expectedPerSecondRate = expectedAnnualRate / 365.0 / 24.0 / 3600.0

    Test.assert(
        result.rate >= expectedPerSecondRate * (1.0 - tolerance) &&
        result.rate <= expectedPerSecondRate * (1.0 + tolerance),
        message: "Rate after 5 days at 0% util should be ~0.00724 APR, expected "
            .concat(expectedPerSecondRate.toString())
            .concat(" per-second, got ")
            .concat(result.rate.toString())
    )
}

// ========== Rate At Target Adaptation Tests ==========

/// Test: Rate adaptation at target utilization (90%)
/// Expected: rateAtTarget should remain stable at INITIAL_RATE_AT_TARGET
access(all)
fun test_solidity_rate_at_target_utilization_stable() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Initialize
    let initResult = irm.calculateAdaptiveRate(
        creditBalance: 1000.0,
        debitBalance: 900.0,  // 90% = target
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // 1 day later at same utilization
    let oneDayInSeconds: UFix64 = 24 * 3600
    let currentTime = getCurrentBlock().timestamp
    let lastUpdate = currentTime - oneDayInSeconds

    let result = irm.calculateAdaptiveRate(
        creditBalance: 1000.0,
        debitBalance: 900.0,
        currentRateAtTarget: initResult.newRateAtTarget,
        lastUpdate: lastUpdate
    )

    // At exact target utilization, error = 0, so rateAtTarget should not change
    Test.assert(
        result.newRateAtTarget >= initResult.newRateAtTarget * (1.0 - tolerance) &&
        result.newRateAtTarget <= initResult.newRateAtTarget * (1.0 + tolerance),
        message: "Rate at target should remain stable at 90% utilization"
    )

    // Rate should equal rateAtTarget when error is zero
    Test.assert(
        result.rate >= result.newRateAtTarget * (1.0 - tolerance) &&
        result.rate <= result.newRateAtTarget * (1.0 + tolerance),
        message: "Rate should equal rateAtTarget at exact target utilization"
    )
}

/// Test: Rate adaptation with 50% error above target (95% utilization)
/// Expected: after 45 days, rateAtTarget ≈ 0.8722 APR (per second)
/// Solidity: 4% * exp(50 * 45/365 * 50%) = 87.22%
access(all)
fun test_solidity_rate_after_45_days_above_target() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Initialize at target
    let initResult = irm.calculateAdaptiveRate(
        creditBalance: 1000.0,
        debitBalance: 900.0,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // 45 days later at 95% utilization (50% error above target)
    let fortyFiveDaysInSeconds: UFix64 = 45 * 24 * 3600
    let currentTime = getCurrentBlock().timestamp
    let lastUpdate = currentTime - fortyFiveDaysInSeconds

    // 95% utilization = (95 - 90) / (100 - 90) = 0.5 error
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 950.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: initResult.newRateAtTarget,
        lastUpdate: lastUpdate
    )

    // Expected: 4% * exp(50 * 45/365 * 50%) ≈ 87.22% APR
    let expectedAnnualRate = 0.8722
    let expectedPerSecondRate = expectedAnnualRate / 365.0 / 24.0 / 3600.0

    Test.assert(
        result.newRateAtTarget >= expectedPerSecondRate * (1.0 - tolerance) &&
        result.newRateAtTarget <= expectedPerSecondRate * (1.0 + tolerance),
        message: "Rate at target after 45 days at 95% util should be ~0.8722 APR, expected "
            .concat(expectedPerSecondRate.toString())
            .concat(" per-second, got ")
            .concat(result.newRateAtTarget.toString())
    )
}
