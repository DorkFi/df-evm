# Deployment scripts

## Current targets

| Target          | Profile           | RPC endpoint    | Script |
|-----------------|-------------------|-----------------|--------|
| Base Sepolia    | `base-sepolia`    | `base_sepolia`  | `LendingPoolV2.s.sol` |
| Hedera Testnet  | `hedera-testnet`  | `hedera_testnet`| `LendingPoolV2Hedera.s.sol` |
| Monad Testnet   | `monad-testnet`   | `monad_testnet` | `LendingPoolV2Monad.s.sol` |

## Deploy

Use `FOUNDRY_PROFILE=<profile>` so the correct `chain_id` is used (profiles are in `foundry.toml`). `forge script` does not accept `--profile`; set the env var instead.

**Unified (recommended):**
```bash
source .env
# Base Sepolia (default if DEPLOY_TARGET is unset)
FOUNDRY_PROFILE=base-sepolia DEPLOY_TARGET=base-sepolia forge script script/Deploy.s.sol:DeployScript \
  --rpc-url base_sepolia --broadcast --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)

# Hedera Testnet
FOUNDRY_PROFILE=hedera-testnet DEPLOY_TARGET=hedera-testnet forge script script/Deploy.s.sol:DeployScript \
  --rpc-url hedera_testnet --broadcast --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)

# Monad Testnet
FOUNDRY_PROFILE=monad-testnet DEPLOY_TARGET=monad-testnet forge script script/Deploy.s.sol:DeployScript \
  --rpc-url monad_testnet --broadcast --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)
```

**Per-target:**
```bash
source .env
FOUNDRY_PROFILE=base-sepolia forge script script/LendingPoolV2.s.sol:LendingPoolV2Script \
  --rpc-url base_sepolia --broadcast --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)

FOUNDRY_PROFILE=hedera-testnet forge script script/LendingPoolV2Hedera.s.sol:LendingPoolV2HederaScript \
  --rpc-url hedera_testnet --broadcast --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)

FOUNDRY_PROFILE=monad-testnet forge script script/LendingPoolV2Monad.s.sol:LendingPoolV2MonadScript \
  --rpc-url monad_testnet --broadcast --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)
```

See [DEPLOY.md](./DEPLOY.md) for all commands and troubleshooting (e.g. "default sender" error).

## Adding a new deployment target

1. **Add profile and RPC in `foundry.toml`:**
   ```toml
   [profile.<target-name>]
   chain_id = <chain_id>

   [rpc_endpoints]
   # ... existing ...
   <target_name> = "https://..."
   ```

2. **Add a script** (if the new chain uses a different pool type):
   - Create `script/LendingPoolV2<Chain>.s.sol` that inherits `LendingPoolV2DeployBase`.
   - Deploy your pool (e.g. `LendingPoolV2` or a chain-specific variant), then call `_deployAndConfigureMarkets(pool, oracle)` and `_logDeployResult(...)`.

3. **Wire the unified deployer** in `script/Deploy.s.sol`:
   - Add a branch in `run()` for your target string (e.g. `"my-chain"`).
   - Instantiate your script and call `.run()` (and add it to the "Supported" log message).

4. **Optional:** If the chain uses the same pool as an existing target (e.g. plain `LendingPoolV2`), you can reuse `LendingPoolV2Script` and only add the profile + RPC + one branch in `Deploy.s.sol` that runs `LendingPoolV2Script` with a different log name, or keep one script per chain for clarity.

## Shared logic

- **`LendingPoolV2DeployBase.s.sol`** – Default market params, deployment of aTokens/stoken, market creation, oracle prices, and caps. Extend this for any new pool deployment script.
- **`LendingPoolV2Config.s.sol`** – Configures an existing pool (e.g. with existing token addresses on Base Sepolia). Use for chains where tokens already exist.
