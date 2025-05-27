# Proper Test Setup for AlpenFlow

## Overview

This document explains the correct way to set up tests for the AlpenFlow project that uses FungibleToken and DeFi Blocks interfaces.

## Key Principles

### 1. **Don't Copy External Repositories**
- ❌ **Wrong**: Copying entire `flow-ft` and `DeFiBlocks` repositories into your project
- ✅ **Right**: Use Flow's dependency management to reference external contracts

### 2. **Use Standard Contract Addresses**
In the Cadence Testing Framework, standard contracts are pre-deployed:
- `FungibleToken`: `0x0000000000000002`
- `ViewResolver`: `0x0000000000000001`
- `MetadataViews`: `0x0000000000000001`
- `Burner`: `0x0000000000000001`

### 3. **Only Deploy What You Need**
- Deploy only your custom contracts (AlpenFlow) and non-standard dependencies (DFB)
- Standard contracts are already available in the test environment

## Correct Project Structure

```
AlpenFlow/
├── cadence/
│   ├── contracts/
│   │   └── AlpenFlow.cdc
│   ├── tests/
│   │   ├── simple_test.cdc
│   │   └── ... other tests
│   ├── transactions/
│   └── scripts/
├── DeFiBlocks/           # Only keep the DFB interface file
│   └── cadence/
│       └── contracts/
│           └── interfaces/
│               └── DFB.cdc
├── flow.json
└── README.md
```

## Proper flow.json Configuration

```json
{
  "contracts": {
    "AlpenFlow": "./cadence/contracts/AlpenFlow.cdc",
    "DFB": {
      "source": "./DeFiBlocks/cadence/contracts/interfaces/DFB.cdc",
      "aliases": {
        "testing": "0x0000000000000008"
      }
    },
    "FungibleToken": {
      "source": "mainnet://f233dcee88fe0abe.FungibleToken",
      "aliases": {
        "emulator": "0xee82856bf20e2aa6",
        "testnet": "0x9a0766d93b6608b7",
        "mainnet": "0xf233dcee88fe0abe",
        "testing": "0x0000000000000002"
      }
    }
    // ... other standard contracts
  }
}
```

## Test Setup Pattern

```cadence
import Test

access(all)
fun setup() {
    // Only deploy non-standard contracts
    var err = Test.deployContract(
        name: "DFB",
        path: "../DeFiBlocks/cadence/contracts/interfaces/DFB.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    
    // Deploy your contract
    err = Test.deployContract(
        name: "AlpenFlow",
        path: "../contracts/AlpenFlow.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}
```

## Why This Approach is Correct

### 1. **Standards Compliance**
- Using FungibleToken interface ensures compatibility with all Flow wallets and DeFi protocols
- Following the official token standard is essential for interoperability

### 2. **DeFi Blocks Integration**
- DeFi Blocks provides standardized components for DeFi protocols
- Using DFB.Sink and DFB.Source interfaces makes your protocol composable
- This is the recommended approach for building DeFi on Flow

### 3. **Dependency Management**
- Flow's dependency system ensures you always use the correct contract versions
- Reduces maintenance burden - no need to update copied contracts
- Smaller repository size and cleaner codebase

## Common Mistakes to Avoid

1. **Don't deploy standard contracts in tests** - They're already available
2. **Don't copy entire repositories** - Use only what you need
3. **Don't hardcode addresses** - Use aliases in flow.json
4. **Don't ignore test framework limitations** - Work within them

## Next Steps

1. Clean up unnecessary files:
   ```bash
   rm -rf flow-ft/  # Remove if you copied the entire repo
   # Keep only DFB.cdc from DeFiBlocks
   ```

2. Update all test files to follow this pattern

3. Run tests:
   ```bash
   flow test cadence/tests/*.cdc
   ```

## Resources

- [Flow Fungible Token Standard](https://github.com/onflow/flow-ft)
- [DeFi Blocks Documentation](https://github.com/onflow/defi-blocks)
- [Cadence Testing Framework](https://cadence-lang.org/docs/testing-framework)
- [Flow Dependency Management](https://developers.flow.com/tools/flow-cli/dependency-manager) 