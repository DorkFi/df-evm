// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {NToken} from "../src/NToken.sol";
import {MockOracle} from "../src/MockOracle.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";

contract LendingPoolV2Test is Test {
    LendingPoolV2 public pool;
    MockOracle public oracle;
    MockERC20 public usdc;
    MockERC20 public weth;

    uint64 constant USDC_MARKET = 0;
    uint64 constant WETH_MARKET = 1;

    address public alice;
    address public bob;
    
    uint256 constant ALICE_PRIVATE_KEY = 0x1;
    uint256 constant BOB_PRIVATE_KEY = 0x2;

    function _defaultParams() internal pure returns (LendingPoolV2.MarketParams memory) {
        return LendingPoolV2.MarketParams({
            borrowRate: 0.05e18,           // 5% base
            slope: 0.10e18,                // 10% slope
            reserveFactor: 0.10e18,        // 10% to reserves
            collateralFactorBps: 8000,     // 80%
            liquidationThresholdBps: 8500, // 85%
            closeFactorBps: 5000,          // 50%
            liquidationBonusBps: 500        // 5%
        });
    }

    function setUp() public {
        alice = vm.addr(ALICE_PRIVATE_KEY);
        bob = vm.addr(BOB_PRIVATE_KEY);
        
        oracle = new MockOracle();
        pool = new LendingPoolV2(address(oracle));

        usdc = new MockERC20("USDC", "USDC", 18);
        weth = new MockERC20("WETH", "WETH", 18);

        usdc.mint(alice, 1_000_000e18);
        usdc.mint(bob, 1_000_000e18);
        weth.mint(alice, 1000e18);
        weth.mint(bob, 1000e18);

        LendingPoolV2.MarketParams memory p = _defaultParams();
        pool.createMarket(address(usdc), p);
        pool.createMarket(address(weth), p);

        pool.setMaxTotalDeposits(USDC_MARKET, type(uint256).max);
        pool.setMaxTotalDeposits(WETH_MARKET, type(uint256).max);
        pool.setMaxTotalBorrows(USDC_MARKET, type(uint256).max);
        pool.setMaxTotalBorrows(WETH_MARKET, type(uint256).max);

        oracle.setPrice(USDC_MARKET, 1e8);   // $1
        oracle.setPrice(WETH_MARKET, 3000e8); // $3000
    }

    function test_Deposit() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.stopPrank();

        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 1000e18);
        assertEq(usdc.balanceOf(address(pool)), 1000e18);
    }

    function test_NTokenBootstrapFromUnderlying() public view {
        NToken nUsdc = NToken(pool.getNToken(USDC_MARKET));
        NToken nWeth = NToken(pool.getNToken(WETH_MARKET));
        assertEq(nUsdc.name(), "DorkFi USDC");
        assertEq(nUsdc.symbol(), "nUSDC");
        assertEq(nUsdc.decimals(), 18);
        assertEq(nWeth.name(), "DorkFi WETH");
        assertEq(nWeth.symbol(), "nWETH");
        assertEq(nWeth.decimals(), 18);
    }

    function test_NTokenBalanceMatchesSupply() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.stopPrank();

        NToken nToken = NToken(pool.getNToken(USDC_MARKET));
        assertEq(nToken.balanceOf(alice), 1000e18);
        assertEq(nToken.balanceOf(alice), pool.getSupplyBalance(alice, USDC_MARKET));
    }

    function test_NTokenNonTransferable() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.stopPrank();

        NToken nToken = NToken(pool.getNToken(USDC_MARKET));
        assertFalse(nToken.transfer(bob, 100e18));
        assertFalse(nToken.transferFrom(alice, bob, 100e18));
        assertEq(nToken.balanceOf(alice), 1000e18);
        assertEq(nToken.balanceOf(bob), 0);
    }

    // --- Deposit flow tests (plan spec) ---

    function test_deposit_first_time_user_updates_balances() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 500e18);
        pool.deposit(USDC_MARKET, 500e18);
        vm.stopPrank();

        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 500e18);
        assertEq(pool.getMarketTotalDeposits(USDC_MARKET), 500e18);
        assertEq(usdc.balanceOf(address(pool)), 500e18);
    }

    function test_deposit_twice_no_state_drift() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 2000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        pool.deposit(USDC_MARKET, 500e18);
        vm.stopPrank();

        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 1500e18);
        assertEq(pool.getMarketTotalDeposits(USDC_MARKET), 1500e18);
        assertEq(usdc.balanceOf(address(pool)), 1500e18);

        NToken nToken = NToken(pool.getNToken(USDC_MARKET));
        assertEq(nToken.balanceOf(alice), 1500e18);
    }

    function test_deposit_two_users_isolated_accounting() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(pool), 500e18);
        pool.deposit(USDC_MARKET, 500e18);
        vm.stopPrank();

        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 1000e18);
        assertEq(pool.getSupplyBalance(bob, USDC_MARKET), 500e18);
        assertEq(pool.getMarketTotalDeposits(USDC_MARKET), 1500e18);
        assertEq(usdc.balanceOf(address(pool)), 1500e18);

        NToken nToken = NToken(pool.getNToken(USDC_MARKET));
        assertEq(nToken.balanceOf(alice), 1000e18);
        assertEq(nToken.balanceOf(bob), 500e18);
    }

    function test_deposit_then_read_methods_match_expected() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.stopPrank();

        uint256 supplyBalance = pool.getSupplyBalance(alice, USDC_MARKET);
        uint256 marketTotal = pool.getMarketTotalDeposits(USDC_MARKET);
        uint256 poolBalance = usdc.balanceOf(address(pool));
        NToken nToken = NToken(pool.getNToken(USDC_MARKET));
        uint256 nTokenBalance = nToken.balanceOf(alice);

        assertEq(supplyBalance, 1000e18);
        assertEq(marketTotal, 1000e18);
        assertEq(poolBalance, 1000e18);
        assertEq(nTokenBalance, 1000e18);
        assertEq(supplyBalance, nTokenBalance);
    }

    // --- Withdraw flow tests (plan spec) ---

    function test_Withdraw() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        pool.withdraw(USDC_MARKET, 400e18);
        vm.stopPrank();

        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 600e18);
        assertEq(usdc.balanceOf(alice), 1_000_000e18 - 600e18);
    }

    function test_withdraw_partial_reduces_collateral_correctly() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);
        pool.withdraw(USDC_MARKET, 300e18);
        vm.stopPrank();

        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 700e18);
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore + 300e18);
        assertEq(usdc.balanceOf(address(pool)), 700e18);
    }

    function test_withdraw_full_clears_only_collateral_market() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        uint256 balance = pool.getSupplyBalance(alice, USDC_MARKET);
        pool.withdraw(USDC_MARKET, balance);
        vm.stopPrank();

        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 0);
        assertEq(pool.getMarketTotalDeposits(USDC_MARKET), 0);
        NToken nToken = NToken(pool.getNToken(USDC_MARKET));
        assertEq(nToken.balanceOf(alice), 0);
    }

    /// @notice Regression: full withdraw when user has borrows - was underflowing in _getHealthFactorAfterWithdraw
    function test_withdraw_full_near_threshold_does_not_underflow() public {
        vm.prank(bob);
        usdc.approve(address(pool), 50_000e18);
        vm.prank(bob);
        pool.deposit(USDC_MARKET, 50_000e18);

        vm.startPrank(alice);
        weth.approve(address(pool), 2e18);
        pool.deposit(WETH_MARKET, 2e18);   // 2 WETH @ $3000 = $6000, 80% = $4800
        pool.borrow(USDC_MARKET, 2400e18); // near limit

        uint256 balance = pool.getSupplyBalance(alice, WETH_MARKET);
        vm.expectRevert(LendingPoolV2.HealthFactorWouldViolate.selector);
        pool.withdraw(WETH_MARKET, balance); // full withdraw would make health < 1
        vm.stopPrank();
    }

    function test_withdraw_full_after_multiple_deposits() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 3000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        pool.deposit(USDC_MARKET, 500e18);
        pool.deposit(USDC_MARKET, 300e18);

        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 1800e18);

        uint256 balance = pool.getSupplyBalance(alice, USDC_MARKET);
        pool.withdraw(USDC_MARKET, balance);
        vm.stopPrank();

        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 0);
        assertEq(usdc.balanceOf(alice), 1_000_000e18);
        assertEq(pool.getMarketTotalDeposits(USDC_MARKET), 0);
    }

    function test_withdraw_more_than_balance_reverts_or_clamps_expectedly() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 500e18);

        vm.expectRevert(LendingPoolV2.InsufficientBalance.selector);
        pool.withdraw(USDC_MARKET, 600e18);
        vm.stopPrank();
    }

    /// @notice Regression: withdraw full balance from single market (no borrows) - was underflowing in _getHealthFactorAfterWithdraw
    function test_WithdrawFullBalanceFromSingleMarket() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 500e18); // only collateral: 500 USDC

        uint256 balance = pool.getSupplyBalance(alice, USDC_MARKET);
        pool.withdraw(USDC_MARKET, balance); // withdraw full remaining balance
        vm.stopPrank();

        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 0);
        assertEq(usdc.balanceOf(alice), 1_000_000e18); // all back
    }

    function test_Borrow() public {
        vm.prank(bob);
        usdc.approve(address(pool), 1000e18);
        vm.prank(bob);
        pool.deposit(USDC_MARKET, 1000e18); // liquidity
        vm.startPrank(alice);
        weth.approve(address(pool), 1e18);
        pool.deposit(WETH_MARKET, 1e18);   // collateral (not same market as borrow)
        pool.borrow(USDC_MARKET, 500e18);   // 80% of 1 WETH @ $3000 = $2400 max
        vm.stopPrank();

        assertEq(pool.getBorrowBalance(alice, USDC_MARKET), 500e18);
        assertEq(usdc.balanceOf(alice), 1_000_000e18 + 500e18);
    }

    function test_Repay() public {
        vm.prank(bob);
        usdc.approve(address(pool), 1000e18);
        vm.prank(bob);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.startPrank(alice);
        weth.approve(address(pool), 1e18);
        pool.deposit(WETH_MARKET, 1e18);
        pool.borrow(USDC_MARKET, 500e18);
        usdc.approve(address(pool), 500e18);
        pool.repay(USDC_MARKET, 300e18);
        vm.stopPrank();

        assertEq(pool.getBorrowBalance(alice, USDC_MARKET), 200e18);
    }

    function test_RepayExcessRefunded() public {
        vm.prank(bob);
        usdc.approve(address(pool), 1000e18);
        vm.prank(bob);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.startPrank(alice);
        weth.approve(address(pool), 1e18);
        pool.deposit(WETH_MARKET, 1e18);
        pool.borrow(USDC_MARKET, 100e18);
        usdc.approve(address(pool), 500e18);
        uint256 aliceBefore = usdc.balanceOf(alice);
        pool.repay(USDC_MARKET, 500e18); // overpay; we only pull 100
        vm.stopPrank();

        assertEq(pool.getBorrowBalance(alice, USDC_MARKET), 0);
        assertEq(usdc.balanceOf(alice), aliceBefore - 100e18); // only 100 actually repaid
    }

    function test_CannotBorrowMoreThanCollateral() public {
        vm.prank(bob);
        usdc.approve(address(pool), 1000e18);
        vm.prank(bob);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.startPrank(alice);
        weth.approve(address(pool), 1e18);
        pool.deposit(WETH_MARKET, 1e18); // 1 WETH @ $3000 = $3000, 80% = $2400
        vm.expectRevert(); // HealthFactorWouldViolate (80% of 1 WETH @ $3000 = $2400 max)
        pool.borrow(USDC_MARKET, 2500e18);
        vm.stopPrank();
    }

    function test_InterestAccrual() public {
        vm.prank(bob);
        usdc.approve(address(pool), 10_000e18);
        vm.prank(bob);
        pool.deposit(USDC_MARKET, 10_000e18);
        vm.startPrank(alice);
        weth.approve(address(pool), 2e18);
        pool.deposit(WETH_MARKET, 2e18);   // 2 WETH @ $3000 = $6000, 80% = $4800 max
        pool.borrow(USDC_MARKET, 4000e18);
        vm.stopPrank();

        uint256 borrowBefore = pool.getBorrowBalance(alice, USDC_MARKET);
        assertEq(borrowBefore, 4000e18);

        vm.warp(block.timestamp + 365 days); // 1 year

        vm.startPrank(bob);
        usdc.approve(address(pool), 1e18);
        pool.deposit(USDC_MARKET, 1e18); // trigger accrual
        vm.stopPrank();

        uint256 borrowAfter = pool.getBorrowBalance(alice, USDC_MARKET);
        assertGt(borrowAfter, borrowBefore); // interest accrued
    }

    function test_CrossMarketCollateral() public {
        vm.prank(bob);
        usdc.approve(address(pool), 50_000e18);
        vm.prank(bob);
        pool.deposit(USDC_MARKET, 50_000e18); // Bob supplies USDC liquidity

        vm.startPrank(alice);
        weth.approve(address(pool), 10e18);
        pool.deposit(WETH_MARKET, 10e18); // 10 WETH @ $3000 = $30k collateral

        usdc.approve(address(pool), 1e18);
        pool.deposit(USDC_MARKET, 1e18);

        uint256 maxBorrow = pool.getMaxBorrow(alice, USDC_MARKET);
        assertApproxEqAbs(maxBorrow, 24_800e18, 1000e18); // 80% of $31k ≈ $24.8k USDC (allow rounding)

        pool.borrow(USDC_MARKET, 20_000e18);
        vm.stopPrank();

        assertEq(pool.getBorrowBalance(alice, USDC_MARKET), 20_000e18);
        assertGt(pool.getHealthFactor(alice), 1e18);
    }

    /// @notice Tests getMaxBorrow with USDC (6 decimals) and cbBTC (8 decimals) - mixed decimal markets
    function test_GetMaxBorrow_Usdc6CbBtc8() public {
        MockOracle oracle2 = new MockOracle();
        LendingPoolV2 pool2 = new LendingPoolV2(address(oracle2));

        MockERC20 usdc6 = new MockERC20("USDC", "USDC", 6);
        MockERC20 cbBtc8 = new MockERC20("cbBTC", "cbBTC", 8);

        usdc6.mint(alice, 1_000_000e6);
        usdc6.mint(bob, 1_000_000e6);
        cbBtc8.mint(alice, 10e8); // 10 cbBTC (8 decimals)

        LendingPoolV2.MarketParams memory p = _defaultParams();
        pool2.createMarket(address(usdc6), p);
        pool2.createMarket(address(cbBtc8), p);
        pool2.setMaxTotalDeposits(0, type(uint256).max);
        pool2.setMaxTotalDeposits(1, type(uint256).max);
        pool2.setMaxTotalBorrows(0, type(uint256).max);
        pool2.setMaxTotalBorrows(1, type(uint256).max);

        oracle2.setPrice(0, 1e8);        // USDC $1
        oracle2.setPrice(1, 100_000e8);  // cbBTC $100k

        // Bob supplies USDC liquidity
        vm.startPrank(bob);
        usdc6.approve(address(pool2), 100_000e6);
        pool2.deposit(0, 100_000e6);
        vm.stopPrank();

        // Alice deposits 0.1 cbBTC (8 dec) = 10e6 units @ $100k = $10k collateral, 80% = $8k max borrow in USDC
        vm.startPrank(alice);
        cbBtc8.approve(address(pool2), 10e6);
        pool2.deposit(1, 10e6);

        uint256 maxBorrowUsdc = pool2.getMaxBorrow(alice, 0);
        assertApproxEqAbs(maxBorrowUsdc, 8_000e6, 10e6); // ~8000 USDC

        // Add more cbBTC collateral: 0.01 cbBTC (8 dec) = 1e6 units @ $100k = $1k
        cbBtc8.approve(address(pool2), 1e6);
        pool2.deposit(1, 1e6);

        uint256 maxBorrowAfterCbBtc = pool2.getMaxBorrow(alice, 0);
        assertGt(maxBorrowAfterCbBtc, maxBorrowUsdc);

        pool2.borrow(0, 5_000e6);
        vm.stopPrank();

        assertEq(pool2.getBorrowBalance(alice, 0), 5_000e6);
        assertGt(pool2.getHealthFactor(alice), 1e18);
    }

    /// @notice Replicates UI scenario: ~$78 collateral (5 USDC + 0.0007 cbBTC + 3 EURC) → ~$62 max borrow in USDC
    function test_GetMaxBorrow_MixedDecimals_78DollarsCollateral() public {
        MockOracle oracle2 = new MockOracle();
        LendingPoolV2 pool2 = new LendingPoolV2(address(oracle2));

        MockERC20 usdc6 = new MockERC20("USDC", "USDC", 6);
        MockERC20 cbBtc8 = new MockERC20("cbBTC", "cbBTC", 8);
        MockERC20 eurc6 = new MockERC20("EURC", "EURC", 6);

        usdc6.mint(alice, 1_000_000e6);
        usdc6.mint(bob, 1_000_000e6);
        cbBtc8.mint(alice, 10e8);
        eurc6.mint(alice, 1_000_000e6);

        LendingPoolV2.MarketParams memory p = _defaultParams();
        pool2.createMarket(address(usdc6), p);
        pool2.createMarket(address(cbBtc8), p);
        pool2.createMarket(address(eurc6), p);
        pool2.setMaxTotalDeposits(0, type(uint256).max);
        pool2.setMaxTotalDeposits(1, type(uint256).max);
        pool2.setMaxTotalDeposits(2, type(uint256).max);
        pool2.setMaxTotalBorrows(0, type(uint256).max);
        pool2.setMaxTotalBorrows(1, type(uint256).max);
        pool2.setMaxTotalBorrows(2, type(uint256).max);

        oracle2.setPrice(0, 1e8);        // USDC $1
        oracle2.setPrice(1, 100_000e8);  // cbBTC $100k
        oracle2.setPrice(2, 1.08e8);     // EURC ~$1.08

        vm.startPrank(bob);
        usdc6.approve(address(pool2), 100_000e6);
        pool2.deposit(0, 100_000e6);
        vm.stopPrank();

        // Alice: 0.0007 cbBTC + 3 EURC ≈ $70 + $3.24 ≈ $73 collateral (no USDC - borrow is in USDC)
        vm.startPrank(alice);
        cbBtc8.approve(address(pool2), 70000); // 0.0007 cbBTC (8 dec)
        pool2.deposit(1, 70000);
        eurc6.approve(address(pool2), 3e6);
        pool2.deposit(2, 3e6);           // 3 EURC

        uint256 maxBorrowUsdc = pool2.getMaxBorrow(alice, 0);
        assertApproxEqAbs(maxBorrowUsdc, 58e6, 10e6); // ~58 USDC (80% of ~$73)

        uint256 maxBorrowCbBtc = pool2.getMaxBorrow(alice, 1);
        assertApproxEqAbs(maxBorrowCbBtc, 58e3, 10e3); // ~0.00058 cbBTC (8 dec)

        uint256 maxBorrowEurc = pool2.getMaxBorrow(alice, 2);
        assertApproxEqAbs(maxBorrowEurc, 54e6, 10e6); // ~54 EURC
        vm.stopPrank();
    }

    /// @notice With ~$1 borrowed, max borrow should decrease accordingly
    function test_GetMaxBorrow_ReducesAfterBorrow() public {
        MockOracle oracle2 = new MockOracle();
        LendingPoolV2 pool2 = new LendingPoolV2(address(oracle2));

        MockERC20 usdc6 = new MockERC20("USDC", "USDC", 6);
        usdc6.mint(alice, 1_000_000e6);
        usdc6.mint(bob, 1_000_000e6);

        MockERC20 weth18 = new MockERC20("WETH", "WETH", 18);
        weth18.mint(alice, 1000e18);
        LendingPoolV2.MarketParams memory p = _defaultParams();
        pool2.createMarket(address(usdc6), p);
        pool2.createMarket(address(weth18), p);
        pool2.setMaxTotalDeposits(0, type(uint256).max);
        pool2.setMaxTotalDeposits(1, type(uint256).max);
        pool2.setMaxTotalBorrows(0, type(uint256).max);
        pool2.setMaxTotalBorrows(1, type(uint256).max);
        oracle2.setPrice(0, 1e8);
        oracle2.setPrice(1, 3000e8); // WETH $3000

        vm.startPrank(bob);
        usdc6.approve(address(pool2), 100_000e6);
        pool2.deposit(0, 100_000e6);
        vm.stopPrank();

        vm.startPrank(alice);
        weth18.approve(address(pool2), 1e18);
        pool2.deposit(1, 1e18); // 1 WETH @ $3000 = $3000 collateral, 80% = $2400 max in USDC

        uint256 maxBefore = pool2.getMaxBorrow(alice, 0);
        assertApproxEqAbs(maxBefore, 2400e6, 10e6);

        pool2.borrow(0, 10e6); // borrow $10 USDC

        uint256 maxAfter = pool2.getMaxBorrow(alice, 0);
        assertApproxEqAbs(maxAfter, 2390e6, 10e6); // $2390 remaining
        assertLt(maxAfter, maxBefore);
        vm.stopPrank();
    }

    /// @notice User with no collateral gets 0 max borrow
    function test_GetMaxBorrow_NoCollateral_ReturnsZero() public view {
        assertEq(pool.getMaxBorrow(alice, USDC_MARKET), 0);
        assertEq(pool.getMaxBorrow(alice, WETH_MARKET), 0);
    }

    /// @notice Non-existent market returns 0
    function test_GetMaxBorrow_InvalidMarket_ReturnsZero() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.stopPrank();

        assertEq(pool.getMaxBorrow(alice, 99), 0);
    }

    // --- getTotalCollateralRealtime / getTotalBorrowsRealtime ---

    function test_GetTotalCollateralRealtime_NoPositions_ReturnsZero() public view {
        assertEq(pool.getTotalCollateralRealtime(alice), 0);
        assertEq(pool.getTotalCollateralRealtime(bob), 0);
    }

    function test_GetTotalBorrowsRealtime_NoBorrows_ReturnsZero() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.stopPrank();
        assertEq(pool.getTotalBorrowsRealtime(alice), 0);
    }

    function test_GetTotalCollateralRealtime_MatchesDepositValue() public {
        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 1000e18); // 1000e18 * 1e8 / 1e18 = 1000e8 USD
        weth.approve(address(pool), 1e18);
        pool.deposit(WETH_MARKET, 1e18);    // 1e18 * 3000e8 / 1e18 = 3000e8 USD
        vm.stopPrank();

        uint256 expected = 1000e8 + 3000e8; // raw collateral value in USD 8 decimals
        assertEq(pool.getTotalCollateralRealtime(alice), expected);
    }

    function test_GetTotalBorrowsRealtime_MatchesBorrowValue() public {
        vm.startPrank(bob);
        usdc.approve(address(pool), 50_000e18);
        pool.deposit(USDC_MARKET, 50_000e18);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(pool), 10e18);
        pool.deposit(WETH_MARKET, 10e18);
        pool.borrow(USDC_MARKET, 500e18); // 500e18 * 1e8 / 1e18 = 500e8 USD
        vm.stopPrank();

        assertEq(pool.getTotalBorrowsRealtime(alice), 500e8);
    }

    function test_GetTotalCollateralRealtime_ReflectsOraclePriceChange() public {
        vm.startPrank(alice);
        weth.approve(address(pool), 1e18);
        pool.deposit(WETH_MARKET, 1e18);
        vm.stopPrank();

        assertEq(pool.getTotalCollateralRealtime(alice), 3000e8); // 1 WETH @ $3000

        oracle.setPrice(WETH_MARKET, 2000e8);
        assertEq(pool.getTotalCollateralRealtime(alice), 2000e8); // 1 WETH @ $2000
    }

    function test_GetTotalBorrowsRealtime_ReflectsOraclePriceChange() public {
        vm.startPrank(bob);
        usdc.approve(address(pool), 100_000e18);
        pool.deposit(USDC_MARKET, 100_000e18);
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(pool), 2e18);
        pool.deposit(WETH_MARKET, 2e18);
        pool.borrow(USDC_MARKET, 1000e18); // $1000 at 1e8
        vm.stopPrank();

        assertEq(pool.getTotalBorrowsRealtime(alice), 1000e8);

        oracle.setPrice(USDC_MARKET, 1.2e8); // USDC price up => borrow value up
        assertEq(pool.getTotalBorrowsRealtime(alice), 1200e8); // 1000e18 * 1.2e8 / 1e18
    }

    function test_HealthFactorBelowOneLiquidatable() public {
        vm.startPrank(bob);
        usdc.approve(address(pool), 50_000e18);
        pool.deposit(USDC_MARKET, 50_000e18); // Bob supplies liquidity
        vm.stopPrank();

        vm.startPrank(alice);
        weth.approve(address(pool), 10e18);
        pool.deposit(WETH_MARKET, 10e18);

        usdc.approve(address(pool), 1e18);
        pool.deposit(USDC_MARKET, 1e18);

        pool.borrow(USDC_MARKET, 24_000e18); // near max, health ~1.06
        vm.stopPrank();

        assertGt(pool.getHealthFactor(alice), 1e18);

        oracle.setPrice(WETH_MARKET, 2000e8); // WETH drops to $2000

        // Use realtime view so we see new oracle price (synced getHealthFactor would use cached price)
        assertLt(pool.getHealthFactorRealtime(alice), 1e18);

        uint256 bobBefore = usdc.balanceOf(bob);
        vm.startPrank(bob);
        usdc.approve(address(pool), 20_000e18);
        pool.liquidateCrossMarket(alice, USDC_MARKET, WETH_MARKET, 12_000e18, 0); // close factor 50% of 24k = 12k max
        vm.stopPrank();

        assertLt(pool.getBorrowBalance(alice, USDC_MARKET), 24_000e18);
        assertGt(weth.balanceOf(bob), 0); // bob received underlying WETH as seized collateral
        assertLt(usdc.balanceOf(bob), bobBefore); // bob spent USDC to repay
    }

    function test_CannotWithdrawWouldViolateHealth() public {
        vm.prank(bob);
        usdc.approve(address(pool), 3000e18);
        vm.prank(bob);
        pool.deposit(USDC_MARKET, 3000e18);
        vm.startPrank(alice);
        weth.approve(address(pool), 1e18);
        pool.deposit(WETH_MARKET, 1e18);   // 1 WETH @ $3000 = $3000, 80% = $2400
        pool.borrow(USDC_MARKET, 2000e18); // near limit

        vm.expectRevert(LendingPoolV2.HealthFactorWouldViolate.selector);
        pool.withdraw(WETH_MARKET, 0.5e18); // would make health < 1
        vm.stopPrank();
    }

    function test_GetAvailableLiquidity() public {
        vm.prank(bob);
        usdc.approve(address(pool), 1000e18);
        vm.prank(bob);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.startPrank(alice);
        weth.approve(address(pool), 1e18);
        pool.deposit(WETH_MARKET, 1e18);
        pool.borrow(USDC_MARKET, 300e18);
        vm.stopPrank();

        assertEq(pool.getAvailableLiquidity(USDC_MARKET), 700e18);
    }

    function test_MarketTotalDepositsAndBorrows() public {
        vm.startPrank(bob);
        usdc.approve(address(pool), 1000e18);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.stopPrank();

        assertEq(pool.getMarketTotalDeposits(USDC_MARKET), 1000e18);
        assertEq(pool.getMarketTotalBorrows(USDC_MARKET), 0);

        vm.startPrank(alice);
        weth.approve(address(pool), 1e18);
        pool.deposit(WETH_MARKET, 1e18);
        pool.borrow(USDC_MARKET, 500e18);
        vm.stopPrank();

        assertEq(pool.getMarketTotalDeposits(USDC_MARKET), 1000e18);
        assertEq(pool.getMarketTotalBorrows(USDC_MARKET), 500e18);
    }

    function test_MarketPausedBlocksOperations() public {
        pool.setMarketPaused(USDC_MARKET, true);

        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        vm.expectRevert(LendingPoolV2.MarketPaused.selector);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.stopPrank();

        pool.setMarketPaused(USDC_MARKET, false);

        vm.startPrank(alice);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.stopPrank();

        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 1000e18);
    }

    function test_PausedBlocksOperations() public {
        pool.setPaused(true);
        assertTrue(pool.paused());

        vm.startPrank(alice);
        usdc.approve(address(pool), 1000e18);
        vm.expectRevert(LendingPoolV2.ProtocolPaused.selector);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.stopPrank();

        pool.setPaused(false);
        assertFalse(pool.paused());

        vm.startPrank(alice);
        pool.deposit(USDC_MARKET, 1000e18);
        vm.stopPrank();

        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 1000e18);
    }

    // --- ERC-20 Permit deposit tests ---

    /// @notice Helper function to sign a permit message
    function _signPermit(
        MockERC20 token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint256 privateKey
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );
        
        uint256 nonce = token.nonces(owner);
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline)
        );
        
        bytes32 domainSeparator = token.DOMAIN_SEPARATOR();
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        (v, r, s) = vm.sign(privateKey, hash);
    }

    function test_depositWithPermit_success() public {
        uint256 amount = 1000e18;
        uint256 deadline = block.timestamp + 1 hours;
        
        // Sign permit
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            usdc,
            alice,
            address(pool),
            amount,
            deadline,
            ALICE_PRIVATE_KEY
        );
        
        // Deposit with permit (no pre-approval needed)
        vm.startPrank(alice);
        pool.depositWithPermit(USDC_MARKET, amount, deadline, v, r, s);
        vm.stopPrank();
        
        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), amount);
        assertEq(usdc.balanceOf(address(pool)), amount);
        assertEq(usdc.allowance(alice, address(pool)), 0); // Permit approval is consumed
    }

    function test_depositWithPermit_updates_balances_correctly() public {
        uint256 amount = 500e18;
        uint256 deadline = block.timestamp + 1 hours;
        
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            usdc,
            alice,
            address(pool),
            amount,
            deadline,
            ALICE_PRIVATE_KEY
        );
        
        vm.startPrank(alice);
        pool.depositWithPermit(USDC_MARKET, amount, deadline, v, r, s);
        vm.stopPrank();
        
        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), amount);
        assertEq(pool.getMarketTotalDeposits(USDC_MARKET), amount);
        
        // Deposit again with regular deposit
        vm.startPrank(alice);
        usdc.approve(address(pool), 300e18);
        pool.deposit(USDC_MARKET, 300e18);
        vm.stopPrank();
        
        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), 800e18);
        assertEq(pool.getMarketTotalDeposits(USDC_MARKET), 800e18);
    }

    function test_depositWithPermit_reverts_on_expired_deadline() public {
        uint256 amount = 1000e18;
        uint256 deadline = block.timestamp - 1; // Expired
        
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            usdc,
            alice,
            address(pool),
            amount,
            deadline,
            ALICE_PRIVATE_KEY
        );
        
        vm.startPrank(alice);
        // Permit will revert with "Permit expired" from MockERC20
        vm.expectRevert("Permit expired");
        pool.depositWithPermit(USDC_MARKET, amount, deadline, v, r, s);
        vm.stopPrank();
    }

    function test_depositWithPermit_reverts_on_invalid_signature() public {
        uint256 amount = 1000e18;
        uint256 deadline = block.timestamp + 1 hours;
        
        // Use wrong private key (Bob's instead of Alice's)
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            usdc,
            alice,
            address(pool),
            amount,
            deadline,
            BOB_PRIVATE_KEY
        );
        
        vm.startPrank(alice);
        vm.expectRevert(); // TransferFailed from permit failure
        pool.depositWithPermit(USDC_MARKET, amount, deadline, v, r, s);
        vm.stopPrank();
    }

    function test_depositWithPermit_works_with_multiple_users() public {
        uint256 aliceAmount = 1000e18;
        uint256 bobAmount = 500e18;
        uint256 deadline = block.timestamp + 1 hours;
        
        // Alice's permit
        (uint8 v1, bytes32 r1, bytes32 s1) = _signPermit(
            usdc,
            alice,
            address(pool),
            aliceAmount,
            deadline,
            ALICE_PRIVATE_KEY
        );
        
        // Bob's permit
        (uint8 v2, bytes32 r2, bytes32 s2) = _signPermit(
            usdc,
            bob,
            address(pool),
            bobAmount,
            deadline,
            BOB_PRIVATE_KEY
        );
        
        vm.startPrank(alice);
        pool.depositWithPermit(USDC_MARKET, aliceAmount, deadline, v1, r1, s1);
        vm.stopPrank();
        
        vm.startPrank(bob);
        pool.depositWithPermit(USDC_MARKET, bobAmount, deadline, v2, r2, s2);
        vm.stopPrank();
        
        assertEq(pool.getSupplyBalance(alice, USDC_MARKET), aliceAmount);
        assertEq(pool.getSupplyBalance(bob, USDC_MARKET), bobAmount);
        assertEq(pool.getMarketTotalDeposits(USDC_MARKET), aliceAmount + bobAmount);
    }
}
