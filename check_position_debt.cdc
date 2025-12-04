import "FlowCreditMarket"
import "MOET"
import "FlowToken"

/// Check position balances including debt
///
/// Returns a report showing:
/// - FLOW collateral (credit balance)
/// - MOET debt (debit balance)
/// - Position health
///
access(all)
fun main(pid: UInt64): {String: AnyStruct} {
    let protocolAddress = Type<@FlowCreditMarket.Pool>().address!
    let pool = getAccount(protocolAddress)
        .capabilities.borrow<&FlowCreditMarket.Pool>(FlowCreditMarket.PoolPublicPath)
        ?? panic("Could not borrow Pool")

    let details = pool.getPositionDetails(pid: pid)

    var flowBalance: UFix64 = 0.0
    var flowDirection: String = "None"
    var moetBalance: UFix64 = 0.0
    var moetDirection: String = "None"

    // Parse balances
    for balance in details.balances {
        if balance.vaultType == Type<@FlowToken.Vault>() {
            flowBalance = balance.balance
            flowDirection = balance.direction == FlowCreditMarket.BalanceDirection.Credit ? "Credit (Collateral)" : "Debit (Debt)"
        }
        if balance.vaultType == Type<@MOET.Vault>() {
            moetBalance = balance.balance
            moetDirection = balance.direction == FlowCreditMarket.BalanceDirection.Credit ? "Credit (Collateral)" : "Debit (Debt)"
        }
    }

    return {
        "positionId": pid,
        "flowBalance": flowBalance,
        "flowDirection": flowDirection,
        "moetBalance": moetBalance,
        "moetDirection": moetDirection,
        "health": details.health,
        "defaultTokenAvailable": details.defaultTokenAvailableBalance
    }
}
