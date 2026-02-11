// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title LendingPoolBase
/// @notice Abstract base with shared lending logic for supply/borrow accounting
/// @dev Children implement asset-specific transfer logic (ETH vs ERC20)
abstract contract LendingPoolBase {
    uint256 public constant COLLATERAL_FACTOR_BPS = 8000; // 80% - can borrow up to 80% of supplied
    uint256 public constant BPS = 10000;

    uint256 public totalSupply;
    uint256 public totalBorrowed;

    mapping(address => uint256) public supplyBalance;
    mapping(address => uint256) public borrowBalance;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Borrow(address indexed user, uint256 amount);
    event Repay(address indexed user, uint256 amount);

    error InsufficientCollateral();
    error InsufficientLiquidity();
    error InsufficientBalance();
    error InvalidAmount();

    /// @dev Pull tokens from user to contract (msg.value for ETH, transferFrom for ERC20)
    function _pull(address from, uint256 amount) internal virtual;

    /// @dev Push tokens from contract to user (call{value} for ETH, transfer for ERC20)
    function _push(address to, uint256 amount) internal virtual;

    /// @dev Execute deposit state updates. Assumes tokens already in contract via _pull.
    function _executeDeposit(address user, uint256 amount) internal {
        if (amount == 0) revert InvalidAmount();

        supplyBalance[user] += amount;
        totalSupply += amount;

        emit Deposit(user, amount);
    }

    /// @dev Execute withdraw state updates. Caller must _push after.
    function _executeWithdraw(address user, uint256 amount) internal {
        if (amount == 0) revert InvalidAmount();
        if (supplyBalance[user] < amount) revert InsufficientBalance();

        uint256 availableSupply = totalSupply - totalBorrowed;
        if (amount > availableSupply) revert InsufficientLiquidity();

        supplyBalance[user] -= amount;
        totalSupply -= amount;

        emit Withdraw(user, amount);
    }

    /// @dev Execute borrow state updates. Caller must _push after.
    function _executeBorrow(address user, uint256 amount) internal {
        if (amount == 0) revert InvalidAmount();

        uint256 maxBorrow = (supplyBalance[user] * COLLATERAL_FACTOR_BPS) / BPS;
        uint256 newBorrow = borrowBalance[user] + amount;

        if (newBorrow > maxBorrow) revert InsufficientCollateral();

        uint256 availableLiquidity = totalSupply - totalBorrowed;
        if (amount > availableLiquidity) revert InsufficientLiquidity();

        borrowBalance[user] = newBorrow;
        totalBorrowed += amount;

        emit Borrow(user, amount);
    }

    /// @dev Execute repay state updates. Returns (repayAmount, excessToRefund).
    /// Caller must _pull(amount) before, and _push(excess) after if excess > 0.
    function _executeRepay(address user, uint256 amount) internal returns (uint256 repayAmount, uint256 excess) {
        if (amount == 0) revert InvalidAmount();

        uint256 debt = borrowBalance[user];
        repayAmount = amount > debt ? debt : amount;

        borrowBalance[user] -= repayAmount;
        totalBorrowed -= repayAmount;

        excess = amount - repayAmount;

        emit Repay(user, repayAmount);
    }

    /// @notice Get user's maximum borrowable amount
    function getMaxBorrow(address user) external view returns (uint256) {
        uint256 maxBorrow = (supplyBalance[user] * COLLATERAL_FACTOR_BPS) / BPS;
        uint256 currentBorrow = borrowBalance[user];
        return maxBorrow > currentBorrow ? maxBorrow - currentBorrow : 0;
    }

    /// @notice Get available liquidity in the pool
    function getAvailableLiquidity() external view returns (uint256) {
        return totalSupply - totalBorrowed;
    }
}
