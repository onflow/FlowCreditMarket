import Test
import "FlowCreditMarketMath"

/// Test suite for AdaptiveCurveIRM mathematical functions
/// Mirrors patterns from test/ExpLibTest.sol and test/UtilsLibTest.sol
///
/// Tests:
/// - wExp() exponential function with various inputs
/// - SignedUFix128 arithmetic operations
/// - bound() clamping function
///
access(all) let tolerance: UFix128 = 0.01  // 1% relative tolerance for Taylor series approximation

access(all)
fun setup() {
    let err = Test.deployContract(
        name: "FlowCreditMarketMath",
        path: "../lib/FlowCreditMarketMath.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

// ========== wExp() Exponential Function Tests ==========

/// Test wExp with zero input (e^0 = 1)
access(all)
fun test_wExp_zero() {
    let input = FlowCreditMarketMath.SignedUFix128(value: 0.0, isNegative: false)
    let result = FlowCreditMarketMath.wExp(input)

    Test.assertEqual(FlowCreditMarketMath.one, result)
}

/// Test wExp with small positive values
access(all)
fun test_wExp_small_positive() {
    // e^0.1 ≈ 1.105170918
    let input = FlowCreditMarketMath.SignedUFix128(value: 0.1, isNegative: false)
    let result = FlowCreditMarketMath.wExp(input)
    let expected: UFix128 = 1.105170918

    Test.assert(
        result >= expected * (1.0 - tolerance) && result <= expected * (1.0 + tolerance),
        message: "e^0.1 should be approximately 1.105, got ".concat(result.toString())
    )
}

/// Test wExp with positive value (e^0.5)
access(all)
fun test_wExp_half() {
    // e^0.5 ≈ 1.648721271
    let input = FlowCreditMarketMath.SignedUFix128(value: 0.5, isNegative: false)
    let result = FlowCreditMarketMath.wExp(input)
    let expected: UFix128 = 1.648721271

    Test.assert(
        result >= expected * (1.0 - tolerance) && result <= expected * (1.0 + tolerance),
        message: "e^0.5 should be approximately 1.649, got ".concat(result.toString())
    )
}

/// Test wExp with e^1
access(all)
fun test_wExp_one() {
    // e^1 ≈ 2.718281828
    let input = FlowCreditMarketMath.SignedUFix128(value: 1.0, isNegative: false)
    let result = FlowCreditMarketMath.wExp(input)
    let expected: UFix128 = 2.718281828

    Test.assert(
        result >= expected * (1.0 - tolerance) && result <= expected * (1.0 + tolerance),
        message: "e^1 should be approximately 2.718, got ".concat(result.toString())
    )
}

/// Test wExp with e^2
access(all)
fun test_wExp_two() {
    // e^2 ≈ 7.389056099
    let input = FlowCreditMarketMath.SignedUFix128(value: 2.0, isNegative: false)
    let result = FlowCreditMarketMath.wExp(input)
    let expected: UFix128 = 7.389056099

    Test.assert(
        result >= expected * (1.0 - tolerance) && result <= expected * (1.0 + tolerance),
        message: "e^2 should be approximately 7.389, got ".concat(result.toString())
    )
}

/// Test wExp with larger positive value (e^5)
access(all)
fun test_wExp_five() {
    // e^5 ≈ 148.413159103
    let input = FlowCreditMarketMath.SignedUFix128(value: 5.0, isNegative: false)
    let result = FlowCreditMarketMath.wExp(input)
    let expected: UFix128 = 148.413159103

    // Use slightly larger tolerance for larger values
    let largeTolerance: UFix128 = 0.001  // 0.1%
    Test.assert(
        result >= expected * (1.0 - largeTolerance) && result <= expected * (1.0 + largeTolerance),
        message: "e^5 should be approximately 148.413, got ".concat(result.toString())
    )
}

/// Test wExp with small negative value
access(all)
fun test_wExp_small_negative() {
    // e^(-0.1) ≈ 0.904837418
    let input = FlowCreditMarketMath.SignedUFix128(value: 0.1, isNegative: true)
    let result = FlowCreditMarketMath.wExp(input)
    let expected: UFix128 = 0.904837418

    Test.assert(
        result >= expected * (1.0 - tolerance) && result <= expected * (1.0 + tolerance),
        message: "e^(-0.1) should be approximately 0.905, got ".concat(result.toString())
    )
}

/// Test wExp with negative value (e^(-0.5))
access(all)
fun test_wExp_negative_half() {
    // e^(-0.5) ≈ 0.606530660
    let input = FlowCreditMarketMath.SignedUFix128(value: 0.5, isNegative: true)
    let result = FlowCreditMarketMath.wExp(input)
    let expected: UFix128 = 0.606530660

    Test.assert(
        result >= expected * (1.0 - tolerance) && result <= expected * (1.0 + tolerance),
        message: "e^(-0.5) should be approximately 0.607, got ".concat(result.toString())
    )
}

/// Test wExp with e^(-1)
access(all)
fun test_wExp_negative_one() {
    // e^(-1) ≈ 0.367879441
    let input = FlowCreditMarketMath.SignedUFix128(value: 1.0, isNegative: true)
    let result = FlowCreditMarketMath.wExp(input)
    let expected: UFix128 = 0.367879441

    Test.assert(
        result >= expected * (1.0 - tolerance) && result <= expected * (1.0 + tolerance),
        message: "e^(-1) should be approximately 0.368, got ".concat(result.toString())
    )
}

/// Test wExp with e^(-2)
access(all)
fun test_wExp_negative_two() {
    // e^(-2) ≈ 0.135335283
    let input = FlowCreditMarketMath.SignedUFix128(value: 2.0, isNegative: true)
    let result = FlowCreditMarketMath.wExp(input)
    let expected: UFix128 = 0.135335283

    Test.assert(
        result >= expected * (1.0 - tolerance) && result <= expected * (1.0 + tolerance),
        message: "e^(-2) should be approximately 0.135, got ".concat(result.toString())
    )
}

/// Test wExp with very small negative (near lower bound)
access(all)
fun test_wExp_too_small() {
    // Values below LN_MIN should return 0
    let input = FlowCreditMarketMath.SignedUFix128(
        value: FlowCreditMarketMath.LN_MIN + 1.0,
        isNegative: true
    )
    let result = FlowCreditMarketMath.wExp(input)

    Test.assertEqual(FlowCreditMarketMath.zero, result)
}

/// Test wExp with very large positive (at upper bound)
access(all)
fun test_wExp_too_large() {
    // Values at or above WEXP_UPPER_BOUND should return WEXP_UPPER_VALUE
    let input = FlowCreditMarketMath.SignedUFix128(
        value: FlowCreditMarketMath.WEXP_UPPER_BOUND,
        isNegative: false
    )
    let result = FlowCreditMarketMath.wExp(input)

    Test.assertEqual(FlowCreditMarketMath.WEXP_UPPER_VALUE, result)
}

/// Test wExp monotonicity for positive values
/// Property: e^x1 < e^x2 when x1 < x2 (for positive x)
access(all)
fun test_wExp_positive_monotonicity() {
    let x1 = FlowCreditMarketMath.SignedUFix128(value: 1.0, isNegative: false)
    let x2 = FlowCreditMarketMath.SignedUFix128(value: 2.0, isNegative: false)

    let result1 = FlowCreditMarketMath.wExp(x1)
    let result2 = FlowCreditMarketMath.wExp(x2)

    Test.assert(result2 > result1, message: "e^2 should be greater than e^1")
}

/// Test wExp monotonicity for negative values
/// Property: e^(-x1) > e^(-x2) when x1 < x2 (for positive x)
access(all)
fun test_wExp_negative_monotonicity() {
    let x1 = FlowCreditMarketMath.SignedUFix128(value: 1.0, isNegative: true)
    let x2 = FlowCreditMarketMath.SignedUFix128(value: 2.0, isNegative: true)

    let result1 = FlowCreditMarketMath.wExp(x1)
    let result2 = FlowCreditMarketMath.wExp(x2)

    Test.assert(result1 > result2, message: "e^(-1) should be greater than e^(-2)")
}

/// Test that all positive wExp results are >= 1.0
access(all)
fun test_wExp_positive_above_one() {
    let inputs: [UFix128] = [0.1, 0.5, 1.0, 2.0, 5.0]

    for value in inputs {
        let input = FlowCreditMarketMath.SignedUFix128(value: value, isNegative: false)
        let result = FlowCreditMarketMath.wExp(input)

        Test.assert(
            result >= FlowCreditMarketMath.one,
            message: "e^".concat(value.toString()).concat(" should be >= 1.0, got ").concat(result.toString())
        )
    }
}

/// Test that all negative wExp results are <= 1.0
access(all)
fun test_wExp_negative_below_one() {
    let inputs: [UFix128] = [0.1, 0.5, 1.0, 2.0, 5.0]

    for value in inputs {
        let input = FlowCreditMarketMath.SignedUFix128(value: value, isNegative: true)
        let result = FlowCreditMarketMath.wExp(input)

        Test.assert(
            result <= FlowCreditMarketMath.one,
            message: "e^(-".concat(value.toString()).concat(") should be <= 1.0, got ").concat(result.toString())
        )
    }
}

// ========== SignedUFix128 Arithmetic Tests ==========

/// Test signedMul with positive * positive
access(all)
fun test_signedMul_positive_positive() {
    let a = FlowCreditMarketMath.SignedUFix128(value: 2.0, isNegative: false)
    let b = FlowCreditMarketMath.SignedUFix128(value: 3.0, isNegative: false)

    let result = FlowCreditMarketMath.signedMul(a, b)

    Test.assertEqual(6.0 as UFix128, result.value)
    Test.assertEqual(false, result.isNegative)
}

/// Test signedMul with positive * negative
access(all)
fun test_signedMul_positive_negative() {
    let a = FlowCreditMarketMath.SignedUFix128(value: 2.0, isNegative: false)
    let b = FlowCreditMarketMath.SignedUFix128(value: 3.0, isNegative: true)

    let result = FlowCreditMarketMath.signedMul(a, b)

    Test.assertEqual(6.0 as UFix128, result.value)
    Test.assertEqual(true, result.isNegative)
}

/// Test signedMul with negative * positive
access(all)
fun test_signedMul_negative_positive() {
    let a = FlowCreditMarketMath.SignedUFix128(value: 2.0, isNegative: true)
    let b = FlowCreditMarketMath.SignedUFix128(value: 3.0, isNegative: false)

    let result = FlowCreditMarketMath.signedMul(a, b)

    Test.assertEqual(6.0 as UFix128, result.value)
    Test.assertEqual(true, result.isNegative)
}

/// Test signedMul with negative * negative
access(all)
fun test_signedMul_negative_negative() {
    let a = FlowCreditMarketMath.SignedUFix128(value: 2.0, isNegative: true)
    let b = FlowCreditMarketMath.SignedUFix128(value: 3.0, isNegative: true)

    let result = FlowCreditMarketMath.signedMul(a, b)

    Test.assertEqual(6.0 as UFix128, result.value)
    Test.assertEqual(false, result.isNegative)
}

/// Test signedDiv with positive / positive
access(all)
fun test_signedDiv_positive_positive() {
    let a = FlowCreditMarketMath.SignedUFix128(value: 6.0, isNegative: false)
    let b = FlowCreditMarketMath.SignedUFix128(value: 3.0, isNegative: false)

    let result = FlowCreditMarketMath.signedDiv(a, b)

    Test.assertEqual(2.0 as UFix128, result.value)
    Test.assertEqual(false, result.isNegative)
}

/// Test signedDiv with positive / negative
access(all)
fun test_signedDiv_positive_negative() {
    let a = FlowCreditMarketMath.SignedUFix128(value: 6.0, isNegative: false)
    let b = FlowCreditMarketMath.SignedUFix128(value: 3.0, isNegative: true)

    let result = FlowCreditMarketMath.signedDiv(a, b)

    Test.assertEqual(2.0 as UFix128, result.value)
    Test.assertEqual(true, result.isNegative)
}

/// Test signedDiv with negative / positive
access(all)
fun test_signedDiv_negative_positive() {
    let a = FlowCreditMarketMath.SignedUFix128(value: 6.0, isNegative: true)
    let b = FlowCreditMarketMath.SignedUFix128(value: 3.0, isNegative: false)

    let result = FlowCreditMarketMath.signedDiv(a, b)

    Test.assertEqual(2.0 as UFix128, result.value)
    Test.assertEqual(true, result.isNegative)
}

/// Test signedDiv with negative / negative
access(all)
fun test_signedDiv_negative_negative() {
    let a = FlowCreditMarketMath.SignedUFix128(value: 6.0, isNegative: true)
    let b = FlowCreditMarketMath.SignedUFix128(value: 3.0, isNegative: true)

    let result = FlowCreditMarketMath.signedDiv(a, b)

    Test.assertEqual(2.0 as UFix128, result.value)
    Test.assertEqual(false, result.isNegative)
}

// ========== bound() Function Tests ==========

/// Test bound with value within range
access(all)
fun test_bound_within_range() {
    let value: UFix128 = 5.0
    let min: UFix128 = 1.0
    let max: UFix128 = 10.0

    let result = FlowCreditMarketMath.bound(value, min, max)

    Test.assertEqual(5.0 as UFix128, result)
}

/// Test bound with value below minimum
access(all)
fun test_bound_below_minimum() {
    let value: UFix128 = 0.5
    let min: UFix128 = 1.0
    let max: UFix128 = 10.0

    let result = FlowCreditMarketMath.bound(value, min, max)

    Test.assertEqual(1.0 as UFix128, result)
}

/// Test bound with value above maximum
access(all)
fun test_bound_above_maximum() {
    let value: UFix128 = 15.0
    let min: UFix128 = 1.0
    let max: UFix128 = 10.0

    let result = FlowCreditMarketMath.bound(value, min, max)

    Test.assertEqual(10.0 as UFix128, result)
}

/// Test bound with value equal to minimum
access(all)
fun test_bound_equal_to_minimum() {
    let value: UFix128 = 1.0
    let min: UFix128 = 1.0
    let max: UFix128 = 10.0

    let result = FlowCreditMarketMath.bound(value, min, max)

    Test.assertEqual(1.0 as UFix128, result)
}

/// Test bound with value equal to maximum
access(all)
fun test_bound_equal_to_maximum() {
    let value: UFix128 = 10.0
    let min: UFix128 = 1.0
    let max: UFix128 = 10.0

    let result = FlowCreditMarketMath.bound(value, min, max)

    Test.assertEqual(10.0 as UFix128, result)
}

/// Test bound with min = max
access(all)
fun test_bound_min_equals_max() {
    let value: UFix128 = 5.0
    let min: UFix128 = 3.0
    let max: UFix128 = 3.0

    let result = FlowCreditMarketMath.bound(value, min, max)

    Test.assertEqual(3.0 as UFix128, result)
}
