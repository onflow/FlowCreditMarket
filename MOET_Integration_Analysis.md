# MOET Stablecoin Integration Analysis

## Current Implementation Status

### What's Implemented on `gio/add-stablecoin` Branch

1. **MOET Contract** (`cadence/contracts/MOET.cdc`)
   - ✅ Implements FungibleToken standard
   - ✅ Has minting capabilities through `Minter` resource
   - ✅ Proper metadata implementation
   - ⚠️ Currently just a mock implementation (as noted in contract comments)
   - ❌ No CDP (Collateralized Debt Position) functionality yet
   - ❌ No stability mechanism or oracle integration

### Current Issues

1. **Separation of Concerns**
   - ✅ Good: MOET is a separate contract, not embedded in TidalProtocol
   - ⚠️ Issue: No clear CDP mechanism separate from the lending pool
   - ⚠️ Issue: The minting is centralized through admin-controlled `Minter`

2. **Integration with TidalProtocol**
   - ❌ MOET is imported but not properly integrated
   - ❌ Hardcoded MOET reference in `TidalProtocolSource.withdrawAvailable`
   - ❌ No proper mechanism to add MOET to lending pools

## Implementation Completed on New Branch

### Branch: `feature/moet-stablecoin-integration`

1. **Added Token Management to Pool**
   ```cadence
   access(all) fun addSupportedToken(
       tokenType: Type, 
       exchangeRate: UFix64, 
       liquidationThreshold: UFix64,
       interestCurve: {InterestCurve}
   )
   ```

2. **Fixed Issues**
   - ✅ Added proper token registration mechanism
   - ✅ Fixed hardcoded MOET reference in withdrawAvailable
   - ✅ Created comprehensive test suite for MOET integration

3. **Test Coverage**
   - `testMOETIntegration`: Tests MOET as a borrowable asset
   - `testMOETAsCollateral`: Tests MOET as collateral
   - `testInvalidTokenOperations`: Tests error cases

## Recommendations for Tracer Bullet

### Phase 1: Basic Integration (Current Implementation) ✅
- Add MOET as a borrowable token pegged to $1
- Users can:
  - Deposit FLOW/other tokens as collateral
  - Borrow MOET against collateral
  - Use MOET as collateral to borrow other tokens

### Phase 2: CDP Implementation (Future)
```cadence
// Suggested structure for CDP functionality
access(all) contract MOETCDPEngine {
    // Vault to lock collateral and mint MOET
    access(all) resource CDP {
        access(self) var collateral: @{FungibleToken.Vault}
        access(all) var debtAmount: UFix64
        
        // Mint MOET against collateral
        access(all) fun mintMOET(amount: UFix64): @MOET.Vault
        
        // Repay debt and unlock collateral
        access(all) fun repayDebt(payment: @MOET.Vault)
    }
}
```

### Phase 3: Governance (Future)
```cadence
// Suggested governance structure
access(all) contract PoolGovernance {
    // Proposal to add new token
    access(all) struct TokenProposal {
        access(all) let tokenType: Type
        access(all) let exchangeRate: UFix64
        access(all) let liquidationThreshold: UFix64
        access(all) let votesFor: UFix64
        access(all) let votesAgainst: UFix64
    }
    
    // Vote on proposals
    access(all) fun voteOnProposal(proposalID: UInt64, support: Bool)
    
    // Execute approved proposals
    access(all) fun executeProposal(proposalID: UInt64)
}
```

## Integration Example

```cadence
// Example: Setting up MOET in a lending pool
let pool <- TidalProtocol.createPool(
    defaultToken: Type<@FlowToken.Vault>(),
    defaultTokenThreshold: 0.8
)

// Add MOET with $1 peg
pool.addSupportedToken(
    tokenType: Type<@MOET.Vault>(),
    exchangeRate: 1.0,  // 1 MOET = 1 FLOW (assuming FLOW = $1)
    liquidationThreshold: 0.75,  // 75% LTV
    interestCurve: StablecoinInterestCurve()  // Custom curve for stablecoins
)
```

## Security Considerations

1. **Oracle Risk**: Exchange rates are currently hardcoded. Need price oracles for production.
2. **Liquidation Risk**: MOET's peg stability depends on proper liquidation mechanisms.
3. **Governance Risk**: Token addition should be controlled by governance, not admin.

## Next Steps

1. **Immediate (Tracer Bullet)**
   - ✅ Basic MOET integration as borrowable token
   - ✅ Test suite demonstrating functionality
   - Deploy and test on emulator

2. **Short Term**
   - Implement proper price oracles
   - Add governance proposal system
   - Create CDP engine for MOET minting

3. **Long Term**
   - Full MakerDAO-style CDP system
   - Multiple collateral types for MOET
   - Stability fees and DSR (DAI Savings Rate) equivalent
   - Emergency shutdown mechanism

## Testing Instructions

```bash
# Run MOET integration tests
flow test --cover cadence/tests/moet_integration_test.cdc

# Deploy contracts with MOET
flow project deploy --network emulator
``` 