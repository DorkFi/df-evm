// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LendingPoolV2} from "../LendingPoolV2.sol";

/// @title BaseMarketParams
/// @notice Shared risk parameters and soft-launch caps for Base mainnet / Sepolia dress rehearsal.
/// @dev Env vars in deploy scripts override these defaults when set.
library BaseMarketParams {
    /// @notice Per-market deposit/borrow caps for soft launch (mainnet defaults).
    struct SoftLaunchCaps {
        uint256 maxDepositsUsdc;
        uint256 maxBorrowsUsdc;
        uint256 maxDepositsWeth;
        uint256 maxBorrowsWeth;
        uint256 maxDepositsCbBtc;
        uint256 maxBorrowsCbBtc;
        uint256 maxDepositsWad;
        uint256 maxBorrowsWad;
    }

    /// Conservative starter risk params — tune per asset before raising caps.
    function defaultMarketParams() internal pure returns (LendingPoolV2.MarketParams memory) {
        return LendingPoolV2.MarketParams({
            borrowRate: 0.05e18,
            slope: 0.10e18,
            reserveFactor: 0.10e18,
            collateralFactorBps: 7500,
            liquidationThresholdBps: 8000,
            closeFactorBps: 5000,
            liquidationBonusBps: 500
        });
    }

    /// @notice Documented soft-launch caps for Base mainnet (see docs/deployment/base-mainnet.md).
    function mainnetSoftLaunchCaps() internal pure returns (SoftLaunchCaps memory) {
        return SoftLaunchCaps({
            maxDepositsUsdc: 1_000_000 * 1e6,
            maxBorrowsUsdc: 500_000 * 1e6,
            maxDepositsWeth: 100 ether,
            maxBorrowsWeth: 50 ether,
            maxDepositsCbBtc: 1 * 1e8,
            maxBorrowsCbBtc: 50_000_000,
            maxDepositsWad: 0,
            maxBorrowsWad: 1_000_000 * 1e6
        });
    }

    /// @notice Generous caps for Sepolia dress rehearsal (testnet liquidity).
    function sepoliaDressRehearsalCaps() internal pure returns (SoftLaunchCaps memory) {
        return SoftLaunchCaps({
            maxDepositsUsdc: type(uint256).max,
            maxBorrowsUsdc: type(uint256).max,
            maxDepositsWeth: type(uint256).max,
            maxBorrowsWeth: type(uint256).max,
            maxDepositsCbBtc: type(uint256).max,
            maxBorrowsCbBtc: type(uint256).max,
            maxDepositsWad: 0,
            maxBorrowsWad: type(uint256).max
        });
    }
}
