## LendingPool

A minimal lending pool contract following the DeFi spec: deposit, withdraw, borrow, and repay ETH.

### Core Functions

- **deposit()** - Deposit ETH into the pool (supply for yield and collateral)
- **withdraw(amount)** - Withdraw deposited ETH
- **borrow(amount)** - Borrow ETH against collateral (up to 80% LTV)
- **repay()** - Repay borrowed ETH (payable)

### Usage

```shell
# Build
forge build

# Test
forge test

# Deploy
forge script script/LendingPool.s.sol:LendingPoolScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Documentation

https://book.getfoundry.sh/
