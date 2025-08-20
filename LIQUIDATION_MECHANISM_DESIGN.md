## Tidal Protocol — Production Liquidation Mechanism (DEX + Auction + Hybrid)

### Objectives
- **Safety**: Permissionless, incentive-aligned liquidations that reliably resolve undercollateralized positions.
- **Coverage**: Dual paths — a direct repay-for-seize (external DEX usage by liquidator) and a protocol-executed DEX path — with an auction fallback for large/illiquid cases.
- **Determinism**: Predictable math, oracle guards, and invariant checks.
- **Observability**: Rich events and view endpoints for keepers/frontends.

### Current foundations (in contract)
- **Risk math**: `healthFactor`, `effectiveCollateral`, `effectiveDebt`, per-token factors; `RiskParams` includes `liquidationBonus`.
- **Position config**: `InternalPosition` has `minHealth`, `targetHealth`, `maxHealth`, optional `topUpSource` and `drawDownSink`.
- **Oracle connectors**: `DeFiActions.PriceOracle` (Band Oracle impl supports staleness checks).

### Out-of-scope for this phase
- Multi-oracle medianization (can be added later).
- Insurance module for bad debt (can be added later, we expose hooks).

## Architecture

### Liquidation paths
- **Permissionless repay-for-seize**: A keeper repays a portion of the borrower’s debt and receives collateral with a bonus. Caller can source tokens via any external venue.
- **Protocol-executed DEX**: Protocol seizes collateral, swaps via allowlisted DEX connector into debt asset, repays debt, and returns any remainder appropriately.
- **Auction fallback (Dutch)**: When DEX liquidity is insufficient or positions are large, run a Dutch auction on a seized collateral lot; bidders pay debt asset to receive collateral.

### Hybrid routing policy
1) Attempt `topUpSource` pull if present to restore health to `minHealth`.
2) If still unhealthy: allow permissionless `repay-for-seize` at any time.
3) If no takers or keeper chooses: allow `liquidateViaDex` within slippage bounds.
4) If inadequate or for large/illiquid positions: `startAuction`, allow `takeAuction` until settled.

## Governance parameters
- **Per-token (or global defaults)**
  - **collateralFactor** (exists)
  - **borrowFactor** (exists)
  - **liquidationBonus** (exists; percent added to seize quote)
  - **twapWindowSec**, **maxDeviationBps** (oracle guards)
  - **dustThresholdCredit**, **dustThresholdDebt**
- **Global**
  - **liquidationThresholdHF** (default ≥ 1.0e18 or equals `minHealth`)
  - **closeFactorBps** (max fraction of debt that can be liquidated per call)
  - **postLiquidationTargetHF** (target HF after a liquidation step)
  - **dexMaxSlippageBps**, **dexMaxRouteHops**
  - **auction**: `durationSec`, `startDiscountBps`, `minTakeSize`, `minBidIncreaseBps`, `kickerBountyBps`
  - **fees**: `protocolLiquidationFeeBps`, `keeperBountyBps`, `feeSink`
  - **connector allowlists**: `allowedSwappers`, `allowedOracles` (by component ID)
  - **circuit breakers**: `liquidationsPaused`

### Storage additions
- **`liquidationParams`** struct stored in pool.
- **`activeAuctions: {UInt64: Auction}`** mapping by position id.
- **Connector allowlists** and **fee sink** capability path.

### Events
- **LiquidationParamsUpdated**
- **LiquidationExecuted**(pid, liquidator, debtType, repayAmount, seizeType, seizeAmount, bonusBps, newHF)
- **LiquidationExecutedViaDex**(pid, seizeType, seized, debtType, repaid, slippageBps, newHF)
- **AuctionStarted**(pid, lotType, lotAmount, startPrice, endTime, kicker)
- **AuctionTaken**(pid, taker, lotAmount, debtPaid, price)
- **AuctionSettled**(pid, debtRepaid, lotSold)
- **AuctionCancelled**(pid)
- **BadDebtWrittenOff**(pid, shortfall)
- **LiquidationsPaused / LiquidationsUnpaused**(by)

## Math and quoting (pure helpers)
- **Eligibility**: `health(view) < liquidationThresholdHF`.
- **Max repay per call**:
  - Clamp by `closeFactorBps` and by amount needed to reach `postLiquidationTargetHF`.
- **Seize for repay** (single collateral type):
  - Let `R = repayTrueAmount` in debt token, `P_d = price(debt)`, `P_c = price(collateral)`, `BF = borrowFactor(debt)`, `CF = collateralFactor(collateral)`, `LB = (1 + liquidationBonus)`.
  - Debt value basis = `(R * P_d) / BF`.
  - Seize amount = `DebtValue * LB / (P_c * CF)`.
- **Collateral selection**: choose collateral with highest effective value and available balance, unless a hint is provided.
- **Quote**: `quoteLiquidation(pid, debtType, seizeType?) -> {repayCap, seizeType, seizeAmount, newHF}`.

## Entrypoints (new public API)
- **View**
  - `isLiquidatable(pid) -> Bool`
  - `quoteLiquidation(pid, debtType, seizeType?) -> Quote`
  - `positionAuction(pid) -> AuctionView?`
  - `getLiquidationParams() -> LiquidationParams`
- **Permissionless actions**
  - `liquidateRepayForSeize(pid, debtType, repayAmount, seizeType, minSeizeAmount)`
  - `startAuction(pid, lotType?, lotAmountHint?)`
  - `takeAuction(pid, maxDebtPay, minLotReceive)`
  - `settleAuction(pid)`
- **Keeper/governance**
  - `liquidateViaDex(pid, debtType, seizeType, maxSeizeAmount, minRepayAmount, routeParams)`
  - `setLiquidationParams(params)`
  - `setConnectorAllowlists(swappers, oracles)`
  - `setFeeSink(sink)`
  - `pauseLiquidations(flag)`

## Execution flows

### Repay-for-seize (permissionless)
- Preconditions: liquidations not paused; fresh indices for involved tokens; oracle staleness/deviation checks; `health < threshold`.
- Steps:
  - Compute `maxRepay`; clamp user input.
  - Transfer `repayActual` debt token from liquidator; reduce position debt.
  - Compute `seizeAmount` with bonus; withdraw from position’s collateral; transfer to liquidator.
  - Apply fees/bounties from seized amount if configured; emit `LiquidationExecuted`.
- Postconditions: health increases; no negative balances; dust rules applied.

### Via DEX (protocol executes swap)
- Preconditions: same as above + swapper allowlisted + slippage bounds.
- Steps:
  - Seize up to `maxSeizeAmount` collateral to an internal temporary vault.
  - Swap seized collateral → debt token via `SwapConnectors.Swapper` with `minOut` based on slippage.
  - Repay debt with swap output; handle any leftover collateral (return to position or fees/sink per params).
  - Emit `LiquidationExecutedViaDex`.
- Security: snapshot → seize → external call → state mutate → emit; never pass borrower’s resources directly out.

### Dutch auction (fallback)
- Kick: `startAuction` when under threshold and no active auction. Move a lot of collateral to the auction resource; pay kicker bounty from the lot.
- Price curve: debt-per-unit-collateral decays from a premium to minimum over `durationSec`.
- Take: bidder pays debt token, receives lot portion at current price; position debt decreases.
- Settle: when lot sold out or time ended; if shortfall remains and no collateral, emit `BadDebtWrittenOff` and (optionally) charge reserve/insurance module.

## Oracle safety and indices
- Use oracle with `staleThreshold`, per-token TWAP window, and `maxDeviationBps` guard vs last snapshot.
- Accrue interest indices for involved tokens on-demand before quoting/execution.

## Invariants and safety checks
- Liquidation only when `health < threshold` and not paused.
- Post-liquidation: `health ≥ pre.health`.
- Balances never negative; dust thresholds applied.
- Fees ≤ seized amount; fee sink receives expected amount.
- Throttles: per-tx close factor, optional per-block liquidation cap, single active auction per pid.

## Scripts and transactions to add
- Scripts: `quote_liquidation.cdc`, `get_liquidation_params.cdc`, `get_auction_state.cdc`.
- Transactions: `liquidate_repay_for_seize.cdc`, `liquidate_via_dex.cdc`, `start_auction.cdc`, `take_auction.cdc`, `settle_auction.cdc`.
- Governance tx: `set_liquidation_params.cdc`, `allow_swapper.cdc`, `pause_liquidations.cdc`.

## Testing strategy
- Unit (pure math): seize calculation vectors; HF monotonic increase on liquidation; close-factor clamping; rounding bias toward protocol.
- Scenarios: price drop → repay-for-seize; large position → partial DEX + auction; stale oracle rejection; top-up source prevents liquidation; bad-debt write-off path.
- Fuzz/property: random portfolios and prices; repeated partial liquidations; assert invariants each step.

## Rollout phases
- **Phase 1**: Params + view quotes + `liquidateRepayForSeize` + tests/events.
- **Phase 2**: `liquidateViaDex` with an allowlisted swapper + slippage guards + tests.
- **Phase 3**: Dutch auction engine + keeper flows + tests.
- **Phase 4**: Oracle deviation guards, fee sinks, monitoring dashboards.
- **Phase 5**: Security review, gas profiling, parameter calibration.

## Open questions
- Single-asset seize per call vs multi-asset? (recommend single per call)
- Target HF after liquidation: `minHealth` or `targetHealth`?
- Fee model: seize-based fee vs spread-sharing; split and sink specifics.
- Reserve/insurance module hookup for bad debt.


