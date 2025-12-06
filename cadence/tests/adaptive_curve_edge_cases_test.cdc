import Test
import "FlowCreditMarket"
import "FlowCreditMarketMath"
import "test_helpers"

/// Test suite for AdaptiveCurveIRM edge cases and boundary conditions
/// Tests extreme values, zero balances, overflow/underflow protection
///
/// Edge Cases:
/// - Zero balances handling
/// - Very small values (near precision limits)
/// - Very large values (near UFix128.max)
/// - Extreme time elapsed
/// - Boundary utilization values

access(all) let tolerance: UFix128 = 0.001  // 0.1% tolerance

access(all)
fun setup() {
    deployContracts()
}

// ========== Zero Balance Tests ==========

/// Test with zero credit balance
access(all)
fun test_edge_case_zero_credit_balance() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 0.0
    let debitBalance: UFix128 = 0.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // With zero credit, should return initial state
    // (In practice, TokenState.updateInterestRates() would return early)
    Test.assert(
        result.newRateAtTarget >= 0.0,
        message: "Should handle zero credit balance gracefully"
    )
}

/// Test with zero debit balance (0% utilization)
access(all)
fun test_edge_case_zero_debit_balance() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 0.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Should initialize rate
    Test.assertEqual(irm.INITIAL_RATE_AT_TARGET, result.newRateAtTarget)

    // With 0% utilization, error = (0 - 0.9) / (1 - 0.9) = -0.9 / 0.1 = -9.0 → clamped to -1.0
    // Curve: rate = (0.75 * -1.0 + 1) * rateAtTarget = 0.25 * rateAtTarget
    let expectedRate = result.newRateAtTarget * 0.25
    Test.assert(
        result.rate >= expectedRate * (1.0 - tolerance) &&
        result.rate <= expectedRate * (1.0 + tolerance),
        message: "Rate should be 0.25x rateAtTarget at 0% utilization"
    )
}

/// Test with zero current rate at target (first interaction)
access(all)
fun test_edge_case_zero_current_rate_at_target() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 900.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,  // First interaction
        lastUpdate: 0
    )

    // Should initialize to INITIAL_RATE_AT_TARGET
    Test.assertEqual(irm.INITIAL_RATE_AT_TARGET, result.newRateAtTarget)
}

/// Test with zero time elapsed
access(all)
fun test_edge_case_zero_time_elapsed() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 950.0
    let currentRate: UFix128 = 0.05

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRate,
        lastUpdate: currentTime  // Same as current time
    )

    // With zero time elapsed, rate should remain unchanged
    Test.assertEqual(currentRate, result.newRateAtTarget)
}

// ========== Very Small Value Tests ==========

/// Test with very small balances (near precision limit)
access(all)
fun test_edge_case_very_small_balances() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // UFix128 has 24 decimal places, smallest step is 1e-24
    // UFix64 has 8 decimal places, smallest step is 1e-8
    let smallBalance: UFix128 = 0.00000001  // Smallest UFix64 value

    let creditBalance: UFix128 = smallBalance
    let debitBalance: UFix128 = smallBalance * 0.9  // 90% utilization

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Should handle small balances without overflow/underflow
    Test.assert(
        result.newRateAtTarget > 0.0,
        message: "Should handle very small balances"
    )

    Test.assert(
        result.rate > 0.0,
        message: "Should calculate rate for very small balances"
    )
}

/// Test with very small rate at target (near minimum)
access(all)
fun test_edge_case_very_small_rate_at_target() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 900.0
    let verySmallRate: UFix128 = irm.MIN_RATE_AT_TARGET  // 0.1% APR

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: verySmallRate,
        lastUpdate: 0
    )

    // Should handle minimum rate
    Test.assert(
        result.newRateAtTarget >= irm.MIN_RATE_AT_TARGET,
        message: "Rate should remain at or above minimum"
    )
}

/// Test with very small time elapsed (1 second)
access(all)
fun test_edge_case_one_second_elapsed() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 950.0
    let currentRate: UFix128 = 0.04

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRate,
        lastUpdate: currentTime - 1  // 1 second ago
    )

    // With 1 second elapsed, change should be very small
    let rateDiff = result.newRateAtTarget > currentRate ?
        result.newRateAtTarget - currentRate :
        currentRate - result.newRateAtTarget

    Test.assert(
        rateDiff < 0.0001,  // Less than 0.01% change
        message: "Rate change should be minimal with 1 second elapsed"
    )
}

// ========== Very Large Value Tests ==========

/// Test with very large balances (near UFix128.max)
access(all)
fun test_edge_case_very_large_balances() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // UFix128.max = 340282366920938463463374607431768211455.999999999999999999999999
    // Use a large but safe value
    let largeBalance: UFix128 = 1000000000000.0  // 1 trillion

    let creditBalance: UFix128 = largeBalance
    let debitBalance: UFix128 = largeBalance * 0.9  // 90% utilization

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Should handle large balances without overflow
    Test.assert(
        result.newRateAtTarget > 0.0,
        message: "Should handle very large balances"
    )

    Test.assert(
        result.rate > 0.0 && result.rate < UFix128.max,
        message: "Should calculate bounded rate for very large balances"
    )
}

/// Test with very large rate at target (near maximum)
access(all)
fun test_edge_case_very_large_rate_at_target() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 900.0
    let veryLargeRate: UFix128 = irm.MAX_RATE_AT_TARGET  // 200% APR

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: veryLargeRate,
        lastUpdate: 0
    )

    // Should handle maximum rate and not exceed it
    Test.assert(
        result.newRateAtTarget <= irm.MAX_RATE_AT_TARGET,
        message: "Rate should not exceed maximum"
    )
}

/// Test with very long time elapsed (1 year)
access(all)
fun test_edge_case_one_year_elapsed() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 950.0
    let currentRate: UFix128 = 0.04
    let oneYear: UFix64 = 31536000  // 365 days

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: currentRate,
        lastUpdate: currentTime - oneYear
    )

    // With 1 year elapsed at high utilization, rate should increase significantly
    // but still be bounded by MAX_RATE_AT_TARGET
    Test.assert(
        result.newRateAtTarget > currentRate,
        message: "Rate should increase significantly over 1 year at high utilization"
    )

    Test.assert(
        result.newRateAtTarget <= irm.MAX_RATE_AT_TARGET,
        message: "Rate should be bounded even after 1 year"
    )
}

// ========== Boundary Utilization Tests ==========

/// Test exactly at utilization boundaries
access(all)
fun test_edge_case_utilization_exactly_at_target() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 100.0
    let debitBalance: UFix128 = 90.0  // Exactly 90%

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.04,
        lastUpdate: 0
    )

    // Error should be exactly zero
    // Rate should equal rateAtTarget
    Test.assert(
        result.rate >= result.newRateAtTarget * (1.0 - tolerance) &&
        result.rate <= result.newRateAtTarget * (1.0 + tolerance),
        message: "Rate should equal rateAtTarget at exactly 90% utilization"
    )
}

/// Test utilization at 0% (minimum)
access(all)
fun test_edge_case_utilization_exactly_zero() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 0.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.04,
        lastUpdate: 0
    )

    // Error = (0 - 0.9) / (1 - 0.9) = -9.0 → clamped to -1.0
    // Minimum possible rate multiplier: 0.25
    let expectedRate = result.newRateAtTarget * 0.25

    Test.assert(
        result.rate >= expectedRate * (1.0 - tolerance) &&
        result.rate <= expectedRate * (1.0 + tolerance),
        message: "Rate should be minimum multiplier at 0% utilization"
    )
}

/// Test utilization at 100% (maximum)
access(all)
fun test_edge_case_utilization_exactly_one_hundred() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 1000.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.04,
        lastUpdate: 0
    )

    // Error = (1.0 - 0.9) / (1 - 0.9) = 1.0
    // Maximum possible rate multiplier: 4.0
    let expectedRate = result.newRateAtTarget * 4.0

    Test.assert(
        result.rate >= expectedRate * (1.0 - tolerance) &&
        result.rate <= expectedRate * (1.0 + tolerance),
        message: "Rate should be maximum multiplier at 100% utilization"
    )
}

// ========== Rate Bound Tests ==========

/// Test that rate never goes negative
access(all)
fun test_edge_case_rate_never_negative() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Try with extreme low utilization
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 0.0
    let veryLowRate: UFix128 = irm.MIN_RATE_AT_TARGET

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: veryLowRate,
        lastUpdate: 0
    )

    Test.assert(
        result.rate >= 0.0,
        message: "Rate should never be negative"
    )

    Test.assert(
        result.newRateAtTarget >= 0.0,
        message: "Rate at target should never be negative"
    )
}

/// Test that rate respects minimum bound under all conditions
access(all)
fun test_edge_case_min_rate_bound_enforced() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    // Sustained very low utilization for extended time
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 100.0
    let startRate: UFix128 = irm.MIN_RATE_AT_TARGET * 2.0
    let oneYear: UFix64 = 31536000

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: startRate,
        lastUpdate: currentTime - oneYear
    )

    // Should be bounded by MIN_RATE_AT_TARGET
    Test.assert(
        result.newRateAtTarget >= irm.MIN_RATE_AT_TARGET,
        message: "Rate at target should never go below MIN_RATE_AT_TARGET"
    )
}

/// Test that rate respects maximum bound under all conditions
access(all)
fun test_edge_case_max_rate_bound_enforced() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    // Sustained very high utilization for extended time
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 999.0
    let startRate: UFix128 = irm.MAX_RATE_AT_TARGET / 2.0
    let oneYear: UFix64 = 31536000

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: startRate,
        lastUpdate: currentTime - oneYear
    )

    // Should be bounded by MAX_RATE_AT_TARGET
    Test.assert(
        result.newRateAtTarget <= irm.MAX_RATE_AT_TARGET,
        message: "Rate at target should never exceed MAX_RATE_AT_TARGET"
    )
}

// ========== Error Clamping Tests ==========

/// Test error clamping for extreme low utilization
access(all)
fun test_edge_case_error_clamping_low() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // 0% utilization produces error = -9.0, should be clamped to -1.0
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 0.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.04,
        lastUpdate: 0
    )

    // With clamped error of -1.0, curve gives: (0.75 * -1.0 + 1) = 0.25
    let expectedRate = result.newRateAtTarget * 0.25

    Test.assert(
        result.rate >= expectedRate * (1.0 - tolerance) &&
        result.rate <= expectedRate * (1.0 + tolerance),
        message: "Error should be clamped to -1.0 for extreme low utilization"
    )
}

/// Test error clamping for extreme high utilization
access(all)
fun test_edge_case_error_clamping_high() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // 100% utilization produces error = 1.0 (already at max, no clamping needed)
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 1000.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.04,
        lastUpdate: 0
    )

    // With error of 1.0, curve gives: (3.0 * 1.0 + 1) = 4.0
    let expectedRate = result.newRateAtTarget * 4.0

    Test.assert(
        result.rate >= expectedRate * (1.0 - tolerance) &&
        result.rate <= expectedRate * (1.0 + tolerance),
        message: "Error of 1.0 should produce maximum curve multiplier"
    )
}

// ========== Precision Tests ==========

/// Test that calculations maintain precision with repeated updates
access(all)
fun test_edge_case_precision_stability() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 900.0  // At target
    let oneMinute: UFix64 = 60

    // Start with initial rate
    var currentRate: UFix128 = 0.04

    // Perform 10 updates with short time intervals
    var i = 0
    while i < 10 {
        let result = irm.calculateAdaptiveRate(
            creditBalance: creditBalance,
            debitBalance: debitBalance,
            currentRateAtTarget: currentRate,
            lastUpdate: currentTime - oneMinute
        )
        currentRate = result.newRateAtTarget
        i = i + 1
    }

    // At target utilization, rate should remain stable
    Test.assert(
        currentRate >= 0.04 * (1.0 - tolerance) &&
        currentRate <= 0.04 * (1.0 + tolerance),
        message: "Rate should remain stable with repeated updates at target utilization"
    )
}

// ========== Division by Zero Protection ==========

/// Test that division by zero is prevented in utilization calculation
access(all)
fun test_edge_case_no_division_by_zero() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Zero credit balance (handled by early return in TokenState)
    // But testing IRM directly
    let creditBalance: UFix128 = 0.00000001  // Minimal credit
    let debitBalance: UFix128 = 0.0

    // Should not panic with division by zero
    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    Test.assert(
        result.newRateAtTarget >= 0.0,
        message: "Should handle minimal credit balance without division errors"
    )
}
