// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title ILendingPoolV2
/// @notice Minimal interface for NToken to read balance data from pool (single source of truth)
interface ILendingPoolV2 {
    function getDepositIndex(uint64 marketId) external view returns (uint256);
    function getSupplyBalance(address user, uint64 marketId) external view returns (uint256);
    function getMarketTotalDeposits(uint64 marketId) external view returns (uint256);
    function getScaledDeposits(address user, uint64 marketId) external view returns (uint256);
    function getTotalScaledDeposits(uint64 marketId) external view returns (uint256);
}
