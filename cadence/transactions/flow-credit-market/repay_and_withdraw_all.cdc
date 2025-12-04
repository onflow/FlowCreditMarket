import FlowALP from 0x6b00ff876c299c61
import FlowToken from 0x1654653399040a61
import FungibleToken from 0x9a0766d93b6608b7
import MOET from 0x6b00ff876c299c61

/// Repay all debt (if any) and withdraw all available FLOW collateral
///
/// This transaction will:
/// 1. Repay MOET debt from your MOET vault using a Sink (deposits ALL available MOET)
/// 2. Withdraw all available FLOW collateral via Pool methods
/// 3. Deposit FLOW to your wallet
///
/// REQUIREMENTS:
/// - You must have MOET in your wallet to repay debt (the more MOET, the more FLOW you can withdraw)
/// - You must have access to the Pool with EPosition entitlement via:
///   a) Direct ownership (if you own the pool at PoolStoragePath), OR
///   b) A stored capability at PoolCapStoragePath with EPosition entitlement
///
/// BEHAVIOR:
/// - The transaction will deposit ALL MOET from your wallet to repay debt
/// - After repayment, it withdraws the maximum safe amount of FLOW
/// - If your position is at minimum health, you may not be able to withdraw anything
///   until you repay more debt
///
/// IMPORTANT LIMITATION:
/// - If your MOET deposit exceeds the pool's depositLimit (typically 5% of capacity),
///   the repayment will be queued and NOT immediately reduce your debt
/// - This means availableBalance will remain 0 and no FLOW will be withdrawn
/// - To avoid this: verify current MOET depositLimit before running, or split repayment
///   across multiple smaller transactions
///
transaction(pid: UInt64) {

    let pool: auth(FlowALP.EPosition) &FlowALP.Pool
    let flowReceiver: &{FungibleToken.Receiver}
    let moetVault: auth(FungibleToken.Withdraw) &{FungibleToken.Vault}?
    let poolCapForPosition: Capability<auth(FlowALP.EPosition, FlowALP.EParticipant) &FlowALP.Pool>

    prepare(signer: auth(Storage, Capabilities) &Account) {
        // Try to borrow pool directly from storage first (if signer owns the pool)
        // Otherwise, load stored capability
        if let directPool = signer.storage.borrow<auth(FlowALP.EPosition) &FlowALP.Pool>(from: FlowALP.PoolStoragePath) {
            // Signer owns the pool - use direct reference
            self.pool = directPool
            // Issue entitled capability from storage for Position construction
            self.poolCapForPosition = signer.capabilities.storage.issue<auth(FlowALP.EPosition, FlowALP.EParticipant) &FlowALP.Pool>(FlowALP.PoolStoragePath)
        } else {
            // Signer doesn't own pool - must have a stored capability
            let poolCap = signer.storage.copy<Capability<auth(FlowALP.EParticipant, FlowALP.EPosition) &FlowALP.Pool>>(
                from: FlowALP.PoolCapStoragePath
            ) ?? panic("Could not load Pool capability - ensure you have been granted access to the pool")

            self.pool = poolCap.borrow() ?? panic("Could not borrow Pool from capability")

            // Use the same entitled capability for Position construction
            self.poolCapForPosition = poolCap

            // Save it back
            signer.storage.save(poolCap, to: FlowALP.PoolCapStoragePath)
        }

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
        // Step 1: Repay any MOET debt using a Sink
        if self.moetVault != nil && self.moetVault!.balance > 0.0 {
            // Create a Position struct to access createSink() method
            let position = FlowALP.Position(id: pid, pool: self.poolCapForPosition)
            let sink = position.createSink(type: Type<@MOET.Vault>())
            sink.depositCapacity(from: self.moetVault!)
        }

        // Step 2: Calculate available FLOW collateral
        let availableFlow = self.pool.availableBalance(
            pid: pid,
            type: Type<@FlowToken.Vault>(),
            pullFromTopUpSource: false
        )

        // Step 3: Withdraw all available FLOW via Pool
        if availableFlow > 0.0 {
            let withdrawn <- self.pool.withdraw(
                pid: pid,
                amount: availableFlow,
                type: Type<@FlowToken.Vault>()
            )

            // Deposit to wallet
            self.flowReceiver.deposit(from: <-withdrawn)
        }
    }
}
