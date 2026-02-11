// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IOracleRouter} from "./interfaces/IOracleRouter.sol";

/// @title MockOracle
/// @notice Mock oracle for testing - returns fixed price (1e8 = $1) for all markets
contract MockOracle is IOracleRouter {
    uint256 public constant PRICE_DECIMALS = 8;

    mapping(uint64 => uint256) public prices;

    /// @notice Set price for a market (for testing)
    function setPrice(uint64 marketId, uint256 price) external {
        prices[marketId] = price;
    }

    /// @inheritdoc IOracleRouter
    function getPrice(uint64 marketId) external view override returns (uint256 price, uint256 timestamp) {
        price = prices[marketId];
        if (price == 0) {
            price = 1e8; // Default $1
        }
        timestamp = block.timestamp;
    }
}
