// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {LendingPoolV2} from "../LendingPoolV2.sol";
import {ChainlinkOracleRouter} from "../ChainlinkOracleRouter.sol";
import {Roles} from "../access/Roles.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title DorkFiDeployLib
/// @notice Shared deployment helpers for Base mainnet (proxy pool, timelock, RBAC handoff).
library DorkFiDeployLib {
  uint256 public constant DEFAULT_TIMELOCK_DELAY = 48 hours;

  struct PoolProxyDeployment {
    address implementation;
    address proxy;
    ProxyAdmin proxyAdmin;
  }

  struct TimelockDeployment {
    TimelockController timelock;
  }

  /// @notice Deploy a TransparentUpgradeableProxy around LendingPoolV2.
  /// @param admin Receives all pool roles at initialization (typically timelock or multisig).
  function deployPoolProxy(
    address oracle,
    address admin
  ) internal returns (PoolProxyDeployment memory d) {
    d.implementation = address(new LendingPoolV2(address(0xdead), address(0)));
    d.proxyAdmin = new ProxyAdmin(admin);
    bytes memory initData = abi.encodeCall(LendingPoolV2.initialize, (oracle, admin));
    d.proxy = address(new TransparentUpgradeableProxy(d.implementation, address(d.proxyAdmin), initData));
  }

  /// @notice Deploy ChainlinkOracleRouter with admin as DEFAULT_ADMIN + ORACLE_ADMIN.
  function deployOracleRouter(address admin) internal returns (ChainlinkOracleRouter router) {
    router = new ChainlinkOracleRouter(admin);
  }

  /// @notice Deploy OpenZeppelin TimelockController.
  /// @param proposer Account(s) that can schedule operations (e.g. multisig).
  /// @param executor Account that can execute; use address(0) for permissionless execution.
  /// @param admin Timelock admin (can cancel); often the same multisig as proposer.
  function deployTimelock(
    address proposer,
    address executor,
    address admin
  ) internal returns (TimelockDeployment memory d) {
    address[] memory proposers = new address[](1);
    address[] memory executors = new address[](1);
    proposers[0] = proposer;
    executors[0] = executor;
    d.timelock = new TimelockController(DEFAULT_TIMELOCK_DELAY, proposers, executors, admin);
  }

  /// @notice Grant pool operational roles to `account` (e.g. timelock). Caller must hold DEFAULT_ADMIN on pool.
  function grantPoolRolesTo(LendingPoolV2 pool, address account) internal {
    pool.grantRole(Roles.POOL_ADMIN_ROLE, account);
    pool.grantRole(Roles.PAUSER_ROLE, account);
    pool.grantRole(Roles.ORACLE_ADMIN_ROLE, account);
  }

  /// @notice Grant oracle operational role to `account`. Caller must hold DEFAULT_ADMIN on router.
  function grantOracleRolesTo(ChainlinkOracleRouter router, address account) internal {
    router.grantRole(Roles.ORACLE_ADMIN_ROLE, account);
  }
}
