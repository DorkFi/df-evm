# Deploy commands by target

**Required:** Copy `.env.example` to `.env`, set `PRIVATE_KEY=0x...`, and run from the **project root**. Each broadcast block below runs `source .env` first so `$PRIVATE_KEY` is set before the `forge script` command.

---

## Targets

| Target          | Profile           | RPC endpoint    |
|-----------------|-------------------|-----------------|
| Base Sepolia    | `base-sepolia`    | `base_sepolia`  |
| Hedera Testnet  | `hedera-testnet`  | `hedera_testnet`|

---

## Unified deploy (recommended)

Single entry point: `script/Deploy.s.sol`. Set `DEPLOY_TARGET` to choose the chain.

### Base Sepolia

```bash
source .env
FOUNDRY_PROFILE=base-sepolia DEPLOY_TARGET=base-sepolia forge script script/Deploy.s.sol:DeployScript --rpc-url base_sepolia --broadcast --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)
```

### Hedera Testnet

```bash
source .env
FOUNDRY_PROFILE=hedera-testnet DEPLOY_TARGET=hedera-testnet forge script script/Deploy.s.sol:DeployScript --rpc-url hedera_testnet --broadcast --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)
```

---

## Per-target deploy

Run the script for a specific chain directly (no `DEPLOY_TARGET`).

### Base Sepolia

```bash
source .env
FOUNDRY_PROFILE=base-sepolia forge script script/LendingPoolV2.s.sol:LendingPoolV2Script --rpc-url base_sepolia --broadcast --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)
```

### Hedera Testnet

```bash
source .env
FOUNDRY_PROFILE=hedera-testnet forge script script/LendingPoolV2Hedera.s.sol:LendingPoolV2HederaScript --rpc-url hedera_testnet --broadcast --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)
```

---

## Dry run (no broadcast)

Same commands without `--broadcast`. Simulates and logs transactions.

**Unified:**

```bash
# Base Sepolia
FOUNDRY_PROFILE=base-sepolia DEPLOY_TARGET=base-sepolia forge script script/Deploy.s.sol:DeployScript --rpc-url base_sepolia

# Hedera Testnet
FOUNDRY_PROFILE=hedera-testnet DEPLOY_TARGET=hedera-testnet forge script script/Deploy.s.sol:DeployScript --rpc-url hedera_testnet
```

**Per-target:**

```bash
FOUNDRY_PROFILE=base-sepolia forge script script/LendingPoolV2.s.sol:LendingPoolV2Script --rpc-url base_sepolia

FOUNDRY_PROFILE=hedera-testnet forge script script/LendingPoolV2Hedera.s.sol:LendingPoolV2HederaScript --rpc-url hedera_testnet
```

---

## Overriding the signer

Use a different key (and its sender):

```bash
export MY_KEY=0x...
forge script script/Deploy.s.sol:DeployScript --rpc-url base_sepolia --broadcast --private-key $MY_KEY --sender $(cast wallet address $MY_KEY)
```

Or inline:

```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url base_sepolia --broadcast --private-key 0x... --sender 0x<address_for_that_key>
```

---

## Notes

- Use `FOUNDRY_PROFILE`, not `--profile`; `forge script` does not accept `--profile`.
- RPC URLs are defined in `foundry.toml` under `[rpc_endpoints]`.
- To add a new target or understand shared logic, see [README.md](./README.md).

---

## "Foundry's default sender" error

If you see **"You seem to be using Foundry's default sender. Be sure to set your own --sender"**:

1. Set `PRIVATE_KEY=0x...` in `.env` at the project root and run from the project root (Foundry loads `.env` from cwd), **or**
2. Use the same pattern as the deploy blocks: `source .env` then the forge command with `--private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)`.
