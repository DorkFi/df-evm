// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {SToken} from "../src/SToken.sol";
import {ChainlinkOracleRouter} from "../src/ChainlinkOracleRouter.sol";
import {ChainlinkFeeds} from "../src/libraries/ChainlinkFeeds.sol";
import {FixedPriceFeed} from "../src/FixedPriceFeed.sol";

/// @title LendingPoolV2BaseMainnetScript
/// @notice Deploys LendingPoolV2 + ChainlinkOracleRouter on Base mainnet with canonical markets:
///         USDC, WETH, cbBTC, and WAD (SToken). Native ETH (`address(0)`) is not listed — use WETH.
///
/// @dev Canonical Base tokens (matches base-bl-ui `BASE_MAINNET_TOKENS`):
///   USDC  0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
///   WETH  0x4200000000000000000000000000000000000006
///   cbBTC 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf
///
/// Market ID order (createMarket order):
///   0 = USDC, 1 = WETH, 2 = cbBTC, 3 = WAD
///
/// Env (optional):
///   MAX_PRICE_AGE              — seconds (default 3600)
///   ENABLE_SEQUENCER           — default true on chainId 8453
///   MAX_TOTAL_DEPOSITS_USDC    — default type(uint256).max (set tighter for soft launch)
///   MAX_TOTAL_BORROWS_USDC     — default type(uint256).max
///   (same pattern for _WETH, _CBBTC, _WAD)
///
/// Dry run:
///   FOUNDRY_PROFILE=base-mainnet forge script script/LendingPoolV2BaseMainnet.s.sol:LendingPoolV2BaseMainnetScript \
///     --rpc-url base
///
/// Broadcast:
///   source .env
///   FOUNDRY_PROFILE=base-mainnet forge script script/LendingPoolV2BaseMainnet.s.sol:LendingPoolV2BaseMainnetScript \
///     --rpc-url base --broadcast --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)
contract LendingPoolV2BaseMainnetScript is Script {
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    struct Result {
        address pool;
        address oracle;
        address wad;
        address wadFeed;
        uint64 marketIdUsdc;
        uint64 marketIdWeth;
        uint64 marketIdCbBtc;
        uint64 marketIdWad;
    }

    function _defaultMarketParams() internal pure returns (LendingPoolV2.MarketParams memory) {
        // Conservative starter params — tune per asset before raising caps.
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

    function run() public {
        require(block.chainid == 8453, "LendingPoolV2BaseMainnet: not Base mainnet (8453)");

        uint256 maxPriceAge = vm.envOr("MAX_PRICE_AGE", uint256(3600));
        bool enableSequencer = vm.envOr("ENABLE_SEQUENCER", true);

        uint256 maxDepUsdc = vm.envOr("MAX_TOTAL_DEPOSITS_USDC", type(uint256).max);
        uint256 maxBorUsdc = vm.envOr("MAX_TOTAL_BORROWS_USDC", type(uint256).max);
        uint256 maxDepWeth = vm.envOr("MAX_TOTAL_DEPOSITS_WETH", type(uint256).max);
        uint256 maxBorWeth = vm.envOr("MAX_TOTAL_BORROWS_WETH", type(uint256).max);
        uint256 maxDepCbBtc = vm.envOr("MAX_TOTAL_DEPOSITS_CBBTC", type(uint256).max);
        uint256 maxBorCbBtc = vm.envOr("MAX_TOTAL_BORROWS_CBBTC", type(uint256).max);
        uint256 maxDepWad = vm.envOr("MAX_TOTAL_DEPOSITS_WAD", uint256(0)); // borrow-only by default
        uint256 maxBorWad = vm.envOr("MAX_TOTAL_BORROWS_WAD", type(uint256).max);

        Result memory r;
        LendingPoolV2.MarketParams memory params = _defaultMarketParams();

        vm.startBroadcast();

        // 1) Oracle first (pool constructor requires an oracle address)
        ChainlinkOracleRouter router = new ChainlinkOracleRouter();
        router.setMaxPriceAge(maxPriceAge);
        if (enableSequencer) {
            router.setSequencerUptimeFeed(ChainlinkFeeds.BASE_SEQUENCER_UPTIME);
        }

        // 2) Pool
        LendingPoolV2 pool = new LendingPoolV2(address(router));
        r.pool = address(pool);
        r.oracle = address(router);

        // 3) Markets: USDC, WETH, cbBTC
        r.marketIdUsdc = pool.createMarket(USDC, params);
        r.marketIdWeth = pool.createMarket(WETH, params);
        r.marketIdCbBtc = pool.createMarket(CBBTC, params);

        // 4) WAD SToken (predict next market id)
        uint64 nextId = pool.totalMarkets();
        SToken wad = new SToken(address(pool), nextId, "Whale Asset Dollar", "WAD", 6);
        r.wad = address(wad);
        r.marketIdWad = pool.createMarket(address(wad), params);
        require(r.marketIdWad == nextId, "WAD marketId mismatch");
        pool.setStokenMarketId(r.marketIdWad);

        // 5) Caps (createMarket defaults to 0 — deposits/borrows blocked until set)
        pool.setMaxTotalDeposits(r.marketIdUsdc, maxDepUsdc);
        pool.setMaxTotalBorrows(r.marketIdUsdc, maxBorUsdc);
        pool.setMaxTotalDeposits(r.marketIdWeth, maxDepWeth);
        pool.setMaxTotalBorrows(r.marketIdWeth, maxBorWeth);
        pool.setMaxTotalDeposits(r.marketIdCbBtc, maxDepCbBtc);
        pool.setMaxTotalBorrows(r.marketIdCbBtc, maxBorCbBtc);
        pool.setMaxTotalDeposits(r.marketIdWad, maxDepWad);
        pool.setMaxTotalBorrows(r.marketIdWad, maxBorWad);

        // 6) Chainlink feeds
        router.setFeed(r.marketIdUsdc, ChainlinkFeeds.BASE_USDC_USD);
        router.setFeed(r.marketIdWeth, ChainlinkFeeds.BASE_ETH_USD);
        router.setFeed(r.marketIdCbBtc, ChainlinkFeeds.BASE_BTC_USD);

        // WAD = fixed $1 (8 decimals)
        FixedPriceFeed wadFeed = new FixedPriceFeed(1e8, "WAD / USD");
        r.wadFeed = address(wadFeed);
        router.setFeed(r.marketIdWad, address(wadFeed));

        vm.stopBroadcast();

        _log(r, enableSequencer);
    }

    function _log(Result memory r, bool enableSequencer) internal pure {
        console.log("");
        console.log("=== LendingPoolV2 Base mainnet ===");
        console.log("Pool                     ", r.pool);
        console.log("ChainlinkOracleRouter    ", r.oracle);
        console.log("SToken_WAD               ", r.wad);
        console.log("FixedPriceFeed_WAD       ", r.wadFeed);
        console.log("--- Market IDs ---");
        console.log("marketId_USDC            ", r.marketIdUsdc);
        console.log("marketId_WETH            ", r.marketIdWeth);
        console.log("marketId_cbBTC           ", r.marketIdCbBtc);
        console.log("marketId_WAD             ", r.marketIdWad);
        console.log("sequencerEnabled         ", enableSequencer);
        console.log("");
        console.log("--- base-bl-ui .env ---");
        console.log("VITE_LENDING_POOL_ADDRESS_MAINNET");
        console.log(r.pool);
        console.log("VITE_LENDING_ORACLE_MAINNET");
        console.log(r.oracle);
        console.log("VITE_WAD_ADDRESS_MAINNET");
        console.log(r.wad);
        console.log("");
        console.log("Next: verify on Basescan, soft-launch caps, smoke-test UI.");
    }
}
