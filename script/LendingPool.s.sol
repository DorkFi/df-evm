// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {LendingPoolETH} from "../src/LendingPoolETH.sol";
import {LendingPoolERC20} from "../src/LendingPoolERC20.sol";

contract LendingPoolScript is Script {
    LendingPoolETH public poolEth;
    LendingPoolERC20 public poolERC20;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        poolEth = new LendingPoolETH();
        // poolERC20 = new LendingPoolERC20(address(TOKEN_ADDRESS)); // set token for ERC20 pool

        vm.stopBroadcast();
    }
}
