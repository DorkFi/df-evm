// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LendingPoolV2} from "../../src/LendingPoolV2.sol";
import {MockOracle} from "../../src/MockOracle.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @notice Property-based fuzz tests for core pool math (DOR-501).
contract LendingPoolV2FuzzTest is Test {
    LendingPoolV2 internal pool;
    MockOracle internal oracle;
    MockERC20 internal usdc;
    MockERC20 internal weth;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    uint64 internal constant USDC_MARKET = 0;
    uint64 internal constant WETH_MARKET = 1;

    function setUp() public {
        oracle = new MockOracle();
        pool = new LendingPoolV2(address(oracle), address(this));

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

        pool.createMarket(address(usdc), p);
        pool.createMarket(address(weth), p);
        pool.setMaxTotalDeposits(USDC_MARKET, type(uint256).max);
        pool.setMaxTotalDeposits(WETH_MARKET, type(uint256).max);
        pool.setMaxTotalBorrows(USDC_MARKET, type(uint256).max);
        pool.setMaxTotalBorrows(WETH_MARKET, type(uint256).max);

        oracle.setPrice(USDC_MARKET, 1e8);
        oracle.setPrice(WETH_MARKET, 3000e8);

        usdc.mint(alice, 1_000_000e18);
        usdc.mint(bob, 1_000_000e18);
        weth.mint(alice, 1000e18);
        weth.mint(bob, 1000e18);
    }

    function testFuzz_depositWithdrawRoundTrip(uint256 amount) public {
        amount = bound(amount, 1, 100_000e18);

        vm.startPrank(bob);
        usdc.approve(address(pool), amount);
        pool.deposit(USDC_MARKET, amount);
        pool.withdraw(USDC_MARKET, amount);
        vm.stopPrank();

        assertEq(pool.getSupplyBalance(bob, USDC_MARKET), 0);
        assertEq(usdc.balanceOf(bob), 1_000_000e18);
    }

    function testFuzz_borrowRepayRoundTrip(uint256 collateral, uint256 borrowAmt) public {
        collateral = bound(collateral, 1e18, 100e18);
        borrowAmt = bound(borrowAmt, 1e18, 2000e18); // well under 80% of $3000 * collateral

        vm.startPrank(bob);
        usdc.approve(address(pool), 500_000e18);
        pool.deposit(USDC_MARKET, 500_000e18);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(pool), collateral);
        pool.deposit(WETH_MARKET, collateral);
        pool.borrow(USDC_MARKET, borrowAmt);
        usdc.approve(address(pool), borrowAmt);
        pool.repay(USDC_MARKET, borrowAmt);
        vm.stopPrank();

        assertEq(pool.getBorrowBalance(alice, USDC_MARKET), 0);
    }

    function testFuzz_healthFactorAboveOneAfterConservativeBorrow(
        uint256 wethAmt,
        uint256 borrowAmt
    ) public {
        wethAmt = bound(wethAmt, 1e18, 50e18);
        // Max borrow at 80% CF: wethAmt * 3000 * 0.8 (token has 18 decimals)
        uint256 maxBorrow = (wethAmt * 3000 * 80) / 100;
        vm.assume(maxBorrow >= 4e18);
        borrowAmt = bound(borrowAmt, 1e18, maxBorrow / 4);

        vm.startPrank(bob);
        usdc.approve(address(pool), 1_000_000e18);
        pool.deposit(USDC_MARKET, 1_000_000e18);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(pool), wethAmt);
        pool.deposit(WETH_MARKET, wethAmt);
        pool.borrow(USDC_MARKET, borrowAmt);
        vm.stopPrank();

        assertGe(pool.getHealthFactorRealtime(alice), 1e18);
    }

    function testFuzz_liquidationReducesDebt(uint256 repayAmount) public {
        vm.startPrank(bob);
        usdc.approve(address(pool), 100_000e18);
        pool.deposit(USDC_MARKET, 100_000e18);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(pool), 10e18);
        pool.deposit(WETH_MARKET, 10e18);
        pool.borrow(USDC_MARKET, 20_000e18);
        vm.stopPrank();

        oracle.setPrice(WETH_MARKET, 1500e8); // underwater

        uint256 debtBefore = pool.getBorrowBalance(alice, USDC_MARKET);
        repayAmount = bound(repayAmount, 1e18, debtBefore / 2);

        vm.startPrank(bob);
        usdc.approve(address(pool), repayAmount);
        pool.liquidateCrossMarket(alice, USDC_MARKET, WETH_MARKET, repayAmount, 0);
        vm.stopPrank();

        assertLt(pool.getBorrowBalance(alice, USDC_MARKET), debtBefore);
    }
}
