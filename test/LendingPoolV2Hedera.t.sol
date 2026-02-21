// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {LendingPoolV2Hedera} from "../src/LendingPoolV2Hedera.sol";
import {MockOracle} from "../src/MockOracle.sol";
import {IPrngSystemContract} from "@hashgraph/smart-contracts/contracts/system-contracts/pseudo-random-number-generator/IPrngSystemContract.sol";

contract LendingPoolV2HederaTest is Test {
    LendingPoolV2Hedera public pool;
    MockOracle public oracle;

    address constant PRNG_PRECOMPILE = address(0x169);

    function setUp() public {
        oracle = new MockOracle();
        pool = new LendingPoolV2Hedera(address(oracle));
    }

    function test_testGetPseudorandomSeed() public {
        bytes32 expectedSeed = keccak256("test seed");
        vm.mockCall(
            PRNG_PRECOMPILE,
            abi.encodeWithSelector(IPrngSystemContract.getPseudorandomSeed.selector),
            abi.encode(expectedSeed)
        );

        uint256 result = pool.testGetPseudorandomSeed();

        assertEq(result, uint256(expectedSeed));
    }
}
