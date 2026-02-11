// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @notice Minimal interface for borrow-only (SToken) market: mint on borrow, burn on repay.
interface ISToken {
    function mint(address to, uint256 amount) external;
    function burnFrom(address from, uint256 amount) external;
}
