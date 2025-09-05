import Test
import BlockchainHelpers

import "MOET"
import "test_helpers.cdc"

// -----------------------------------------------------------------------------
// Pool Creation Workflow Test
// -----------------------------------------------------------------------------
// Validates that a pool can be created and that essential invariants hold.
// -----------------------------------------------------------------------------

access(all) let protocolAccount = Test.getAccount(0x0000000000000007)
access(all) let testerAccount = Test.getAccount(0x0000000000000008)
access(all) var snapshot: UInt64 = 0

// -----------------------------------------------------------------------------
// SETUP
// -----------------------------------------------------------------------------
access(all)
fun setup() {
    deployContracts()

    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)

    let exists = poolExists(address: protocolAccount.address)
    Test.assert(exists)

    // Reserve balance should be zero for default token
    let reserveBal = getReserveBalance(vaultIdentifier: defaultTokenIdentifier)
    Test.assertEqual(0.0, reserveBal)

    snapshot = getCurrentBlockHeight()
}

// -----------------------------------------------------------------------------
// TEST CASES
// -----------------------------------------------------------------------------

access(all)
fun testPositionCreationFail() {

    let txResult = _executeTransaction(
        "../tests/transactions/tidal-protocol/pool-management/01_negative_no_eparticipant_fail.cdc",
        [],
        protocolAccount
    )
    Test.expect(txResult, Test.beFailed())
} 

access(all)
fun testPositionCreationSuccess() {
    Test.reset(to: snapshot)

    let txResult = _executeTransaction(
        "../tests/transactions/tidal-protocol/pool-management/02_positive_with_eparticipant_pass.cdc",
        [],
        protocolAccount
    )

    Test.expect(txResult, Test.beSucceeded())
} 

access(all)
fun testOpenPositionSuccess() {
    Test.reset(to: snapshot)

    let betaTxResult = grantBeta(protocolAccount, testerAccount)

    Test.expect(betaTxResult, Test.beSucceeded())

    let openPositionResult = _executeTransaction("../tests/transactions/tidal-protocol/pool-management/04_open_position_beta.cdc", [], testerAccount)
    Test.expect(openPositionResult, Test.beSucceeded())
}

access(all)
fun testNegativeCap() {
    Test.reset(to: snapshot)

    let negativeResult = _executeTransaction("../tests/transactions/tidal-protocol/pool-management/05_negative_cap.cdc", [], testerAccount)
    Test.expect(negativeResult, Test.beFailed())
}

access(all)
fun testNegativePool() {
    Test.reset(to: snapshot)

    let negativeBetaTxn = Test.Transaction(
        code: Test.readFile("../tests/transactions/tidal-protocol/pool-management/06_negative_pool_check.cdc"),
        authorizers: [protocolAccount.address, testerAccount.address],
        signers: [protocolAccount, testerAccount],
        arguments: []
    )
    let negativeBetaTxResult = Test.executeTransaction(negativeBetaTxn)

    Test.expect(negativeBetaTxResult, Test.beFailed())

    let openPositionResult = _executeTransaction("../tests/transactions/tidal-protocol/pool-management/04_open_position_beta.cdc", [], testerAccount)
    Test.expect(openPositionResult, Test.beFailed())
}
