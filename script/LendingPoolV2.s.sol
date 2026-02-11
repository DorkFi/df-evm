// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {MockOracle} from "../src/MockOracle.sol";
import {AToken} from "../src/AToken.sol";
import {SToken} from "../src/SToken.sol";

contract LendingPoolV2Script is Script {
    function run() public {
        vm.startBroadcast();

        MockOracle oracle = new MockOracle();
        LendingPoolV2 pool = new LendingPoolV2(address(oracle));

        AToken usdc = new AToken("USD Coin", "USDC", 6, 0);
        AToken cbBtc = new AToken("Coinbase Wrapped Bitcoin", "cbBTC", 8, 0);
        AToken eurc = new AToken("Euro Coin", "EURC", 6, 0);

        LendingPoolV2.MarketParams memory params = LendingPoolV2.MarketParams({
            borrowRate: 0.05e18,
            slope: 0.10e18,
            reserveFactor: 0.10e18,
            collateralFactorBps: 8000,
            liquidationThresholdBps: 8500,
            closeFactorBps: 5000,
            liquidationBonusBps: 500
        });

        uint64 marketIdUsdc = pool.createMarket(address(usdc), params);
        uint64 marketIdCbBtc = pool.createMarket(address(cbBtc), params);
        uint64 marketIdEurc = pool.createMarket(address(eurc), params);

        // Borrow-only (SToken) market: deploy SToken with next marketId (3), then create market and set as stoken
        uint64 nextMarketId = pool.totalMarkets();
        SToken stoken = new SToken(
            address(pool),
            nextMarketId,
            "Whale Asset Dollar",
            "WAD",
            6
        );
        uint64 marketIdStoken = pool.createMarket(address(stoken), params);
        pool.setStokenMarketId(marketIdStoken);

        oracle.setPrice(marketIdUsdc, 1e8); // USDC ~$1
        oracle.setPrice(marketIdCbBtc, 100_000e8); // cbBTC ~$100k
        oracle.setPrice(marketIdEurc, 1.08e8); // EURC ~$1.08
        oracle.setPrice(marketIdStoken, 1e8); // sUSDC ~$1

        pool.setMaxTotalDeposits(marketIdUsdc, type(uint256).max);
        pool.setMaxTotalDeposits(marketIdCbBtc, type(uint256).max);
        pool.setMaxTotalDeposits(marketIdEurc, type(uint256).max);
        pool.setMaxTotalBorrows(marketIdUsdc, type(uint256).max);
        pool.setMaxTotalBorrows(marketIdCbBtc, type(uint256).max);
        pool.setMaxTotalBorrows(marketIdEurc, type(uint256).max);
        pool.setMaxTotalBorrows(marketIdStoken, type(uint256).max);

        vm.stopBroadcast();

        console.log("");
        console.log("=== LendingPoolV2 deployment ===");
        console.log("MockOracle      ", address(oracle));
        console.log("LendingPoolV2   ", address(pool));
        console.log("AToken_USDC     ", address(usdc));
        console.log("AToken_cbBTC    ", address(cbBtc));
        console.log("AToken_EURC     ", address(eurc));
        console.log("SToken_WAD    ", address(stoken));
        console.log("--- Market IDs ---");
        console.log("marketId_USDC   ", marketIdUsdc);
        console.log("marketId_cbBTC  ", marketIdCbBtc);
        console.log("marketId_EURC   ", marketIdEurc);
        console.log("marketId_WAD  ", marketIdStoken);
    }
}
