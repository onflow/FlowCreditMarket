import "FlowCreditMarket"
import "FlowToken"
import "FungibleToken"
import "MOET"

/// Repay all debt (if any) and withdraw all available FLOW collateral
///
/// This transaction will:
/// 1. Repay any MOET debt from your MOET vault
/// 2. Withdraw all available FLOW collateral
/// 3. Deposit FLOW to your wallet
///
/// IMPORTANT: You must have enough MOET in your wallet to repay debt
///
transaction() {

    let position: auth(FungibleToken.Withdraw) &FlowCreditMarket.Position
    let flowReceiver: &{FungibleToken.Receiver}
    let moetVault: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}?

    prepare(signer: auth(Storage, Capabilities) &Account) {
        // Get position
        self.position = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowCreditMarket.Position>(
            from: FlowCreditMarket.PositionStoragePath
        ) ?? panic("Could not borrow Position from storage")

        // Get FLOW receiver
        self.flowReceiver = signer.capabilities
            .get<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
            .borrow() ?? panic("Could not borrow FlowToken receiver")

        // Try to get MOET vault (may not exist if no debt)
        self.moetVault = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
            from: MOET.VaultStoragePath
        )
    }

    execute {
        // Step 1: Repay any MOET debt
        if self.moetVault != nil && self.moetVault!.balance > 0.0 {
            let sink = self.position.createSink(type: Type<@MOET.Vault>())
            sink.depositCapacity(from: self.moetVault!)
        }

        // Step 2: Calculate available FLOW collateral
        let availableFlow = self.position.availableBalance(
            type: Type<@FlowToken.Vault>(),
            pullFromTopUpSource: false
        )

        // Step 3: Withdraw all available FLOW
        if availableFlow > 0.0 {
            let withdrawn <- self.position.withdraw(
                type: Type<@FlowToken.Vault>(),
                amount: availableFlow
            )

            // Deposit to wallet
            self.flowReceiver.deposit(from: <-withdrawn)
        }
    }
}
