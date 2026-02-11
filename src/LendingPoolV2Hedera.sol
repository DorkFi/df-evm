// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LendingPoolV2} from "./LendingPoolV2.sol";

/// @title LendingPoolV2Hedera
/// @notice Hedera-specific variant of LendingPoolV2. Extends the base pool with chain-specific logic
///         (e.g. HTS token handling, association checks, or Hedera native service integration).
/// @dev Add all Hedera-specific code in this contract. If you need to override token transfer
///      behavior (_pull/_push) or price-feed payment (_ensurePaymentForFetchPriceFeed), the base
///      contract will need those functions marked virtual in LendingPoolV2.sol.
contract LendingPoolV2Hedera is LendingPoolV2 {
    // -------------------------------------------------------------------------
    // Hedera-specific state (add as needed)
    // -------------------------------------------------------------------------
    // Example: IHederaTokenService public constant HTS = IHederaTokenService(0x...);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    constructor(address _oracle) LendingPoolV2(_oracle) {}

    // -------------------------------------------------------------------------
    // Hedera-specific logic (add implementations below)
    // -------------------------------------------------------------------------
    // Possible extensions:
    // - HTS token association checks before deposit/withdraw
    // - Hedera-native price feed payment in HBAR
    // - Custom transfer path for HTS tokens (requires virtual _pull/_push in base)
    // - Event or callback integration with Hedera services
}
