import Test
import TidalProtocol from "../contracts/TidalProtocol.cdc"
import FlowToken from 0x1654653399040a61
import MOET from "../contracts/MOET.cdc"
import FungibleToken from 0xf233dcee88fe0abe

access(all) let account = Test.getAccount(0x0000000000000007)

access(all) fun setup() {
    let err = Test.deployContract(
        name: "MOET",
        path: "../contracts/MOET.cdc",
        arguments: [1000000.0] // Initial mint of 1M MOET
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testMOETIntegration() {
    // Create a pool with FlowToken as the default token
    let pool <- TidalProtocol.createPool(
        defaultToken: Type<@FlowToken.Vault>(),
        defaultTokenThreshold: 0.8
    )

    // Add MOET as a supported token
    // Exchange rate: 1 MOET = 1 FLOW (assuming FLOW is worth $1 for simplicity)
    // Liquidation threshold: 0.75 (can borrow up to 75% of MOET collateral value)
    pool.addSupportedToken(
        tokenType: Type<@MOET.Vault>(),
        exchangeRate: 1.0,
        liquidationThreshold: 0.75,
        interestCurve: TidalProtocol.SimpleInterestCurve()
    )

    // Verify MOET is supported
    Test.assert(pool.isTokenSupported(tokenType: Type<@MOET.Vault>()))

    // Check supported tokens
    let supportedTokens = pool.getSupportedTokens()
    Test.assertEqual(supportedTokens.length, 2) // FlowToken and MOET

    // Create a position
    let positionID = pool.createPosition()

    // Mint some FLOW tokens for testing
    let flowVault <- FlowToken.createEmptyVault(vaultType: Type<@FlowToken.Vault>())
    flowVault.deposit(from: <- Test.mintFlowTokens(100.0))

    // Deposit FLOW as collateral
    pool.deposit(pid: positionID, funds: <-flowVault)

    // Verify FLOW deposit
    Test.assertEqual(pool.reserveBalance(type: Type<@FlowToken.Vault>()), 100.0)

    // Borrow MOET against FLOW collateral
    // With 100 FLOW at 0.8 threshold, can borrow up to 80 FLOW worth
    // Since MOET exchange rate is 1:1, can borrow up to 80 MOET
    let moetBorrowed <- pool.withdraw(pid: positionID, amount: 50.0, type: Type<@MOET.Vault>())
    Test.assertEqual(moetBorrowed.balance, 50.0)

    // Check position health
    let health = pool.positionHealth(pid: positionID)
    Test.assert(health > 1.0, message: "Position should be healthy after borrowing")

    // Get position details
    let details = pool.getPositionDetails(pid: positionID)
    Test.assertEqual(details.balances.length, 2) // FLOW credit and MOET debit

    // Find FLOW and MOET balances
    var flowBalance: UFix64 = 0.0
    var moetBalance: UFix64 = 0.0
    var moetDirection: TidalProtocol.BalanceDirection? = nil
    
    for balance in details.balances {
        if balance.type == Type<@FlowToken.Vault>() {
            flowBalance = balance.balance
        } else if balance.type == Type<@MOET.Vault>() {
            moetBalance = balance.balance
            moetDirection = balance.direction
        }
    }

    Test.assertEqual(flowBalance, 100.0) // FLOW collateral
    Test.assertEqual(moetBalance, 50.0) // MOET debt
    Test.assertEqual(moetDirection!, TidalProtocol.BalanceDirection.Debit)

    // Clean up
    destroy moetBorrowed
    destroy pool
}

access(all) fun testMOETAsCollateral() {
    // Create a pool with FlowToken as the default token
    let pool <- TidalProtocol.createPool(
        defaultToken: Type<@FlowToken.Vault>(),
        defaultTokenThreshold: 0.8
    )

    // Add MOET as a supported token
    pool.addSupportedToken(
        tokenType: Type<@MOET.Vault>(),
        exchangeRate: 1.0,
        liquidationThreshold: 0.75,
        interestCurve: TidalProtocol.SimpleInterestCurve()
    )

    // Create a position
    let positionID = pool.createPosition()

    // Get MOET minter and mint some MOET
    let minter = account.storage.borrow<&MOET.Minter>(from: MOET.AdminStoragePath)!
    let moetVault <- minter.mintTokens(amount: 1000.0)

    // Deposit MOET as collateral
    pool.deposit(pid: positionID, funds: <-moetVault)

    // Verify MOET deposit
    Test.assertEqual(pool.reserveBalance(type: Type<@MOET.Vault>()), 1000.0)

    // Borrow FLOW against MOET collateral
    // With 1000 MOET at 0.75 threshold, can borrow up to 750 FLOW worth
    let flowBorrowed <- pool.withdraw(pid: positionID, amount: 500.0, type: Type<@FlowToken.Vault>())
    Test.assertEqual(flowBorrowed.balance, 500.0)

    // Check position health
    let health = pool.positionHealth(pid: positionID)
    Test.assert(health > 1.0, message: "Position should be healthy after borrowing")

    // Clean up
    destroy flowBorrowed
    destroy pool
}

access(all) fun testInvalidTokenOperations() {
    // Create a pool
    let pool <- TidalProtocol.createPool(
        defaultToken: Type<@FlowToken.Vault>(),
        defaultTokenThreshold: 0.8
    )

    // Try to add the same token twice
    pool.addSupportedToken(
        tokenType: Type<@MOET.Vault>(),
        exchangeRate: 1.0,
        liquidationThreshold: 0.75,
        interestCurve: TidalProtocol.SimpleInterestCurve()
    )

    // This should fail
    Test.expectFailure(fun() {
        pool.addSupportedToken(
            tokenType: Type<@MOET.Vault>(),
            exchangeRate: 1.0,
            liquidationThreshold: 0.75,
            interestCurve: TidalProtocol.SimpleInterestCurve()
        )
    }, errorMessageSubstring: "Token type already supported")

    destroy pool
} 