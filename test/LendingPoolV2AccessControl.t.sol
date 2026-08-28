// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {MockOracle} from "../src/MockOracle.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {Roles} from "../src/access/Roles.sol";
import {DorkFiDeployLib} from "../src/deploy/DorkFiDeployLib.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract LendingPoolV2AccessControlTest is Test {
    LendingPoolV2 public pool;
    MockOracle public oracle;
    MockERC20 public usdc;

    address public admin = address(this);
    address public pauser = address(0x00000000000000000000000000000000000000A1);
    address public stranger = address(0xBEEF);

    function setUp() public {
        oracle = new MockOracle();
        pool = new LendingPoolV2(address(oracle), admin);
        usdc = new MockERC20("USDC", "USDC", 18);
    }

    function test_adminHasAllRoles() public view {
        assertTrue(pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(pool.hasRole(Roles.POOL_ADMIN_ROLE, admin));
        assertTrue(pool.hasRole(Roles.PAUSER_ROLE, admin));
        assertTrue(pool.hasRole(Roles.ORACLE_ADMIN_ROLE, admin));
    }

    function test_pauserCanPause_notCreateMarket() public {
        pool.grantRole(Roles.PAUSER_ROLE, pauser);
        pool.revokeRole(Roles.POOL_ADMIN_ROLE, pauser);

        vm.prank(pauser);
        pool.setPaused(true);
        assertTrue(pool.paused());

        LendingPoolV2.MarketParams memory p = LendingPoolV2.MarketParams({
            borrowRate: 0.05e18,
            slope: 0.10e18,
            reserveFactor: 0.10e18,
            collateralFactorBps: 8000,
            liquidationThresholdBps: 8500,
            closeFactorBps: 5000,
            liquidationBonusBps: 500
        });

        vm.prank(pauser);
        vm.expectRevert();
        pool.createMarket(address(usdc), p);
    }

    function test_strangerCannotPause() public {
        vm.prank(stranger);
        vm.expectRevert();
        pool.setPaused(true);
    }

    function test_proxyDeployAndInitialize() public {
        MockOracle oracle2 = new MockOracle();
        DorkFiDeployLib.PoolProxyDeployment memory d =
            DorkFiDeployLib.deployPoolProxy(address(oracle2), admin);

        LendingPoolV2 proxied = LendingPoolV2(d.proxy);
        assertEq(address(proxied.oracle()), address(oracle2));
        assertTrue(proxied.hasRole(Roles.POOL_ADMIN_ROLE, admin));

        // Implementation locked
        vm.expectRevert(LendingPoolV2.AlreadyInitialized.selector);
        LendingPoolV2(d.implementation).initialize(address(oracle2), admin);
    }

    function test_timelockDeploy() public {
        address multisig = address(0x00000000000000000000000000000000000000B1);
        DorkFiDeployLib.TimelockDeployment memory td =
            DorkFiDeployLib.deployTimelock(multisig, address(0), multisig);
        assertEq(td.timelock.getMinDelay(), DorkFiDeployLib.DEFAULT_TIMELOCK_DELAY);
        assertTrue(td.timelock.hasRole(td.timelock.PROPOSER_ROLE(), multisig));
    }

    function test_setTreasury() public {
        address newTreasury = address(0x00000000000000000000000000000000000000C1);
        pool.setTreasury(newTreasury);
        assertEq(pool.treasury(), newTreasury);
    }
}
