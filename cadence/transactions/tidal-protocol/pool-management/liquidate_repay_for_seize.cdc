import "FungibleToken"
import "FlowToken"

import "TidalProtocol"
import "MOET"

/// Liquidate a position by repaying exactly the required amount to reach target HF and seizing collateral
/// debtVaultIdentifier: e.g., Type<@MOET.Vault>().identifier
/// seizeVaultIdentifier: e.g., Type<@FlowToken.Vault>().identifier
transaction(pid: UInt64, debtVaultIdentifier: String, seizeVaultIdentifier: String, maxRepayAmount: UFix64, minSeizeAmount: UFix64) {
    let pool: &TidalProtocol.Pool
    let receiver: &{FungibleToken.Receiver}
    let debtType: Type
    let seizeType: Type
    let requiredRepay: UFix64
    let repay: @{FungibleToken.Vault}

    prepare(signer: auth(BorrowValue, SaveValue, IssueStorageCapabilityController, PublishCapability, UnpublishCapability) &Account) {
        let protocolAddress = Type<@TidalProtocol.Pool>().address!
        self.pool = getAccount(protocolAddress).capabilities.borrow<&TidalProtocol.Pool>(TidalProtocol.PoolPublicPath)
            ?? panic("Could not borrow Pool at \(TidalProtocol.PoolPublicPath)")

        // Resolve types
        self.debtType = CompositeType(debtVaultIdentifier) ?? panic("Invalid debtVaultIdentifier: \(debtVaultIdentifier)")
        self.seizeType = CompositeType(seizeVaultIdentifier) ?? panic("Invalid seizeVaultIdentifier: \(seizeVaultIdentifier)")

        // Quote required repay and seize amounts
        let quote = self.pool.quoteLiquidation(pid: pid, debtType: self.debtType, seizeType: self.seizeType)
        assert(quote.requiredRepay > 0.0, message: "Nothing to liquidate")
        assert(quote.seizeAmount >= minSeizeAmount, message: "Seize below minimum")
        self.requiredRepay = quote.requiredRepay

        // Withdraw exactly requiredRepay, honoring maxRepayAmount and available balance
        assert(maxRepayAmount >= self.requiredRepay, message: "Max repay too low")
        var tmpRepay: @{FungibleToken.Vault}? <- nil
        if self.debtType == Type<@MOET.Vault>() {
            let repayVaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: MOET.VaultStoragePath)
                ?? panic("No MOET vault in storage")
            assert(repayVaultRef.balance >= self.requiredRepay, message: "Insufficient MOET balance for required repay")
            tmpRepay <-! repayVaultRef.withdraw(amount: self.requiredRepay)
        }
        if tmpRepay == nil && self.debtType == Type<@FlowToken.Vault>() {
            let repayVaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: /storage/flowTokenVault)
                ?? panic("No Flow vault in storage")
            assert(repayVaultRef.balance >= self.requiredRepay, message: "Insufficient Flow balance for required repay")
            tmpRepay <-! repayVaultRef.withdraw(amount: self.requiredRepay)
        }
        assert(tmpRepay != nil, message: "Unsupported debt token type for demo transaction")
        self.repay <- tmpRepay!

        // Receiver for seized collateral (supports Flow or MOET in demo)
        let flowRecv = signer.capabilities.borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
        let moetRecv = signer.capabilities.borrow<&{FungibleToken.Receiver}>(MOET.ReceiverPublicPath)
        assert(flowRecv != nil || moetRecv != nil, message: "Missing receiver for seized tokens")
        if flowRecv != nil {
            self.receiver = flowRecv!
        } else {
            self.receiver = moetRecv!
        }
    }

    execute {
        // Execute liquidation; get seized collateral vault
        let seized <- self.pool.liquidateRepayForSeize(
            pid: pid,
            debtType: self.debtType,
            maxRepayAmount: self.requiredRepay,
            seizeType: self.seizeType,
            minSeizeAmount: minSeizeAmount,
            from: <-self.repay
        )

        // Deposit seized assets to signer's receiver
        self.receiver.deposit(from: <-seized)
    }
}
