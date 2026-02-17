// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LendingPoolV2DeployBase} from "./LendingPoolV2DeployBase.s.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {MockOracle} from "../src/MockOracle.sol";

/// @notice Deploys LendingPoolV2 + MockOracle + markets for Base Sepolia (or any EVM chain).
/// @dev Run: FOUNDRY_PROFILE=base-sepolia forge script script/LendingPoolV2.s.sol:LendingPoolV2Script --rpc-url base_sepolia --broadcast
contract LendingPoolV2Script is LendingPoolV2DeployBase {
    function run() public {
        vm.startBroadcast();

        MockOracle oracle = new MockOracle();
        LendingPoolV2 pool = new LendingPoolV2(address(oracle));

        DeployResult memory r = _deployAndConfigureMarkets(pool, oracle);

        vm.stopBroadcast();

        _logDeployResult("LendingPoolV2 deployment (Base Sepolia)", r);
    }
}
