// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {ChainlinkOracleRouter} from "../src/ChainlinkOracleRouter.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {FixedPriceFeed} from "../src/FixedPriceFeed.sol";
import {BaseTokens} from "../src/libraries/BaseTokens.sol";
import {BaseMarketParams} from "../src/libraries/BaseMarketParams.sol";
import {BaseLaunchDeploy} from "../src/deploy/BaseLaunchDeploy.sol";
import {DorkFiDeployLib} from "../src/deploy/DorkFiDeployLib.sol";

/// @title LendingPoolV2BaseSepoliaScript
/// @notice Dress-rehearsal deploy on Base Sepolia: proxy pool + Chainlink (ETH/USD) + fixed feeds.
///
/// Markets: USDC, WETH, mock cbBTC, WAD (matches mainnet layout).
/// cbBTC is a deploy-time MockERC20 because no canonical cbBTC exists on Sepolia.
///
/// Dry run:
///   FOUNDRY_PROFILE=base-sepolia forge script script/LendingPoolV2BaseSepolia.s.sol:LendingPoolV2BaseSepoliaScript --rpc-url base_sepolia
///
/// Broadcast:
///   source .env && FOUNDRY_PROFILE=base-sepolia forge script script/LendingPoolV2BaseSepolia.s.sol:LendingPoolV2BaseSepoliaScript \
///     --rpc-url base_sepolia --broadcast --private-key $PRIVATE_KEY
contract LendingPoolV2BaseSepoliaScript is Script {
    struct Result {
        address pool;
        address poolImplementation;
        address proxyAdmin;
        address oracle;
        address wad;
        address wadFeed;
        address cbBtcMock;
        address usdcFixedFeed;
        address btcFixedFeed;
        BaseLaunchDeploy.MarketIds marketIds;
    }

    function run() public {
        require(block.chainid == 84532, "LendingPoolV2BaseSepolia: not Base Sepolia (84532)");

        uint256 maxPriceAge = vm.envOr("MAX_PRICE_AGE", uint256(3600));
        BaseMarketParams.SoftLaunchCaps memory caps = BaseMarketParams.sepoliaDressRehearsalCaps();

        Result memory r;

        vm.startBroadcast();

        address admin = msg.sender;

        ChainlinkOracleRouter router = DorkFiDeployLib.deployOracleRouter(admin);
        r.oracle = address(router);
        BaseLaunchDeploy.configureOracle(router, maxPriceAge, false, address(0));

        DorkFiDeployLib.PoolProxyDeployment memory pd =
            DorkFiDeployLib.deployPoolProxy(address(router), admin);
        r.pool = pd.proxy;
        r.poolImplementation = pd.implementation;
        r.proxyAdmin = address(pd.proxyAdmin);

        MockERC20 cbBtc = new MockERC20("Coinbase Wrapped BTC", "cbBTC", 8);
        r.cbBtcMock = address(cbBtc);

        LendingPoolV2 pool = LendingPoolV2(r.pool);
        BaseLaunchDeploy.StackResult memory stack = BaseLaunchDeploy.createCanonicalMarkets(
            pool,
            BaseTokens.SEPOLIA_USDC,
            BaseTokens.SEPOLIA_WETH,
            r.cbBtcMock,
            caps
        );
        r.wad = stack.wad;
        r.marketIds = stack.marketIds;

        r.wadFeed = BaseLaunchDeploy.deployWadFeed();
        r.usdcFixedFeed = address(new FixedPriceFeed(1e8, "USDC / USD"));
        r.btcFixedFeed = address(new FixedPriceFeed(100_000e8, "cbBTC / USD"));

        BaseLaunchDeploy.OracleFeeds memory feeds =
            BaseLaunchDeploy.sepoliaOracleFeeds(r.usdcFixedFeed, r.btcFixedFeed);
        feeds.wadUsd = r.wadFeed;
        BaseLaunchDeploy.wireOracleFeeds(router, r.marketIds, feeds);

        vm.stopBroadcast();

        _log(r);
    }

    function _log(Result memory r) internal view {
        console.log("");
        console.log("=== LendingPoolV2 Base Sepolia dress rehearsal ===");
        console.log("Pool proxy              ", r.pool);
        console.log("Pool implementation     ", r.poolImplementation);
        console.log("ProxyAdmin              ", r.proxyAdmin);
        console.log("ChainlinkOracleRouter   ", r.oracle);
        console.log("Mock cbBTC              ", r.cbBtcMock);
        console.log("SToken_WAD              ", r.wad);
        console.log("FixedPriceFeed_WAD      ", r.wadFeed);
        console.log("FixedPriceFeed_USDC     ", r.usdcFixedFeed);
        console.log("FixedPriceFeed_cbBTC    ", r.btcFixedFeed);
        console.log("marketId_USDC           ", r.marketIds.usdc);
        console.log("marketId_WETH           ", r.marketIds.weth);
        console.log("marketId_cbBTC          ", r.marketIds.cbBtc);
        console.log("marketId_WAD            ", r.marketIds.wad);
        console.log("");
        console.log("VITE_LENDING_POOL_ADDRESS_SEPOLIA");
        console.log(r.pool);
        console.log("VITE_LENDING_ORACLE_SEPOLIA");
        console.log(r.oracle);
        console.log("VITE_WAD_ADDRESS_SEPOLIA");
        console.log(r.wad);
    }
}
