// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LendingPoolBase} from "./LendingPoolBase.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @title LendingPoolERC20
/// @notice Lending pool for ERC20 tokens - deposit, withdraw, borrow, repay
/// @dev Phase 0 simplified MVP - single asset, no interest
contract LendingPoolERC20 is LendingPoolBase {
    IERC20 public immutable TOKEN;

    constructor(address _token) {
        TOKEN = IERC20(_token);
    }

    /// @dev Pull tokens from user via transferFrom
    function _pull(address from, uint256 amount) internal override {
        require(TOKEN.transferFrom(from, address(this), amount), "Transfer failed");
    }

    /// @dev Push tokens to user via transfer
    function _push(address to, uint256 amount) internal override {
        if (amount > 0) {
            require(TOKEN.transfer(to, amount), "Transfer failed");
        }
    }

    /// @notice Deposit ERC20 tokens into the pool to use as collateral
    /// @param amount Amount to deposit (caller must approve this contract first)
    function deposit(uint256 amount) external {
        _pull(msg.sender, amount);
        _executeDeposit(msg.sender, amount);
    }

    /// @notice Withdraw ERC20 tokens from the pool
    function withdraw(uint256 amount) external {
        _executeWithdraw(msg.sender, amount);
        _push(msg.sender, amount);
    }

    /// @notice Borrow ERC20 tokens against deposited collateral
    function borrow(uint256 amount) external {
        _executeBorrow(msg.sender, amount);
        _push(msg.sender, amount);
    }

    /// @notice Repay borrowed ERC20 tokens
    /// @param amount Amount to repay (caller must approve this contract first)
    function repay(uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        _pull(msg.sender, amount);
        (, uint256 excess) = _executeRepay(msg.sender, amount);
        if (excess > 0) {
            _push(msg.sender, excess);
        }
    }
}
