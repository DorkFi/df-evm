// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {LendingPoolHandler} from "./LendingPoolHandler.sol";
import {LendingPoolV2} from "../../src/LendingPoolV2.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";

/// @dev Run: forge test --match-contract LendingPoolInvariant -vv
contract LendingPoolInvariant is StdInvariant, Test {
    LendingPoolHandler internal handler;
    LendingPoolV2 internal pool;
    MockERC20 internal usdc;
    MockERC20 internal weth;

    uint64 internal constant USDC_MARKET = 0;
    uint64 internal constant WETH_MARKET = 1;

    function setUp() public {
        handler = new LendingPoolHandler(address(this));
        pool = handler.pool();
        usdc = handler.usdc();
        weth = handler.weth();

        targetContract(address(handler));
        excludeContract(address(handler.oracle()));
    }

    /// @notice On-chain token balance covers withdrawable liquidity (wei-level rounding slack).
    function invariant_balanceCoversAvailableLiquidityUsdc() public view {
        assertGe(usdc.balanceOf(address(pool)) + 100, pool.getAvailableLiquidity(USDC_MARKET));
    }

    function invariant_balanceCoversAvailableLiquidityWeth() public view {
        assertGe(weth.balanceOf(address(pool)) + 100, pool.getAvailableLiquidity(WETH_MARKET));
    }

    /// @notice Borrows cannot exceed deposits in a single market.
    function invariant_borrowsLteDepositsUsdc() public view {
        assertLe(pool.getMarketTotalBorrows(USDC_MARKET), pool.getMarketTotalDeposits(USDC_MARKET));
    }

    function invariant_borrowsLteDepositsWeth() public view {
        assertLe(pool.getMarketTotalBorrows(WETH_MARKET), pool.getMarketTotalDeposits(WETH_MARKET));
    }

    /// @notice Indices are non-zero after markets exist.
    function invariant_indicesInitialized() public view {
        assertGe(pool.getDepositIndex(USDC_MARKET), 1e18);
        assertGe(pool.getDepositIndex(WETH_MARKET), 1e18);
    }
}
