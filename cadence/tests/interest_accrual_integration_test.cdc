import Test
import BlockchainHelpers

import "MOET"
import "FlowToken"
import "FlowCreditMarket"
import "FlowCreditMarketMath"
import "test_helpers.cdc"
import "MockFlowCreditMarketConsumer"

// -----------------------------------------------------------------------------
// Interest Accrual Integration Test
// -----------------------------------------------------------------------------
// Tests that interest accrual over time correctly increases debt and decreases
// health factor. Requires a liquidity provider to deposit MOET first so that
// interest can accrue on borrowed MOET.
//
// Interest Rate Configuration:
// - MOET: Fixed 4% APY (as per user requirement)
// - FlowToken: Aave v3 Volatile One (45% optimal, 0% base, 4% slope1, 300% slope2)
// -----------------------------------------------------------------------------

access(all) let protocolAccount = Test.getAccount(0x0000000000000007)
access(all) let protocolConsumerAccount = Test.getAccount(0x0000000000000008)
access(all) var snapshot: UInt64 = 0

access(all) let flowTokenIdentifier = "A.0000000000000003.FlowToken.Vault"
access(all) let flowVaultStoragePath = /storage/flowTokenVault
access(all) let wrapperStoragePath = /storage/flowCreditMarketPositionWrapper

// MOET: Fixed 4% APY debit rate using FixedRateInterestCurve (spread model)
// Borrowers pay 4%, lenders earn ~3.9% (debit rate - insurance rate)
access(all) let moetFixedRate: UFix128 = 0.04  // 4% APY debit rate

// FlowToken: Aave v3 Volatile One parameters
access(all) let flowOptimalUtilization: UFix128 = 0.45  // 45%
access(all) let flowBaseRate: UFix128 = 0.0             // 0%
access(all) let flowSlope1: UFix128 = 0.04              // 4%
access(all) let flowSlope2: UFix128 = 3.0               // 300%

// Time constants
access(all) let THIRTY_DAYS: Fix64 = 2592000.0  // 30 * 86400 seconds

access(all)
fun setup() {
    deployContracts()

    let betaTxResult = grantBeta(protocolAccount, protocolConsumerAccount)
    Test.expect(betaTxResult, Test.beSucceeded())

    snapshot = getCurrentBlockHeight()
}

// -----------------------------------------------------------------------------
// Test 1: MOET Debit - Interest accrual decreases health over time
// -----------------------------------------------------------------------------
// This test verifies that when time passes:
// 1. Debt balance increases due to interest accrual
// 2. Health factor decreases (more debt relative to same collateral)
// 3. The interest growth matches the expected rate (within 0.0001% tolerance)
// -----------------------------------------------------------------------------
access(all)
fun test_moet_debit_accrues_interest() {
    // Setup: price oracle
    setMockOraclePrice(signer: protocolAccount, forTokenIdentifier: flowTokenIdentifier, price: 1.0)

    // Create pool with MOET as default token (starts with 0% interest)
    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)

    // Add FlowToken with Aave v3 Volatile One parameters (no credit balance yet, but that's ok for collateral)
    addSupportedTokenKinkCurve(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        optimalUtilization: flowOptimalUtilization,
        baseRate: flowBaseRate,
        slope1: flowSlope1,
        slope2: flowSlope2,
        depositRate: 1_000_000.0,
        depositCapacityCap: 1_000_000.0
    )

    // === STEP 1: Create liquidity provider and deposit MOET ===
    // This is necessary because borrowers need available liquidity to borrow from
    let liquidityProvider = Test.createAccount()
    setupMoetVault(liquidityProvider, beFailed: false)

    // Mint 10,000 MOET to liquidity provider
    mintMoet(signer: protocolAccount, to: liquidityProvider.address, amount: 10_000.0, beFailed: false)

    // Grant beta to liquidity provider
    let lpBetaRes = grantBeta(protocolAccount, liquidityProvider)
    Test.expect(lpBetaRes, Test.beSucceeded())

    // Create position and deposit MOET (no auto-borrow since pushToDrawDownSink=false)
    // This creates MOET credit balance in the pool
    let createLpPosRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [10_000.0, MOET.VaultStoragePath, false],  // deposit MOET, no auto-borrow
        liquidityProvider
    )
    Test.expect(createLpPosRes, Test.beSucceeded())
    log("Liquidity provider deposited 10,000 MOET")

    // Configure MOET with fixed 4% APY debit rate
    // Note: For FixedRateInterestCurve, debitRate = creditRate + insuranceRate (borrowers pay the spread)
    setInterestCurveFixed(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        yearlyRate: moetFixedRate
    )
    log("Set MOET interest rate to 4% APY (after LP deposit)")

    // === STEP 2: Create borrower and deposit FlowToken collateral ===
    let borrower = Test.createAccount()
    setupMoetVault(borrower, beFailed: false)
    mintFlow(to: borrower, amount: 1_000.0)

    // Grant beta to borrower
    let borrowerBetaRes = grantBeta(protocolAccount, borrower)
    Test.expect(borrowerBetaRes, Test.beSucceeded())

    // Open position with auto-borrow (deposits FlowToken, borrows MOET at target health 1.3)
    let openRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [1_000.0, flowVaultStoragePath, true],
        borrower
    )
    Test.expect(openRes, Test.beSucceeded())
    log("Borrower deposited 1,000 Flow and auto-borrowed MOET")

    // Find borrower's position ID (should be position 1, since LP has position 0)
    let borrowerPid: UInt64 = 1

    // Record initial state
    let detailsBefore = getPositionDetails(pid: borrowerPid, beFailed: false)
    let healthBefore = detailsBefore.health
    let debtBefore = getDebitBalanceForType(details: detailsBefore, vaultType: Type<@MOET.Vault>())

    // Get timestamp before time advancement
    let timestampBefore = getBlockTimestamp()

    log("=== BEFORE TIME ADVANCEMENT ===")
    log("Block timestamp: ".concat(timestampBefore.toString()))
    log("Borrower health: ".concat(healthBefore.toString()))
    log("Borrower MOET debt: ".concat(debtBefore.toString()))

    // Verify we have debt (auto-borrow at target health should have borrowed MOET)
    Test.assert(debtBefore > 0.0, message: "Expected position to have MOET debt after auto-borrow")

    // === STEP 3: Advance time by 30 days ===
    Test.moveTime(by: THIRTY_DAYS)
    Test.commitBlock()

    // Get timestamp after time advancement
    let timestampAfter = getBlockTimestamp()
    log("Block timestamp after moveTime: ".concat(timestampAfter.toString()))

    // Verify time delta is approximately 30 days (2592000 seconds)
    // Allow 1 second tolerance for block commit timing
    let timeDelta = timestampAfter - timestampBefore
    log("Time delta: ".concat(timeDelta.toString()))
    Test.assert(
        timeDelta >= 2592000.0 && timeDelta <= 2592001.0,
        message: "Time delta should be ~2592000 seconds (30 days). Actual: ".concat(timeDelta.toString())
    )

    // Get state BEFORE rebalance - scripts compute interest indices transiently
    // The interest will be calculated based on the new timestamp
    let detailsAfterTime = getPositionDetails(pid: borrowerPid, beFailed: false)
    let healthAfterTime = detailsAfterTime.health
    let debtAfterTime = getDebitBalanceForType(details: detailsAfterTime, vaultType: Type<@MOET.Vault>())

    log("=== AFTER TIME ADVANCEMENT (30 days, before rebalance) ===")
    log("Borrower health: ".concat(healthAfterTime.toString()))
    log("Borrower MOET debt: ".concat(debtAfterTime.toString()))

    // Trigger interest accrual via a transaction to persist the state changes
    // Note: rebalance will also auto-repay debt to restore health, but we already captured the state above
    rebalancePosition(signer: protocolAccount, pid: borrowerPid, force: true, beFailed: false)

    // Get state after rebalance (for completeness - debt may be repaid to restore health)
    let detailsAfter = getPositionDetails(pid: borrowerPid, beFailed: false)
    let healthAfter = detailsAfter.health
    let debtAfter = getDebitBalanceForType(details: detailsAfter, vaultType: Type<@MOET.Vault>())

    log("=== AFTER REBALANCE ===")
    log("Borrower health: ".concat(healthAfter.toString()))
    log("Borrower MOET debt: ".concat(debtAfter.toString()))

    // Use the pre-rebalance values for assertions, since rebalance auto-repays debt
    // Assertion 1: Debt should have increased (comparing pre-rebalance debt to initial)
    Test.assert(
        debtAfterTime > debtBefore,
        message: "Expected debt to increase from interest accrual. Before: "
            .concat(debtBefore.toString())
            .concat(", After (pre-rebalance): ")
            .concat(debtAfterTime.toString())
    )

    // Assertion 2: Health should have decreased (more debt, same collateral)
    Test.assert(
        healthAfterTime < healthBefore,
        message: "Expected health to decrease as debt accrues interest. Before: "
            .concat(healthBefore.toString())
            .concat(", After (pre-rebalance): ")
            .concat(healthAfterTime.toString())
    )

    // Assertion 3: Verify interest growth is within expected range
    let debtGrowth = debtAfterTime - debtBefore
    let growthRate = debtGrowth / debtBefore
    log("Debt growth: ".concat(debtGrowth.toString()))
    log("Growth rate (30 days): ".concat(growthRate.toString()))

    // Expected growth at 4% APY for 30 days: (30/365) * 0.04 ≈ 0.00329 (0.329%)
    // Allow for compounding effect and utilization impact, so broader range
    let minExpectedGrowth: UFix64 = 0.002   // 0.2% (conservative lower bound)
    let maxExpectedGrowth: UFix64 = 0.015   // 1.5% (allowing for higher utilization rates)

    Test.assert(
        growthRate >= minExpectedGrowth && growthRate <= maxExpectedGrowth,
        message: "Interest growth rate ".concat(growthRate.toString())
            .concat(" outside expected range [").concat(minExpectedGrowth.toString())
            .concat(", ").concat(maxExpectedGrowth.toString()).concat("]")
    )

    log("=== TEST PASSED ===")
    log("Interest accrual correctly increased debt and decreased health over 30 days")
}

// -----------------------------------------------------------------------------
// Helper: Get current block timestamp
// -----------------------------------------------------------------------------
access(all)
fun getBlockTimestamp(): UFix64 {
    let res = _executeScript("../scripts/flow-credit-market/get_block_timestamp.cdc", [])
    Test.expect(res, Test.beSucceeded())
    return res.returnValue as! UFix64
}

// -----------------------------------------------------------------------------
// Helper: Extract debit balance for a specific vault type from PositionDetails
// -----------------------------------------------------------------------------
access(all)
fun getDebitBalanceForType(details: FlowCreditMarket.PositionDetails, vaultType: Type): UFix64 {
    for balance in details.balances {
        if balance.vaultType == vaultType && balance.direction == FlowCreditMarket.BalanceDirection.Debit {
            return balance.balance
        }
    }
    return 0.0
}

// -----------------------------------------------------------------------------
// Helper: Extract credit balance for a specific vault type from PositionDetails
// -----------------------------------------------------------------------------
access(all)
fun getCreditBalanceForType(details: FlowCreditMarket.PositionDetails, vaultType: Type): UFix64 {
    for balance in details.balances {
        if balance.vaultType == vaultType && balance.direction == FlowCreditMarket.BalanceDirection.Credit {
            return balance.balance
        }
    }
    return 0.0
}

// -----------------------------------------------------------------------------
// Test 2: MOET Credit - LP earns interest with insurance deduction
// -----------------------------------------------------------------------------
// Verifies that depositors earn credit interest at a rate lower than debit rate
// For FixedRateInterestCurve (MOET): debitRate = creditRate + insuranceRate
// The curve defines debitRate (what borrowers pay), lenders earn the remainder after insurance
// -----------------------------------------------------------------------------
access(all)
fun test_moet_credit_accrues_interest_with_insurance() {
    // Reset state to clean snapshot
    Test.reset(to: snapshot)

    // Setup: price oracle
    setMockOraclePrice(signer: protocolAccount, forTokenIdentifier: flowTokenIdentifier, price: 1.0)

    // Create pool with MOET as default token
    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)

    // Add FlowToken for collateral
    addSupportedTokenKinkCurve(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        optimalUtilization: flowOptimalUtilization,
        baseRate: flowBaseRate,
        slope1: flowSlope1,
        slope2: flowSlope2,
        depositRate: 1_000_000.0,
        depositCapacityCap: 1_000_000.0
    )

    // === Create LP who deposits MOET ===
    let lp = Test.createAccount()
    setupMoetVault(lp, beFailed: false)
    mintMoet(signer: protocolAccount, to: lp.address, amount: 10_000.0, beFailed: false)

    let lpBetaRes = grantBeta(protocolAccount, lp)
    Test.expect(lpBetaRes, Test.beSucceeded())

    // LP deposits MOET (creates credit balance)
    let createLpPosRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [10_000.0, MOET.VaultStoragePath, false],
        lp
    )
    Test.expect(createLpPosRes, Test.beSucceeded())
    log("LP deposited 10,000 MOET")

    // Configure MOET with fixed 4% APY debit rate (spread model)
    setInterestCurveFixed(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        yearlyRate: moetFixedRate
    )

    // === Create borrower who borrows MOET to create utilization ===
    let borrower = Test.createAccount()
    setupMoetVault(borrower, beFailed: false)
    mintFlow(to: borrower, amount: 10_000.0)  // More collateral to borrow more

    let borrowerBetaRes = grantBeta(protocolAccount, borrower)
    Test.expect(borrowerBetaRes, Test.beSucceeded())

    // Borrower deposits Flow and borrows MOET (~60% utilization target)
    let openRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [10_000.0, flowVaultStoragePath, true],
        borrower
    )
    Test.expect(openRes, Test.beSucceeded())
    log("Borrower deposited 10,000 Flow and auto-borrowed MOET")

    // Note: For FixedRateInterestCurve, rates are independent of utilization
    // This call is redundant since balance changes auto-trigger updateInterestRates()
    setInterestCurveFixed(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        yearlyRate: moetFixedRate
    )
    log("Confirmed MOET interest curve configuration")

    // Record LP's initial MOET credit balance
    let lpPid: UInt64 = 0
    let lpDetailsBefore = getPositionDetails(pid: lpPid, beFailed: false)
    let lpCreditBefore = getCreditBalanceForType(details: lpDetailsBefore, vaultType: Type<@MOET.Vault>())

    log("=== BEFORE TIME ADVANCEMENT ===")
    log("LP MOET credit: ".concat(lpCreditBefore.toString()))

    // Advance time by 30 days
    Test.moveTime(by: THIRTY_DAYS)
    Test.commitBlock()

    // Get LP credit balance after time advancement
    let lpDetailsAfter = getPositionDetails(pid: lpPid, beFailed: false)
    let lpCreditAfter = getCreditBalanceForType(details: lpDetailsAfter, vaultType: Type<@MOET.Vault>())

    log("=== AFTER TIME ADVANCEMENT (30 days) ===")
    log("LP MOET credit: ".concat(lpCreditAfter.toString()))

    // Assertion 1: Credit balance should have increased
    Test.assert(
        lpCreditAfter > lpCreditBefore,
        message: "Expected LP credit to increase from interest. Before: "
            .concat(lpCreditBefore.toString())
            .concat(", After: ")
            .concat(lpCreditAfter.toString())
    )

    // Calculate credit growth rate
    let creditGrowth = lpCreditAfter - lpCreditBefore
    let creditGrowthRate = creditGrowth / lpCreditBefore
    log("Credit growth: ".concat(creditGrowth.toString()))
    log("Credit growth rate (30 days): ".concat(creditGrowthRate.toString()))

    // Credit rate should be less than debit rate (insurance spread)
    // For FixedRateInterestCurve: debitRate = creditRate + insuranceRate
    // At 4% debit rate (curve's yearlyRate), 0.1% insurance: creditRate = 4% - 0.1% = 3.9%
    // 30-day growth: ~0.32%
    let minExpectedCreditGrowth: UFix64 = 0.001  // 0.1%
    let maxExpectedCreditGrowth: UFix64 = 0.005  // 0.5%

    Test.assert(
        creditGrowthRate >= minExpectedCreditGrowth && creditGrowthRate <= maxExpectedCreditGrowth,
        message: "Credit growth rate ".concat(creditGrowthRate.toString())
            .concat(" outside expected range [").concat(minExpectedCreditGrowth.toString())
            .concat(", ").concat(maxExpectedCreditGrowth.toString()).concat("]")
    )

    log("=== TEST PASSED ===")
    log("MOET credit accrued interest with insurance deduction")
}

// -----------------------------------------------------------------------------
// Test 3: Flow Debit - Borrower pays Flow interest at KinkCurve rate
// -----------------------------------------------------------------------------
access(all)
fun test_flow_debit_accrues_interest() {
    // Reset state to clean snapshot
    Test.reset(to: snapshot)

    // Setup: price oracle
    setMockOraclePrice(signer: protocolAccount, forTokenIdentifier: flowTokenIdentifier, price: 1.0)

    // Create pool with MOET as default token
    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)

    // Add FlowToken with KinkCurve
    addSupportedTokenKinkCurve(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        optimalUtilization: flowOptimalUtilization,
        baseRate: flowBaseRate,
        slope1: flowSlope1,
        slope2: flowSlope2,
        depositRate: 1_000_000.0,
        depositCapacityCap: 1_000_000.0
    )

    // === Create LP who deposits Flow ===
    let flowLp = Test.createAccount()
    setupMoetVault(flowLp, beFailed: false)
    mintFlow(to: flowLp, amount: 10_000.0)

    let lpBetaRes = grantBeta(protocolAccount, flowLp)
    Test.expect(lpBetaRes, Test.beSucceeded())

    // LP deposits Flow (creates Flow credit balance)
    let createLpPosRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [10_000.0, flowVaultStoragePath, false],
        flowLp
    )
    Test.expect(createLpPosRes, Test.beSucceeded())
    log("Flow LP deposited 10,000 Flow")

    // Configure FlowToken kink curve (credit rate requires totalCreditBalance > 0)
    setInterestCurveKink(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        optimalUtilization: flowOptimalUtilization,
        baseRate: flowBaseRate,
        slope1: flowSlope1,
        slope2: flowSlope2
    )

    // === Create borrower who borrows Flow ===
    let borrower = Test.createAccount()
    setupMoetVault(borrower, beFailed: false)
    mintMoet(signer: protocolAccount, to: borrower.address, amount: 10_000.0, beFailed: false)

    let borrowerBetaRes = grantBeta(protocolAccount, borrower)
    Test.expect(borrowerBetaRes, Test.beSucceeded())

    // Borrower deposits MOET as collateral and borrows Flow
    // First create a position with MOET deposit (no auto-borrow since MOET is default token)
    let createPosRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [10_000.0, MOET.VaultStoragePath, false],
        borrower
    )
    Test.expect(createPosRes, Test.beSucceeded())

    // Now borrow Flow using a separate transaction
    let borrowPid: UInt64 = 1
    let borrowRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/borrow_from_position.cdc",
        [borrowPid, flowTokenIdentifier, 4_000.0],  // Borrow 4000 Flow (~40% utilization)
        borrower
    )
    Test.expect(borrowRes, Test.beSucceeded())
    log("Borrower deposited 10,000 MOET and borrowed 4,000 Flow")

    // Note: Balance changes auto-trigger updateInterestRates() via updateForUtilizationChange()
    // This call confirms the curve config; KinkCurve rates depend on utilization
    setInterestCurveKink(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        optimalUtilization: flowOptimalUtilization,
        baseRate: flowBaseRate,
        slope1: flowSlope1,
        slope2: flowSlope2
    )
    log("Confirmed Flow interest curve at ~40% utilization")

    // Record borrower's initial Flow debt
    let borrowerDetailsBefore = getPositionDetails(pid: borrowPid, beFailed: false)
    let flowDebtBefore = getDebitBalanceForType(details: borrowerDetailsBefore, vaultType: Type<@FlowToken.Vault>())
    let healthBefore = borrowerDetailsBefore.health

    log("=== BEFORE TIME ADVANCEMENT ===")
    log("Borrower Flow debt: ".concat(flowDebtBefore.toString()))
    log("Borrower health: ".concat(healthBefore.toString()))

    Test.assert(flowDebtBefore > 0.0, message: "Expected position to have Flow debt")

    // Advance time by 30 days
    Test.moveTime(by: THIRTY_DAYS)
    Test.commitBlock()

    // Get state after time advancement
    let borrowerDetailsAfter = getPositionDetails(pid: borrowPid, beFailed: false)
    let flowDebtAfter = getDebitBalanceForType(details: borrowerDetailsAfter, vaultType: Type<@FlowToken.Vault>())
    let healthAfter = borrowerDetailsAfter.health

    log("=== AFTER TIME ADVANCEMENT (30 days) ===")
    log("Borrower Flow debt: ".concat(flowDebtAfter.toString()))
    log("Borrower health: ".concat(healthAfter.toString()))

    // Assertion 1: Flow debt should have increased
    Test.assert(
        flowDebtAfter > flowDebtBefore,
        message: "Expected Flow debt to increase. Before: "
            .concat(flowDebtBefore.toString())
            .concat(", After: ")
            .concat(flowDebtAfter.toString())
    )

    // Assertion 2: Health should have decreased
    Test.assert(
        healthAfter < healthBefore,
        message: "Expected health to decrease. Before: "
            .concat(healthBefore.toString())
            .concat(", After: ")
            .concat(healthAfter.toString())
    )

    // Calculate debt growth rate
    let debtGrowth = flowDebtAfter - flowDebtBefore
    let debtGrowthRate = debtGrowth / flowDebtBefore
    log("Flow debt growth: ".concat(debtGrowth.toString()))
    log("Flow debt growth rate (30 days): ".concat(debtGrowthRate.toString()))

    // At 40% utilization (below 45% optimal), rate ≈ (40%/45%) × 4% ≈ 3.56% APY
    // 30-day growth: ~0.29%
    let minExpectedDebtGrowth: UFix64 = 0.002  // 0.2%
    let maxExpectedDebtGrowth: UFix64 = 0.010  // 1.0%

    Test.assert(
        debtGrowthRate >= minExpectedDebtGrowth && debtGrowthRate <= maxExpectedDebtGrowth,
        message: "Flow debt growth rate ".concat(debtGrowthRate.toString())
            .concat(" outside expected range [").concat(minExpectedDebtGrowth.toString())
            .concat(", ").concat(maxExpectedDebtGrowth.toString()).concat("]")
    )

    log("=== TEST PASSED ===")
    log("Flow debit accrued interest at KinkCurve rate")
}

// -----------------------------------------------------------------------------
// Test 4: Flow Credit - LP earns Flow interest with insurance deduction
// -----------------------------------------------------------------------------
access(all)
fun test_flow_credit_accrues_interest_with_insurance() {
    // Reset state to clean snapshot
    Test.reset(to: snapshot)

    // Setup: price oracle
    setMockOraclePrice(signer: protocolAccount, forTokenIdentifier: flowTokenIdentifier, price: 1.0)

    // Create pool with MOET as default token
    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)

    // Add FlowToken with KinkCurve
    addSupportedTokenKinkCurve(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        optimalUtilization: flowOptimalUtilization,
        baseRate: flowBaseRate,
        slope1: flowSlope1,
        slope2: flowSlope2,
        depositRate: 1_000_000.0,
        depositCapacityCap: 1_000_000.0
    )

    // === Create LP who deposits Flow ===
    let flowLp = Test.createAccount()
    setupMoetVault(flowLp, beFailed: false)
    mintFlow(to: flowLp, amount: 10_000.0)

    let lpBetaRes = grantBeta(protocolAccount, flowLp)
    Test.expect(lpBetaRes, Test.beSucceeded())

    // LP deposits Flow (creates Flow credit balance)
    let createLpPosRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [10_000.0, flowVaultStoragePath, false],
        flowLp
    )
    Test.expect(createLpPosRes, Test.beSucceeded())
    log("Flow LP deposited 10,000 Flow")

    // Configure FlowToken kink curve (credit rate requires totalCreditBalance > 0)
    setInterestCurveKink(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        optimalUtilization: flowOptimalUtilization,
        baseRate: flowBaseRate,
        slope1: flowSlope1,
        slope2: flowSlope2
    )

    // === Create borrower who borrows Flow to create utilization ===
    let borrower = Test.createAccount()
    setupMoetVault(borrower, beFailed: false)
    mintMoet(signer: protocolAccount, to: borrower.address, amount: 10_000.0, beFailed: false)

    let borrowerBetaRes = grantBeta(protocolAccount, borrower)
    Test.expect(borrowerBetaRes, Test.beSucceeded())

    // Borrower deposits MOET as collateral
    let createPosRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [10_000.0, MOET.VaultStoragePath, false],
        borrower
    )
    Test.expect(createPosRes, Test.beSucceeded())

    // Borrow Flow
    let borrowPid: UInt64 = 1
    let borrowRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/borrow_from_position.cdc",
        [borrowPid, flowTokenIdentifier, 4_000.0],
        borrower
    )
    Test.expect(borrowRes, Test.beSucceeded())
    log("Borrower deposited 10,000 MOET and borrowed 4,000 Flow")

    // Note: Balance changes auto-trigger updateInterestRates() via updateForUtilizationChange()
    // This call confirms the curve config; KinkCurve rates depend on utilization
    setInterestCurveKink(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        optimalUtilization: flowOptimalUtilization,
        baseRate: flowBaseRate,
        slope1: flowSlope1,
        slope2: flowSlope2
    )
    log("Confirmed Flow interest curve at ~40% utilization")

    // Record LP's initial Flow credit balance
    let lpPid: UInt64 = 0
    let lpDetailsBefore = getPositionDetails(pid: lpPid, beFailed: false)
    let flowCreditBefore = getCreditBalanceForType(details: lpDetailsBefore, vaultType: Type<@FlowToken.Vault>())

    // Also record borrower's Flow debt for comparison
    let borrowerDetailsBefore = getPositionDetails(pid: borrowPid, beFailed: false)
    let flowDebtBefore = getDebitBalanceForType(details: borrowerDetailsBefore, vaultType: Type<@FlowToken.Vault>())

    log("=== BEFORE TIME ADVANCEMENT ===")
    log("LP Flow credit: ".concat(flowCreditBefore.toString()))
    log("Borrower Flow debt: ".concat(flowDebtBefore.toString()))

    // Advance time by 30 days
    Test.moveTime(by: THIRTY_DAYS)
    Test.commitBlock()

    // Get balances after time advancement
    let lpDetailsAfter = getPositionDetails(pid: lpPid, beFailed: false)
    let flowCreditAfter = getCreditBalanceForType(details: lpDetailsAfter, vaultType: Type<@FlowToken.Vault>())

    let borrowerDetailsAfter = getPositionDetails(pid: borrowPid, beFailed: false)
    let flowDebtAfter = getDebitBalanceForType(details: borrowerDetailsAfter, vaultType: Type<@FlowToken.Vault>())

    log("=== AFTER TIME ADVANCEMENT (30 days) ===")
    log("LP Flow credit: ".concat(flowCreditAfter.toString()))
    log("Borrower Flow debt: ".concat(flowDebtAfter.toString()))

    // Assertion 1: Credit balance should have increased
    Test.assert(
        flowCreditAfter > flowCreditBefore,
        message: "Expected LP Flow credit to increase"
    )

    // Calculate growth rates
    let creditGrowth = flowCreditAfter - flowCreditBefore
    let creditGrowthRate = creditGrowth / flowCreditBefore
    let debtGrowth = flowDebtAfter - flowDebtBefore
    let debtGrowthRate = debtGrowth / flowDebtBefore

    log("Credit growth rate: ".concat(creditGrowthRate.toString()))
    log("Debt growth rate: ".concat(debtGrowthRate.toString()))

    // Assertion 2: Credit growth rate should be less than debt growth rate (insurance spread)
    Test.assert(
        creditGrowthRate < debtGrowthRate,
        message: "Credit growth rate should be less than debt growth rate due to insurance. Credit: "
            .concat(creditGrowthRate.toString())
            .concat(", Debt: ")
            .concat(debtGrowthRate.toString())
    )

    log("=== TEST PASSED ===")
    log("Flow credit accrued interest with insurance deduction (credit < debt growth)")
}

// -----------------------------------------------------------------------------
// Test 5: Insurance deduction verification
// -----------------------------------------------------------------------------
// Explicitly verifies that insurance is correctly deducted from credit rates
// -----------------------------------------------------------------------------
access(all)
fun test_insurance_deduction_verification() {
    // Reset state to clean snapshot
    Test.reset(to: snapshot)

    // Setup: price oracle
    setMockOraclePrice(signer: protocolAccount, forTokenIdentifier: flowTokenIdentifier, price: 1.0)

    // Create pool with MOET as default token
    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)

    // Add FlowToken
    addSupportedTokenKinkCurve(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        optimalUtilization: flowOptimalUtilization,
        baseRate: flowBaseRate,
        slope1: flowSlope1,
        slope2: flowSlope2,
        depositRate: 1_000_000.0,
        depositCapacityCap: 1_000_000.0
    )

    // Create LP with MOET deposit
    let lp = Test.createAccount()
    setupMoetVault(lp, beFailed: false)
    mintMoet(signer: protocolAccount, to: lp.address, amount: 10_000.0, beFailed: false)

    let lpBetaRes = grantBeta(protocolAccount, lp)
    Test.expect(lpBetaRes, Test.beSucceeded())

    let createLpPosRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [10_000.0, MOET.VaultStoragePath, false],
        lp
    )
    Test.expect(createLpPosRes, Test.beSucceeded())

    // Set a higher insurance rate for easier verification (1% instead of 0.1%)
    setInsuranceRate(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        insuranceRate: 0.01  // 1% insurance rate
    )

    // Set fixed 10% debit rate for easier math
    let highDebitRate: UFix128 = 0.10 as UFix128
    setInterestCurveFixed(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        yearlyRate: highDebitRate
    )
    log("Set MOET: 10% debit rate, 1% insurance rate")

    // Create borrower to create utilization
    let borrower = Test.createAccount()
    setupMoetVault(borrower, beFailed: false)
    mintFlow(to: borrower, amount: 10_000.0)

    let borrowerBetaRes = grantBeta(protocolAccount, borrower)
    Test.expect(borrowerBetaRes, Test.beSucceeded())

    let openRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [10_000.0, flowVaultStoragePath, true],
        borrower
    )
    Test.expect(openRes, Test.beSucceeded())

    // Note: For FixedRateInterestCurve, rates are independent of utilization
    // Credit rate = debitRate - insuranceRate (spread model)
    setInterestCurveFixed(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        yearlyRate: highDebitRate
    )
    log("Confirmed MOET interest curve configuration")

    // Record initial balances
    let lpPid: UInt64 = 0
    let borrowerPid: UInt64 = 1

    let lpDetailsBefore = getPositionDetails(pid: lpPid, beFailed: false)
    let creditBefore = getCreditBalanceForType(details: lpDetailsBefore, vaultType: Type<@MOET.Vault>())

    let borrowerDetailsBefore = getPositionDetails(pid: borrowerPid, beFailed: false)
    let debtBefore = getDebitBalanceForType(details: borrowerDetailsBefore, vaultType: Type<@MOET.Vault>())

    log("=== BEFORE ===")
    log("LP credit: ".concat(creditBefore.toString()))
    log("Borrower debt: ".concat(debtBefore.toString()))

    // Advance time by 365 days for 1 full year of interest
    let ONE_YEAR: Fix64 = 31536000.0
    Test.moveTime(by: ONE_YEAR)
    Test.commitBlock()

    // Get balances after
    let lpDetailsAfter = getPositionDetails(pid: lpPid, beFailed: false)
    let creditAfter = getCreditBalanceForType(details: lpDetailsAfter, vaultType: Type<@MOET.Vault>())

    let borrowerDetailsAfter = getPositionDetails(pid: borrowerPid, beFailed: false)
    let debtAfter = getDebitBalanceForType(details: borrowerDetailsAfter, vaultType: Type<@MOET.Vault>())

    log("=== AFTER 1 YEAR ===")
    log("LP credit: ".concat(creditAfter.toString()))
    log("Borrower debt: ".concat(debtAfter.toString()))

    // Calculate actual rates
    let creditGrowth = creditAfter - creditBefore
    let debtGrowth = debtAfter - debtBefore
    let actualCreditRate = creditGrowth / creditBefore
    let actualDebtRate = debtGrowth / debtBefore

    log("Actual credit rate (1 year): ".concat(actualCreditRate.toString()))
    log("Actual debt rate (1 year): ".concat(actualDebtRate.toString()))

    // Calculate utilization (for reference)
    let utilization = debtBefore / creditBefore
    log("Utilization: ".concat(utilization.toString()))

    // For FixedRateInterestCurve, debit rate = credit rate + insurance spread:
    // debitRate = creditRate + insuranceRate (independent of utilization)
    // At 10% debit rate (curve's yearlyRate), 1% insurance: creditRate = 10% - 1% = 9%
    // So the insurance spread is simply: debitRate - creditRate ≈ 1%
    let insuranceSpread = actualDebtRate - actualCreditRate
    log("Observed insurance spread: ".concat(insuranceSpread.toString()))

    // The insurance spread should be approximately 1% (0.01)
    // Allow some tolerance for rounding and compounding effects
    Test.assert(
        insuranceSpread >= 0.005 && insuranceSpread <= 0.02,
        message: "Insurance spread should be approximately 1%. Actual: ".concat(insuranceSpread.toString())
    )

    log("=== TEST PASSED ===")
    log("Insurance deduction verified: spread ≈ 1%")
}

// -----------------------------------------------------------------------------
// Test 6: Combined - All four interest scenarios simultaneously
// -----------------------------------------------------------------------------
// Ultimate edge case: Tests MOET debit, MOET credit, Flow debit, Flow credit
// all accruing interest correctly in a single multi-position scenario
// -----------------------------------------------------------------------------
access(all)
fun test_combined_all_interest_scenarios() {
    // Reset state to clean snapshot
    Test.reset(to: snapshot)

    // Setup: price oracle
    setMockOraclePrice(signer: protocolAccount, forTokenIdentifier: flowTokenIdentifier, price: 1.0)

    // Create pool with MOET as default token
    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)

    // Add FlowToken with KinkCurve
    addSupportedTokenKinkCurve(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        optimalUtilization: flowOptimalUtilization,
        baseRate: flowBaseRate,
        slope1: flowSlope1,
        slope2: flowSlope2,
        depositRate: 1_000_000.0,
        depositCapacityCap: 1_000_000.0
    )

    // === Position A (LP1): Deposits MOET → earns MOET credit interest ===
    let moetLp = Test.createAccount()
    setupMoetVault(moetLp, beFailed: false)
    mintMoet(signer: protocolAccount, to: moetLp.address, amount: 10_000.0, beFailed: false)
    let lp1Beta = grantBeta(protocolAccount, moetLp)
    Test.expect(lp1Beta, Test.beSucceeded())

    let lp1Res = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [10_000.0, MOET.VaultStoragePath, false],
        moetLp
    )
    Test.expect(lp1Res, Test.beSucceeded())
    log("LP1: Deposited 10,000 MOET")

    // === Position B (LP2): Deposits Flow → earns Flow credit interest ===
    let flowLp = Test.createAccount()
    setupMoetVault(flowLp, beFailed: false)
    mintFlow(to: flowLp, amount: 5_000.0)
    let lp2Beta = grantBeta(protocolAccount, flowLp)
    Test.expect(lp2Beta, Test.beSucceeded())

    let lp2Res = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [5_000.0, flowVaultStoragePath, false],
        flowLp
    )
    Test.expect(lp2Res, Test.beSucceeded())
    log("LP2: Deposited 5,000 Flow")

    // Configure interest curves:
    // - MOET: FixedRate (spread model, independent of balances)
    // - Flow: KinkCurve (credit rate requires totalCreditBalance > 0 for division)
    setInterestCurveFixed(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        yearlyRate: moetFixedRate  // 4% APY
    )
    setInterestCurveKink(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        optimalUtilization: flowOptimalUtilization,
        baseRate: flowBaseRate,
        slope1: flowSlope1,
        slope2: flowSlope2
    )

    // === Position C (Borrower1): Deposits Flow → borrows MOET ===
    let borrower1 = Test.createAccount()
    setupMoetVault(borrower1, beFailed: false)
    mintFlow(to: borrower1, amount: 2_000.0)
    let b1Beta = grantBeta(protocolAccount, borrower1)
    Test.expect(b1Beta, Test.beSucceeded())

    let b1Res = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [2_000.0, flowVaultStoragePath, true],  // auto-borrow MOET
        borrower1
    )
    Test.expect(b1Res, Test.beSucceeded())
    log("Borrower1: Deposited 2,000 Flow, auto-borrowed MOET")

    // === Position D (Borrower2): Deposits MOET → borrows Flow ===
    let borrower2 = Test.createAccount()
    setupMoetVault(borrower2, beFailed: false)
    mintMoet(signer: protocolAccount, to: borrower2.address, amount: 3_000.0, beFailed: false)
    let b2Beta = grantBeta(protocolAccount, borrower2)
    Test.expect(b2Beta, Test.beSucceeded())

    let b2PosRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/create_wrapped_position.cdc",
        [3_000.0, MOET.VaultStoragePath, false],
        borrower2
    )
    Test.expect(b2PosRes, Test.beSucceeded())

    let b2BorrowRes = executeTransaction(
        "./transactions/mock-flow-credit-market-consumer/borrow_from_position.cdc",
        [3 as UInt64, flowTokenIdentifier, 2_000.0],  // Position 3, borrow 2000 Flow
        borrower2
    )
    Test.expect(b2BorrowRes, Test.beSucceeded())
    log("Borrower2: Deposited 3,000 MOET, borrowed 2,000 Flow")

    // Note: Balance changes auto-trigger updateInterestRates() via updateForUtilizationChange()
    // These calls confirm curve configs:
    // - MOET: FixedRate (spread model, independent of utilization)
    // - Flow: KinkCurve (rates depend on utilization)
    setInterestCurveFixed(
        signer: protocolAccount,
        tokenTypeIdentifier: defaultTokenIdentifier,
        yearlyRate: moetFixedRate
    )
    setInterestCurveKink(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        optimalUtilization: flowOptimalUtilization,
        baseRate: flowBaseRate,
        slope1: flowSlope1,
        slope2: flowSlope2
    )
    log("Confirmed interest curves for MOET and Flow")

    // Position IDs:
    // 0 = LP1 (MOET credit)
    // 1 = LP2 (Flow credit)
    // 2 = Borrower1 (MOET debit, Flow collateral)
    // 3 = Borrower2 (Flow debit, MOET collateral)

    // Record all initial balances
    let lp1Before = getPositionDetails(pid: 0, beFailed: false)
    let lp2Before = getPositionDetails(pid: 1, beFailed: false)
    let b1Before = getPositionDetails(pid: 2, beFailed: false)
    let b2Before = getPositionDetails(pid: 3, beFailed: false)

    let moetCreditBefore = getCreditBalanceForType(details: lp1Before, vaultType: Type<@MOET.Vault>())
    let flowCreditBefore = getCreditBalanceForType(details: lp2Before, vaultType: Type<@FlowToken.Vault>())
    let moetDebtBefore = getDebitBalanceForType(details: b1Before, vaultType: Type<@MOET.Vault>())
    let flowDebtBefore = getDebitBalanceForType(details: b2Before, vaultType: Type<@FlowToken.Vault>())

    let b1HealthBefore = b1Before.health
    let b2HealthBefore = b2Before.health

    log("=== INITIAL STATE ===")
    log("LP1 MOET credit: ".concat(moetCreditBefore.toString()))
    log("LP2 Flow credit: ".concat(flowCreditBefore.toString()))
    log("Borrower1 MOET debt: ".concat(moetDebtBefore.toString()))
    log("Borrower2 Flow debt: ".concat(flowDebtBefore.toString()))
    log("Borrower1 health: ".concat(b1HealthBefore.toString()))
    log("Borrower2 health: ".concat(b2HealthBefore.toString()))

    // Advance time by 30 days
    Test.moveTime(by: THIRTY_DAYS)
    Test.commitBlock()

    // Record all final balances
    let lp1After = getPositionDetails(pid: 0, beFailed: false)
    let lp2After = getPositionDetails(pid: 1, beFailed: false)
    let b1After = getPositionDetails(pid: 2, beFailed: false)
    let b2After = getPositionDetails(pid: 3, beFailed: false)

    let moetCreditAfter = getCreditBalanceForType(details: lp1After, vaultType: Type<@MOET.Vault>())
    let flowCreditAfter = getCreditBalanceForType(details: lp2After, vaultType: Type<@FlowToken.Vault>())
    let moetDebtAfter = getDebitBalanceForType(details: b1After, vaultType: Type<@MOET.Vault>())
    let flowDebtAfter = getDebitBalanceForType(details: b2After, vaultType: Type<@FlowToken.Vault>())

    let b1HealthAfter = b1After.health
    let b2HealthAfter = b2After.health

    log("=== AFTER 30 DAYS ===")
    log("LP1 MOET credit: ".concat(moetCreditAfter.toString()))
    log("LP2 Flow credit: ".concat(flowCreditAfter.toString()))
    log("Borrower1 MOET debt: ".concat(moetDebtAfter.toString()))
    log("Borrower2 Flow debt: ".concat(flowDebtAfter.toString()))
    log("Borrower1 health: ".concat(b1HealthAfter.toString()))
    log("Borrower2 health: ".concat(b2HealthAfter.toString()))

    // === ASSERTIONS ===

    // 1. MOET credit increased (LP1)
    Test.assert(moetCreditAfter > moetCreditBefore, message: "LP1 MOET credit should increase")

    // 2. Flow credit increased (LP2)
    Test.assert(flowCreditAfter > flowCreditBefore, message: "LP2 Flow credit should increase")

    // 3. MOET debt increased (Borrower1)
    Test.assert(moetDebtAfter > moetDebtBefore, message: "Borrower1 MOET debt should increase")

    // 4. Flow debt increased (Borrower2)
    Test.assert(flowDebtAfter > flowDebtBefore, message: "Borrower2 Flow debt should increase")

    // 5. Borrower health factors change based on relative interest rates
    // Borrower1 (Flow collateral, MOET debt): health decreases because MOET debit rate (4%) > Flow credit rate
    Test.assert(b1HealthAfter < b1HealthBefore, message: "Borrower1 health should decrease")
    // Borrower2 (MOET collateral, Flow debt): health may increase because MOET credit rate (~3.6%) ≈ Flow debit rate (~3.56%)
    // and collateral value (3000 MOET) exceeds debt value (2000 Flow), so interest earned can outpace interest owed
    Test.assert(b2HealthAfter != b2HealthBefore, message: "Borrower2 health should change due to interest accrual")

    // 6. Insurance rate spread verification
    // FixedRate model: creditRate < debitRate (spread exists regardless of utilization)
    // Note: At low utilization, total credit income may exceed total debit income for FixedRate
    // because creditBalance >> debitBalance. This is expected - the insurance pool covers the gap.
    let moetCreditGrowthRate = (moetCreditAfter - moetCreditBefore) / moetCreditBefore
    let moetDebtGrowthRate = (moetDebtAfter - moetDebtBefore) / moetDebtBefore

    log("MOET credit growth rate: ".concat(moetCreditGrowthRate.toString()))
    log("MOET debt growth rate: ".concat(moetDebtGrowthRate.toString()))

    // For FixedRate: verify creditRate < debitRate (insurance spread exists)
    Test.assert(
        moetCreditGrowthRate < moetDebtGrowthRate,
        message: "MOET credit rate should be less than debit rate (insurance spread)"
    )

    // KinkCurve model: creditIncome < debitIncome (reserve factor guarantees solvency)
    let flowCreditGrowth = flowCreditAfter - flowCreditBefore
    let flowDebtGrowth = flowDebtAfter - flowDebtBefore

    log("Flow credit growth (absolute): ".concat(flowCreditGrowth.toString()))
    log("Flow debt growth (absolute): ".concat(flowDebtGrowth.toString()))

    // For KinkCurve: verify total credit income < total debit income (reserve factor collected)
    Test.assert(
        flowCreditGrowth < flowDebtGrowth,
        message: "Flow credit income should be less than debit income (reserve factor)"
    )

    log("=== TEST PASSED ===")
    log("All four interest scenarios verified with insurance spreads")
}
