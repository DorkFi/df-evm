// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title Roles
/// @notice Shared role identifiers for DorkFi protocol contracts.
library Roles {
    /// @notice Create markets, caps, reserves, treasury, SToken config.
    bytes32 public constant POOL_ADMIN_ROLE = keccak256("POOL_ADMIN_ROLE");
    /// @notice Protocol-wide and per-market pause.
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    /// @notice Point pool at a new oracle; configure Chainlink feeds.
    bytes32 public constant ORACLE_ADMIN_ROLE = keccak256("ORACLE_ADMIN_ROLE");
}
