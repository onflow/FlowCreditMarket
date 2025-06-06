import Test
import BlockchainHelpers

import "MOET"

import "test_helpers.cdc"

/*
    Platform integration tests covering the path used by platforms using TidalProtocol to create
    and manage new positions. These tests currently only cover the happy path, ensuring that
    transactions creating & updating positions succeed.
 */

access(all) let protocolAccount = Test.getAccount(0x0000000000000007)

access(all) var snapshot: UInt64 = 0

access(all) let defaultTokenIdentifier = "A.0000000000000007.MOET.Vault"
access(all) let flowTokenIdentifier = "A.0000000000000003.FlowToken.Vault"

access(all) let flowVaultStoragePath = /storage/flowTokenVault

access(all)
fun setup() {
    deployContracts()

    var err = Test.deployContract(
        name: "MockOracle",
        path: "../contracts/mocks/MockOracle.cdc",
        arguments: [defaultTokenIdentifier]
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "MockTidalProtocolConsumer",
        path: "../contracts/mocks/MockTidalProtocolConsumer.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    err = Test.deployContract(
        name: "FungibleTokenStack",
        path: "../../DeFiBlocks/cadence/contracts/connectors/FungibleTokenStack.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all)
fun testDeploymentSucceeds() {
    log("Success: contracts deployed")
}

access(all)
fun testCreatePoolSucceeds() {
    snapshot = getCurrentBlockHeight()

    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)

    let existsRes = executeScript("../scripts/tidal-protocol/pool_exists.cdc", [protocolAccount.address])
    Test.expect(existsRes, Test.beSucceeded())

    let exists = existsRes.returnValue as! Bool
    Test.assert(exists)
}

access(all)
fun testCreateUserPositionSucceeds() {
    Test.reset(to: snapshot)

    // mock setup
    setMockOraclePrice(signer: protocolAccount, forTokenIdentifier: flowTokenIdentifier, price: 1.0)

    // create pool & add FLOW as supported token in globalLedger
    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)
    addSupportedTokenSimpleInterestCurve(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        depositRate: 1_000_000.0,
        depositCapacityCap: 1_000_000.0
    )

    let collateralAmount = 1_000.0 // FLOW

    // configure user account
    let user = Test.createAccount()
    setupMoetVault(user, beFailed: false)
    mintFlow(to: user, amount: collateralAmount)

    // ensure user does not have a MOET balance
    var moetBalance = getBalance(address: user.address, vaultPublicPath: MOET.VaultPublicPath)!
    Test.assertEqual(0.0, moetBalance)

    // ensure there is not yet a position open - fails as there are no open positions yet
    getAvailableBalance(pid: 0, vaultIdentifier: defaultTokenIdentifier, pullFromTopUpSource: false, beFailed: true)
    
    // open the position & push to drawDownSink - forces MOET to downstream test sink which is user's MOET Vault
    let res = executeTransaction("./transactions/mock-tidal-protocol-consumer/create_wrapped_position.cdc",
            [collateralAmount, flowVaultStoragePath, true], // amount, vaultStoragePath, pushToDrawDownSink
            user
        )
    Test.expect(res, Test.beSucceeded())

    // ensure the position is now open
    let pidZeroBalance = getAvailableBalance(pid: 0, vaultIdentifier: defaultTokenIdentifier, pullFromTopUpSource: false, beFailed: false)
    Test.assert(pidZeroBalance > 0.0)

    // ensure MOET has flown to the user's MOET Vault via the VaultSink provided when opening the position
    moetBalance = getBalance(address: user.address, vaultPublicPath: MOET.VaultPublicPath)!
    Test.assert(moetBalance > 0.0)
}

access(all)
fun testUndercollateralizedPositionRebalanceSucceeds() {
    Test.reset(to: snapshot)

    let initialFlowPrice = 1.0
    let priceChange = 0.5
    
    // mock setup
    setMockOraclePrice(signer: protocolAccount, forTokenIdentifier: flowTokenIdentifier, price: initialFlowPrice)

    // create pool & add FLOW as supported token in globalLedger
    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)
    addSupportedTokenSimpleInterestCurve(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        depositRate: 1_000_000.0,
        depositCapacityCap: 1_000_000.0
    )

    let collateralAmount = 1_000.0 // FLOW

    // configure user account
    let user = Test.createAccount()
    setupMoetVault(user, beFailed: false)
    mintFlow(to: user, amount: collateralAmount)


    // open the position & push to drawDownSink - forces MOET to downstream test sink which is user's MOET Vault
    let res = executeTransaction("./transactions/mock-tidal-protocol-consumer/create_wrapped_position.cdc",
            [collateralAmount, flowVaultStoragePath, true], // amount, vaultStoragePath, pushToDrawDownSink
            user
        )
    Test.expect(res, Test.beSucceeded())

    // check how much MOET the user has after borrowing
    let moetBalanceBeforeRebalance = getBalance(address: user.address, vaultPublicPath: MOET.VaultPublicPath)!
    let availableBefore = getAvailableBalance(pid: 0, vaultIdentifier: defaultTokenIdentifier, pullFromTopUpSource: false, beFailed: false)
    let healthBefore = getPositionHealth(pid: 0, beFailed: false)

    // decrease the price of the collateral
    setMockOraclePrice(signer: protocolAccount, forTokenIdentifier: flowTokenIdentifier, price: initialFlowPrice * priceChange)

    // rebalance should pull from the topUpSource
    rebalancePosition(signer: protocolAccount, pid: 0, force: true, beFailed: false)

    let moetBalanceAfterRebalance = getBalance(address: user.address, vaultPublicPath: MOET.VaultPublicPath)!
    let availableAfter = getAvailableBalance(pid: 0, vaultIdentifier: defaultTokenIdentifier, pullFromTopUpSource: false, beFailed: false)
    let healthAfter = getPositionHealth(pid: 0, beFailed: false)
    log("MOET BEFORE: \(moetBalanceBeforeRebalance)")
    log("MOET AFTER: \(moetBalanceAfterRebalance)")
    log("AVAILABLE BEFORE: \(availableBefore)")
    log("AVAILABLE AFTER: \(availableAfter)")
    log("HEALTH BEFORE: \(healthBefore)")
    log("HEALTH AFTER: \(healthAfter)")
}
