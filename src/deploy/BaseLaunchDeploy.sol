// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LendingPoolV2} from "../LendingPoolV2.sol";
import {SToken} from "../SToken.sol";
import {ChainlinkOracleRouter} from "../ChainlinkOracleRouter.sol";
import {ChainlinkFeeds} from "../libraries/ChainlinkFeeds.sol";
import {BaseMarketParams} from "../libraries/BaseMarketParams.sol";
import {FixedPriceFeed} from "../FixedPriceFeed.sol";
import {DorkFiDeployLib} from "./DorkFiDeployLib.sol";

/// @title BaseLaunchDeploy
/// @notice Shared canonical market setup for Base mainnet and Sepolia dress rehearsal.
library BaseLaunchDeploy {
    struct OracleFeeds {
        address usdcUsd;
        address ethUsd;
        address btcUsd;
        address wadUsd;
    }

    struct MarketIds {
        uint64 usdc;
        uint64 weth;
        uint64 cbBtc;
        uint64 wad;
    }

    struct StackResult {
        address pool;
        address poolImplementation;
        address proxyAdmin;
        address oracle;
        address wad;
        address wadFeed;
        address cbBtcToken;
        MarketIds marketIds;
    }

    function configureOracle(
        ChainlinkOracleRouter router,
        uint256 maxPriceAge,
        bool enableSequencer,
        address sequencerFeed
    ) internal {
        router.setMaxPriceAge(maxPriceAge);
        if (enableSequencer && sequencerFeed != address(0)) {
            router.setSequencerUptimeFeed(sequencerFeed);
        }
    }

    function wireOracleFeeds(
        ChainlinkOracleRouter router,
        MarketIds memory ids,
        OracleFeeds memory feeds
    ) internal {
        if (feeds.usdcUsd != address(0)) router.setFeed(ids.usdc, feeds.usdcUsd);
        if (feeds.ethUsd != address(0)) router.setFeed(ids.weth, feeds.ethUsd);
        if (feeds.btcUsd != address(0)) router.setFeed(ids.cbBtc, feeds.btcUsd);
        if (feeds.wadUsd != address(0)) router.setFeed(ids.wad, feeds.wadUsd);
    }

    function createCanonicalMarkets(
        LendingPoolV2 pool,
        address usdc,
        address weth,
        address cbBtc,
        BaseMarketParams.SoftLaunchCaps memory caps
    ) internal returns (StackResult memory r) {
        LendingPoolV2.MarketParams memory params = BaseMarketParams.defaultMarketParams();

        r.marketIds.usdc = pool.createMarket(usdc, params);
        r.marketIds.weth = pool.createMarket(weth, params);
        r.marketIds.cbBtc = pool.createMarket(cbBtc, params);
        r.cbBtcToken = cbBtc;

        uint64 nextId = pool.totalMarkets();
        SToken wad = new SToken(address(pool), nextId, "Whale Asset Dollar", "WAD", 6);
        r.wad = address(wad);
        r.marketIds.wad = pool.createMarket(address(wad), params);
        require(r.marketIds.wad == nextId, "WAD marketId mismatch");
        pool.setStokenMarketId(r.marketIds.wad);

        pool.setMaxTotalDeposits(r.marketIds.usdc, caps.maxDepositsUsdc);
        pool.setMaxTotalBorrows(r.marketIds.usdc, caps.maxBorrowsUsdc);
        pool.setMaxTotalDeposits(r.marketIds.weth, caps.maxDepositsWeth);
        pool.setMaxTotalBorrows(r.marketIds.weth, caps.maxBorrowsWeth);
        pool.setMaxTotalDeposits(r.marketIds.cbBtc, caps.maxDepositsCbBtc);
        pool.setMaxTotalBorrows(r.marketIds.cbBtc, caps.maxBorrowsCbBtc);
        pool.setMaxTotalDeposits(r.marketIds.wad, caps.maxDepositsWad);
        pool.setMaxTotalBorrows(r.marketIds.wad, caps.maxBorrowsWad);
    }

    function deployWadFeed() internal returns (address) {
        return address(new FixedPriceFeed(1e8, "WAD / USD"));
    }

    function mainnetOracleFeeds() internal pure returns (OracleFeeds memory) {
        return OracleFeeds({
            usdcUsd: ChainlinkFeeds.BASE_USDC_USD,
            ethUsd: ChainlinkFeeds.BASE_ETH_USD,
            btcUsd: ChainlinkFeeds.BASE_BTC_USD,
            wadUsd: address(0)
        });
    }

    /// @dev Sepolia: ETH/USD Chainlink; USDC/BTC use fixed $1 feeds when Chainlink absent.
    function sepoliaOracleFeeds(address usdcFixed, address btcFixed) internal pure returns (OracleFeeds memory) {
        return OracleFeeds({
            usdcUsd: usdcFixed,
            ethUsd: ChainlinkFeeds.BASE_SEPOLIA_ETH_USD,
            btcUsd: btcFixed,
            wadUsd: address(0)
        });
    }
}
