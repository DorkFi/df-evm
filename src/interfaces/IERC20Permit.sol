// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/// @title IERC20Permit
/// @notice Interface for ERC-20 Permit extension (EIP-2612)
/// @dev Allows approval via signature instead of transaction
interface IERC20Permit {
    /// @notice Returns the current nonce for `owner`
    function nonces(address owner) external view returns (uint256);

    /// @notice Returns the domain separator used in the permit signature
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice Approves `spender` to spend `value` tokens from `owner` using a signature
    /// @param owner The token owner
    /// @param spender The spender address
    /// @param value The amount to approve
    /// @param deadline The deadline timestamp (unix time)
    /// @param v The recovery byte of the signature
    /// @param r The r component of the signature
    /// @param s The s component of the signature
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
