// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {MockOracle} from "../src/MockOracle.sol";

/// @notice Configures an existing LendingPoolV2: creates markets and sets oracle prices.
/// @dev Requires LENDING_POOL_ADDRESS and ORACLE_ADDRESS env vars.
/// Run: LENDING_POOL_ADDRESS=0x... ORACLE_ADDRESS=0x... forge script script/LendingPoolV2Config.s.sol:LendingPoolV2ConfigScript --rpc-url <RPC> --broadcast
contract LendingPoolV2ConfigScript is Script {
    // Base Sepolia token addresses
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant CB_BTC = 0xcbB7C0006F23900c38EB856149F799620fcb8A4a;
    address constant EURC = 0x808456652fdb597867f38412077A9182bf77359F;

    function run() public {
        address poolAddr = vm.envAddress("LENDING_POOL_ADDRESS");
        address oracleAddr = vm.envAddress("ORACLE_ADDRESS");

        LendingPoolV2 pool = LendingPoolV2(poolAddr);
        MockOracle oracle = MockOracle(oracleAddr);

        LendingPoolV2.MarketParams memory params = LendingPoolV2.MarketParams({
            borrowRate: 0.05e18,
            slope: 0.10e18,
            reserveFactor: 0.10e18,
            collateralFactorBps: 8000,
            liquidationThresholdBps: 8500,
            closeFactorBps: 5000,
            liquidationBonusBps: 500
        });

        vm.startBroadcast();

        // Create markets and capture marketIds (handles pools that already have markets)
        uint64 marketIdUsdc = pool.createMarket(USDC, params);
        uint64 marketIdCbBtc = pool.createMarket(CB_BTC, params);
        uint64 marketIdEurc = pool.createMarket(EURC, params);

        // Set oracle prices (8 decimals: 1e8 = $1)
        oracle.setPrice(marketIdUsdc, 1e8);           // USDC ~$1
        oracle.setPrice(marketIdCbBtc, 100_000e8);     // cbBTC ~$100k
        oracle.setPrice(marketIdEurc, 1.08e8);        // EURC ~$1.08

        vm.stopBroadcast();
    }
}
