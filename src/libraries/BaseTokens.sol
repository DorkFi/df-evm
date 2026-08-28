// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title BaseTokens
/// @notice Canonical ERC-20 addresses for DorkFi Base deployments.
library BaseTokens {
    // -------------------------------------------------------------------------
    // Base mainnet (chainId 8453)
    // -------------------------------------------------------------------------
    address internal constant MAINNET_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address internal constant MAINNET_WETH = 0x4200000000000000000000000000000000000006;
    address internal constant MAINNET_CBBTC = 0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf;

    // -------------------------------------------------------------------------
    // Base Sepolia (chainId 84532)
    // -------------------------------------------------------------------------
    /// @dev Circle USDC on Base Sepolia (6 decimals)
    address internal constant SEPOLIA_USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
    /// @dev Canonical WETH on OP-stack Base Sepolia
    address internal constant SEPOLIA_WETH = 0x4200000000000000000000000000000000000006;
}
