// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {NToken} from "../src/NToken.sol";
import {SToken} from "../src/SToken.sol";
import {FixedPriceFeed} from "../src/FixedPriceFeed.sol";
import {DorkFiDeployLib} from "../src/deploy/DorkFiDeployLib.sol";
import {MockOracle} from "../src/MockOracle.sol";

/// @notice Print creation-code hashes for audit bytecode freeze (Entersoft / DOR-502).
/// Run: forge script script/AuditBytecodeHash.s.sol -vv
contract AuditBytecodeHashScript is Script {
    function run() external {
        address admin = makeAddr("audit-freeze-admin");

        console2.log("=== DorkFi audit bytecode freeze ===");

        console2.log("LendingPoolV2 creation code hash:");
        console2.logBytes32(keccak256(type(LendingPoolV2).creationCode));

        console2.log("NToken creation code hash:");
        console2.logBytes32(keccak256(type(NToken).creationCode));

        console2.log("SToken creation code hash:");
        console2.logBytes32(keccak256(type(SToken).creationCode));

        console2.log("FixedPriceFeed creation code hash:");
        console2.logBytes32(keccak256(type(FixedPriceFeed).creationCode));

        MockOracle oracle = new MockOracle();
        DorkFiDeployLib.PoolProxyDeployment memory d =
            DorkFiDeployLib.deployPoolProxy(address(oracle), admin);

        console2.log("LendingPoolV2 implementation (locked):");
        console2.logAddress(d.implementation);
        console2.log("TransparentUpgradeableProxy (runtime):");
        console2.logAddress(d.proxy);
        console2.log("ProxyAdmin:");
        console2.logAddress(address(d.proxyAdmin));

        console2.log("Note: ChainlinkOracleRouter is OUT OF SCOPE for this audit.");
    }
}
