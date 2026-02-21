// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LendingPoolV2Hedera} from "../src/LendingPoolV2Hedera.sol";

/// @notice Calls startKeeper on an existing LendingPoolV2Hedera on Hedera Testnet.
/// @dev Requires LENDING_POOL_ADDRESS. Optional: MARKET_ID (default 0), KEEPER_INTERVAL_SECONDS (default 3600).
///
/// RECOMMENDED: Use cast send so the call runs only on Hedera (Schedule Service 0x16B exists there).
/// Forge script still runs the script in the local VM to build the broadcast list, so it reverts on 0x16B
/// even with --skip-simulation. The tutorial-hss-rebalancer works because Hardhat sends the tx without
/// simulating contract execution locally.
///
///   cast send $LENDING_POOL_ADDRESS "startKeeper(uint64,uint256)" 0 3600 \
///     --rpc-url https://testnet.hashio.io/api --chain-id 296 --private-key $PRIVATE_KEY
///
/// With env: MARKET_ID=0 KEEPER_INTERVAL_SECONDS=3600
///   cast send $LENDING_POOL_ADDRESS "startKeeper(uint64,uint256)" $MARKET_ID $KEEPER_INTERVAL_SECONDS \
///     --rpc-url https://testnet.hashio.io/api --chain-id 296 --private-key $PRIVATE_KEY
contract StartKeeperHederaScript is Script {
    function run() public {
        address poolAddr = vm.envAddress("LENDING_POOL_ADDRESS");
        uint64 marketId = uint64(vm.envOr("MARKET_ID", uint256(0)));
        uint256 intervalSeconds = vm.envOr("KEEPER_INTERVAL_SECONDS", uint256(3600));

        console.log("LENDING_POOL_ADDRESS:", poolAddr);
        console.log("MARKET_ID (0=USDC, 1=cbBTC, 2=EURC, 3=WAD):", marketId);
        console.log("KEEPER_INTERVAL_SECONDS:", intervalSeconds);

        LendingPoolV2Hedera pool = LendingPoolV2Hedera(payable(poolAddr));

        vm.startBroadcast();
        pool.startKeeper(marketId, intervalSeconds);
        vm.stopBroadcast();
    }
}
