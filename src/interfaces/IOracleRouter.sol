// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title IOracleRouter
/// @notice Interface for price oracle - returns price with 8 decimals (Chainlink-style)
interface IOracleRouter {
    /// @notice Get the price for a market's underlying token
    /// @param marketId The market ID
    /// @return price Price with 8 decimals (e.g. 1e8 = $1)
    /// @return timestamp When the price was last updated
    function getPrice(uint64 marketId) external view returns (uint256 price, uint256 timestamp);
}
