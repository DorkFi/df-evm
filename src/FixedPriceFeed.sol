// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/// @title FixedPriceFeed
/// @notice Minimal AggregatorV3-compatible feed that always returns a fixed USD price (8 decimals).
/// @dev Used for WAD ($1) on Base mainnet until a dedicated Chainlink feed exists.
contract FixedPriceFeed is AggregatorV3Interface {
    uint8 public constant override decimals = 8;

    int256 private immutable _answer;
    string private _description;

    constructor(int256 answer_, string memory description_) {
        require(answer_ > 0, "FixedPriceFeed: answer");
        _answer = answer_;
        _description = description_;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return _latest();
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return _latest();
    }

    function _latest()
        private
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        // Always "fresh" so ChainlinkOracleRouter stale checks pass.
        return (1, _answer, block.timestamp, block.timestamp, 1);
    }
}
