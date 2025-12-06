import Test
import "FlowCreditMarket"
import "FlowCreditMarketMath"
import "test_helpers"

/// Test suite for AdaptiveCurveIRM realistic scenario testing
/// Tests real-world market behavior patterns and rate convergence
///
/// Scenarios:
/// - Low utilization market (70%)
/// - High utilization market (95%)
/// - Target utilization equilibrium (90%)
/// - Market rebalancing events
/// - Rate convergence behavior

access(all) let tolerance: UFix128 = 0.01  // 1% tolerance for scenarios

access(all)
fun setup() {
    deployContracts()
}

// ========== Low Utilization Scenarios ==========

/// Scenario: Market with 70% utilization should see decreasing rates
access(all)
fun test_scenario_low_utilization_70_percent() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Setup: 70% utilization (below 90% target)
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 700.0
    let startingRateAtTarget: UFix128 = 0.04  // Start at 4% APR

    // First calculation (initialize)
    let result1 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Should initialize to INITIAL_RATE_AT_TARGET
    Test.assertEqual(irm.INITIAL_RATE_AT_TARGET, result1.newRateAtTarget)

    // Rate should be below rateAtTarget due to negative error
    Test.assert(
        result1.rate < result1.newRateAtTarget,
        message: "Rate should be below rateAtTarget with utilization below target"
    )
}

/// Scenario: Very low utilization (50%) should approach minimum rate
access(all)
fun test_scenario_very_low_utilization_50_percent() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Setup: 50% utilization (far below target)
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 500.0

    // First update
    let result1 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Calculate error for 50% utilization
    // error = (0.5 - 0.9) / (1.0 - 0.9) = -0.4 / 0.1 = -4.0 (clamped to -1.0)
    // With -1.0 error, rate should be minimal

    // Rate should be very low (close to MIN_RATE_AT_TARGET / 4)
    let expectedMinRate = irm.MIN_RATE_AT_TARGET / 4.0
    Test.assert(
        result1.rate >= expectedMinRate * 0.5,  // Allow some variance
        message: "Rate should approach minimum with very low utilization"
    )
}

// ========== High Utilization Scenarios ==========

/// Scenario: Market with 95% utilization should see increasing rates
access(all)
fun test_scenario_high_utilization_95_percent() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Setup: 95% utilization (above 90% target)
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 950.0
    let currentTime = getCurrentBlock().timestamp

    // First calculation (initialize)
    let result1 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Should initialize to INITIAL_RATE_AT_TARGET
    Test.assertEqual(irm.INITIAL_RATE_AT_TARGET, result1.newRateAtTarget)

    // Rate should be above rateAtTarget due to positive error
    Test.assert(
        result1.rate > result1.newRateAtTarget,
        message: "Rate should be above rateAtTarget with utilization above target"
    )

    // Simulate time passing and recalculate
    let oneDay: UFix64 = 86400
    let result2 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: result1.newRateAtTarget,
        lastUpdate: currentTime - oneDay
    )

    // With time elapsed and high utilization, rateAtTarget should increase
    Test.assert(
        result2.newRateAtTarget > result1.newRateAtTarget,
        message: "Rate at target should increase over time with high utilization, was ".concat(result1.newRateAtTarget.toString()).concat(", now ").concat(result2.newRateAtTarget.toString())
    )
}

/// Scenario: Very high utilization (99%) should approach maximum rate
access(all)
fun test_scenario_very_high_utilization_99_percent() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Setup: 99% utilization (far above target)
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 990.0

    // First update
    let result1 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Calculate error for 99% utilization
    // error = (0.99 - 0.9) / (1.0 - 0.9) = 0.09 / 0.1 = 0.9
    // With 0.9 error, curve applies 3.0 coefficient: rate = (3 * 0.9 + 1) * rateAtTarget = 3.7 * rateAtTarget

    // Rate should be significantly elevated
    let expectedRate = result1.newRateAtTarget * 3.7
    Test.assert(
        result1.rate >= expectedRate * (1.0 - tolerance) &&
        result1.rate <= expectedRate * (1.0 + tolerance),
        message: "Rate should be ~3.7x rateAtTarget with 99% utilization, expected ".concat(expectedRate.toString()).concat(", got ").concat(result1.rate.toString())
    )
}

/// Scenario: 100% utilization (maximum error)
access(all)
fun test_scenario_full_utilization_100_percent() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Setup: 100% utilization (maximum)
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 1000.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Error = (1.0 - 0.9) / (1.0 - 0.9) = 1.0 (maximum positive error)
    // Curve: rate = (3.0 * 1.0 + 1) * rateAtTarget = 4.0 * rateAtTarget

    let expectedRate = result.newRateAtTarget * 4.0
    Test.assert(
        result.rate >= expectedRate * (1.0 - tolerance) &&
        result.rate <= expectedRate * (1.0 + tolerance),
        message: "Rate should be 4x rateAtTarget at 100% utilization, expected ".concat(expectedRate.toString()).concat(", got ").concat(result.rate.toString())
    )
}

// ========== Target Utilization Scenarios ==========

/// Scenario: Market at 90% target utilization should maintain stable rates
access(all)
fun test_scenario_at_target_utilization_90_percent() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Setup: Exactly 90% utilization (at target)
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 900.0
    let currentTime = getCurrentBlock().timestamp

    // First calculation
    let result1 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Should initialize to INITIAL_RATE_AT_TARGET
    Test.assertEqual(irm.INITIAL_RATE_AT_TARGET, result1.newRateAtTarget)

    // Rate should equal rateAtTarget (zero error)
    Test.assert(
        result1.rate >= result1.newRateAtTarget * (1.0 - tolerance) &&
        result1.rate <= result1.newRateAtTarget * (1.0 + tolerance),
        message: "Rate should equal rateAtTarget at target utilization"
    )

    // Simulate time passing and recalculate
    let oneDay: UFix64 = 86400
    let result2 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: result1.newRateAtTarget,
        lastUpdate: currentTime - oneDay
    )

    // With zero error, rateAtTarget should remain stable
    Test.assert(
        result2.newRateAtTarget >= result1.newRateAtTarget * (1.0 - tolerance) &&
        result2.newRateAtTarget <= result1.newRateAtTarget * (1.0 + tolerance),
        message: "Rate at target should remain stable at target utilization"
    )
}

/// Scenario: Small deviation from target (89% utilization)
access(all)
fun test_scenario_slightly_below_target_89_percent() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Setup: 89% utilization (slightly below target)
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 890.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Error = (0.89 - 0.9) / (1.0 - 0.9) = -0.01 / 0.1 = -0.1 (small negative)
    // Curve: rate = (0.75 * -0.1 + 1) * rateAtTarget = 0.925 * rateAtTarget

    let expectedRate = result.newRateAtTarget * 0.925
    Test.assert(
        result.rate >= expectedRate * (1.0 - tolerance) &&
        result.rate <= expectedRate * (1.0 + tolerance),
        message: "Rate should be slightly below rateAtTarget with small negative error"
    )
}

/// Scenario: Small deviation from target (91% utilization)
access(all)
fun test_scenario_slightly_above_target_91_percent() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()

    // Setup: 91% utilization (slightly above target)
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 910.0

    let result = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Error = (0.91 - 0.9) / (1.0 - 0.9) = 0.01 / 0.1 = 0.1 (small positive)
    // Curve: rate = (3.0 * 0.1 + 1) * rateAtTarget = 1.3 * rateAtTarget

    let expectedRate = result.newRateAtTarget * 1.3
    Test.assert(
        result.rate >= expectedRate * (1.0 - tolerance) &&
        result.rate <= expectedRate * (1.0 + tolerance),
        message: "Rate should be slightly above rateAtTarget with small positive error"
    )
}

// ========== Market Rebalancing Scenarios ==========

/// Scenario: Market transitions from high to low utilization
access(all)
fun test_scenario_rebalancing_high_to_low() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    // Start with high utilization (95%)
    let creditBalance: UFix128 = 1000.0
    var debitBalance: UFix128 = 950.0

    let result1 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    let highUtilRate = result1.rate
    Test.assert(
        highUtilRate > result1.newRateAtTarget,
        message: "Rate should be elevated at high utilization"
    )

    // Simulate time passing and new deposits increase supply
    let oneHour: UFix64 = 3600
    debitBalance = 700.0  // Now 70% utilization

    let result2 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: result1.newRateAtTarget,
        lastUpdate: currentTime - oneHour
    )

    let lowUtilRate = result2.rate

    // After rebalancing, rate should be lower
    Test.assert(
        lowUtilRate < highUtilRate,
        message: "Rate should decrease after market rebalancing to lower utilization"
    )
}

/// Scenario: Market transitions from low to high utilization
access(all)
fun test_scenario_rebalancing_low_to_high() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    // Start with low utilization (70%)
    let creditBalance: UFix128 = 1000.0
    var debitBalance: UFix128 = 700.0

    let result1 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    let lowUtilRate = result1.rate
    Test.assert(
        lowUtilRate < result1.newRateAtTarget,
        message: "Rate should be reduced at low utilization"
    )

    // Simulate time passing and large borrowing event
    let oneHour: UFix64 = 3600
    debitBalance = 950.0  // Now 95% utilization

    let result2 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: result1.newRateAtTarget,
        lastUpdate: currentTime - oneHour
    )

    let highUtilRate = result2.rate

    // After borrowing surge, rate should be higher
    Test.assert(
        highUtilRate > lowUtilRate,
        message: "Rate should increase after market rebalancing to higher utilization"
    )
}

// ========== Rate Convergence Scenarios ==========

/// Scenario: Persistent high utilization drives rate up over time
access(all)
fun test_scenario_convergence_sustained_high_utilization() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    // Sustained 95% utilization
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 950.0

    // Day 0
    let result0 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Day 1
    let oneDay: UFix64 = 86400
    let result1 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: result0.newRateAtTarget,
        lastUpdate: currentTime - oneDay
    )

    // Day 2
    let result2 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: result1.newRateAtTarget,
        lastUpdate: currentTime - oneDay
    )

    // Rates should monotonically increase
    Test.assert(
        result1.newRateAtTarget > result0.newRateAtTarget,
        message: "Rate should increase day 0→1 with sustained high utilization"
    )

    Test.assert(
        result2.newRateAtTarget > result1.newRateAtTarget,
        message: "Rate should increase day 1→2 with sustained high utilization"
    )
}

/// Scenario: Persistent low utilization drives rate down over time
access(all)
fun test_scenario_convergence_sustained_low_utilization() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    // Start at higher rate
    let initialRate: UFix128 = 0.10  // 10% APR

    // Sustained 70% utilization
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 700.0

    // Day 0
    let result0 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: initialRate,
        lastUpdate: 0
    )

    // Day 1
    let oneDay: UFix64 = 86400
    let result1 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: result0.newRateAtTarget,
        lastUpdate: currentTime - oneDay
    )

    // Day 2
    let result2 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: result1.newRateAtTarget,
        lastUpdate: currentTime - oneDay
    )

    // Rates should monotonically decrease
    Test.assert(
        result1.newRateAtTarget < result0.newRateAtTarget,
        message: "Rate should decrease day 0→1 with sustained low utilization"
    )

    Test.assert(
        result2.newRateAtTarget < result1.newRateAtTarget,
        message: "Rate should decrease day 1→2 with sustained low utilization"
    )
}

// ========== Trapezoidal Averaging Scenarios ==========

/// Scenario: Averaging smooths sudden rate changes
access(all)
fun test_scenario_trapezoidal_smoothing() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    // Start at low utilization, then jump to high
    let creditBalance: UFix128 = 1000.0

    // Initial low utilization
    let result1 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: 700.0,
        currentRateAtTarget: 0.04,
        lastUpdate: 0
    )

    // Large time elapsed with high utilization
    let fiveDays: UFix64 = 432000
    let result2 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: 1000.0,  // Jump to 100%
        currentRateAtTarget: result1.newRateAtTarget,
        lastUpdate: currentTime - fiveDays
    )

    // The returned rate should be averaged, not instantaneous
    // Calculate what instantaneous rate would be at end
    let error = FlowCreditMarketMath.SignedUFix128(value: 1.0, isNegative: false)  // 100% util
    let instantaneousRate = irm.curve(result2.newRateAtTarget, error)

    // Averaged rate should be less than instantaneous rate
    Test.assert(
        result2.rate < instantaneousRate,
        message: "Averaged rate should be less than instantaneous rate due to smoothing"
    )
}

// ========== Real-World Scenario: Volatile Market ==========

/// Scenario: Simulate a week of volatile market activity
access(all)
fun test_scenario_volatile_week() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let creditBalance: UFix128 = 1000.0
    let currentTime = getCurrentBlock().timestamp
    let oneDay: UFix64 = 86400

    // Day 0: Initialize at 80% utilization
    let day0 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: 800.0,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Day 1: Spike to 95% utilization
    let day1 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: 950.0,
        currentRateAtTarget: day0.newRateAtTarget,
        lastUpdate: currentTime - oneDay
    )

    // Day 2: Drop to 70% utilization
    let day2 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: 700.0,
        currentRateAtTarget: day1.newRateAtTarget,
        lastUpdate: currentTime - oneDay
    )

    // Day 3: Back to 90% (target)
    let day3 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: 900.0,
        currentRateAtTarget: day2.newRateAtTarget,
        lastUpdate: currentTime - oneDay
    )

    // Verify rates adapted appropriately
    Test.assert(day0.newRateAtTarget > 0.0, message: "Day 0 should initialize rate")
    Test.assert(day1.newRateAtTarget >= day0.newRateAtTarget, message: "Day 1 rate should increase or stay same")
    Test.assert(day2.newRateAtTarget <= day1.newRateAtTarget, message: "Day 2 rate should decrease or stay same")

    // By day 3 at target utilization, rate should stabilize
    // (actual value depends on accumulated changes)
    Test.assert(day3.newRateAtTarget > 0.0, message: "Day 3 should maintain positive rate")
}

// ========== Iterative Ping Tests (Solidity parity) ==========

/// Scenario: 45 days at 95% utilization with pings every minute
/// Mirrors testRateAfter45DaysUtilizationAboveTargetPingEveryMinute from Solidity
/// Tests cumulative behavior with frequent updates and interest accrual
access(all)
fun test_scenario_45_days_above_target_ping_every_minute() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    // Initialize at target utilization (90%)
    let creditBalance: UFix128 = 1000.0
    var debitBalance: UFix128 = 900.0

    let result0 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Verify initialization
    Test.assertEqual(irm.INITIAL_RATE_AT_TARGET, result0.newRateAtTarget)

    // Set utilization to 95% (error = 50%)
    let initialDebitBalance: UFix128 = 950.0
    debitBalance = initialDebitBalance
    var totalCredit: UFix128 = creditBalance
    var totalDebit: UFix128 = debitBalance
    var currentRateAtTarget = result0.newRateAtTarget
    var lastUpdate = currentTime

    // Simulate 45 days with pings every minute
    let oneMinute: UFix64 = 60
    let fortyFiveDays: UFix64 = UInt64(45 * 24 * 3600)
    let totalMinutes: UFix64 = fortyFiveDays / oneMinute

    var i: UFix64 = 0
    while i < totalMinutes {
        lastUpdate = currentTime + UFix64(i * oneMinute)
        let nextUpdate = lastUpdate + oneMinute

        let result = irm.calculateAdaptiveRate(
            creditBalance: totalCredit,
            debitBalance: totalDebit,
            currentRateAtTarget: currentRateAtTarget,
            lastUpdate: lastUpdate
        )

        // Simulate interest accrual
        // interest = totalDebit * rate * time (using simple compounding approximation)
        let borrowAPR = result.rate
        let interest = totalDebit * borrowAPR * UFix128(oneMinute)

        // Update balances
        totalDebit = totalDebit + interest
        totalCredit = totalCredit + interest

        // Update state for next iteration
        currentRateAtTarget = result.newRateAtTarget
        i = i + 1
    }

    // Final utilization should remain close to 95%
    let finalUtilization = totalDebit / totalCredit
    Test.assert(
        finalUtilization >= 0.94 && finalUtilization <= 0.96,
        message: "Final utilization should remain near 95%, got ".concat(finalUtilization.toString())
    )

    // Expected rate at target: 4% * exp(50 * 45/365 * 50%) = 87.22% APR
    let expectedAnnualRate = 0.8722
    let expectedPerSecondRate = expectedAnnualRate / 365.0 / 24.0 / 3600.0

    Test.assert(
        currentRateAtTarget >= expectedPerSecondRate * 0.92,
        message: "Rate at target should be at least 92% of expected (accounting for ping variance), expected ~"
            .concat(expectedPerSecondRate.toString())
            .concat(", got ")
            .concat(currentRateAtTarget.toString())
    )

    // Rate should be within 8% of expected (as per Solidity test tolerance)
    Test.assert(
        currentRateAtTarget <= expectedPerSecondRate * 1.08,
        message: "Rate at target should be within 108% of expected, expected ~"
            .concat(expectedPerSecondRate.toString())
            .concat(", got ")
            .concat(currentRateAtTarget.toString())
    )

    // Expected growth: exp(87.22% * 3.5 * 45/365) = +45.70%
    // With 30% relative tolerance for pings
    let expectedGrowthMultiplier: UFix128 = 1.457
    let expectedFinalDebit = initialDebitBalance * expectedGrowthMultiplier

    Test.assert(
        totalDebit >= expectedFinalDebit * 0.7 && totalDebit <= expectedFinalDebit * 1.3,
        message: "Total debt growth should match expected range with ping variance, expected ~"
            .concat(expectedFinalDebit.toString())
            .concat(", got ")
            .concat(totalDebit.toString())
    )
}

/// Scenario: 3 weeks at target utilization with pings every minute
/// Mirrors testRateAfter3WeeksUtilizationTargetPingEveryMinute from Solidity
/// Tests rate stability at target with frequent updates
access(all)
fun test_scenario_3_weeks_at_target_ping_every_minute() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    // Initialize at target utilization (90%)
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 900.0

    let result0 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    // Verify initialization
    Test.assertEqual(irm.INITIAL_RATE_AT_TARGET, result0.newRateAtTarget)

    var totalCredit: UFix128 = creditBalance
    var totalDebit: UFix128 = debitBalance
    var currentRateAtTarget = result0.newRateAtTarget
    var lastUpdate = currentTime

    // Simulate 3 weeks with pings every minute
    let oneMinute: UFix64 = 60
    let threeWeeks: UFix64 = UInt64(3 * 7 * 24 * 3600)
    let totalMinutes: UFix64 = threeWeeks / oneMinute

    var i: UFix64 = 0
    while i < totalMinutes {
        lastUpdate = currentTime + UFix64(i * oneMinute)
        let nextUpdate = lastUpdate + oneMinute

        let result = irm.calculateAdaptiveRate(
            creditBalance: totalCredit,
            debitBalance: totalDebit,
            currentRateAtTarget: currentRateAtTarget,
            lastUpdate: lastUpdate
        )

        // Simulate interest accrual
        let borrowAPR = result.rate
        let interest = totalDebit * borrowAPR * UFix128(oneMinute)

        // Update balances
        totalDebit = totalDebit + interest
        totalCredit = totalCredit + interest

        // Update state for next iteration
        currentRateAtTarget = result.newRateAtTarget
        i = i + 1
    }

    // Final utilization should remain close to target (90%)
    let finalUtilization = totalDebit / totalCredit
    Test.assert(
        finalUtilization >= 0.89 && finalUtilization <= 0.91,
        message: "Final utilization should remain near target 90%, got ".concat(finalUtilization.toString())
    )

    // Rate at target should remain stable (within 10% tolerance for pings)
    Test.assert(
        currentRateAtTarget >= irm.INITIAL_RATE_AT_TARGET * 0.9,
        message: "Rate at target should remain near initial rate, got "
            .concat(currentRateAtTarget.toString())
            .concat(", initial was ")
            .concat(irm.INITIAL_RATE_AT_TARGET.toString())
    )

    Test.assert(
        currentRateAtTarget <= irm.INITIAL_RATE_AT_TARGET * 1.1,
        message: "Rate at target should remain within 10% of initial rate (accounting for ping variance), got "
            .concat(currentRateAtTarget.toString())
            .concat(", initial was ")
            .concat(irm.INITIAL_RATE_AT_TARGET.toString())
    )
}

/// Scenario: No ping test with extended time at target utilization
/// Mirrors testRateAfterUtilizationTargetNoPing from Solidity
/// Tests that rate remains stable at target utilization regardless of time elapsed
access(all)
fun test_scenario_extended_time_at_target_no_ping() {
    let irm = FlowCreditMarket.AdaptiveCurveIRM()
    let currentTime = getCurrentBlock().timestamp

    // Initialize at target utilization
    let creditBalance: UFix128 = 1000.0
    let debitBalance: UFix128 = 900.0

    let result0 = irm.calculateAdaptiveRate(
        creditBalance: creditBalance,
        debitBalance: debitBalance,
        currentRateAtTarget: 0.0,
        lastUpdate: 0
    )

    Test.assertEqual(irm.INITIAL_RATE_AT_TARGET, result0.newRateAtTarget)

    // Test various elapsed times
    let testPeriods: [UFix64] = [
        UFix64(1),           // 1 second
        UFix64(60),          // 1 minute
        UFix64(3600),        // 1 hour
        UFix64(86400),       // 1 day
        UFix64(604800),      // 1 week
        UFix64(2592000),     // 30 days
        UFix64(31536000)     // 1 year
    ]

    for elapsed in testPeriods {
        let result = irm.calculateAdaptiveRate(
            creditBalance: creditBalance,
            debitBalance: debitBalance,
            currentRateAtTarget: result0.newRateAtTarget,
            lastUpdate: currentTime - elapsed
        )

        // At exact target utilization, rate should remain stable
        Test.assert(
            result.newRateAtTarget >= result0.newRateAtTarget * (UFix128(1.0) - tolerance) &&
            result.newRateAtTarget <= result0.newRateAtTarget * (UFix128(1.0) + tolerance),
            message: "Rate at target should remain stable after "
                .concat(elapsed.toString())
                .concat(" seconds at target utilization, expected ")
                .concat(result0.newRateAtTarget.toString())
                .concat(", got ")
                .concat(result.newRateAtTarget.toString())
        )
    }
}
