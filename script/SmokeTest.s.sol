// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {MockOracle} from "../src/MockOracle.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice Smoke test script for deposit and withdraw on deployed contracts
/// @dev Run: LENDING_POOL_ADDRESS=0x... forge script script/SmokeTest.s.sol:SmokeTestScript --rpc-url https://sepolia.base.org --broadcast --chain-id 84532
contract SmokeTestScript is Script {
    // Base Sepolia token addresses
    address constant USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    address constant CB_BTC = 0xcbB7C0006F23900c38EB856149F799620fcb8A4a;
    address constant EURC = 0x808456652fdb597867f38412077A9182bf77359F;

    function run() public {
        address poolAddr = vm.envAddress("LENDING_POOL_ADDRESS");
        LendingPoolV2 pool = LendingPoolV2(poolAddr);

        console.log("=== Smoke Test: Deposit & Withdraw ===");
        console.log("Pool address:", poolAddr);
        console.log("Deployer address:", msg.sender);

        vm.startBroadcast();

        // Find USDC market ID (should be 0 if it's the first market)
        uint64 usdcMarketId = pool.marketIdByToken(USDC);
        console.log("USDC Market ID:", uint256(usdcMarketId));

        // Get USDC token
        IERC20 usdc = IERC20(USDC);
        uint256 deployerBalance = usdc.balanceOf(msg.sender);
        console.log("Deployer USDC balance:", deployerBalance);

        // Test 1: Deposit
        // Use 1 USDC (1e6) or 10% of available balance, whichever is smaller
        uint256 depositAmount = deployerBalance >= 10e6 ? 1e6 : (deployerBalance / 2); // 1 USDC or half of available
        if (deployerBalance >= depositAmount && depositAmount > 0) {
            console.log("\n--- Test 1: Deposit ---");
            console.log("Depositing:", depositAmount);
            
            usdc.approve(address(pool), depositAmount);
            pool.deposit(usdcMarketId, depositAmount);
            
            uint256 supplyBalance = pool.getSupplyBalance(msg.sender, usdcMarketId);
            uint256 marketTotal = pool.getMarketTotalDeposits(usdcMarketId);
            console.log("Supply balance after deposit:", supplyBalance);
            console.log("Market total deposits:", marketTotal);
            
            require(supplyBalance == depositAmount, "Supply balance mismatch");
            require(marketTotal >= depositAmount, "Market total mismatch");
            console.log("[PASS] Deposit test passed");
        } else {
            console.log("[SKIP] Skipping deposit test - insufficient USDC balance");
        }

        // Test 2: Withdraw (partial)
        uint256 currentBalance = pool.getSupplyBalance(msg.sender, usdcMarketId);
        if (currentBalance > 0) {
            console.log("\n--- Test 2: Withdraw (partial) ---");
            uint256 withdrawAmount = currentBalance / 2; // Withdraw half
            console.log("Withdrawing:", withdrawAmount);
            
            uint256 balanceBefore = usdc.balanceOf(msg.sender);
            pool.withdraw(usdcMarketId, withdrawAmount);
            uint256 balanceAfter = usdc.balanceOf(msg.sender);
            
            uint256 supplyBalanceAfter = pool.getSupplyBalance(msg.sender, usdcMarketId);
            console.log("Supply balance after withdraw:", supplyBalanceAfter);
            console.log("USDC balance increase:", balanceAfter - balanceBefore);
            
            require(supplyBalanceAfter == currentBalance - withdrawAmount, "Supply balance after withdraw mismatch");
            require(balanceAfter > balanceBefore, "USDC balance did not increase");
            console.log("[PASS] Withdraw test passed");
        } else {
            console.log("[SKIP] Skipping withdraw test - no deposit balance");
        }

        // Test 3: Verify state consistency
        console.log("\n--- Test 3: State Consistency ---");
        uint256 finalSupplyBalance = pool.getSupplyBalance(msg.sender, usdcMarketId);
        uint256 finalMarketTotal = pool.getMarketTotalDeposits(usdcMarketId);
        uint256 poolUsdcBalance = usdc.balanceOf(address(pool));
        
        console.log("Final supply balance:", finalSupplyBalance);
        console.log("Final market total:", finalMarketTotal);
        console.log("Pool USDC balance:", poolUsdcBalance);
        
        require(finalMarketTotal >= finalSupplyBalance, "Market total should be >= user balance");
        require(poolUsdcBalance >= finalMarketTotal, "Pool balance should be >= market total");
        console.log("[PASS] State consistency check passed");

        vm.stopBroadcast();

        console.log("\n=== All smoke tests passed! ===");
    }
}
