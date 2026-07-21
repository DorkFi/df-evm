// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {ChainlinkOracleRouter} from "../src/ChainlinkOracleRouter.sol";
import {ChainlinkFeeds} from "../src/libraries/ChainlinkFeeds.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";

/// @notice Deploy ChainlinkOracleRouter and optionally point an existing LendingPoolV2 at it.
/// @dev Env:
///   POOL_ADDRESS          — if set, calls pool.setOracle(router) (caller must be pool owner)
///   ETH_MARKET_ID         — marketId for ETH/WETH (default 0)
///   USDC_MARKET_ID        — marketId for USDC (default 1)
///   CBETH_MARKET_ID       — marketId for cbETH (default 2); skip via SKIP_CBETH=1
///   CBBTC_MARKET_ID       — marketId for cbBTC; set with SET_CBBTC=1 (uses BASE_BTC_USD)
///   ENABLE_SEQUENCER=1    — set Base sequencer uptime feed (mainnet only)
///   MAX_PRICE_AGE         — seconds (default 3600)
///
/// Note: LendingPoolV2BaseMainnet.s.sol already wires feeds for USDC/WETH/cbBTC/WAD.
/// Use this script when attaching a router to an existing pool.
///
/// Run (Base mainnet example):
///   forge script script/ChainlinkOracleRouter.s.sol:ChainlinkOracleRouterScript \
///     --rpc-url base --broadcast --private-key $PRIVATE_KEY
contract ChainlinkOracleRouterScript is Script {
    function run() public {
        uint64 ethMarketId = uint64(vm.envOr("ETH_MARKET_ID", uint256(0)));
        uint64 usdcMarketId = uint64(vm.envOr("USDC_MARKET_ID", uint256(1)));
        uint64 cbethMarketId = uint64(vm.envOr("CBETH_MARKET_ID", uint256(2)));
        uint64 cbbtcMarketId = uint64(vm.envOr("CBBTC_MARKET_ID", uint256(2)));
        bool skipCbeth = vm.envOr("SKIP_CBETH", false);
        bool setCbBtc = vm.envOr("SET_CBBTC", false);
        bool enableSequencer = vm.envOr("ENABLE_SEQUENCER", false);
        uint256 maxPriceAge = vm.envOr("MAX_PRICE_AGE", uint256(3600));
        address poolAddr = vm.envOr("POOL_ADDRESS", address(0));

        uint256 chainId = block.chainid;
        address ethFeed;
        address usdcFeed;
        address cbethFeed;
        address btcFeed;
        address sequencerFeed;

        if (chainId == 8453) {
            ethFeed = ChainlinkFeeds.BASE_ETH_USD;
            usdcFeed = ChainlinkFeeds.BASE_USDC_USD;
            cbethFeed = ChainlinkFeeds.BASE_CBETH_USD;
            btcFeed = ChainlinkFeeds.BASE_BTC_USD;
            sequencerFeed = ChainlinkFeeds.BASE_SEQUENCER_UPTIME;
        } else if (chainId == 84532) {
            ethFeed = ChainlinkFeeds.BASE_SEPOLIA_ETH_USD;
            // USDC/cbETH Sepolia feeds: set manually after deploy if available
            usdcFeed = address(0);
            cbethFeed = address(0);
            btcFeed = address(0);
            sequencerFeed = address(0);
        } else {
            revert("Unsupported chain: set feeds manually or add to ChainlinkFeeds");
        }

        vm.startBroadcast();

        ChainlinkOracleRouter router = new ChainlinkOracleRouter();
        router.setMaxPriceAge(maxPriceAge);

        if (ethFeed != address(0)) {
            router.setFeed(ethMarketId, ethFeed);
        }
        if (usdcFeed != address(0)) {
            router.setFeed(usdcMarketId, usdcFeed);
        }
        if (!skipCbeth && cbethFeed != address(0)) {
            router.setFeed(cbethMarketId, cbethFeed);
        }
        if (setCbBtc && btcFeed != address(0)) {
            router.setFeed(cbbtcMarketId, btcFeed);
        }
        if (enableSequencer && sequencerFeed != address(0)) {
            router.setSequencerUptimeFeed(sequencerFeed);
        }

        if (poolAddr != address(0)) {
            LendingPoolV2(poolAddr).setOracle(address(router));
        }

        vm.stopBroadcast();

        console.log("ChainlinkOracleRouter", address(router));
        console.log("chainId", chainId);
        console.log("ETH feed / market", ethFeed, ethMarketId);
        console.log("USDC feed / market", usdcFeed, usdcMarketId);
        if (!skipCbeth) {
            console.log("cbETH feed / market", cbethFeed, cbethMarketId);
        }
        if (setCbBtc) {
            console.log("cbBTC feed / market", btcFeed, cbbtcMarketId);
        }
        if (enableSequencer) {
            console.log("sequencer uptime", sequencerFeed);
        }
        if (poolAddr != address(0)) {
            console.log("pool.setOracle ->", poolAddr);
        }
    }
}
