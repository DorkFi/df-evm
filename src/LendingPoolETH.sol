// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LendingPoolBase} from "./LendingPoolBase.sol";

/// @title LendingPoolETH
/// @notice Lending pool for native ETH - deposit, withdraw, borrow, repay
/// @dev Phase 0 simplified MVP - single asset, no interest
contract LendingPoolETH is LendingPoolBase {
    /// @dev ETH arrives with msg.value; no pull needed
    function _pull(address, uint256) internal pure override {
        // ETH already in contract via msg.value
    }

    /// @dev Send ETH to user
    function _push(address to, uint256 amount) internal override {
        (bool success,) = to.call{value: amount}("");
        require(success, "Transfer failed");
    }

    /// @notice Deposit ETH into the pool to use as collateral
    function deposit() external payable {
        if (msg.value == 0) revert InvalidAmount();
        _executeDeposit(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH from the pool
    function withdraw(uint256 amount) external {
        _executeWithdraw(msg.sender, amount);
        _push(msg.sender, amount);
    }

    /// @notice Borrow ETH against deposited collateral
    function borrow(uint256 amount) external {
        _executeBorrow(msg.sender, amount);
        _push(msg.sender, amount);
    }

    /// @notice Repay borrowed ETH
    function repay() external payable {
        if (msg.value == 0) revert InvalidAmount();
        (, uint256 excess) = _executeRepay(msg.sender, msg.value);
        if (excess > 0) {
            _push(msg.sender, excess);
        }
    }

    receive() external payable {
        revert("Use deposit()");
    }
}
