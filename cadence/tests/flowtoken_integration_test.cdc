import Test
import "TidalProtocol"
import "FlowToken"
import "FungibleToken"
import "MOET"

access(all) fun setup() {
    // Deploy contracts in correct order
    var err = Test.deployContract(
        name: "DFB",
        path: "../../DeFiBlocks/cadence/contracts/interfaces/DFB.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
    
    err = Test.deployContract(
        name: "MOET",
        path: "../contracts/MOET.cdc",
        arguments: [1000000.0]
    )
    Test.expect(err, Test.beNil())
    
    err = Test.deployContract(
        name: "TidalProtocol",
        path: "../contracts/TidalProtocol.cdc",
        arguments: []
    )
    Test.expect(err, Test.beNil())
}

access(all) fun testFlowTokenIntegration() {
    // Create a pool with FlowToken as the default token
    let pool <- TidalProtocol.createPool(
        defaultToken: Type<@FlowToken.Vault>(),
        defaultTokenThreshold: 0.8
    )
    let poolRef = &pool as auth(TidalProtocol.EPosition, TidalProtocol.EGovernance) &TidalProtocol.Pool

    // Add MOET as a supported token
    poolRef.addSupportedToken(
        tokenType: Type<@MOET.Vault>(),
        exchangeRate: 1.0,
        liquidationThreshold: 0.75,
        interestCurve: TidalProtocol.SimpleInterestCurve()
    )

    // Verify both tokens are supported
    Test.assert(poolRef.isTokenSupported(tokenType: Type<@FlowToken.Vault>()))
    Test.assert(poolRef.isTokenSupported(tokenType: Type<@MOET.Vault>()))
    
    let supportedTokens = poolRef.getSupportedTokens()
    Test.assertEqual(supportedTokens.length, 2)

    // Create a position
    let positionID = poolRef.createPosition()
    Test.assertEqual(positionID, UInt64(0))

    // Test basic pool functionality
    let health = poolRef.positionHealth(pid: positionID)
    Test.assert(health >= 1.0, message: "New position should be healthy")

    destroy pool
}

access(all) fun testFlowTokenType() {
    // Simple test to verify FlowToken type can be referenced
    // This avoids inline code while still testing FlowToken availability
    
    let flowTokenType = Type<@FlowToken.Vault>()
    let moetType = Type<@MOET.Vault>()
    
    // Verify types are different
    Test.assertNotEqual(flowTokenType, moetType)
    
    // Create a pool with FlowToken
    let pool <- TidalProtocol.createPool(
        defaultToken: flowTokenType,
        defaultTokenThreshold: 0.8
    )
    
    // Verify the pool was created with FlowToken
    let supportedTokens = pool.getSupportedTokens()
    Test.assertEqual(supportedTokens.length, 1)
    Test.assertEqual(supportedTokens[0], flowTokenType)
    
    destroy pool
}

access(all) fun testPoolWithFlowTokenAndMOET() {
    // Create a pool that uses FlowToken as base and can accept MOET
    let pool <- TidalProtocol.createPool(
        defaultToken: Type<@FlowToken.Vault>(),
        defaultTokenThreshold: 0.8
    )
    let poolRef = &pool as auth(TidalProtocol.EPosition, TidalProtocol.EGovernance) &TidalProtocol.Pool

    // Add MOET with a specific exchange rate
    poolRef.addSupportedToken(
        tokenType: Type<@MOET.Vault>(),
        exchangeRate: 0.5,  // 1 MOET = 0.5 FLOW
        liquidationThreshold: 0.7,
        interestCurve: TidalProtocol.SimpleInterestCurve()
    )

    // Create a position
    let positionID = poolRef.createPosition()
    
    // Check that we can query the pool's state
    Test.assertEqual(poolRef.reserveBalance(type: Type<@FlowToken.Vault>()), 0.0)
    Test.assertEqual(poolRef.reserveBalance(type: Type<@MOET.Vault>()), 0.0)
    
    destroy pool
} 