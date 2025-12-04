# AdaptiveCurveIRM Implementation for FlowCreditMarket

This document describes the implementation of the AdaptiveCurveIRM (Interest Rate Model) for non-MOET assets in FlowCreditMarket, ported from Morpho Blue's battle-tested implementation.

## Overview

The AdaptiveCurveIRM is a dynamic interest rate model that automatically adjusts borrowing rates based on market utilization, ensuring efficient capital allocation and stable lending rates.

### Key Features

- **Target-driven**: Automatically adjusts rates to maintain ~90% utilization
- **Smooth adaptation**: Uses exponential rate adjustments with trapezoidal averaging
- **Bounded rates**: Safely constrained between 0.1% and 200% APR at target
- **Battle-tested**: Based on Morpho Blue's proven implementation

## Implementation Details

### Architecture

The implementation consists of three main components:

#### 1. Mathematical Libraries (`FlowCreditMarketMath.cdc`)

**Added functionality:**
- `SignedUFix128`: Struct to handle signed fixed-point numbers (since UFix128 is unsigned)
- `wExp()`: Exponential function using 2nd-order Taylor series approximation
- `bound()`: Bounds values between min and max
- `signedMul()` / `signedDiv()`: Arithmetic operations for signed values

**Key constants:**
- `LN_2`: Natural logarithm of 2 (0.693147...)
- `LN_MIN`: Lower bound for exponential calculations
- `WEXP_UPPER_BOUND`: Upper bound to prevent overflow

#### 2. AdaptiveCurveIRM Struct (`FlowCreditMarket.cdc`)

**Parameters:**
```cadence
TARGET_UTILIZATION: 0.9      // 90% target utilization
CURVE_STEEPNESS: 4.0         // 4x steepness
ADJUSTMENT_SPEED: 50/year    // Rate adaptation speed
INITIAL_RATE_AT_TARGET: 0.04 // 4% APR initial rate
MIN_RATE_AT_TARGET: 0.001    // 0.1% APR minimum
MAX_RATE_AT_TARGET: 2.0      // 200% APR maximum
```

**Core methods:**
- `calculateAdaptiveRate()`: Calculates rate with state management
- `curve()`: Applies piecewise linear curve function
- `newRateAtTarget()`: Calculates rate adaptation using exponential growth/decay

#### 3. TokenState Integration

**New fields:**
- `adaptiveRateAtTarget`: Stores the current rate at target utilization
- `adaptiveLastUpdate`: Timestamp of last adaptive rate update

**Modified methods:**
- `updateInterestRates()`: Detects AdaptiveCurveIRM and handles state updates

### Rate Calculation Formula

The adaptive rate calculation follows these steps:

1. **Calculate utilization:**
   ```
   utilization = totalDebitBalance / totalCreditBalance
   ```

2. **Calculate normalized error:**
   ```
   error = (utilization - targetUtilization) / normalizationFactor
   ```

3. **Calculate adaptation speed:**
   ```
   speed = ADJUSTMENT_SPEED * error
   linearAdaptation = speed * elapsedTime
   ```

4. **Update rate at target:**
   ```
   newRateAtTarget = bound(
       startRateAtTarget * exp(linearAdaptation),
       MIN_RATE_AT_TARGET,
       MAX_RATE_AT_TARGET
   )
   ```

5. **Apply curve function:**
   ```
   if error < 0:
       rate = ((1 - 1/CURVE_STEEPNESS) * error + 1) * rateAtTarget
   else:
       rate = ((CURVE_STEEPNESS - 1) * error + 1) * rateAtTarget
   ```

6. **Use trapezoidal averaging:**
   ```
   avgRate = (startRate + endRate + 2 * midRate) / 4
   ```

### Key Differences from Solidity Implementation

1. **Signed arithmetic**: Cadence doesn't have signed fixed-point types, so we use `SignedUFix128` struct
2. **State storage**: State is stored in `TokenState` rather than in the curve struct (Cadence structs are value types)
3. **Type checking**: Uses `getType()` to detect AdaptiveCurveIRM at runtime
4. **No immutable deployment**: Constants are stored per-curve instance (can be modified for different tokens if needed)

## Usage

### Adding a Token with AdaptiveCurveIRM

Use the governance transaction:

```bash
flow transactions send \
  ./cadence/transactions/flow-credit-market/pool-governance/add_supported_token_adaptive_curve_irm.cdc \
  --arg String:"A.xxx.TokenContract.Vault" \  # Token type identifier
  --arg UFix64:0.8 \                          # Collateral factor (80%)
  --arg UFix64:1.0 \                          # Borrow factor (100%)
  --arg UFix64:100.0 \                        # Deposit rate
  --arg UFix64:1000000.0                      # Deposit capacity cap
```

### Programmatic Creation

```cadence
import FlowCreditMarket from 0x...

// In your contract or transaction
let adaptiveIRM = FlowCreditMarket.AdaptiveCurveIRM()

pool.addSupportedToken(
    tokenType: Type<@YourToken.Vault>(),
    collateralFactor: 0.8,
    borrowFactor: 1.0,
    interestCurve: adaptiveIRM,
    depositRate: 100.0,
    depositCapacityCap: 1000000.0
)
```

### Rate Behavior Examples

**Scenario 1: Below target utilization (e.g., 70%)**
- Error is negative
- `rateAtTarget` decreases exponentially over time
- Actual rate is below `rateAtTarget` due to curve function
- Incentivizes more borrowing

**Scenario 2: Above target utilization (e.g., 95%)**
- Error is positive
- `rateAtTarget` increases exponentially over time
- Actual rate is above `rateAtTarget` due to curve steepness
- Incentivizes more lending and repayment

**Scenario 3: At target utilization (90%)**
- Error is zero
- `rateAtTarget` stays constant
- Rate equals `rateAtTarget`
- System is in equilibrium

## Testing

The implementation can be tested with the existing FlowCreditMarket test suite:

```bash
# Run all tests
./run_tests.sh

# Run specific interest rate tests
flow test --filter "interest"
```

### Manual Testing Steps

1. Create a pool with AdaptiveCurveIRM token
2. Deposit collateral
3. Borrow up to different utilization levels
4. Observe rate changes over time
5. Verify rates converge toward target utilization

## Security Considerations

1. **Overflow protection**: wExp function has upper bounds to prevent overflow
2. **Underflow protection**: Rates are bounded to prevent negative values
3. **Time manipulation resistance**: Uses block timestamp (not manipulable on Flow)
4. **Rate caps**: MIN and MAX rate bounds prevent extreme values
5. **Gradual adaptation**: 50/year speed prevents sudden rate shocks

## Performance

- **Gas efficiency**: Similar to SimpleInterestCurve with additional calculation overhead
- **State updates**: Only updates adaptive state when rates are recalculated
- **Calculation complexity**: O(1) with fixed number of exponential operations

## Comparison with SimpleInterestCurve

| Feature | SimpleInterestCurve | AdaptiveCurveIRM |
|---------|-------------------|------------------|
| Rate adjustment | Manual/fixed | Automatic/dynamic |
| Utilization targeting | No | Yes (90%) |
| Parameter tuning | Required | Self-optimizing |
| Best for | MOET / stable assets | Non-MOET / volatile assets |
| Complexity | Simple | Moderate |
| Gas cost | Lower | Slightly higher |

## Future Enhancements

Potential improvements for future versions:

1. **Configurable parameters**: Allow different targets/speeds per token
2. **Rate history**: Store historical rates for analytics
3. **Circuit breakers**: Additional safety mechanisms for extreme conditions
4. **Multi-target curves**: Support for multiple utilization targets
5. **Off-chain rate preview**: Helper scripts to estimate future rates

## References

- [Morpho Blue AdaptiveCurveIRM](https://github.com/morpho-org/morpho-blue-irm)
- [Morpho Blue Documentation](https://docs.morpho.org/)
- [Interest Rate Model Theory](https://docs.aave.com/risk/liquidity-risk/borrow-interest-rate)

## Support

For questions or issues:
- GitHub: [Flow Credit Market Issues](https://github.com/...)
- Documentation: See FlowCreditMarket README
- Contact: [Add contact information]
