// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LendingPoolV2DeployBase} from "./LendingPoolV2DeployBase.s.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {MockOracle} from "../src/MockOracle.sol";

/// @notice Deploys LendingPoolV2 + MockOracle + markets for 0G (OG) Testnet.
/// @dev Run: FOUNDRY_PROFILE=og-testnet forge script script/LendingPoolV2OG.s.sol:LendingPoolV2OGScript --rpc-url og_testnet --broadcast
contract LendingPoolV2OGScript is LendingPoolV2DeployBase {
    function run() public {
        vm.startBroadcast();

        MockOracle oracle = new MockOracle();
        LendingPoolV2 pool = new LendingPoolV2(address(oracle));

        DeployResult memory r = _deployAndConfigureMarkets(pool, oracle);

        vm.stopBroadcast();

        _logDeployResult("LendingPoolV2 deployment (0G Testnet)", r);
    }
}
