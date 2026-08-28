# Base mainnet deploy (LendingPoolV2)

Production deploy for canonical Base tokens: **USDC**, **WETH**, **cbBTC**, and **WAD** (SToken). Native ETH (`address(0)`) is not listed — use WETH.

Script: [`script/LendingPoolV2BaseMainnet.s.sol`](../../script/LendingPoolV2BaseMainnet.s.sol)

## Prerequisites

1. Copy `.env.example` → `.env` and set `PRIVATE_KEY` (deployer must have ETH on Base for gas).
2. Prefer a dedicated Base RPC; override if needed:
   ```bash
   export BASE_RPC_URL=https://…
   ```
3. Confirm Chainlink feed addresses in [`src/libraries/ChainlinkFeeds.sol`](../../src/libraries/ChainlinkFeeds.sol) against [Chainlink docs](https://docs.chain.link/data-feeds/price-feeds/addresses?network=base).

## Phase 1 (RBAC + proxy + timelock)

- **Pool** deploys behind `TransparentUpgradeableProxy` via [`src/deploy/DorkFiDeployLib.sol`](../../src/deploy/DorkFiDeployLib.sol).
- **Roles** (`src/access/Roles.sol`): `POOL_ADMIN_ROLE`, `PAUSER_ROLE`, `ORACLE_ADMIN_ROLE`, plus `DEFAULT_ADMIN_ROLE`.
- **Timelock** (optional): set `USE_TIMELOCK=1` and `TIMELOCK_ADMIN=<multisig>` (48h default delay).
- **Direct testnet deploys** (Sepolia/Hedera/Monad): still use `new LendingPoolV2(oracle, msg.sender)` without proxy.

## Market order (IDs)

| ID | Asset | Token | Oracle feed |
|----|-------|-------|-------------|
| 0 | USDC | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` | USDC/USD |
| 1 | WETH | `0x4200000000000000000000000000000000000006` | ETH/USD |
| 2 | cbBTC | `0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf` | BTC/USD |
| 3 | WAD | deployed `SToken` | `FixedPriceFeed` @ `$1` (8 decimals) |

WAD is borrow-only (`setStokenMarketId`). Default deposit cap is `0`; borrow cap is unlimited unless overridden.

## Soft-launch caps (defaults)

Defined in [`src/libraries/BaseMarketParams.sol`](../../src/libraries/BaseMarketParams.sol). Used by default when `USE_SOFT_LAUNCH_CAPS=1` (default).

| Market | Max deposits | Max borrows |
|--------|--------------|-------------|
| USDC | 1,000,000 (6 dec) | 500,000 |
| WETH | 100 | 50 |
| cbBTC | 1 (8 dec) | 0.5 |
| WAD | 0 (borrow-only) | 1,000,000 |

Override via `MAX_TOTAL_DEPOSITS_*` / `MAX_TOTAL_BORROWS_*` env vars, or set `USE_SOFT_LAUNCH_CAPS=0` for unlimited.

## Dry run

```bash
FOUNDRY_PROFILE=base-mainnet forge script \
  script/LendingPoolV2BaseMainnet.s.sol:LendingPoolV2BaseMainnetScript \
  --rpc-url base
```

## Broadcast

```bash
source .env
FOUNDRY_PROFILE=base-mainnet forge script \
  script/LendingPoolV2BaseMainnet.s.sol:LendingPoolV2BaseMainnetScript \
  --rpc-url base \
  --broadcast \
  --private-key $PRIVATE_KEY \
  --sender $(cast wallet address $PRIVATE_KEY)
```

Optional soft-launch caps (example):

```bash
MAX_TOTAL_DEPOSITS_USDC=1000000000000 \   # 1M USDC (6 decimals)
MAX_TOTAL_BORROWS_USDC=500000000000 \
MAX_TOTAL_DEPOSITS_WETH=100000000000000000000 \  # 100 WETH
MAX_TOTAL_BORROWS_WETH=50000000000000000000 \
MAX_TOTAL_DEPOSITS_CBBTC=100000000 \     # 1 cbBTC (8 decimals)
MAX_TOTAL_BORROWS_CBBTC=50000000 \
MAX_TOTAL_BORROWS_WAD=1000000000000 \    # 1M WAD
ENABLE_SEQUENCER=true \
FOUNDRY_PROFILE=base-mainnet forge script ...
```

## After deploy

1. Copy logged addresses into `base-bl-ui` env:
   ```bash
   VITE_LENDING_POOL_ADDRESS_MAINNET=0x…
   VITE_LENDING_ORACLE_MAINNET=0x…
   VITE_WAD_ADDRESS_MAINNET=0x…
   ```
2. Verify contracts on Basescan.
3. Transfer ownership of pool + oracle to multisig.
4. Smoke-test via UI `/debug` → Markets Active, then supply/borrow/repay/mint WAD.
5. Fill the address sheet in [`base-bl-ui/docs/deployment/base-mainnet.md`](../../../base-bl-ui/docs/deployment/base-mainnet.md) (sibling repo).

## Related

- Oracle-only (existing pool): `script/ChainlinkOracleRouter.s.sol`
- UI checklist: `base-bl-ui` → `docs/deployment/base-mainnet.md`
