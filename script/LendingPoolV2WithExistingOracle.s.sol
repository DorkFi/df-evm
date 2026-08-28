// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/Console.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";

/// @notice Deploys a new LendingPoolV2 using an existing MockOracle.
/// @dev Requires ORACLE_ADDRESS env var.
/// Run: ORACLE_ADDRESS=0x... forge script script/LendingPoolV2WithExistingOracle.s.sol:LendingPoolV2WithExistingOracleScript --rpc-url <RPC> --broadcast
contract LendingPoolV2WithExistingOracleScript is Script {
    function run() public {
        address oracleAddr = vm.envAddress("ORACLE_ADDRESS");

        vm.startBroadcast();

        LendingPoolV2 pool = new LendingPoolV2(oracleAddr, msg.sender);
        console.log("LendingPoolV2 deployed at:", address(pool));

        vm.stopBroadcast();
    }
}
