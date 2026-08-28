// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LendingPoolV2DeployBase} from "./LendingPoolV2DeployBase.s.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {MockOracle} from "../src/MockOracle.sol";

/// @notice Deploys LendingPoolV2 + MockOracle + markets for Monad Testnet.
/// @dev Run: FOUNDRY_PROFILE=monad-testnet forge script script/LendingPoolV2Monad.s.sol:LendingPoolV2MonadScript --rpc-url monad_testnet --broadcast
contract LendingPoolV2MonadScript is LendingPoolV2DeployBase {
    function run() public {
        vm.startBroadcast();

        MockOracle oracle = new MockOracle();
        LendingPoolV2 pool = new LendingPoolV2(address(oracle), msg.sender);

        DeployResult memory r = _deployAndConfigureMarkets(pool, oracle);

        vm.stopBroadcast();

        _logDeployResult("LendingPoolV2 deployment (Monad Testnet)", r);
    }
}
