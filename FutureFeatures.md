# AlpenFlow Future Features and Tests

This document lists features that are not yet implemented in the AlpenFlow contract but may be added in the future, along with the tests that would need to be implemented when these features are added.

## 1. Deposit Queue with Rate Limiting

### Features to Implement:
- Rate-limited deposit queue mechanism
- TPS (Tokens Per Second) throttling
- Queue processing scheduler
- Queue-first withdrawal logic

### Tests to Add (D-series from original plan):
```
D-1: Throttle applies
- Set TPS = 10 FLOW/s
- After 1 second, deposit 100 FLOW
- Verify only ~10 FLOW lands in position, 90 queued

D-2: Scheduler clears queue
- Advance 9 seconds
- Call processQueue()
- Verify remaining 90 FLOW credited, queue empty

D-3: Queue-first withdrawal
- 50 FLOW queued + 10 FLOW in main position
- Withdraw 30 FLOW
- Verify 30 taken from queue, 20 left in queue
```

## 2. Functional Sink/Source Hooks

### Features to Implement:
- Real Sink implementation (not dummy)
- Real Source implementation (not dummy)
- Automatic rebalancing based on position health
- Sink capacity limits
- Source availability checks

### Tests to Add (E-series from original plan):
```
E-1: Push to sink on surplus
- Provide StakeSink
- When health = 2.0, excess pushed to sink
- Verify reserves decrease

E-2: Pull from source on shortfall
- Provide DummySource with 10 FLOW
- Slash price so HF < 1
- Call rebalance()
- Verify source supplies FLOW, health >= 1

E-3: Sink cap honoured
- Set minimumCapacity = 5
- Try to push 8
- Verify only 5 accepted, 3 remain in pool
```

## 3. Governance and Upgradability

### Features to Implement:
- Governance capability/resource
- Hot-swappable InterestCurve
- Parameter updates (thresholds, rates)
- Risk module upgrades
- Admin functions

### Tests to Add (F-series from original plan):
```
F-1: Swap InterestCurve
- Deploy SimpleInterestCurve
- Hot-swap to AggressiveCurve
- Verify updateInterestRates() uses new APY
- Verify indices stay continuous
```

## 4. Multi-Token Support

### Features to Implement:
- Support for multiple vault types beyond FlowVault
- Token whitelisting mechanism
- Per-token configuration (thresholds, curves)
- Cross-token collateralization

### Tests to Add:
```
- Deposit multiple token types
- Borrow against multi-token collateral
- Token-specific liquidation thresholds
- Exchange rate updates
```

## 5. Oracle Integration

### Features to Implement:
- Price oracle interface
- Oracle price feeds
- Exchange rate updates from oracles
- Price staleness checks

### Tests to Add:
```
- Oracle price updates
- Stale price handling
- Price manipulation protection
- Multi-oracle aggregation
```

## 6. Liquidation Mechanism

### Features to Implement:
- Liquidator role/capability
- Liquidation function
- Liquidation incentives/penalties
- Partial vs full liquidation
- Liquidation queue

### Tests to Add:
```
- Liquidate underwater position
- Liquidation incentive calculation
- Partial liquidation
- Liquidation protection period
```

## 7. Non-Zero Interest Rates

### Features to Implement:
- Replace SimpleInterestCurve with real curves
- Multiple interest curve models
- Dynamic rate adjustment
- Rate limits and caps

### Tests to Add:
```
- Interest accrual over time
- Rate changes based on utilization
- Compound interest calculations
- Rate limit enforcement
```

## 8. Advanced Position Management

### Features to Implement:
- Position NFTs
- Position transfers
- Position merging/splitting
- Delegated position management

### Tests to Add:
```
- Transfer position ownership
- Merge two positions
- Split position into multiple
- Delegate management rights
```

## 9. Flash Loan Support

### Features to Implement:
- Flash loan interface
- Flash loan fees
- Reentrancy protection
- Flash loan callbacks

### Tests to Add:
```
- Execute flash loan
- Flash loan fee collection
- Failed flash loan rollback
- Nested flash loans
```

## 10. Emergency Controls

### Features to Implement:
- Pause mechanism
- Emergency withdrawal
- Circuit breakers
- Recovery mode

### Tests to Add:
```
- Pause all operations
- Emergency withdraw funds
- Circuit breaker triggers
- Recovery from emergency
```

## Implementation Notes

When implementing these features:

1. **Maintain Backward Compatibility**: Ensure existing positions and functionality continue to work
2. **Add Comprehensive Tests**: Each feature should have thorough test coverage
3. **Update Documentation**: Keep TestsOverview.md and other docs in sync
4. **Security First**: Each feature needs security review and audit
5. **Gradual Rollout**: Consider feature flags or phased deployment

## Test File Structure for Future Features

```
cadence/tests/future/
├── deposit_queue_test.cdc       # D-series tests
├── sink_source_test.cdc         # E-series tests  
├── governance_test.cdc          # F-series tests
├── multi_token_test.cdc         # Multi-token tests
├── oracle_test.cdc              # Oracle tests
├── liquidation_test.cdc         # Liquidation tests
├── interest_curves_test.cdc     # Real interest tests
├── advanced_position_test.cdc   # Advanced position tests
├── flash_loan_test.cdc          # Flash loan tests
└── emergency_test.cdc           # Emergency control tests
``` 