// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ChainlinkOracleRouter} from "../src/ChainlinkOracleRouter.sol";
import {Roles} from "../src/access/Roles.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MockAggregatorV3} from "../src/mocks/MockAggregatorV3.sol";
import {ChainlinkFeeds} from "../src/libraries/ChainlinkFeeds.sol";
import {AggregatorV3Interface} from "../src/interfaces/AggregatorV3Interface.sol";

contract ChainlinkOracleRouterTest is Test {
    ChainlinkOracleRouter public router;
    MockAggregatorV3 public ethUsd;
    MockAggregatorV3 public usdcUsd;

    uint64 constant ETH_MARKET = 0;
    uint64 constant USDC_MARKET = 1;

    function setUp() public {
        // Foundry default timestamp is too low for (timestamp - age) math.
        vm.warp(1_700_000_000);

        router = new ChainlinkOracleRouter(address(this));
        ethUsd = new MockAggregatorV3(8, 3000e8); // $3000
        usdcUsd = new MockAggregatorV3(8, 1e8); // $1

        router.setFeed(ETH_MARKET, address(ethUsd));
        router.setFeed(USDC_MARKET, address(usdcUsd));
    }

    function test_getPrice_returnsNormalizedUsd8() public view {
        (uint256 price, uint256 ts) = router.getPrice(ETH_MARKET);
        assertEq(price, 3000e8);
        assertEq(ts, block.timestamp);

        (uint256 usdcPrice, ) = router.getPrice(USDC_MARKET);
        assertEq(usdcPrice, 1e8);
    }

    function test_getPrice_scalesUpWhenFeedHasFewerDecimals() public {
        MockAggregatorV3 feed6 = new MockAggregatorV3(6, 2500e6); // $2500 with 6 decimals
        router.setFeed(ETH_MARKET, address(feed6));

        (uint256 price, ) = router.getPrice(ETH_MARKET);
        assertEq(price, 2500e8);
    }

    function test_getPrice_scalesDownWhenFeedHasMoreDecimals() public {
        MockAggregatorV3 feed18 = new MockAggregatorV3(18, 2500e18);
        router.setFeed(ETH_MARKET, address(feed18));

        (uint256 price, ) = router.getPrice(ETH_MARKET);
        assertEq(price, 2500e8);
    }

    function test_getPrice_revertsWhenFeedNotSet() public {
        vm.expectRevert(abi.encodeWithSelector(ChainlinkOracleRouter.FeedNotSet.selector, uint64(99)));
        router.getPrice(99);
    }

    function test_getPrice_revertsOnInvalidPrice() public {
        ethUsd.setAnswer(0);
        vm.expectRevert(ChainlinkOracleRouter.InvalidPrice.selector);
        router.getPrice(ETH_MARKET);

        ethUsd.setAnswer(-1);
        vm.expectRevert(ChainlinkOracleRouter.InvalidPrice.selector);
        router.getPrice(ETH_MARKET);
    }

    function test_getPrice_revertsOnStalePrice() public {
        ethUsd.setUpdatedAt(block.timestamp - 2 hours);
        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkOracleRouter.StalePrice.selector,
                block.timestamp - 2 hours,
                1 hours
            )
        );
        router.getPrice(ETH_MARKET);
    }

    function test_getPrice_revertsOnIncompleteRound() public {
        ethUsd.setRound(5, 4); // answeredInRound < roundId
        vm.expectRevert(ChainlinkOracleRouter.IncompleteRound.selector);
        router.getPrice(ETH_MARKET);
    }

    function test_setMaxPriceAge_allowsFresherWindow() public {
        ethUsd.setUpdatedAt(block.timestamp - 90 minutes);
        router.setMaxPriceAge(2 hours);
        (uint256 price, ) = router.getPrice(ETH_MARKET);
        assertEq(price, 3000e8);
    }

    function test_sequencerDown_reverts() public {
        MockAggregatorV3 uptime = new MockAggregatorV3(0, 0);
        uptime.setSequencerStatus(false, block.timestamp);
        router.setSequencerUptimeFeed(address(uptime));

        vm.expectRevert(ChainlinkOracleRouter.SequencerDown.selector);
        router.getPrice(ETH_MARKET);
    }

    function test_sequencerGracePeriod_reverts() public {
        MockAggregatorV3 uptime = new MockAggregatorV3(0, 0);
        // Sequencer just came back up
        uptime.setSequencerStatus(true, block.timestamp - 10 minutes);
        router.setSequencerUptimeFeed(address(uptime));

        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkOracleRouter.GracePeriodNotOver.selector,
                10 minutes,
                3600
            )
        );
        router.getPrice(ETH_MARKET);
    }

    function test_sequencerUpAfterGrace_allowsPrice() public {
        MockAggregatorV3 uptime = new MockAggregatorV3(0, 0);
        uptime.setSequencerStatus(true, block.timestamp - 2 hours);
        router.setSequencerUptimeFeed(address(uptime));

        (uint256 price, ) = router.getPrice(ETH_MARKET);
        assertEq(price, 3000e8);
    }

    function test_onlyRole_guards() public {
        address stranger = address(0xBEEF);
        bytes32 adminRole = router.DEFAULT_ADMIN_ROLE();

        vm.startPrank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                Roles.ORACLE_ADMIN_ROLE
            )
        );
        router.setFeed(ETH_MARKET, address(ethUsd));

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                Roles.ORACLE_ADMIN_ROLE
            )
        );
        router.setMaxPriceAge(1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                adminRole
            )
        );
        router.grantRole(adminRole, stranger);
        vm.stopPrank();
    }

    function test_grantOracleAdminRole() public {
        address newAdmin = address(0xABCD);
        router.grantRole(Roles.ORACLE_ADMIN_ROLE, newAdmin);

        vm.prank(newAdmin);
        router.setMaxPriceAge(30 minutes);
        assertEq(router.maxPriceAge(), 30 minutes);
    }
}

/// @dev Live Base mainnet fork smoke test. Run with:
///   forge test --match-contract ChainlinkOracleRouterForkTest --fork-url $BASE_RPC_URL
contract ChainlinkOracleRouterForkTest is Test {
    uint256 constant BASE_MAINNET_CHAIN_ID = 8453;

    function setUp() public {
        // Skip when not forking Base (local anvil / default has chainId 31337)
        if (block.chainid != BASE_MAINNET_CHAIN_ID) {
            vm.skip(true);
        }
    }

    function testFork_ethUsdFeedIsLive() public view {
        AggregatorV3Interface feed = AggregatorV3Interface(ChainlinkFeeds.BASE_ETH_USD);
        (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
        assertGt(answer, 0);
        assertGt(updatedAt, 0);
        assertEq(feed.decimals(), 8);
    }

    function testFork_routerReadsEthUsd() public {
        ChainlinkOracleRouter router = new ChainlinkOracleRouter(address(this));
        router.setFeed(0, ChainlinkFeeds.BASE_ETH_USD);
        // Sequencer may be within grace depending on feed state; disable for price read smoke.
        // Production deploys should enable BASE_SEQUENCER_UPTIME.
        (uint256 price, uint256 ts) = router.getPrice(0);
        assertGt(price, 100e8); // > $100
        assertLt(price, 1_000_000e8); // sanity upper bound
        assertGt(ts, 0);
    }
}
