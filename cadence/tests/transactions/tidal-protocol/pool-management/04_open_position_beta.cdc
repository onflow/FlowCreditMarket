import "FungibleToken"
import "DeFiActions"
import "TidalProtocol"
import "TestHelpers"
import "MOET"
import "DeFiActionsUtils"
import "ClosedBeta"

transaction() {
    prepare(signer: auth(BorrowValue, Storage, Capabilities) &Account) {
        let betaCap: Capability<&{ClosedBeta.IBeta}> =
            signer.capabilities.storage.issue<&{ClosedBeta.IBeta}>(
                ClosedBeta.BetaBadgeStoragePath
            )

        let zero1 <- DeFiActionsUtils.getEmptyVault(Type<@MOET.Vault>())

        let _pos = TidalProtocol.openPosition_beta(
            betaCap: betaCap,
            collateral: <- zero1,
            issuanceSink: TestHelpers.NoopSink(),
            repaymentSource: nil,
            pushToDrawDownSink: false
        )
    }
}
