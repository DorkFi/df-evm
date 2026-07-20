# Chainlink Oracle Integration — Implementation Checklist

Tracked plan to replace `MockOracle` with Chainlink Data Feeds on Base via `ChainlinkOracleRouter`.

## Status

| Phase | Status |
|-------|--------|
| A. Design decisions | Done (defaults below) |
| B. Adapter contract | **Done** — `src/ChainlinkOracleRouter.sol` |
| C. Unit + fork tests | **Done** — `test/ChainlinkOracleRouter.t.sol` |
| D. Deploy script / feed constants | **Done** — `script/ChainlinkOracleRouter.s.sol`, `src/libraries/ChainlinkFeeds.sol` |
| E. Base Sepolia cutover | **Partial** — ETH/USD feed verified live on Sepolia (`0x4aDC…7cb1`). Do **not** `setOracle` on the current mock-token pool (USDC/cbBTC/EURC/WAD have no matching feeds). Deploy router standalone for smoke; full cutover waits on real markets. |
| F. UI / docs / mainnet | **Partial** — UI supports `oracleWritable: false` for Chainlink read-only mode; flip after live cutover. |

## Design decisions (locked for MVS)

| Decision | Choice |
|----------|--------|
| Interface | Existing `IOracleRouter` (8-decimal USD + timestamp) |
| Stale policy | Revert if `block.timestamp - updatedAt > maxPriceAge` (default 1h) |
| Fallback owner price | **None** for launch (safer) |
| L2 sequencer | Optional via `setSequencerUptimeFeed`; enable on Base mainnet |
| MVS feeds | WETH→ETH/USD, USDC→USDC/USD, cbETH→cbETH/USD |
| Pool changes | None required; use `setOracle(router)` |

## Files

| Path | Role |
|------|------|
| `src/interfaces/IOracleRouter.sol` | Existing pool oracle interface |
| `src/interfaces/AggregatorV3Interface.sol` | Minimal Chainlink consumer ABI |
| `src/ChainlinkOracleRouter.sol` | Production adapter |
| `src/libraries/ChainlinkFeeds.sol` | Known Base / Base Sepolia proxy addresses |
| `src/mocks/MockAggregatorV3.sol` | Unit-test feed |
| `src/MockOracle.sol` | Kept for local / multi-chain testnet deploys |
| `test/ChainlinkOracleRouter.t.sol` | Unit tests + optional Base fork tests |
| `script/ChainlinkOracleRouter.s.sol` | Deploy + optional `pool.setOracle` |

## Test plan

### Unit (always)

```bash
forge test --match-contract ChainlinkOracleRouterTest -vv
```

Coverage:

- [x] Happy path 8-decimal prices
- [x] Decimal scale up / down
- [x] `FeedNotSet`, `InvalidPrice`, `StalePrice`, `IncompleteRound`
- [x] Sequencer down + grace period
- [x] `onlyOwner` guards

### Fork (Base mainnet RPC)

```bash
forge test --match-contract ChainlinkOracleRouterForkTest --fork-url $BASE_RPC_URL -vv
```

- [ ] Live ETH/USD answer > 0
- [ ] Router `getPrice(0)` returns sane USD band

### Manual Sepolia smoke (after deploy)

- [ ] Deploy router; `setFeed` for available Sepolia feeds
- [ ] `pool.setOracle(router)`
- [ ] Deposit / borrow / repay still succeeds
- [ ] Lower `maxPriceAge` in a throwaway deploy and confirm stale revert

## Cutover steps

### E. Base Sepolia

1. Confirm Sepolia feed proxies on [Chainlink docs](https://docs.chain.link/data-feeds/price-feeds/addresses) (ETH/USD constant exists; USDC/cbETH may be missing — keep MockOracle for those markets or skip).
2. `forge script script/ChainlinkOracleRouter.s.sol:ChainlinkOracleRouterScript --rpc-url base_sepolia --broadcast`
3. Map `marketId`s to feeds (`setFeed`); set `POOL_ADDRESS` to call `setOracle`.
4. Update `base-bl-ui` `chains.ts` `contracts.oracle` for Base Sepolia.
5. Gate / hide mock oracle admin UI when router is live.

### F. Mainnet (post-audit)

1. Re-verify `ChainlinkFeeds` addresses against docs.
2. Deploy with `ENABLE_SEQUENCER=1`, correct `*_MARKET_ID`s, real WETH/cbETH/USDC markets.
3. `POOL_ADDRESS=<pool> forge script ... --rpc-url $BASE_RPC_URL --broadcast`
4. Verify router + pool on Basescan.
5. UI: add Base mainnet to `supportedChainConfigs`; remove faucet / mock price setter.
6. Monitoring: alert on router reverts / stale `updatedAt`.

## Remaining work (not in this PR)

- [ ] Real canonical Base markets (WETH/cbETH/USDC) instead of mintable ATokens
- [ ] External audit of router + pool oracle path
- [ ] Optional: pool-level use of `timestamp` from `getPrice` (router already reverts on stale)
- [ ] Liquidation indexer / subgraph
- [ ] Position NFT (Phase 3)

## Cost note

Chainlink **Data Feeds** on Base: no LINK subscription — only gas for `latestRoundData` external calls during pool accrue. See planning discussion in chat / Base planning spec §4 Oracle Plan.
