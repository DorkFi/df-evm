// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LendingPoolV2Hedera} from "../src/LendingPoolV2Hedera.sol";

/// @notice Calls testGetPseudorandomSeed() on an existing LendingPoolV2Hedera (e.g. on Hedera Testnet).
/// @dev Requires LENDING_POOL_ADDRESS. Use --skip-simulation when targeting Hedera (PRNG at 0x169 exists only on Hedera).
/// Run: LENDING_POOL_ADDRESS=0x... forge script script/TestGetPseudorandomSeedHedera.s.sol:TestGetPseudorandomSeedHederaScript --rpc-url hedera_testnet --broadcast --skip-simulation
contract TestGetPseudorandomSeedHederaScript is Script {
    function run() public {
        address poolAddr = _parsePoolAddress();
        console.log("LENDING_POOL_ADDRESS:", poolAddr);

        LendingPoolV2Hedera pool = LendingPoolV2Hedera(payable(poolAddr));

        vm.startBroadcast();
        uint256 seed = pool.testGetPseudorandomSeed();
        vm.stopBroadcast();

        console.log("testGetPseudorandomSeed():", seed);
    }

    /// @dev Parses LENDING_POOL_ADDRESS; pads with leading 0 if hex has odd length (e.g. 39 chars).
    function _parsePoolAddress() internal view returns (address) {
        string memory s = vm.envString("LENDING_POOL_ADDRESS");
        bytes memory b = bytes(s);
        if (b.length == 0) revert("LENDING_POOL_ADDRESS is not set");
        uint256 start = 0;
        if (b.length >= 2 && b[0] == "0" && (b[1] == "x" || b[1] == "X")) start = 2;
        uint256 hexLen = b.length - start;
        if (hexLen == 0) revert("LENDING_POOL_ADDRESS is empty");
        if (hexLen % 2 == 1) {
            s = string(abi.encodePacked("0x0", _slice(s, start, b.length)));
        }
        return vm.parseAddress(s);
    }

    function _slice(string memory s, uint256 from, uint256 to) private pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(to - from);
        for (uint256 i = from; i < to; i++) out[i - from] = b[i];
        return string(out);
    }
}
