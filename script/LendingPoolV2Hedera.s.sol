// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LendingPoolV2DeployBase} from "./LendingPoolV2DeployBase.s.sol";
import {LendingPoolV2Hedera} from "../src/LendingPoolV2Hedera.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {MockOracle} from "../src/MockOracle.sol";

/// @notice Deploys LendingPoolV2Hedera + MockOracle + markets for Hedera Testnet.
/// @dev Run: FOUNDRY_PROFILE=hedera-testnet forge script script/LendingPoolV2Hedera.s.sol:LendingPoolV2HederaScript --rpc-url hedera_testnet --broadcast
contract LendingPoolV2HederaScript is LendingPoolV2DeployBase {
    function run() public {
        vm.startBroadcast();

        MockOracle oracle = new MockOracle();
        LendingPoolV2Hedera pool = new LendingPoolV2Hedera(address(oracle));

        DeployResult memory r = _deployAndConfigureMarkets(LendingPoolV2(address(pool)), oracle);

        vm.stopBroadcast();

        _logDeployResult("LendingPoolV2Hedera deployment (Hedera Testnet)", r);
    }
}
