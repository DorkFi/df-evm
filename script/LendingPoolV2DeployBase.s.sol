// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LendingPoolV2} from "../src/LendingPoolV2.sol";
import {MockOracle} from "../src/MockOracle.sol";
import {AToken} from "../src/AToken.sol";
import {SToken} from "../src/SToken.sol";

/// @notice Shared deployment logic for LendingPoolV2 and chain-specific variants.
/// @dev Extend this in target scripts and call _deployAndConfigureMarkets after deploying pool + oracle.
abstract contract LendingPoolV2DeployBase is Script {
    struct DeployResult {
        address oracle;
        address pool;
        address aTokenUsdc;
        address aTokenCbBtc;
        address aTokenEurc;
        address aTokenEth;
        address stokenWad;
        uint64 marketIdUsdc;
        uint64 marketIdCbBtc;
        uint64 marketIdEurc;
        uint64 marketIdEth;
        uint64 marketIdStoken;
    }

    function _defaultMarketParams() internal pure returns (LendingPoolV2.MarketParams memory) {
        return LendingPoolV2.MarketParams({
            borrowRate: 0.05e18,
            slope: 0.10e18,
            reserveFactor: 0.10e18,
            collateralFactorBps: 8000,
            liquidationThresholdBps: 8500,
            closeFactorBps: 5000,
            liquidationBonusBps: 500
        });
    }

    /// @dev Oracle price for ETH in 8 decimals (default $3000). Override with ETH_PRICE_USD env var.
    function _ethOraclePrice() internal view returns (uint256) {
        return vm.envOr("ETH_PRICE_USD", uint256(3000e8));
    }

    /// @dev Deploy mintable ETH AToken, register market, set oracle price and deposit/borrow limits.
    function _deployAndConfigureEthMarket(
        LendingPoolV2 pool,
        MockOracle oracle
    ) internal returns (address aTokenEth, uint64 marketIdEth) {
        AToken eth = new AToken("Ether", "ETH", 18, 0);
        aTokenEth = address(eth);
        marketIdEth = pool.createMarket(aTokenEth, _defaultMarketParams());
        oracle.setPrice(marketIdEth, _ethOraclePrice());
        pool.setMaxTotalDeposits(marketIdEth, type(uint256).max);
        pool.setMaxTotalBorrows(marketIdEth, type(uint256).max);
    }

    function _logEthMarketResult(
        address poolAddr,
        address aTokenEth,
        uint64 marketIdEth
    ) internal pure {
        console.log("");
        console.log("=== ETH market added ===");
        console.log("Pool            ", poolAddr);
        console.log("AToken_ETH      ", aTokenEth);
        console.log("marketId_ETH    ", marketIdEth);
        console.log("");
        console.log("--- chains.ts snippet ---");
        console.log('atokens: { eth: "%s" }', aTokenEth);
        console.log('tokens: { "%s": { symbol: "ETH", decimals: 18 } }', aTokenEth);
    }

    /// @dev Deploys aTokens, creates markets, sets oracle prices and limits. Call inside vm.startBroadcast/stopBroadcast.
    function _deployAndConfigureMarkets(
        LendingPoolV2 pool,
        MockOracle oracle
    ) internal returns (DeployResult memory r) {
        r.oracle = address(oracle);
        r.pool = address(pool);

        AToken usdc = new AToken("USD Coin", "USDC", 6, 0);
        AToken cbBtc = new AToken("Coinbase Wrapped Bitcoin", "cbBTC", 8, 0);
        AToken eurc = new AToken("Euro Coin", "EURC", 6, 0);

        r.aTokenUsdc = address(usdc);
        r.aTokenCbBtc = address(cbBtc);
        r.aTokenEurc = address(eurc);

        LendingPoolV2.MarketParams memory params = _defaultMarketParams();

        r.marketIdUsdc = pool.createMarket(address(usdc), params);
        r.marketIdCbBtc = pool.createMarket(address(cbBtc), params);
        r.marketIdEurc = pool.createMarket(address(eurc), params);

        (r.aTokenEth, r.marketIdEth) = _deployAndConfigureEthMarket(pool, oracle);

        uint64 nextMarketId = pool.totalMarkets();
        SToken stoken = new SToken(
            address(pool),
            nextMarketId,
            "Whale Asset Dollar",
            "WAD",
            6
        );
        r.stokenWad = address(stoken);
        r.marketIdStoken = pool.createMarket(address(stoken), params);
        pool.setStokenMarketId(r.marketIdStoken);

        oracle.setPrice(r.marketIdUsdc, 1e8);
        oracle.setPrice(r.marketIdCbBtc, 100_000e8);
        oracle.setPrice(r.marketIdEurc, 1.08e8);
        oracle.setPrice(r.marketIdStoken, 1e8);

        pool.setMaxTotalDeposits(r.marketIdUsdc, type(uint256).max);
        pool.setMaxTotalDeposits(r.marketIdCbBtc, type(uint256).max);
        pool.setMaxTotalDeposits(r.marketIdEurc, type(uint256).max);
        pool.setMaxTotalBorrows(r.marketIdUsdc, type(uint256).max);
        pool.setMaxTotalBorrows(r.marketIdCbBtc, type(uint256).max);
        pool.setMaxTotalBorrows(r.marketIdEurc, type(uint256).max);
        pool.setMaxTotalBorrows(r.marketIdStoken, type(uint256).max);
    }

    function _logDeployResult(string memory deploymentName, DeployResult memory r) internal pure {
        console.log("");
        console.log("=== %s ===", deploymentName);
        console.log("MockOracle      ", r.oracle);
        console.log("Pool            ", r.pool);
        console.log("AToken_USDC     ", r.aTokenUsdc);
        console.log("AToken_cbBTC    ", r.aTokenCbBtc);
        console.log("AToken_EURC     ", r.aTokenEurc);
        console.log("AToken_ETH      ", r.aTokenEth);
        console.log("SToken_WAD      ", r.stokenWad);
        console.log("--- Market IDs ---");
        console.log("marketId_USDC   ", r.marketIdUsdc);
        console.log("marketId_cbBTC  ", r.marketIdCbBtc);
        console.log("marketId_EURC   ", r.marketIdEurc);
        console.log("marketId_ETH    ", r.marketIdEth);
        console.log("marketId_WAD    ", r.marketIdStoken);
    }
}
