import "FungibleToken"
import "FlowToken"

import "DeFiActions"
import "DeFiActionsUtils"
import "FlowALP"
import "MOET"
import "FungibleTokenConnectors"
import "FlowALPSchedulerRegistry"

/// Opens a FlowALP position for a given market and registers the position
/// with the liquidation scheduler registry.
///
/// This is a convenience transaction used primarily in E2E tests to ensure
/// positions are discoverable by the Supervisor without modifying core
/// FlowALP storage.
///
/// - `marketID`: logical market identifier already registered via `create_market`.
/// - `amount`: amount of FLOW to deposit as initial collateral.
transaction(marketID: UInt64, amount: UFix64) {
    prepare(signer: auth(BorrowValue, SaveValue, IssueStorageCapabilityController, PublishCapability) &Account) {

        let pool = signer.storage.borrow<auth(FlowALP.EParticipant, FlowALP.EPosition) &FlowALP.Pool>(
            from: FlowALP.PoolStoragePath
        ) ?? panic("open_position_for_market: could not borrow FlowALP.Pool from storage")

        let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
            from: /storage/flowTokenVault
        ) ?? panic("open_position_for_market: could not borrow FlowToken Vault from signer")

        let flowFunds <- vaultRef.withdraw(amount: amount)

        let depositVaultCap = signer.capabilities.get<&{FungibleToken.Vault}>(MOET.VaultPublicPath)
        assert(
            depositVaultCap.check(),
            message: "open_position_for_market: invalid MOET Vault public capability; ensure Vault is configured"
        )

        let depositSink = FungibleTokenConnectors.VaultSink(
            max: UFix64.max,
            depositVault: depositVaultCap,
            uniqueID: nil
        )

        // Create the FlowALP position and immediately rebalance for the provided collateral.
        let pid = pool.createPosition(
            funds: <-flowFunds,
            issuanceSink: depositSink,
            repaymentSource: nil,
            pushToDrawDownSink: false
        )
        pool.rebalancePosition(pid: pid, force: true)

        // Register the new position with the scheduler registry under the given market.
        FlowALPSchedulerRegistry.registerPosition(marketID: marketID, positionID: pid)
    }
}


