import "FungibleToken"
import "DeFiActions"
import "TidalProtocol"
import "TestHelpers"
import "MOET"
import "DeFiActionsUtils"

transaction() {
    prepare(signer: auth(BorrowValue, Storage, Capabilities) &Account) {
        let betaCap: Capability<&{TidalProtocol.PoolBeta}> =
            signer.capabilities.storage.issue<&{TidalProtocol.PoolBeta}>(
                TidalProtocol.BetaBadgeStoragePath
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
