import Test
import BlockchainHelpers

import "MOET"
import "test_helpers.cdc"

access(all) let protocolAccount = Test.getAccount(0x0000000000000007)

access(all)
fun setup() {
    deployContracts()
    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)
}

// -----------------------------------------------------------------------------
// Test: collectInsurance full success flow with formula verification
// Full flow: deposit to create credit → advance time → collect insurance
// → verify MOET returned, reserves reduced, timestamp updated, and formula
// Formula: insuranceAmount = totalCreditBalance * insuranceRate * (timeElapsed / secondsPerYear)
//
// This test runs in isolation (separate file) to ensure totalCreditBalance
// equals exactly the depositAmount without interference from other tests.
// -----------------------------------------------------------------------------
access(all)
fun test_collectInsurance_success_fullAmount() {
    // setup user and create a position with deposit
    let user = Test.createAccount()
    setupMoetVault(user, beFailed: false)
    mintMoet(signer: protocolAccount, to: user.address, amount: 1000.0, beFailed: false)

    // create position with 500.0 deposit - totalCreditBalance = 500.0 (isolated test)
    grantPoolCapToConsumer()
    createWrappedPosition(signer: user, amount: 500.0, vaultStoragePath: MOET.VaultStoragePath, pushToDrawDownSink: false)

    // setup protocol account with MOET vault for the swapper
    setupMoetVault(protocolAccount, beFailed: false)
    mintMoet(signer: protocolAccount, to: protocolAccount.address, amount: 10000.0, beFailed: false)

    // configure insurance swapper (1:1 ratio)
    let swapperResult = setInsuranceSwapper(signer: protocolAccount, tokenTypeIdentifier: defaultTokenIdentifier, priceRatio: 1.0)
    Test.expect(swapperResult, Test.beSucceeded())

    // set insurance rate (10% annual)
    let rateResult = setInsuranceRate(signer: protocolAccount, tokenTypeIdentifier: defaultTokenIdentifier, insuranceRate: 0.1)
    Test.expect(rateResult, Test.beSucceeded())

    // initial insurance and reserves
    let initialInsuranceBalance = getInsuranceFundBalance()
    Test.assertEqual(0.0, initialInsuranceBalance)
    let reserveBalanceBefore = getReserveBalance(vaultIdentifier: defaultTokenIdentifier)
    Test.assert(reserveBalanceBefore > 0.0, message: "Reserves should exist after deposit")

    // record timestamp before advancing time
    let timestampBefore = getBlockTimestamp()

    Test.moveTime(by: 31536000.0) // 1 year

    collectInsurance(signer: protocolAccount, tokenTypeIdentifier: defaultTokenIdentifier, beFailed: false)

    // verify insurance was collected, reserves decreased
    let finalInsuranceBalance = getInsuranceFundBalance()
    Test.assert(finalInsuranceBalance > 0.0, message: "Insurance fund should have received MOET")
    let reserveBalanceAfter = getReserveBalance(vaultIdentifier: defaultTokenIdentifier)
    Test.assert(reserveBalanceAfter < reserveBalanceBefore, message: "Reserves should have decreased after collection")

    // verify the amount withdrawn from reserves equals the insurance fund balance (1:1 swap ratio)
    let amountWithdrawnFromReserves = reserveBalanceBefore - reserveBalanceAfter
    Test.assertEqual(amountWithdrawnFromReserves, finalInsuranceBalance)

    // verify lastInsuranceCollection was updated to current block timestamp
    let currentTimestamp = getBlockTimestamp()
    let lastCollection = getLastInsuranceCollection(tokenTypeIdentifier: defaultTokenIdentifier)
    Test.assertEqual(currentTimestamp, lastCollection!)

    // verify formula: insuranceAmount = totalCreditBalance * insuranceRate * (timeElapsed / secondsPerYear)
    // Expected: 500.0 * 0.1 * (31536000.0 / 31536000.0) = 50.0 MOET
    let expectedAmount: UFix64 = 50.0

    // collection is limited by reserve balance - verify we got min(expected, reserves)
    if reserveBalanceBefore >= expectedAmount {
        // reserves sufficient - collected should match expected (within 1% for rounding)
        Test.assert(finalInsuranceBalance >= expectedAmount * 0.99, message: "Collected should match expected (lower)")
        Test.assert(finalInsuranceBalance <= expectedAmount * 1.01, message: "Collected should match expected (upper)")
    } else {
        // reserves insufficient - collected equals available reserves
        Test.assertEqual(reserveBalanceBefore, finalInsuranceBalance)
    }
}
