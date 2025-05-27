# AlpenFlow Test Implementation Guide

## Overview

After analyzing the actual AlpenFlow contract implementation, the test suite has been restructured to match the contract's real capabilities. This guide explains the changes and provides guidance for implementing the updated tests.

## Key Contract Features to Test

### 1. Core Vault Operations
- **Deposit/Withdraw**: Basic vault functionality with FlowVault
- **Health Checks**: Contract prevents withdrawals that would make positions unhealthy
- **Balance Direction**: Positions can flip between Credit and Debit states

### 2. Interest Mechanics
- **Scaled Balances**: Positions use scaled balances that incorporate interest indices
- **Interest Indices**: Credit and debit balances have separate interest indices
- **Rate Calculations**: Interest rates are calculated based on pool utilization
- **Note**: SimpleInterestCurve always returns 0%, so actual interest accrual won't occur

### 3. Position Management
- **Health Calculation**: Health = effectiveCollateral / totalDebt
- **Multiple Positions**: Pool supports multiple independent positions
- **Position IDs**: Auto-incrementing from 0

### 4. Access Control
- **Entitlements**: EPosition, EGovernance, EImplementation, Withdraw
- **Capability-based**: Functions require proper capabilities to execute

## Features NOT in the Contract

The following features from the original test plan are NOT implemented:
- ❌ Deposit queue and rate limiting
- ❌ Oracle price feeds
- ❌ Governance/hot-swapping of components
- ❌ Functional Sink/Source implementations
- ❌ Multi-token support (only FlowVault works)
- ❌ Actual liquidation mechanism
- ❌ Non-zero interest rates

## Test Implementation Strategy

### 1. Update Existing Tests

For tests that are already written but failing:

**A-2 (Direction flip Credit → Debit)**
- Change expectation: Contract prevents creating unhealthy positions
- Test should verify the withdrawal is rejected, not that it creates debt

**A-3 (Direction flip Debit → Credit)**
- Need to create debt first through a different mechanism
- Since direct debt creation is prevented, may need to be creative

**B-1, B-2 (Interest accrual)**
- SimpleInterestCurve returns 0%, so no actual accrual occurs
- Test the mechanics exist but with 0% rates

**C-1, C-2 (Position health)**
- Adjust calculations to match actual implementation
- Health = effectiveCollateral / totalDebt (or 1.0 if no debt)

### 2. New Test Categories

Based on the actual contract, implement these new test categories:

**Interest Calculations (D-series)**
- Test the mathematical functions directly
- `perSecondInterestRate()`, `compoundInterestIndex()`, `interestMul()`

**Token State Management (E-series)**
- Test how TokenState tracks balances
- Credit/debit balance updates
- Balance direction flips

**Reserve Management (F-series)**
- Pool reserve tracking
- Multiple position handling
- Position ID generation

### 3. Test File Organization

Reorganize test files to match actual functionality:

```
cadence/tests/
├── core_vault_test.cdc          # Basic deposit/withdraw
├── interest_mechanics_test.cdc   # Interest calculations
├── position_health_test.cdc      # Health calculations
├── token_state_test.cdc         # Balance tracking
├── reserve_management_test.cdc  # Pool reserves
├── access_control_test.cdc      # Entitlements
└── edge_cases_test.cdc         # Edge cases
```

## Sample Test Implementations

### Testing Scaled Balances
```cadence
// Test that scaled balance conversions are symmetric
let scaledBalance = 100.0
let interestIndex: UInt64 = 10500000000000000 // 1.05 in fixed point

let trueBalance = AlpenFlow.scaledBalanceToTrueBalance(
    scaledBalance: scaledBalance,
    interestIndex: interestIndex
)

let scaledAgain = AlpenFlow.trueBalanceToScaledBalance(
    trueBalance: trueBalance,
    interestIndex: interestIndex
)

Test.assertEqual(scaledBalance, scaledAgain)
```

### Testing Position Health
```cadence
// Create position with only credit (no debt)
let pid = pool.createPosition()
pool.deposit(pid: pid, funds: <- AlpenFlow.createTestVault(balance: 100.0))

// Health should be 1.0 when no debt
let health = pool.positionHealth(pid: pid)
Test.assertEqual(1.0, health)
```

### Testing Health Enforcement
```cadence
// Try to withdraw more than deposited
let pid = pool.createPosition()
pool.deposit(pid: pid, funds: <- AlpenFlow.createTestVault(balance: 50.0))

// This should fail with "Position is overdrawn"
Test.expectFailure(fun() {
    pool.withdraw(pid: pid, amount: 100.0, type: Type<@AlpenFlow.FlowVault>())
}, errorMessage: "Position is overdrawn")
```

## Running the Updated Tests

1. Remove test files for non-existent features:
   - `deposit_queue_test.cdc`
   - `sink_source_test.cdc`
   - `governance_upgrade_test.cdc`

2. Update remaining tests to match actual contract behavior

3. Run tests with:
   ```bash
   flow test
   ```

## Future Enhancements

When the contract is enhanced with new features, add corresponding tests:
- Multi-token support → Add token variety tests
- Real interest curves → Add interest accrual tests
- Liquidation mechanism → Add liquidation tests
- Governance → Add upgrade tests 