// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {
    HederaScheduleService
} from "@hashgraph/smart-contracts/contracts/system-contracts/hedera-schedule-service/HederaScheduleService.sol";
import {
    HederaResponseCodes
} from "@hashgraph/smart-contracts/contracts/system-contracts/HederaResponseCodes.sol";
import {
    PrngSystemContract
} from "@hashgraph/smart-contracts/contracts/system-contracts/pseudo-random-number-generator/PrngSystemContract.sol";

import {LendingPoolV2} from "./LendingPoolV2.sol";

// References:
// <https://github.com/hashgraph/hedera-smart-contracts/tree/main/contracts/system-contracts/hedera-schedule-service>

/// @title LendingPoolV2Hedera
/// @notice Hedera-specific variant of LendingPoolV2. Extends the base pool with chain-specific logic
///         (e.g. HTS token handling, association checks, or Hedera native service integration).
/// @dev Add all Hedera-specific code in this contract. If you need to override token transfer
///      behavior (_pull/_push) or price-feed payment (_ensurePaymentForFetchPriceFeed), the base
///      contract will need those functions marked virtual in LendingPoolV2.sol.
contract LendingPoolV2Hedera is LendingPoolV2, HederaScheduleService {
    // -------------------------------------------------------------------------
    // Hedera-specific state (add as needed)
    // -------------------------------------------------------------------------
    // Example: IHederaTokenService public constant HTS = IHederaTokenService(0x...);
    uint256 internal constant KEEPER_GAS_LIMIT = 2_000_000;

    struct KeeperConfig {
        bool active;
        uint256 intervalSeconds;
        uint256 lastCallTime;
        uint256 callCount;
        address lastScheduleAddress;
    }

    mapping(uint64 => KeeperConfig) public keeperConfigs;

    event KeeperStarted(uint256 intervalSeconds, uint256 firstScheduledAt);
    event KeeperScheduled(
        uint256 chosenTime,
        uint256 desiredTime,
        address scheduleAddres
    );
    event KeeperExecuted(uint256 timestamp, uint256 count);
    event KeeperStopped();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------
    constructor(address _oracle) payable LendingPoolV2(_oracle) {}
    receive() external payable {}

    // -------------------------------------------------------------------------
    // Hedera-specific logic (add implementations below)
    // -------------------------------------------------------------------------
    // Possible extensions:
    // - HTS token association checks before deposit/withdraw
    // - Hedera-native price feed payment in HBAR
    // - Custom transfer path for HTS tokens (requires virtual _pull/_push in base)
    // - Event or callback integration with Hedera services
    function startKeeper(uint64 marketId, uint256 intervalSeconds) external {
        // TODO: check if market exists
        require(intervalSeconds > 0, "interval must be > 0");
        require(!keeperConfigs[marketId].active, "already active");

        keeperConfigs[marketId].active = true;
        keeperConfigs[marketId].intervalSeconds = intervalSeconds;
        keeperConfigs[marketId].lastCallTime = block.timestamp;
        keeperConfigs[marketId].callCount = 0;

        uint256 desiredTime = block.timestamp + intervalSeconds;
        uint256 scheduledAt = _scheduleNextKeeperCall(marketId, desiredTime);
        emit KeeperStarted(intervalSeconds, scheduledAt);
    }

    function runKeeper(uint64 marketId) external {
        require(keeperConfigs[marketId].active, "not active");
        keeperConfigs[marketId].callCount += 1;
        keeperConfigs[marketId].lastCallTime = block.timestamp;

        emit KeeperExecuted(block.timestamp, keeperConfigs[marketId].callCount);

        uint256 desiredTime = block.timestamp +
            keeperConfigs[marketId].intervalSeconds;
        _scheduleNextKeeperCall(marketId, desiredTime);
    }

    function _scheduleNextKeeperCall(
        uint64 marketId,
        uint256 desiredTime
    ) internal returns (uint256 chosenTime) {
        chosenTime = _findAvailableSecond(desiredTime, KEEPER_GAS_LIMIT, 8);
        bytes memory callData = abi.encodeWithSelector(
            this.runKeeper.selector,
            marketId
        );
        int64 rc;
        address scheduleAddress;
        (rc, scheduleAddress) = scheduleCall(
            address(this),
            chosenTime,
            KEEPER_GAS_LIMIT,
            0,
            callData
        );
        require(rc == HederaResponseCodes.SUCCESS, "scheduleCall failed");
        keeperConfigs[marketId].lastScheduleAddress = scheduleAddress;
        emit KeeperScheduled(chosenTime, desiredTime, scheduleAddress);
    }

    function _findAvailableSecond(
        uint256 expiry,
        uint256 gasLimit,
        uint256 maxProbes
    ) internal returns (uint256 second) {
        if (hasScheduleCapacity(expiry, gasLimit)) {
            return expiry;
        }
        bytes32 seed = PrngSystemContract(address(0x169)).getPseudorandomSeed();
        for (uint256 i = 0; i < maxProbes; i++) {
            uint256 baseDelay = 2 ** i;
            // forge-lint: disable-next-line(asm-keccak256)
            bytes32 hash = keccak256(abi.encodePacked(seed, i));
            uint16 randomValue = uint16(uint256(hash));
            uint256 jitter = uint256(randomValue) % (baseDelay + 1);

            uint256 candidate = expiry + baseDelay + jitter;
            if (hasScheduleCapacity(candidate, gasLimit)) {
                return candidate;
            }
        }
        revert("No capacity after maxProbes");
    }
}
