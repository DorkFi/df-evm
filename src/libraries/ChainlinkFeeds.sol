// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title ChainlinkFeeds
/// @notice Known Chainlink AggregatorV3 proxy addresses for DorkFi Base markets.
/// @dev Verify against https://docs.chain.link/data-feeds/price-feeds/addresses before mainnet use.
library ChainlinkFeeds {
    // -------------------------------------------------------------------------
    // Base mainnet (chainId 8453)
    // -------------------------------------------------------------------------

    /// @dev ETH / USD
    address internal constant BASE_ETH_USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    /// @dev USDC / USD
    address internal constant BASE_USDC_USD = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;

    /// @dev cbETH / USD
    address internal constant BASE_CBETH_USD = 0xd7818272B9e248357d13057AAb0B417aF31E817d;

    /// @dev L2 sequencer uptime feed (https://docs.chain.link/data-feeds/l2-sequencer-feeds)
    address internal constant BASE_SEQUENCER_UPTIME = 0xBCF85224fc0756B9Fa45aA7892530B47e10b6433;

    // -------------------------------------------------------------------------
    // Base Sepolia (chainId 84532) — confirm on docs before relying in prod tests
    // -------------------------------------------------------------------------

    /// @dev ETH / USD (Base Sepolia)
    address internal constant BASE_SEPOLIA_ETH_USD = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;

    // USDC / cbETH feeds on Base Sepolia may be absent or rotate; set via setFeed after deploy.
}
