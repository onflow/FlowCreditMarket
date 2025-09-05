import "FungibleToken"
import "DeFiActions"
import "TidalProtocol"
import "TestHelpers"
import "MOET"
import "DeFiActionsUtils"
import "TidalProtocolClosedBeta"

transaction() {
    prepare(signer: auth(BorrowValue, Storage, Capabilities) &Account) {
        let betaRef = signer.storage.borrow<&{TidalProtocolClosedBeta.IBeta}>(
            from: TidalProtocolClosedBeta.BetaBadgeStoragePath
        ) ?? panic("Beta badge missing on strategies account")

        let zero1 <- DeFiActionsUtils.getEmptyVault(Type<@MOET.Vault>())

        let _pos = TidalProtocol.openPosition_beta(
            betaRef: betaRef,
            collateral: <- zero1,
            issuanceSink: TestHelpers.NoopSink(),
            repaymentSource: nil,
            pushToDrawDownSink: false
        )
    }
}
