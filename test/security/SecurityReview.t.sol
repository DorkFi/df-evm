// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LendingPoolV2} from "../../src/LendingPoolV2.sol";
import {ChainlinkOracleRouter} from "../../src/ChainlinkOracleRouter.sol";
import {MockOracle} from "../../src/MockOracle.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {Roles} from "../../src/access/Roles.sol";
import {DorkFiDeployLib} from "../../src/deploy/DorkFiDeployLib.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice Automated checks from internal security review checklist (DOR-501).
contract SecurityReviewTest is Test {
    address internal admin = address(this);
    address internal pauser = address(0x00000000000000000000000000000000000000A1);
    address internal oracleAdmin = address(0x00000000000000000000000000000000000000A2);
    address internal stranger = address(0xBEEF);

    // --- RBAC: pool ---

    function test_review_pauserCannotCreateMarket() public {
        MockOracle oracle = new MockOracle();
        LendingPoolV2 pool = new LendingPoolV2(address(oracle), admin);
        MockERC20 token = new MockERC20("T", "T", 18);

        pool.grantRole(Roles.PAUSER_ROLE, pauser);
        pool.revokeRole(Roles.POOL_ADMIN_ROLE, pauser);

        LendingPoolV2.MarketParams memory p = _params();
        vm.prank(pauser);
        vm.expectRevert();
        pool.createMarket(address(token), p);
    }

    function test_review_oracleAdminCannotWithdrawReserves() public {
        MockOracle oracle = new MockOracle();
        LendingPoolV2 pool = new LendingPoolV2(address(oracle), admin);
        MockERC20 token = new MockERC20("T", "T", 18);

        pool.grantRole(Roles.ORACLE_ADMIN_ROLE, oracleAdmin);
        pool.revokeRole(Roles.POOL_ADMIN_ROLE, oracleAdmin);

        vm.startPrank(admin);
        pool.createMarket(address(token), _params());
        pool.setMaxTotalDeposits(0, type(uint256).max);
        vm.stopPrank();

        vm.prank(oracleAdmin);
        vm.expectRevert();
        pool.withdrawReserves(0, 1);
    }

    function test_review_oracleAdminCanSetOracle() public {
        MockOracle oracle = new MockOracle();
        MockOracle oracle2 = new MockOracle();
        LendingPoolV2 pool = new LendingPoolV2(address(oracle), admin);

        pool.grantRole(Roles.ORACLE_ADMIN_ROLE, oracleAdmin);
        pool.revokeRole(Roles.ORACLE_ADMIN_ROLE, admin);

        vm.prank(oracleAdmin);
        pool.setOracle(address(oracle2));
        assertEq(address(pool.oracle()), address(oracle2));
    }

    function test_review_strangerCannotPause() public {
        MockOracle oracle = new MockOracle();
        LendingPoolV2 pool = new LendingPoolV2(address(oracle), admin);

        vm.prank(stranger);
        vm.expectRevert();
        pool.setPaused(true);
    }

    // --- RBAC: oracle router ---

    function test_review_oracleRouter_strangerCannotSetFeed() public {
        ChainlinkOracleRouter router = new ChainlinkOracleRouter(admin);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                Roles.ORACLE_ADMIN_ROLE
            )
        );
        router.setFeed(0, address(0x1));
    }

    // --- Initialization / proxy ---

    function test_review_implementationCannotReinitialize() public {
        MockOracle oracle = new MockOracle();
        DorkFiDeployLib.PoolProxyDeployment memory d =
            DorkFiDeployLib.deployPoolProxy(address(oracle), admin);

        vm.expectRevert(LendingPoolV2.AlreadyInitialized.selector);
        LendingPoolV2(d.implementation).initialize(address(oracle), admin);
    }

    function test_review_proxyInitializeOnce() public {
        MockOracle oracle = new MockOracle();
        DorkFiDeployLib.PoolProxyDeployment memory d =
            DorkFiDeployLib.deployPoolProxy(address(oracle), admin);

        vm.expectRevert(LendingPoolV2.AlreadyInitialized.selector);
        LendingPoolV2(d.proxy).initialize(address(oracle), stranger);
    }

    function test_review_zeroAdminRejected() public {
        MockOracle oracle = new MockOracle();
        vm.expectRevert(LendingPoolV2.ZeroAdmin.selector);
        new LendingPoolV2(address(oracle), address(0));
    }

    // --- Oracle path ---

    function test_review_mockOracleIsTestOnlyArtifact() public {
        // Document: MockOracle has no access control — must not be used on mainnet.
        MockOracle oracle = new MockOracle();
        assertTrue(address(oracle).code.length > 0);
    }

    function _params() internal pure returns (LendingPoolV2.MarketParams memory) {
        return LendingPoolV2.MarketParams({
            borrowRate: 0.05e18,
            slope: 0.10e18,
            reserveFactor: 0.10e18,
            collateralFactorBps: 8000,
            liquidationThresholdBps: 8500,
            closeFactorBps: 5000,
            liquidationBonusBps: 500
        });
    }
}
