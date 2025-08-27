import Test
import "test_helpers.cdc"
import "TidalProtocol"
import "MOET"
import "DeFiActionsMathUtils"

access(all) let flowTokenIdentifier = "A.0000000000000003.FlowToken.Vault"

access(all)
fun setup() {
    deployContracts()

    let protocolAccount = Test.getAccount(0x0000000000000007)

    setMockOraclePrice(signer: protocolAccount, forTokenIdentifier: flowTokenIdentifier, price: 1.0)
    createAndStorePool(signer: protocolAccount, defaultTokenIdentifier: defaultTokenIdentifier, beFailed: false)
    addSupportedTokenSimpleInterestCurve(
        signer: protocolAccount,
        tokenTypeIdentifier: flowTokenIdentifier,
        collateralFactor: 0.8,
        borrowFactor: 1.0,
        depositRate: 1_000_000.0,
        depositCapacityCap: 1_000_000.0
    )
}

access(all)
fun test_liquidation_phase1_quote_and_execute() {
    let pid: UInt64 = 0

    // user setup
    let user = Test.createAccount()
    setupMoetVault(user, beFailed: false)
    transferFlowTokens(to: user, amount: 1000.0)

    // open wrapped position and deposit via existing helper txs
    let openRes = _executeTransaction(
        "./transactions/mock-tidal-protocol-consumer/create_wrapped_position.cdc",
        [1000.0, /storage/flowTokenVault, true],
        user
    )
    Test.expect(openRes, Test.beSucceeded())

    // health before price drop
    let hBefore = getPositionHealth(pid: pid, beFailed: false)
    let hBeforeUF = DeFiActionsMathUtils.toUFix64Round(hBefore)
    log("[LIQ] Health before price drop: raw=\(hBefore), approx=\(hBeforeUF)")

    // cause undercollateralization
    setMockOraclePrice(signer: Test.getAccount(0x0000000000000007), forTokenIdentifier: flowTokenIdentifier, price: 0.7)
    let hAfterPrice = getPositionHealth(pid: pid, beFailed: false)
    let hAfterPriceUF = DeFiActionsMathUtils.toUFix64Round(hAfterPrice)
    log("[LIQ] Health after price drop: raw=\(hAfterPrice), approx=\(hAfterPriceUF)")

    // quote liquidation
    let quoteRes = _executeScript(
        "../scripts/tidal-protocol/quote_liquidation.cdc",
        [0 as UInt64, Type<@MOET.Vault>().identifier, flowTokenIdentifier]
    )
    Test.expect(quoteRes, Test.beSucceeded())
    let quote = quoteRes.returnValue as! TidalProtocol.LiquidationQuote
    log("[LIQ] Quote: requiredRepay=\(quote.requiredRepay) seizeAmount=\(quote.seizeAmount) newHF=\(quote.newHF)")
    Test.assert(quote.requiredRepay > 0.0)
    Test.assert(quote.seizeAmount > 0.0)

    // execute liquidation
    let liquidator = Test.createAccount()
    setupMoetVault(liquidator, beFailed: false)
    _executeTransaction("../transactions/moet/mint_moet.cdc", [liquidator.address, quote.requiredRepay + 1.0], Test.getAccount(0x0000000000000007))

    let liqBalance = getBalance(address: liquidator.address, vaultPublicPath: /public/moetBalance) ?? 0.0
    log("Liquidator MOET balance after mint: \(liqBalance)")

    let liqRes = _executeTransaction(
        "../transactions/tidal-protocol/pool-management/liquidate_repay_for_seize.cdc",
        [pid, Type<@MOET.Vault>().identifier, flowTokenIdentifier, quote.requiredRepay + 1.0, 0.0],
        liquidator
    )
    Test.expect(liqRes, Test.beSucceeded())

    // health after liquidation
    let hAfterLiq = getPositionHealth(pid: pid, beFailed: false)
    let hAfterLiqUF = DeFiActionsMathUtils.toUFix64Round(hAfterLiq)
    log("[LIQ] Health after liquidation: raw=\(hAfterLiq), approx=\(hAfterLiqUF)")

    // Assert final health ≈ target (1.05e24, allow tolerance for rounding)
    let targetHF = UInt128(1050000000000000000000000)  // 1.05e24
    let tolerance = UInt128(10000000000000000000)  // 0.01e24
    Test.assert(hAfterLiq >= targetHF - tolerance && hAfterLiq <= targetHF + tolerance, message: "Post-liquidation health \(hAfterLiqUF) not at target 1.05")

    // Assert quoted newHF matches actual
    Test.assert(quote.newHF >= targetHF - tolerance && quote.newHF <= targetHF + tolerance, message: "Quoted newHF not at target")

    let detailsAfter = getPositionDetails(pid: pid, beFailed: false)
    Test.assert(detailsAfter.health >= targetHF - tolerance, message: "Health not restored")
}

access(all)
fun test_liquidation_insolvency() {
    let pid: UInt64 = 0

    let user = Test.createAccount()
    setupMoetVault(user, beFailed: false)
    transferFlowTokens(to: user, amount: 1000.0)

    let openRes = _executeTransaction(
        "./transactions/mock-tidal-protocol-consumer/create_wrapped_position.cdc",
        [1000.0, /storage/flowTokenVault, true],
        user
    )
    Test.expect(openRes, Test.beSucceeded())

    // Severe undercollateralization (insolvent)
    setMockOraclePrice(signer: Test.getAccount(0x0000000000000007), forTokenIdentifier: flowTokenIdentifier, price: 0.5)
    let hAfter = getPositionHealth(pid: pid, beFailed: false)
    Test.assert(hAfter < DeFiActionsMathUtils.e24)

    // Quote should suggest full seize and partial repay
    let quoteRes = _executeScript(
        "../scripts/tidal-protocol/quote_liquidation.cdc",
        [pid, Type<@MOET.Vault>().identifier, flowTokenIdentifier]
    )
    Test.expect(quoteRes, Test.beSucceeded())
    let quote = quoteRes.returnValue as! TidalProtocol.LiquidationQuote
    Test.assert(quote.requiredRepay > 0.0)
    Test.assert(quote.seizeAmount == 1000.0)  // Full seize for insolvency

    // Execute
    let keeper = Test.createAccount()
    setupMoetVault(keeper, beFailed: false)
    _executeTransaction("../transactions/moet/mint_moet.cdc", [keeper.address, quote.requiredRepay + 0.00000001], Test.getAccount(0x0000000000000007))

    let liqRes = _executeTransaction(
        "../transactions/tidal-protocol/pool-management/liquidate_repay_for_seize.cdc",
        [pid, Type<@MOET.Vault>().identifier, flowTokenIdentifier, quote.requiredRepay + 0.00000001, 0.0],
        keeper
    )
    Test.expect(liqRes, Test.beSucceeded())

    // Health should be max (zero debt left after partial repay)
    let hFinal = getPositionHealth(pid: pid, beFailed: false)
    log("hFinal: \(DeFiActionsMathUtils.toUFix64Round(hFinal)), hAfter: \(DeFiActionsMathUtils.toUFix64Round(hAfter))")
    Test.assert(hFinal > hAfter, message: "Health not improved after insolvency liquidation")
}

access(all)
fun test_multi_liquidation() {
    let pid: UInt64 = 0

    let user = Test.createAccount()
    setupMoetVault(user, beFailed: false)
    transferFlowTokens(to: user, amount: 1000.0)

    _executeTransaction(
        "./transactions/mock-tidal-protocol-consumer/create_wrapped_position.cdc",
        [1000.0, /storage/flowTokenVault, true],
        user
    )

    // Mild undercollateralization
    setMockOraclePrice(signer: Test.getAccount(0x0000000000000007), forTokenIdentifier: flowTokenIdentifier, price: 0.9)
    let hInitial = getPositionHealth(pid: pid, beFailed: false)
    Test.assert(hInitial < DeFiActionsMathUtils.e24)

    // First partial liquidation (half the required repay)
    let quote1Res = _executeScript(
        "../scripts/tidal-protocol/quote_liquidation.cdc",
        [pid, Type<@MOET.Vault>().identifier, flowTokenIdentifier]
    )
    let quote1 = quote1Res.returnValue as! TidalProtocol.LiquidationQuote

    let keeper1 = Test.createAccount()
    setupMoetVault(keeper1, beFailed: false)
    _executeTransaction("../transactions/moet/mint_moet.cdc", [keeper1.address, quote1.requiredRepay / 2.0 + 10.0], Test.getAccount(0x0000000000000007))

    _executeTransaction(
        "../transactions/tidal-protocol/pool-management/liquidate_repay_for_seize.cdc",
        [pid, Type<@MOET.Vault>().identifier, flowTokenIdentifier, quote1.requiredRepay / 2.0, 0.0],
        keeper1
    )

    let hAfter1 = getPositionHealth(pid: pid, beFailed: false)
    Test.assert(hAfter1 > hInitial && hAfter1 < DeFiActionsMathUtils.e24, message: "Partial liquidation didn't improve health correctly")
    log("hAfter1: \(DeFiActionsMathUtils.toUFix64Round(hAfter1)), hInitial: \(DeFiActionsMathUtils.toUFix64Round(hInitial))")

    let dummy = Test.createAccount()
    let emptyTx = Test.Transaction(
        code: "transaction {}",
        authorizers: [],
        signers: [dummy],
        arguments: []
    )
    Test.executeTransaction(emptyTx)

    // Second liquidation to resolve
    let quote2Res = _executeScript(
        "../scripts/tidal-protocol/quote_liquidation.cdc",
        [pid, Type<@MOET.Vault>().identifier, flowTokenIdentifier]
    )
    let quote2 = quote2Res.returnValue as! TidalProtocol.LiquidationQuote

    let keeper2 = Test.createAccount()
    setupMoetVault(keeper2, beFailed: false)
    _executeTransaction("../transactions/moet/mint_moet.cdc", [keeper2.address, quote2.requiredRepay + 10.0], Test.getAccount(0x0000000000000007))

    _executeTransaction(
        "../transactions/tidal-protocol/pool-management/liquidate_repay_for_seize.cdc",
        [pid, Type<@MOET.Vault>().identifier, flowTokenIdentifier, quote2.requiredRepay, 0.0],
        keeper2
    )

    let hFinal = getPositionHealth(pid: pid, beFailed: false)
    let targetHF = UInt128(1050000000000000000000000)
    Test.assert(hFinal >= targetHF - 10000000000000000000 && hFinal <= targetHF + 10000000000000000000, message: "Final health not at target")
}
