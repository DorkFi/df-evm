// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LendingPoolV2} from "../../src/LendingPoolV2.sol";
import {MockOracle} from "../../src/MockOracle.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Stateful fuzz handler for LendingPoolV2 core flows.
contract LendingPoolHandler is Test {
    LendingPoolV2 public pool;
    MockOracle public oracle;
    MockERC20 public usdc;
    MockERC20 public weth;

    uint64 internal constant USDC_MARKET = 0;
    uint64 internal constant WETH_MARKET = 1;

    address internal immutable admin;
    address[3] internal actors;

    uint256 public ghostDepositsUsdc;
    uint256 public ghostDepositsWeth;
    uint256 public ghostBorrowsUsdc;

    constructor(address _admin) {
        admin = _admin;
        actors[0] = address(0xA11CE);
        actors[1] = address(0xB0B);
        actors[2] = address(0xCAFE);

        oracle = new MockOracle();
        pool = new LendingPoolV2(address(oracle), admin);

        usdc = new MockERC20("USDC", "USDC", 18);
        weth = new MockERC20("WETH", "WETH", 18);

        LendingPoolV2.MarketParams memory p = LendingPoolV2.MarketParams({
            borrowRate: 0.05e18,
            slope: 0.10e18,
            reserveFactor: 0.10e18,
            collateralFactorBps: 8000,
            liquidationThresholdBps: 8500,
            closeFactorBps: 5000,
            liquidationBonusBps: 500
        });

        vm.startPrank(admin);
        pool.createMarket(address(usdc), p);
        pool.createMarket(address(weth), p);
        pool.setMaxTotalDeposits(USDC_MARKET, type(uint256).max);
        pool.setMaxTotalDeposits(WETH_MARKET, type(uint256).max);
        pool.setMaxTotalBorrows(USDC_MARKET, type(uint256).max);
        pool.setMaxTotalBorrows(WETH_MARKET, type(uint256).max);
        vm.stopPrank();

        oracle.setPrice(USDC_MARKET, 1e8);
        oracle.setPrice(WETH_MARKET, 3000e8);

        for (uint256 i = 0; i < actors.length; i++) {
            usdc.mint(actors[i], 10_000_000e18);
            weth.mint(actors[i], 10_000e18);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function depositUsdc(uint256 actorSeed, uint256 amount) external {
        address user = _actor(actorSeed);
        amount = bound(amount, 1, 1_000_000e18);
        vm.startPrank(user);
        usdc.approve(address(pool), amount);
        try pool.deposit(USDC_MARKET, amount) {
            ghostDepositsUsdc += amount;
        } catch {}
        vm.stopPrank();
    }

    function depositWeth(uint256 actorSeed, uint256 amount) external {
        address user = _actor(actorSeed);
        amount = bound(amount, 1, 1000e18);
        vm.startPrank(user);
        weth.approve(address(pool), amount);
        try pool.deposit(WETH_MARKET, amount) {
            ghostDepositsWeth += amount;
        } catch {}
        vm.stopPrank();
    }

    function withdrawUsdc(uint256 actorSeed, uint256 amount) external {
        address user = _actor(actorSeed);
        uint256 bal = pool.getSupplyBalance(user, USDC_MARKET);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(user);
        try pool.withdraw(USDC_MARKET, amount) {} catch {}
    }

    function withdrawWeth(uint256 actorSeed, uint256 amount) external {
        address user = _actor(actorSeed);
        uint256 bal = pool.getSupplyBalance(user, WETH_MARKET);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vm.prank(user);
        try pool.withdraw(WETH_MARKET, amount) {} catch {}
    }

    function borrowUsdc(uint256 actorSeed, uint256 amount) external {
        address user = _actor(actorSeed);
        amount = bound(amount, 1, 500_000e18);
        vm.prank(user);
        try pool.borrow(USDC_MARKET, amount) {
            ghostBorrowsUsdc += amount;
        } catch {}
    }

    function repayUsdc(uint256 actorSeed, uint256 amount) external {
        address user = _actor(actorSeed);
        uint256 debt = pool.getBorrowBalance(user, USDC_MARKET);
        if (debt == 0) return;
        amount = bound(amount, 1, debt);
        vm.startPrank(user);
        usdc.approve(address(pool), amount);
        try pool.repay(USDC_MARKET, amount) {} catch {}
        vm.stopPrank();
    }

    function warpTime(uint256 seconds_) external {
        seconds_ = (seconds_ % (30 days)) + 1;
        vm.warp(block.timestamp + seconds_);
        // Trigger interest accrual via a tiny deposit from admin liquidity provider.
        vm.startPrank(actors[0]);
        uint256 liq = pool.getAvailableLiquidity(USDC_MARKET);
        if (liq > 0) {
            uint256 amt = liq > 1e18 ? 1e18 : liq;
            usdc.approve(address(pool), amt);
            try pool.deposit(USDC_MARKET, amt) {} catch {}
        }
        vm.stopPrank();
    }

    function setWethPrice(uint256 price8) external {
        price8 = bound(price8, 500e8, 10_000e8);
        oracle.setPrice(WETH_MARKET, price8);
    }
}
