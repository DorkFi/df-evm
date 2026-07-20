// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IOracleRouter} from "./interfaces/IOracleRouter.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";

/// @title ChainlinkOracleRouter
/// @notice Maps LendingPoolV2 marketIds to Chainlink AggregatorV3 feeds and returns
///         USD prices with 8 decimals (IOracleRouter convention).
/// @dev On Base (and other L2s), optionally set a sequencer uptime feed so prices
///      revert while the sequencer is down or during the post-uptime grace period.
contract ChainlinkOracleRouter is IOracleRouter {
    uint256 public constant PRICE_DECIMALS = 8;

    address public owner;

    /// @notice Max age of a price answer before it is considered stale.
    uint256 public maxPriceAge = 1 hours;

    /// @notice Optional L2 sequencer uptime feed (address(0) = disabled).
    AggregatorV3Interface public sequencerUptimeFeed;

    /// @notice Grace period after sequencer comes back online before prices are usable.
    uint256 public sequencerGracePeriod = 3600;

    mapping(uint64 => AggregatorV3Interface) public feeds;

    error Unauthorized();
    error ZeroAddress();
    error FeedNotSet(uint64 marketId);
    error InvalidPrice();
    error StalePrice(uint256 updatedAt, uint256 maxAge);
    error IncompleteRound();
    error SequencerDown();
    error GracePeriodNotOver(uint256 timeSinceUp, uint256 gracePeriod);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event FeedSet(uint64 indexed marketId, address indexed feed);
    event MaxPriceAgeSet(uint256 maxPriceAge);
    event SequencerUptimeFeedSet(address indexed feed);
    event SequencerGracePeriodSet(uint256 gracePeriod);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    /// @inheritdoc IOracleRouter
    function getPrice(uint64 marketId) external view override returns (uint256 price, uint256 timestamp) {
        _requireSequencerUp();

        AggregatorV3Interface feed = feeds[marketId];
        if (address(feed) == address(0)) revert FeedNotSet(marketId);

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        if (answer <= 0) revert InvalidPrice();
        if (updatedAt == 0 || answeredInRound < roundId) revert IncompleteRound();
        if (block.timestamp - updatedAt > maxPriceAge) {
            revert StalePrice(updatedAt, maxPriceAge);
        }

        uint8 feedDecimals = feed.decimals();
        uint256 raw = uint256(answer);
        if (feedDecimals == PRICE_DECIMALS) {
            price = raw;
        } else if (feedDecimals < PRICE_DECIMALS) {
            price = raw * (10 ** (PRICE_DECIMALS - feedDecimals));
        } else {
            price = raw / (10 ** (feedDecimals - PRICE_DECIMALS));
        }

        timestamp = updatedAt;
    }

    function setFeed(uint64 marketId, address feed) external onlyOwner {
        if (feed == address(0)) revert ZeroAddress();
        feeds[marketId] = AggregatorV3Interface(feed);
        emit FeedSet(marketId, feed);
    }

    function setMaxPriceAge(uint256 maxAge) external onlyOwner {
        maxPriceAge = maxAge;
        emit MaxPriceAgeSet(maxAge);
    }

    function setSequencerUptimeFeed(address feed) external onlyOwner {
        // address(0) disables the check (useful on L1 / test mocks).
        sequencerUptimeFeed = AggregatorV3Interface(feed);
        emit SequencerUptimeFeedSet(feed);
    }

    function setSequencerGracePeriod(uint256 gracePeriod) external onlyOwner {
        sequencerGracePeriod = gracePeriod;
        emit SequencerGracePeriodSet(gracePeriod);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function _requireSequencerUp() internal view {
        AggregatorV3Interface uptime = sequencerUptimeFeed;
        if (address(uptime) == address(0)) return;

        (
            ,
            int256 answer,
            uint256 startedAt,
            ,
        ) = uptime.latestRoundData();

        // answer == 0: sequencer up; answer == 1: sequencer down
        if (answer != 0) revert SequencerDown();

        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= sequencerGracePeriod) {
            revert GracePeriodNotOver(timeSinceUp, sequencerGracePeriod);
        }
    }
}
