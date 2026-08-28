// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {ChainlinkOracleRouter} from "../src/ChainlinkOracleRouter.sol";
import {ChainlinkFeeds} from "../src/libraries/ChainlinkFeeds.sol";
import {BaseTokens} from "../src/libraries/BaseTokens.sol";
import {BaseMarketParams} from "../src/libraries/BaseMarketParams.sol";
import {BaseLaunchDeploy} from "../src/deploy/BaseLaunchDeploy.sol";
import {DorkFiDeployLib} from "../src/deploy/DorkFiDeployLib.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title LendingPoolV2BaseMainnetScript
/// @notice Deploys LendingPoolV2 (proxy) + ChainlinkOracleRouter on Base mainnet.
/// @dev Soft-launch caps default to `BaseMarketParams.mainnetSoftLaunchCaps()`; override via MAX_TOTAL_* env.
contract LendingPoolV2BaseMainnetScript is Script {
    struct Result {
        address pool;
        address poolImplementation;
        address proxyAdmin;
        address oracle;
        address timelock;
        address wad;
        address wadFeed;
        BaseLaunchDeploy.MarketIds marketIds;
    }

    function run() public {
        require(block.chainid == 8453, "LendingPoolV2BaseMainnet: not Base mainnet (8453)");

        uint256 maxPriceAge = vm.envOr("MAX_PRICE_AGE", uint256(3600));
        bool enableSequencer = vm.envOr("ENABLE_SEQUENCER", true);
        bool useTimelock = vm.envOr("USE_TIMELOCK", false);

        BaseMarketParams.SoftLaunchCaps memory caps = _resolveCaps();

        Result memory r;

        vm.startBroadcast();

        address broadcaster = msg.sender;
        address protocolAdmin = vm.envOr("TIMELOCK_ADMIN", broadcaster);

        if (useTimelock) {
            DorkFiDeployLib.TimelockDeployment memory td =
                DorkFiDeployLib.deployTimelock(protocolAdmin, address(0), protocolAdmin);
            r.timelock = address(td.timelock);
            protocolAdmin = address(td.timelock);
        }

        ChainlinkOracleRouter router = DorkFiDeployLib.deployOracleRouter(protocolAdmin);
        r.oracle = address(router);
        BaseLaunchDeploy.configureOracle(
            router, maxPriceAge, enableSequencer, ChainlinkFeeds.BASE_SEQUENCER_UPTIME
        );

        DorkFiDeployLib.PoolProxyDeployment memory pd =
            DorkFiDeployLib.deployPoolProxy(address(router), protocolAdmin);
        r.pool = pd.proxy;
        r.poolImplementation = pd.implementation;
        r.proxyAdmin = address(pd.proxyAdmin);

        LendingPoolV2 pool = LendingPoolV2(r.pool);
        BaseLaunchDeploy.StackResult memory stack = BaseLaunchDeploy.createCanonicalMarkets(
            pool,
            BaseTokens.MAINNET_USDC,
            BaseTokens.MAINNET_WETH,
            BaseTokens.MAINNET_CBBTC,
            caps
        );
        r.wad = stack.wad;
        r.marketIds = stack.marketIds;

        r.wadFeed = BaseLaunchDeploy.deployWadFeed();
        BaseLaunchDeploy.OracleFeeds memory feeds = BaseLaunchDeploy.mainnetOracleFeeds();
        feeds.wadUsd = r.wadFeed;
        BaseLaunchDeploy.wireOracleFeeds(router, r.marketIds, feeds);

        vm.stopBroadcast();

        _log(r, enableSequencer, useTimelock, broadcaster);
    }

    function _resolveCaps() internal view returns (BaseMarketParams.SoftLaunchCaps memory caps) {
        caps = BaseMarketParams.mainnetSoftLaunchCaps();
        if (vm.envOr("USE_SOFT_LAUNCH_CAPS", true) == false) {
            caps.maxDepositsUsdc = type(uint256).max;
            caps.maxBorrowsUsdc = type(uint256).max;
            caps.maxDepositsWeth = type(uint256).max;
            caps.maxBorrowsWeth = type(uint256).max;
            caps.maxDepositsCbBtc = type(uint256).max;
            caps.maxBorrowsCbBtc = type(uint256).max;
            caps.maxBorrowsWad = type(uint256).max;
            return caps;
        }
        caps.maxDepositsUsdc = vm.envOr("MAX_TOTAL_DEPOSITS_USDC", caps.maxDepositsUsdc);
        caps.maxBorrowsUsdc = vm.envOr("MAX_TOTAL_BORROWS_USDC", caps.maxBorrowsUsdc);
        caps.maxDepositsWeth = vm.envOr("MAX_TOTAL_DEPOSITS_WETH", caps.maxDepositsWeth);
        caps.maxBorrowsWeth = vm.envOr("MAX_TOTAL_BORROWS_WETH", caps.maxBorrowsWeth);
        caps.maxDepositsCbBtc = vm.envOr("MAX_TOTAL_DEPOSITS_CBBTC", caps.maxDepositsCbBtc);
        caps.maxBorrowsCbBtc = vm.envOr("MAX_TOTAL_BORROWS_CBBTC", caps.maxBorrowsCbBtc);
        caps.maxDepositsWad = vm.envOr("MAX_TOTAL_DEPOSITS_WAD", caps.maxDepositsWad);
        caps.maxBorrowsWad = vm.envOr("MAX_TOTAL_BORROWS_WAD", caps.maxBorrowsWad);
    }

    function _log(Result memory r, bool enableSequencer, bool useTimelock, address broadcaster) internal view {
        console.log("");
        console.log("=== LendingPoolV2 Base mainnet (Phase 2) ===");
        console.log("Pool proxy              ", r.pool);
        console.log("Pool implementation     ", r.poolImplementation);
        console.log("ProxyAdmin              ", r.proxyAdmin);
        console.log("ChainlinkOracleRouter   ", r.oracle);
        if (useTimelock) {
            console.log("Timelock                ", r.timelock);
        }
        console.log("Broadcaster             ", broadcaster);
        console.log("SToken_WAD              ", r.wad);
        console.log("FixedPriceFeed_WAD      ", r.wadFeed);
        console.log("marketId_USDC           ", r.marketIds.usdc);
        console.log("marketId_WETH           ", r.marketIds.weth);
        console.log("marketId_cbBTC          ", r.marketIds.cbBtc);
        console.log("marketId_WAD            ", r.marketIds.wad);
        console.log("sequencerEnabled        ", enableSequencer);
        console.log("");
        console.log("VITE_LENDING_POOL_ADDRESS_MAINNET");
        console.log(r.pool);
        console.log("VITE_LENDING_ORACLE_MAINNET");
        console.log(r.oracle);
        console.log("VITE_WAD_ADDRESS_MAINNET");
        console.log(r.wad);
    }
}
