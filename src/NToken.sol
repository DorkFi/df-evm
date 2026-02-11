// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ILendingPoolV2} from "./interfaces/ILendingPoolV2.sol";

/// @notice Minimal ERC20 metadata for bootstrap
interface IERC20Metadata {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

/// @title NToken
/// @notice Non-transferable deposit receipt token for a lending market. Represents supplied collateral and accruing interest.
/// @dev Only the LendingPool can mint/burn. transfer and transferFrom always return false.
/// @dev Balances are read from LendingPool (single source of truth); no internal balance storage.
/// @dev Name, symbol, decimals are bootstrapped from the underlying token (AVM-style).
contract NToken {
    address public immutable lendingPool;
    uint64 public immutable marketId;

    string public name;
    string public symbol;
    uint8 public decimals;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Mint(address indexed to, uint256 scaledAmount);
    event Burn(address indexed from, uint256 scaledAmount);

    error Unauthorized();

    modifier onlyLendingPool() {
        if (msg.sender != lendingPool) revert Unauthorized();
        _;
    }

    /// @notice Bootstrap from underlying token metadata (AVM-style: "DorkFi " + name, "n" + symbol).
    constructor(
        address _lendingPool,
        uint64 _marketId,
        address _underlyingToken
    ) {
        lendingPool = _lendingPool;
        marketId = _marketId;
        (name, symbol, decimals) = _bootstrap(_underlyingToken);
    }

    /// @notice Derive NToken metadata from underlying token (name, symbol, decimals).
    function _bootstrap(address underlying) internal view returns (string memory _name, string memory _symbol, uint8 _decimals) {
        try IERC20Metadata(underlying).name() returns (string memory n) {
            _name = string(abi.encodePacked("DorkFi ", n));
        } catch {
            _name = "DorkFi Unknown";
        }
        try IERC20Metadata(underlying).symbol() returns (string memory s) {
            _symbol = string(abi.encodePacked("n", s));
        } catch {
            _symbol = "n??";
        }
        try IERC20Metadata(underlying).decimals() returns (uint8 d) {
            _decimals = d;
        } catch {
            _decimals = 18;
        }
    }

    /// @notice Returns the actual balance. Reads from LendingPool (single source of truth).
    function balanceOf(address account) external view returns (uint256) {
        return ILendingPoolV2(lendingPool).getSupplyBalance(account, marketId);
    }

    /// @notice Returns the scaled balance. Reads from LendingPool.
    function scaledBalanceOf(address account) external view returns (uint256) {
        return ILendingPoolV2(lendingPool).getScaledDeposits(account, marketId);
    }

    /// @notice Returns total supply. Reads from LendingPool.
    function totalSupply() external view returns (uint256) {
        return ILendingPoolV2(lendingPool).getMarketTotalDeposits(marketId);
    }

    /// @notice Returns total scaled supply. Reads from LendingPool.
    function totalScaledSupply() external view returns (uint256) {
        return ILendingPoolV2(lendingPool).getTotalScaledDeposits(marketId);
    }

    /// @notice Mint NTokens. Only callable by LendingPool. Emits events only; pool holds state.
    function mint(address to, uint256 scaledAmount) external onlyLendingPool {
        if (scaledAmount == 0) return;
        emit Mint(to, scaledAmount);
        emit Transfer(address(0), to, scaledAmount);
    }

    /// @notice Burn NTokens from an account. Only callable by LendingPool. Emits events only; pool holds state.
    function burnFrom(address from, uint256 scaledAmount) external onlyLendingPool {
        if (scaledAmount == 0) return;
        emit Burn(from, scaledAmount);
        emit Transfer(from, address(0), scaledAmount);
    }

    /// @notice Non-transferable: always returns false. NTokens cannot be transferred.
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    /// @notice Non-transferable: always returns false. NTokens cannot be transferred.
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }

    /// @notice Non-transferable: always returns false. NTokens cannot be transferred.
    function approve(address, uint256) external pure returns (bool) {
        return false;
    }

    /// @notice Allowance is always 0 (non-transferable).
    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }
}
