// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {ChainlinkOracleRouter} from "../src/ChainlinkOracleRouter.sol";
import {ChainlinkFeeds} from "../src/libraries/ChainlinkFeeds.sol";
import {BaseTokens} from "../src/libraries/BaseTokens.sol";
import {BaseMarketParams} from "../src/libraries/BaseMarketParams.sol";
import {BaseLaunchDeploy} from "../src/deploy/BaseLaunchDeploy.sol";
import {DorkFiDeployLib} from "../src/deploy/DorkFiDeployLib.sol";
import {FixedPriceFeed} from "../src/FixedPriceFeed.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";

interface IERC20 {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
}

/// @dev Base mainnet fork oracle smoke tests. Run:
///   forge test --match-contract BaseMainnetForkTest -vv
contract BaseMainnetForkTest is Test {
    uint256 constant BASE_MAINNET = 8453;

    function setUp() public {
        vm.createSelectFork("base");
        if (block.chainid != BASE_MAINNET) vm.skip(true);
    }

    function testFork_ethUsdFeedLive() public view {
        _assertFeedLive(ChainlinkFeeds.BASE_ETH_USD, 100e8, 50_000e8);
    }

    function testFork_usdcUsdFeedLive() public view {
        _assertFeedLive(ChainlinkFeeds.BASE_USDC_USD, 0.5e8, 2e8);
    }

    function testFork_routerReadsUsdcAndEthFeeds() public {
        ChainlinkOracleRouter router = new ChainlinkOracleRouter(address(this));
        router.setMaxPriceAge(30 days);
        router.setFeed(0, ChainlinkFeeds.BASE_USDC_USD);
        router.setFeed(1, ChainlinkFeeds.BASE_ETH_USD);

        (uint256 usdc, ) = router.getPrice(0);
        (uint256 eth, ) = router.getPrice(1);

        assertGt(usdc, 0.5e8);
        assertGt(eth, 100e8);
    }

    function testFork_sequencerFeedConfigured() public view {
        AggregatorV3Interface seq = AggregatorV3Interface(ChainlinkFeeds.BASE_SEQUENCER_UPTIME);
        (, int256 answer, , , ) = seq.latestRoundData();
        assertTrue(answer == 0 || answer == 1);
    }

    function testFork_routerWithSequencerWhenUp() public {
        ChainlinkOracleRouter router = new ChainlinkOracleRouter(address(this));
        router.setMaxPriceAge(2 hours);
        router.setSequencerUptimeFeed(ChainlinkFeeds.BASE_SEQUENCER_UPTIME);
        router.setFeed(1, ChainlinkFeeds.BASE_ETH_USD);

        (, int256 seqAnswer, uint256 startedAt, , ) =
            AggregatorV3Interface(ChainlinkFeeds.BASE_SEQUENCER_UPTIME).latestRoundData();

        if (seqAnswer != 0) {
            vm.skip(true);
        }
        if (block.timestamp - startedAt <= router.sequencerGracePeriod()) {
            vm.skip(true);
        }

        (uint256 eth, ) = router.getPrice(1);
        assertGt(eth, 100e8);
    }

    function _assertFeedLive(address feedAddr, uint256 minPrice, uint256 maxPrice) internal view {
        AggregatorV3Interface feed = AggregatorV3Interface(feedAddr);
        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
        assertGt(answer, 0);
        assertGt(updatedAt, 0);
        assertEq(feed.decimals(), 8);
        uint256 price = uint256(answer);
        assertGt(price, minPrice);
        assertLt(price, maxPrice);
    }
}

/// @dev Base Sepolia fork dress-rehearsal E2E. Run:
///   forge test --match-contract BaseSepoliaDressRehearsalForkTest -vv
contract BaseSepoliaDressRehearsalForkTest is Test {
    uint256 constant BASE_SEPOLIA = 84532;

    uint64 constant USDC_MARKET = 0;
    uint64 constant WETH_MARKET = 1;
    uint64 constant CBBTC_MARKET = 2;
    uint64 constant WAD_MARKET = 3;

    LendingPoolV2 pool;
    address oracle;
    address user = address(0xA11CE);

    function setUp() public {
        vm.createSelectFork("base_sepolia");
        if (block.chainid != BASE_SEPOLIA) vm.skip(true);

        ChainlinkOracleRouter router = DorkFiDeployLib.deployOracleRouter(address(this));
        BaseLaunchDeploy.configureOracle(router, 1 hours, false, address(0));
        oracle = address(router);

        DorkFiDeployLib.PoolProxyDeployment memory pd =
            DorkFiDeployLib.deployPoolProxy(oracle, address(this));
        pool = LendingPoolV2(pd.proxy);

        MockERC20 cbBtc = new MockERC20("cbBTC", "cbBTC", 8);
        cbBtc.mint(user, 10 * 1e8);

        BaseLaunchDeploy.createCanonicalMarkets(
            pool,
            BaseTokens.SEPOLIA_USDC,
            BaseTokens.SEPOLIA_WETH,
            address(cbBtc),
            BaseMarketParams.sepoliaDressRehearsalCaps()
        );

        address usdcFeed = address(new FixedPriceFeed(1e8, "USDC / USD"));
        address btcFeed = address(new FixedPriceFeed(100_000e8, "cbBTC / USD"));
        address wadFeed = BaseLaunchDeploy.deployWadFeed();

        BaseLaunchDeploy.MarketIds memory ids = BaseLaunchDeploy.MarketIds({
            usdc: USDC_MARKET,
            weth: WETH_MARKET,
            cbBtc: CBBTC_MARKET,
            wad: WAD_MARKET
        });
        BaseLaunchDeploy.OracleFeeds memory feeds =
            BaseLaunchDeploy.sepoliaOracleFeeds(usdcFeed, btcFeed);
        feeds.wadUsd = wadFeed;
        BaseLaunchDeploy.wireOracleFeeds(router, ids, feeds);

        deal(BaseTokens.SEPOLIA_WETH, user, 10 ether);
        deal(BaseTokens.SEPOLIA_USDC, user, 100_000 * 1e6);
    }

    function testFork_depositBorrowRepayWithdraw() public {
        vm.startPrank(user);

        IERC20(BaseTokens.SEPOLIA_WETH).approve(address(pool), 5 ether);
        pool.deposit(WETH_MARKET, 5 ether);

        uint256 borrowAmount = 1000 * 1e6;
        pool.borrow(WAD_MARKET, borrowAmount);
        assertGt(pool.getBorrowBalance(user, WAD_MARKET), 0);

        pool.repay(WAD_MARKET, borrowAmount / 2);
        assertLt(pool.getBorrowBalance(user, WAD_MARKET), borrowAmount);

        pool.withdraw(WETH_MARKET, 1 ether);
        assertGt(pool.getSupplyBalance(user, WETH_MARKET), 0);

        vm.stopPrank();
    }

    function testFork_stalePriceReverts() public {
        ChainlinkOracleRouter router = ChainlinkOracleRouter(oracle);
        router.setMaxPriceAge(1);

        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert();
        router.getPrice(WETH_MARKET);
    }
}
