// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LendingPoolV2DeployBase} from "./LendingPoolV2DeployBase.s.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {MockOracle} from "../src/MockOracle.sol";

/// @notice Adds an ETH test market (mintable AToken) to an existing LendingPoolV2 deployment.
/// @dev Requires pool owner PRIVATE_KEY. Set LENDING_POOL_ADDRESS and ORACLE_ADDRESS.
///
/// Base Sepolia example:
///   source .env
///   LENDING_POOL_ADDRESS=0x8045c02eCd91E8ff98BE8B49277730c0781D2215 \
///   ORACLE_ADDRESS=0x74F6246AF46d21D1bC68a57A5934A42BB4F8EBdD \
///   FOUNDRY_PROFILE=base-sepolia forge script script/AddEthMarket.s.sol:AddEthMarketScript \
///     --rpc-url base_sepolia --broadcast \
///     --private-key $PRIVATE_KEY --sender $(cast wallet address $PRIVATE_KEY)
///
/// Optional: ETH_PRICE_USD=300000000000 (8 decimals; default 3000e8 = $3000)
contract AddEthMarketScript is LendingPoolV2DeployBase {
    function run() public {
        address poolAddr = vm.envAddress("LENDING_POOL_ADDRESS");
        address oracleAddr = vm.envAddress("ORACLE_ADDRESS");

        LendingPoolV2 pool = LendingPoolV2(poolAddr);
        MockOracle oracle = MockOracle(oracleAddr);

        vm.startBroadcast();

        (address aTokenEth, uint64 marketIdEth) = _deployAndConfigureEthMarket(pool, oracle);

        vm.stopBroadcast();

        _logEthMarketResult(poolAddr, aTokenEth, marketIdEth);
    }
}
