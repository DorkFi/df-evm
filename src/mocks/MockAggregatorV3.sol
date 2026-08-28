// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";

/// @title MockAggregatorV3
/// @notice Controllable AggregatorV3 for unit tests.
contract MockAggregatorV3 is AggregatorV3Interface {
    uint8 private _decimals;
    int256 public answer;
    uint256 public updatedAt;
    uint80 public roundId = 1;
    uint80 public answeredInRound = 1;
    uint256 public startedAt;

    constructor(uint8 decimals_, int256 initialAnswer) {
        _decimals = decimals_;
        answer = initialAnswer;
        updatedAt = block.timestamp;
        startedAt = block.timestamp;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "MockAggregatorV3";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function setAnswer(int256 newAnswer) external {
        answer = newAnswer;
        updatedAt = block.timestamp;
        roundId += 1;
        answeredInRound = roundId;
    }

    function setUpdatedAt(uint256 ts) external {
        updatedAt = ts;
    }

    function setRound(uint80 roundId_, uint80 answeredInRound_) external {
        roundId = roundId_;
        answeredInRound = answeredInRound_;
    }

    /// @notice For sequencer uptime feeds: answer 0 = up, 1 = down; startedAt = when status began.
    function setSequencerStatus(bool isUp, uint256 startedAt_) external {
        answer = isUp ? int256(0) : int256(1);
        startedAt = startedAt_;
        updatedAt = block.timestamp;
        roundId += 1;
        answeredInRound = roundId;
    }

    function getRoundData(
        uint80
    )
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
