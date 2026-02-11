# LendingPool Implementation

## Overview

The `LendingPool` contract is a simplified lending protocol where users deposit ETH to earn yield and use as collateral, then borrow ETH against their deposited balance. It serves as the main point of interaction for deposit, withdraw, borrow, and repay operations.

## Architecture

### Core Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| `COLLATERAL_FACTOR_BPS` | 8000 (80%) | Maximum borrow amount as a percentage of supplied collateral |
| `BPS` | 10000 | Basis points denominator |

### State Variables

- **`totalSupply`** — Total ETH deposited across all users
- **`totalBorrowed`** — Total ETH currently borrowed
- **`supplyBalance[address]`** — Per-user deposited balance
- **`borrowBalance[address]`** — Per-user outstanding debt

## Functions

### Deposit

```solidity
function deposit() external payable
```

- Accepts ETH via `msg.value`
- Increases user's `supplyBalance` and pool `totalSupply`
- `msg.value` must be > 0 (`InvalidAmount` if zero)

### Withdraw

```solidity
function withdraw(uint256 amount) external
```

- Withdraws `amount` of ETH to the caller
- Requires sufficient `supplyBalance` (`InsufficientBalance`)
- Requires sufficient pool liquidity (`InsufficientLiquidity`) — cannot withdraw more than `totalSupply - totalBorrowed`
- Decreases user's `supplyBalance` and pool `totalSupply`
- Sends ETH via low-level `call`

### Borrow

```solidity
function borrow(uint256 amount) external
```

- Borrows `amount` of ETH against deposited collateral
- Maximum borrow: `supplyBalance[user] * 80%` (collateral factor)
- New borrow must not exceed max (`InsufficientCollateral`)
- Pool must have available liquidity (`InsufficientLiquidity`)
- Increases user's `borrowBalance` and pool `totalBorrowed`
- Sends ETH via low-level `call`

### Repay

```solidity
function repay() external payable
```

- Repays debt using `msg.value`
- Repays up to full debt; excess ETH is refunded to the caller
- Decreases user's `borrowBalance` and pool `totalBorrowed`
- Refunds overpayment via low-level `call`

### View Functions

| Function | Returns | Description |
|----------|---------|-------------|
| `getMaxBorrow(address user)` | `uint256` | Maximum borrowable amount given current supply and existing debt |
| `getAvailableLiquidity()` | `uint256` | `totalSupply - totalBorrowed` |

## Errors

| Error | Condition |
|-------|-----------|
| `InsufficientCollateral` | Borrow would exceed collateral factor |
| `InsufficientLiquidity` | Not enough free ETH in pool for withdraw/borrow |
| `InsufficientBalance` | User balance too low for requested operation |
| `InvalidAmount` | Zero amount passed to deposit/withdraw/borrow/repay |

## Events

- `Deposit(address indexed user, uint256 amount)`
- `Withdraw(address indexed user, uint256 amount)`
- `Borrow(address indexed user, uint256 amount)`
- `Repay(address indexed user, uint256 amount)`

## Security Considerations

- **`receive()`** — Reverts with "Use deposit()" to force explicit deposit flow
- **ETH transfers** — Uses `call` with `require(success)` for transfers and refunds
- **Reentrancy** — State updates occur before external calls where possible (CEI pattern); repay refund happens after state update

## Example Flow

1. User deposits 10 ETH → `supplyBalance = 10`, `totalSupply += 10`
2. User borrows 8 ETH (80% of 10) → `borrowBalance = 8`, `totalBorrowed += 8`
3. User repays 4 ETH → `borrowBalance = 4`, `totalBorrowed -= 4`
4. User can borrow up to 4 more ETH (8 total - 4 repaid)
5. User withdraws 2 ETH (if pool has liquidity) → `supplyBalance = 8`, `totalSupply -= 2`
