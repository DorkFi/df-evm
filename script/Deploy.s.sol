// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LendingPoolV2Script} from "./LendingPoolV2.s.sol";
import {LendingPoolV2HederaScript} from "./LendingPoolV2Hedera.s.sol";
import {LendingPoolV2MonadScript} from "./LendingPoolV2Monad.s.sol";
import {LendingPoolV2OGScript} from "./LendingPoolV2OG.s.sol";

/// @notice Single entry point for deployments. Select target via DEPLOY_TARGET env var.
/// @dev
///   Signing: private key is read from env. Put PRIVATE_KEY=0x... in .env (project root); Foundry loads .env automatically when you run forge script.
///   Targets: base-sepolia | hedera-testnet | monad-testnet | og-testnet
///   Examples (use FOUNDRY_PROFILE, not --profile):
///     FOUNDRY_PROFILE=base-sepolia   DEPLOY_TARGET=base-sepolia forge script script/Deploy.s.sol:DeployScript --rpc-url base_sepolia --broadcast
///     FOUNDRY_PROFILE=hedera-testnet DEPLOY_TARGET=hedera-testnet forge script script/Deploy.s.sol:DeployScript --rpc-url hedera_testnet --broadcast
///     FOUNDRY_PROFILE=monad-testnet  DEPLOY_TARGET=monad-testnet forge script script/Deploy.s.sol:DeployScript --rpc-url monad_testnet --broadcast
///     FOUNDRY_PROFILE=og-testnet     DEPLOY_TARGET=og-testnet forge script script/Deploy.s.sol:DeployScript --rpc-url og_testnet --broadcast
///   To add a new target: add a profile in foundry.toml, add an rpc_endpoint, then add a branch here and a script contract.
contract DeployScript is Script {
    function run() public {
        string memory target = vm.envOr("DEPLOY_TARGET", string("base-sepolia"));

        if (eq(target, "base-sepolia")) {
            new LendingPoolV2Script().run();
            return;
        }
        if (eq(target, "hedera-testnet")) {
            new LendingPoolV2HederaScript().run();
            return;
        }
        if (eq(target, "monad-testnet")) {
            new LendingPoolV2MonadScript().run();
            return;
        }
        if (eq(target, "og-testnet")) {
            new LendingPoolV2OGScript().run();
            return;
        }

        console.log("Unknown DEPLOY_TARGET: %s", target);
        console.log("Supported: base-sepolia, hedera-testnet, monad-testnet, og-testnet");
        revert("Unknown DEPLOY_TARGET");
    }

    function eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }
}
