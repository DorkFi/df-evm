// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IOracleRouter} from "./interfaces/IOracleRouter.sol";
import {IERC20Permit} from "./interfaces/IERC20Permit.sol";
import {ISToken} from "./interfaces/ISToken.sol";
import {NToken} from "./NToken.sol";

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IERC20Metadata {
    function decimals() external view returns (uint8);
}

/// @title LendingPoolV2
/// @notice Phase 1: Multi-market ERC20 lending with scaled accounting, interest, oracle, health factor, liquidation
contract LendingPoolV2 {
    uint256 public constant SCALE = 1e18;
    uint256 public constant BPS = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant PRICE_DECIMALS = 8;

    // Default risk params (bps)
    uint256 public constant DEFAULT_COLLATERAL_FACTOR_BPS = 8000; // 80%
    uint256 public constant DEFAULT_LIQUIDATION_THRESHOLD_BPS = 8500; // 85%
    uint256 public constant DEFAULT_CLOSE_FACTOR_BPS = 5000; // 50%
    uint256 public constant DEFAULT_LIQUIDATION_BONUS_BPS = 500; // 5%

    struct MarketParams {
        uint256 borrowRate; // Base borrow rate (1e18)
        uint256 slope; // Slope for utilization (1e18)
        uint256 reserveFactor; // Reserve factor (1e18)
        uint256 collateralFactorBps;
        uint256 liquidationThresholdBps;
        uint256 closeFactorBps;
        uint256 liquidationBonusBps;
    }

    struct MarketData {
        IERC20 token; // EVM specific
        NToken nToken;
        uint256 totalScaledDeposits;
        uint256 totalScaledBorrows;
        uint256 depositIndex;
        uint256 borrowIndex;
        uint256 lastUpdateTime;
        uint256 reserves;
        MarketParams params;
        bool exists; // EVM specific
        bool paused;
        uint8 decimals; // Cached token decimals to save gas
        uint256 lastPrice; // Cached price (8 decimals), synced during state-changing ops
        uint256 maxTotalDeposits; // Cap on total deposits (type(uint256).max = no limit)
        uint256 maxTotalBorrows; // Cap on total borrows (type(uint256).max = no limit)
    }

    uint64 public totalMarkets;
    /// @notice Market ID of the borrow-only SToken market (type(uint64).max = none).
    uint64 public stokenMarketId;
    mapping(uint64 => MarketData) public markets;
    mapping(address => uint64) public marketIdByToken;

    struct UserMarketData {
        uint256 scaledDeposits;
        uint256 scaledBorrows;
        uint256 depositIndex;
        uint256 borrowIndex;
        uint64 lastUpdateTime;
        uint256 lastPrice;
    }
    mapping(uint64 => mapping(address => UserMarketData)) public userMarketData;

    /// @notice Per-user cumulative collateral and borrow values across all markets (USD, SCALE)
    struct GlobalUserData {
        uint256 totalCollateralValue;
        uint256 totalBorrowValue;
        uint64 lastUpdateTime;
    }
    mapping(address => GlobalUserData) public globalUsers;

    IOracleRouter public oracle;
    address public owner;
    bool public paused;

    event MarketCreated(uint64 indexed marketId, address token);
    event PauseSet(bool paused);
    event MarketPauseSet(uint64 indexed marketId, bool paused);

    event Deposit(
        uint64 indexed marketId,
        address indexed user,
        uint256 amount
    );
    event Withdraw(
        uint64 indexed marketId,
        address indexed user,
        uint256 amount
    );
    event Borrow(uint64 indexed marketId, address indexed user, uint256 amount);
    event Repay(uint64 indexed marketId, address indexed user, uint256 amount);
    event Liquidate(
        uint64 indexed debtMarketId,
        uint64 indexed collateralMarketId,
        address indexed user,
        address liquidator,
        uint256 debtAmount,
        uint256 collateralSeized
    );
    event UserHealth(
        address indexed user,
        uint256 totalCollateralValue,
        uint256 totalBorrowValue
    );

    error MarketNotFound();
    error InvalidAmount();
    error InsufficientCollateral();
    error InsufficientLiquidity();
    error InsufficientBalance();
    error HealthFactorWouldViolate();
    error NotLiquidatable();
    error InvalidHealthFactor();
    error Unauthorized();
    error TransferFailed();
    error TokenAlreadyHasMarket();
    error ProtocolPaused();
    error MarketPaused();
    error CannotUseStokenMarketForThisOperation();
    error StokenMarketCannotBeCollateral();
    error InsufficientReserves();

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ProtocolPaused();
        _;
    }

    constructor(address _oracle) {
        oracle = IOracleRouter(_oracle);
        owner = msg.sender;
        stokenMarketId = type(uint64).max; // no SToken market by default
    }

    /// @notice Create a new ERC20 market. NToken name/symbol/decimals are bootstrapped from the underlying token.
    function createMarket(
        address token,
        MarketParams calldata params
    ) external onlyOwner returns (uint64 marketId) {
        uint64 existingId = marketIdByToken[token];
        if (
            markets[existingId].exists &&
            address(markets[existingId].token) == token
        ) {
            revert TokenAlreadyHasMarket();
        }

        marketId = totalMarkets++;
        MarketData storage m = markets[marketId];
        m.token = IERC20(token);
        m.nToken = new NToken(address(this), marketId, token);
        m.depositIndex = SCALE;
        m.borrowIndex = SCALE;
        m.lastUpdateTime = block.timestamp;
        m.params = params;
        m.exists = true;
        m.paused = false;
        m.maxTotalDeposits = 0; // Must be set by owner before deposits
        m.maxTotalBorrows = 0; // Must be set by owner before borrows
        // Cache decimals to save gas on frequent lookups
        try IERC20Metadata(token).decimals() returns (uint8 d) {
            m.decimals = d;
        } catch {
            m.decimals = 18; // Default to 18 if not available
        }
        marketIdByToken[token] = marketId;

        emit MarketCreated(marketId, token);
    }

    /// @notice Set the borrow-only SToken market ID (owner only). Use type(uint64).max to clear.
    function setStokenMarketId(uint64 marketId) external onlyOwner {
        if (marketId != type(uint64).max && !markets[marketId].exists) revert MarketNotFound();
        stokenMarketId = marketId;
    }

    /// @notice True if the market is the designated borrow-only SToken market.
    function _isStokenMarket(uint64 marketId) internal view returns (bool) {
        return marketId == stokenMarketId;
    }

    /// @notice Set protocol pause state (owner only)
    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PauseSet(_paused);
    }

    /// @notice Set market pause state (owner only)
    function setMarketPaused(uint64 marketId, bool _paused) external onlyOwner {
        MarketData storage m = markets[marketId];
        if (!m.exists) revert MarketNotFound();
        m.paused = _paused;
        emit MarketPauseSet(marketId, _paused);
    }

    /// @notice Set max total deposits for a market (type(uint256).max = no limit)
    function setMaxTotalDeposits(
        uint64 marketId,
        uint256 _maxTotalDeposits
    ) external onlyOwner {
        MarketData storage m = markets[marketId];
        if (!m.exists) revert MarketNotFound();
        m.maxTotalDeposits = _maxTotalDeposits;
    }

    /// @notice Set max total borrows for a market (type(uint256).max = no limit)
    function setMaxTotalBorrows(
        uint64 marketId,
        uint256 _maxTotalBorrows
    ) external onlyOwner {
        MarketData storage m = markets[marketId];
        if (!m.exists) revert MarketNotFound();
        m.maxTotalBorrows = _maxTotalBorrows;
    }

    /// @notice Withdraw accrued reserves for a market. For SToken (borrow-only) market, mints to owner; otherwise transfers from pool.
    function withdrawReserves(uint64 marketId, uint256 amount) external onlyOwner {
        MarketData storage m = markets[marketId];
        if (!m.exists) revert MarketNotFound();
        if (amount > m.reserves) revert InsufficientReserves();
        m.reserves -= amount;
        if (_isStokenMarket(marketId)) {
            ISToken(address(m.token)).mint(owner, amount);
        } else {
            _push(marketId, owner, amount);
        }
    }

    /// @notice Ensure payment for fetch price feed (from user)
    function _ensurePaymentForFetchPriceFeed(
        address user,
        uint256 multiplier
    ) internal {
        // ensure payment for fetch price feed (from user)
        // if (user.balance < 0) revert InsufficientBalance();
        // user.balance -= 1;
    }

    /// @notice Returns the price to use as "previous" for this user: their last known price if set, else the market price.
    /// @param userLastPrice The user's last stored price (0 if never set).
    /// @param marketPrice The current market price.
    /// @return The previous price to use for this user.
    function _getPreviousPrice(
        uint256 userLastPrice,
        uint256 marketPrice
    ) internal pure returns (uint256) {
        return userLastPrice > 0 ? userLastPrice : marketPrice;
    }

    /// @notice Update a user's market collateral values when market prices change.
    function _updateUserMarketCollateral(
        address user,
        uint64 marketId
    ) internal {
        UserMarketData storage u = userMarketData[marketId][user];
        if (u.scaledDeposits == 0) return;

        MarketData storage m = markets[marketId];

        // Safety check: if user's deposit_index is 0 (new user), use current market index
        uint256 userDepositIndex = u.depositIndex > 0
            ? u.depositIndex
            : m.depositIndex;

        uint256 oldDepositAmount = (u.scaledDeposits * userDepositIndex) /
            SCALE;
        uint256 newDepositAmount = (u.scaledDeposits * m.depositIndex) / SCALE;
        uint256 priceForOld = _getPreviousPrice(u.lastPrice, m.lastPrice);
        uint256 oldDepositValue = _getValueInUsd8(
            oldDepositAmount,
            priceForOld,
            marketId
        );
        uint256 newDepositValue = _getValueInUsd8(
            newDepositAmount,
            m.lastPrice,
            marketId
        );
        _updateGlobalCollateral(user, oldDepositValue, newDepositValue);
    }

    function _updateUserMarketBorrows(address user, uint64 marketId) internal {
        UserMarketData storage u = userMarketData[marketId][user];
        if (u.scaledBorrows == 0) return;

        MarketData storage m = markets[marketId];

        uint256 userBorrowAmount = (u.scaledBorrows * u.borrowIndex) / SCALE;
        uint256 newBorrowAmount = (u.scaledBorrows * m.borrowIndex) / SCALE;
        uint256 priceForOld = _getPreviousPrice(u.lastPrice, m.lastPrice);
        uint256 oldBorrowValue = _getValueInUsd8(
            userBorrowAmount,
            priceForOld,
            marketId
        );
        uint256 newBorrowValue = _getValueInUsd8(
            newBorrowAmount,
            m.lastPrice,
            marketId
        );
        _updateGlobalBorrows(user, oldBorrowValue, newBorrowValue);
    }

    /// @notice Update user global values for price change.
    function _updateUserGlobalValuesForPriceChange(
        address user,
        uint64 marketId
    ) internal {
        UserMarketData storage u = userMarketData[marketId][user];
        if (u.scaledDeposits == 0 && u.scaledBorrows == 0) return;

        MarketData storage m = markets[marketId];
        if (!m.exists) revert MarketNotFound();

        _updateUserMarketCollateral(user, marketId);
        _updateUserMarketBorrows(user, marketId);
    }

    /// @notice Returns the accrued deposit interest for a user in a market (current balance minus balance at last snapshot).
    function _calculateUserInterest(
        address user,
        uint64 marketId
    ) internal returns (uint256) {
        UserMarketData storage u = userMarketData[marketId][user];
        if (u.scaledDeposits == 0) return 0;

        MarketData storage m = markets[marketId];
        uint256 userDepositIndex = u.depositIndex > 0
            ? u.depositIndex
            : m.depositIndex;
        uint256 lastUnderlying = (u.scaledDeposits * userDepositIndex) / SCALE;
        uint256 currentUnderlying = (u.scaledDeposits * m.depositIndex) / SCALE;

        return
            currentUnderlying > lastUnderlying
                ? currentUnderlying - lastUnderlying
                : 0;
    }

    function _calculateUserDebtInterest(
        address user,
        uint64 marketId
    ) internal returns (uint256) {
        UserMarketData storage u = userMarketData[marketId][user];
        if (u.scaledBorrows == 0) return 0;

        MarketData storage m = markets[marketId];

        uint256 userTotalDebt = (u.scaledBorrows * m.borrowIndex) / SCALE;
        uint256 userBorrowIndex = m.borrowIndex > 0
            ? u.borrowIndex
            : m.borrowIndex;
        uint256 originalPrincipal = (u.scaledBorrows * userBorrowIndex) / SCALE;

        uint256 interest = userTotalDebt >= originalPrincipal
            ? userTotalDebt - originalPrincipal
            : 0;

        return interest;
    }

    /// @notice Converts an underlying token amount to scaled deposit units for a market using its deposit index.
    function _getMarketScaledDeposit(
        uint64 marketId,
        uint256 amount
    ) internal view returns (uint256) {
        MarketData storage m = markets[marketId];
        uint256 depositIndex = m.depositIndex == 0 ? SCALE : m.depositIndex;
        return (amount * SCALE) / depositIndex;
    }

    /// @notice Converts an underlying token amount to scaled borrow units for a market using its borrow index.
    function _getMarketScaledBorrow(
        uint64 marketId,
        uint256 amount
    ) internal view returns (uint256) {
        MarketData storage m = markets[marketId];
        uint256 borrowIndex = m.borrowIndex == 0 ? SCALE : m.borrowIndex;
        return (amount * SCALE) / borrowIndex;
    }

    /// @notice Increment a user's scaled deposits in a market by the given amount.
    function _incrementMarketUserScaledDeposits(
        address user,
        uint64 marketId,
        uint256 amount
    ) internal {
        UserMarketData storage u = userMarketData[marketId][user];
        MarketData storage m = markets[marketId];
        u.scaledDeposits += amount;
        u.depositIndex = m.depositIndex;
        u.lastUpdateTime = uint64(block.timestamp);
        u.lastPrice = m.lastPrice;
    }

    /// @notice Decrement a user's scaled deposits in a market by the given amount.
    /// @dev Caller must also decrement market totalScaledDeposits (and global collateral when applicable).
    function _decrementMarketUserScaledDeposits(
        address user,
        uint64 marketId,
        uint256 amount
    ) internal {
        UserMarketData storage u = userMarketData[marketId][user];
        MarketData storage m = markets[marketId];
        if (u.scaledDeposits < amount) revert InsufficientBalance();
        u.scaledDeposits -= amount;
        u.depositIndex = m.depositIndex;
        u.lastUpdateTime = uint64(block.timestamp);
        u.lastPrice = m.lastPrice;
    }

    /// @notice Increment a user's scaled borrows in a market by the given amount.
    function _incrementMarketUserScaledBorrows(
        address user,
        uint64 marketId,
        uint256 amount
    ) internal {
        UserMarketData storage u = userMarketData[marketId][user];
        MarketData storage m = markets[marketId];
        u.scaledBorrows += amount;
        u.borrowIndex = m.borrowIndex;
        u.lastUpdateTime = uint64(block.timestamp);
        u.lastPrice = m.lastPrice;
    }

    /// @notice Decrement a user's scaled borrows in a market by the given amount.
    function _decrementMarketUserScaledBorrows(
        address user,
        uint64 marketId,
        uint256 amount
    ) internal {
        UserMarketData storage u = userMarketData[marketId][user];
        MarketData storage m = markets[marketId];
        if (u.scaledBorrows < amount) revert InsufficientBalance();
        u.scaledBorrows -= amount;
        u.borrowIndex = m.borrowIndex;
        u.lastUpdateTime = uint64(block.timestamp);
        u.lastPrice = m.lastPrice;
    }

    /// @notice Resolve accumulated deposit interest for a user's market.
    function _resolveAccumulatedDepositInterest(
        address user,
        uint64 marketId
    ) internal {
        UserMarketData storage u = userMarketData[marketId][user];
        if (u.scaledDeposits == 0) return;

        MarketData storage m = markets[marketId];

        uint256 interest = _calculateUserInterest(user, marketId);
        if (interest == 0) return;

        uint256 interestScaledAmount = _getMarketScaledDeposit(
            marketId,
            interest
        );
        uint256 interestValue = _getValueInUsd8(
            interest,
            m.lastPrice,
            marketId
        );
        m.nToken.mint(user, interestScaledAmount);
        _incrementMarketUserScaledDeposits(
            user,
            marketId,
            interestScaledAmount
        );
        _updateGlobalCollateral(user, 0, interestValue);
        // TODO emit event
    }

    function _resolveAccumulatedBorrowInterest(
        address user,
        uint64 marketId
    ) internal {
        UserMarketData storage u = userMarketData[marketId][user];
        if (u.scaledBorrows == 0) return;

        MarketData storage m = markets[marketId];
        uint256 interest = _calculateUserDebtInterest(user, marketId);
        if (interest == 0) return;

        uint256 interestScaledAmount = _getMarketScaledBorrow(
            marketId,
            interest
        );
        uint256 interestValue = _getValueInUsd8(
            interest,
            m.lastPrice,
            marketId
        );
        _incrementMarketUserScaledBorrows(user, marketId, interestScaledAmount);
        _updateGlobalBorrows(user, 0, interestValue);
        // TODO emit event
    }

    /// @notice Sync user market for price change (accrue interest, resolve interest, update globals).
    function syncUserMarketForPriceChange(address user, uint64 marketId) external {
        _syncUserMarketForPriceChange(user, marketId);
    }

    /// @notice Sync user market for price change (accrue interest, resolve interest, update globals).
    function _syncUserMarketForPriceChange(
        address user,
        uint64 marketId
    ) internal {
        _ensurePaymentForFetchPriceFeed(user, 1);
        _accrueInterest(marketId);
        _updateUserGlobalValuesForPriceChange(user, marketId);
        _resolveAccumulatedDepositInterest(user, marketId);
        _resolveAccumulatedBorrowInterest(user, marketId);
    }

    /// @notice Sync user markets for price change (accrue interest, resolve interest, update globals).
    function syncUserMarketsForPriceChange(address user) external {
        for (uint64 i = 0; i < totalMarkets; i++) {
            _syncUserMarketForPriceChange(user, i);
        }
    }

    /// @notice Increment market total scaled deposits by the given amount.
    function _incrementMarketTotalScaledDeposits(
        uint64 marketId,
        uint256 amount
    ) internal {
        MarketData storage m = markets[marketId];
        m.totalScaledDeposits += amount;
    }

    /// @notice Decrement market total scaled deposits by the given amount.
    /// @param marketId The market ID.
    /// @param amount Scaled amount to subtract from totalScaledDeposits.
    function _decrementMarketTotalScaledDeposits(
        uint64 marketId,
        uint256 amount
    ) internal {
        MarketData storage m = markets[marketId];
        if (m.totalScaledDeposits < amount) revert InsufficientBalance();
        m.totalScaledDeposits -= amount;
    }

    /// @notice Increment global collateral for a user by the given value.
    function _incrementGlobalCollateral(address user, uint256 amount) internal {
        GlobalUserData storage g = globalUsers[user];
        g.totalCollateralValue += amount;
    }

    /// @notice Increment global borrows for a user by the given value.
    function _incrementGlobalBorrows(address user, uint256 amount) internal {
        GlobalUserData storage g = globalUsers[user];
        g.totalBorrowValue += amount;
    }

    /// @notice Decrement global borrows for a user by the given value.
    function _decrementGlobalBorrows(address user, uint256 amount) internal {
        GlobalUserData storage g = globalUsers[user];
        if (g.totalBorrowValue < amount) revert InsufficientBalance();
        g.totalBorrowValue -= amount;
    }

    /// @notice Decrement global collateral for a user by the given value.
    /// @param user The user whose totalCollateralValue to decrement.
    /// @param amount The USD value (same units as totalCollateralValue) to subtract.
    function _decrementGlobalCollateral(address user, uint256 amount) internal {
        GlobalUserData storage g = globalUsers[user];
        if (g.totalCollateralValue < amount) revert InsufficientBalance();
        g.totalCollateralValue -= amount;
    }

    /// @notice Record a collateral deposit (pull tokens, mint nToken, update user/market/global).
    function _collateralDeposit(
        address user,
        address beneficiary,
        uint64 marketId,
        uint256 amount,
        uint256 scaledAmount,
        uint256 value
    ) internal {
        MarketData storage m = markets[marketId];
        _pull(marketId, user, amount);
        m.nToken.mint(beneficiary, scaledAmount);
        _incrementMarketUserScaledDeposits(beneficiary, marketId, scaledAmount);
        _incrementMarketTotalScaledDeposits(marketId, scaledAmount);
        _incrementGlobalCollateral(beneficiary, value);
    }

    /// @notice Record a collateral withdraw (burn nToken, push tokens, update user/market/global).
    function _collateralWithdraw(
        address user,
        address beneficiary,
        uint64 marketId,
        uint256 amount,
        uint256 scaledAmount,
        uint256 value
    ) internal {
        MarketData storage m = markets[marketId];
        m.nToken.burnFrom(user, scaledAmount);
        _push(marketId, beneficiary, amount);
        _decrementMarketUserScaledDeposits(user, marketId, scaledAmount);
        _decrementMarketTotalScaledDeposits(marketId, scaledAmount);
        _decrementGlobalCollateral(user, value);
    }

    /// @notice Deposit ERC20 into a market
    function deposit(uint64 marketId, uint256 amount) external whenNotPaused {
        _syncUserMarketForPriceChange(msg.sender, marketId);
        _deposit(msg.sender, marketId, amount);
    }

    /// @notice Deposit ERC20 into a market using ERC-20 Permit (EIP-2612)
    /// @param marketId The market ID
    /// @param amount The amount to deposit
    /// @param deadline The permit deadline timestamp
    /// @param v The recovery byte of the permit signature
    /// @param r The r component of the permit signature
    /// @param s The s component of the permit signature
    /// @dev This function allows users to approve and deposit in a single transaction
    /// by signing a permit message off-chain. The token must support EIP-2612.
    function depositWithPermit(
        uint64 marketId,
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused {
        MarketData storage m = markets[marketId];
        if (!m.exists) revert MarketNotFound();
        if (m.paused) revert MarketPaused();
        if (amount == 0) revert InvalidAmount();

        // Call permit on the token to approve this contract
        // If the token doesn't support permit, this will revert
        // Users should use regular deposit() with pre-approval for non-permit tokens
        IERC20Permit(address(m.token)).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );

        _syncUserMarketForPriceChange(msg.sender, marketId);
        _deposit(msg.sender, marketId, amount);
    }

    /// @notice Internal deposit: add ERC20 to a market and update collateral.
    function _deposit(address user, uint64 marketId, uint256 amount) internal {
        if (_isStokenMarket(marketId)) revert CannotUseStokenMarketForThisOperation();
        MarketData storage m = markets[marketId];
        if (!m.exists) revert MarketNotFound();
        if (m.paused) revert MarketPaused();
        if (amount == 0) revert InvalidAmount();

        uint256 totalDeposits = (m.totalScaledDeposits * m.depositIndex) /
            SCALE;
        if (totalDeposits + amount > m.maxTotalDeposits) revert InvalidAmount();

        uint256 scaledAmount = (amount * SCALE) / m.depositIndex;
        uint256 collateralDelta = _getValueInUsd8(
            amount,
            m.lastPrice,
            marketId
        );
        _collateralDeposit(
            user,
            user,
            marketId,
            amount,
            scaledAmount,
            collateralDelta
        );

        emit Deposit(marketId, user, amount);
    }

    /// @notice Withdraw ERC20 from a market
    function withdraw(uint64 marketId, uint256 amount) external whenNotPaused {
        _syncUserMarketForPriceChange(msg.sender, marketId);
        _withdraw(msg.sender, marketId, amount);
    }

    /// @notice Internal withdraw: remove ERC20 from a market and update collateral.
    /// @dev Health check uses the withdrawing market's collateral factor for the user's total
    ///      remaining collateral, so low-CF market exposure requires higher over-collateralization.
    function _withdraw(address user, uint64 marketId, uint256 amount) internal {
        if (_isStokenMarket(marketId)) revert CannotUseStokenMarketForThisOperation();
        MarketData storage m = markets[marketId];
        if (!m.exists) revert MarketNotFound();
        if (m.paused) revert MarketPaused();
        if (amount == 0) revert InvalidAmount();

        uint256 scaledBalance = userMarketData[marketId][user].scaledDeposits;
        uint256 balance = (scaledBalance * m.depositIndex) / SCALE;
        if (balance < amount) revert InsufficientBalance();

        uint256 totalBorrows = (m.totalScaledBorrows * m.borrowIndex) / SCALE;
        uint256 totalDeposits = (m.totalScaledDeposits * m.depositIndex) /
            SCALE;
        uint256 available = totalDeposits - totalBorrows;
        if (amount > available) revert InsufficientLiquidity();

        uint256 collateralDelta = _getValueInUsd8(
            amount,
            m.lastPrice,
            marketId
        );

        GlobalUserData storage g = globalUsers[user];

        if (collateralDelta > g.totalCollateralValue)
            revert InsufficientCollateral();

        // Health check uses the *withdrawing* market's collateral factor applied to
        // the user's total remaining collateral (not just this market). Exposure to
        // low-CF markets therefore requires higher over-collateralization to withdraw.
        if (g.totalBorrowValue > 0) {
            uint256 availableCollateralValue = g.totalCollateralValue -
                collateralDelta;
            if (
                (availableCollateralValue * m.params.collateralFactorBps) /
                    BPS <
                g.totalBorrowValue
            ) {
                revert HealthFactorWouldViolate();
            }
        }

        uint256 scaledAmount = (amount * SCALE) / m.depositIndex;

        _collateralWithdraw(
            user,
            user,
            marketId,
            amount,
            scaledAmount,
            collateralDelta
        );

        emit Withdraw(marketId, user, amount);
    }

    /// @notice Borrow ERC20 from a market
    function borrow(uint64 marketId, uint256 amount) external whenNotPaused {
        _syncUserMarketForPriceChange(msg.sender, marketId);
        _borrow(msg.sender, marketId, amount);
    }

    /// @notice Internal debt borrow: add ERC20 to a market and update collateral.
    function _debtBorrow(
        address user,
        address beneficiary,
        uint64 marketId,
        uint256 amount,
        uint256 scaledAmount,
        uint256 collateralDelta
    ) internal {
        if (_isStokenMarket(marketId)) {
            ISToken(address(markets[marketId].token)).mint(beneficiary, amount);
        } else {
            _push(marketId, beneficiary, amount);
        }
        _incrementMarketUserScaledBorrows(user, marketId, scaledAmount);
        _incrementMarketTotalScaledBorrows(marketId, scaledAmount);
        _incrementGlobalBorrows(user, collateralDelta);
    }

    function _debtRepay(
        address payer,
        address beneficiary,
        uint64 marketId,
        uint256 amount,
        uint256 scaledAmount,
        uint256 collateralDelta
    ) internal {
        if (_isStokenMarket(marketId)) {
            ISToken(address(markets[marketId].token)).burnFrom(payer, amount);
        } else {
            _pull(marketId, payer, amount);
        }
        _decrementMarketUserScaledBorrows(beneficiary, marketId, scaledAmount);
        _decrementMarketTotalScaledBorrows(marketId, scaledAmount);
        _decrementGlobalBorrows(beneficiary, collateralDelta);
    }

    /// @notice Internal borrow: add ERC20 to a market and update collateral.
    function _borrow(address user, uint64 marketId, uint256 amount) internal {
        MarketData storage m = markets[marketId];
        if (!m.exists) revert MarketNotFound();
        if (m.paused) revert MarketPaused();
        if (amount == 0) revert InvalidAmount();

        uint256 totalBorrows = (m.totalScaledBorrows * m.borrowIndex) / SCALE;
        uint256 totalDeposits = (m.totalScaledDeposits * m.depositIndex) /
            SCALE;
        if (totalBorrows + amount > m.maxTotalBorrows) revert InvalidAmount();
        if (!_isStokenMarket(marketId)) {
            uint256 available = totalDeposits - totalBorrows;
            if (amount > available) revert InsufficientLiquidity();
        }

        uint256 additionalBorrowValue = _getValueInUsd8(
            amount,
            m.lastPrice,
            marketId
        );
        GlobalUserData storage g = globalUsers[user];
        uint256 totalBorrowAfter = g.totalBorrowValue + additionalBorrowValue;

        UserMarketData storage u = userMarketData[marketId][user];

        uint256 depositedAmount = (u.scaledDeposits * m.depositIndex) / SCALE;
        uint256 excludedValue = _getValueInUsd8(
            depositedAmount,
            m.lastPrice,
            marketId
        );
        uint256 effectiveCollateralValue = u.scaledDeposits == 0
            ? g.totalCollateralValue
            : g.totalCollateralValue > excludedValue
                ? g.totalCollateralValue - excludedValue
                : 0;

        // Health check uses the *borrowing* market's CF applied to collateral in
        // *other* markets only (exclude this market to prevent self-collateralization).
        // Low-CF markets therefore require higher over-collateralization to borrow.
        if (totalBorrowAfter > 0) {
            uint256 availableCollateralAtBorrowingMarketCf = (effectiveCollateralValue *
                    m.params.collateralFactorBps) / BPS;
            if (availableCollateralAtBorrowingMarketCf < totalBorrowAfter) {
                revert HealthFactorWouldViolate();
            }
        }

        uint256 scaledAmount = _getMarketScaledBorrow(marketId, amount);

        _debtBorrow(
            user,
            user,
            marketId,
            amount,
            scaledAmount,
            additionalBorrowValue
        );

        emit Borrow(marketId, user, amount);
    }

    /// @notice Repay borrowed ERC20
    function repay(uint64 marketId, uint256 amount) external whenNotPaused {
        _syncUserMarketForPriceChange(msg.sender, marketId);
        _repay(msg.sender, msg.sender, marketId, amount);
    }

    /// @notice Internal repay: remove ERC20 from a market and update collateral.
    function _repay(
        address payer,
        address beneficiary,
        uint64 marketId,
        uint256 amount
    ) internal {
        MarketData storage m = markets[marketId];
        if (!m.exists) revert MarketNotFound();
        if (m.paused) revert MarketPaused();
        if (amount == 0) revert InvalidAmount();

        uint256 debt = (userMarketData[marketId][beneficiary].scaledBorrows *
            m.borrowIndex) / SCALE;

        uint256 repayAmount = amount > debt ? debt : amount;
        uint256 scaledRepay = _getMarketScaledBorrow(marketId, repayAmount);
        uint256 repayValue = _getValueInUsd8(
            repayAmount,
            m.lastPrice,
            marketId
        );

        _debtRepay(
            payer,
            beneficiary,
            marketId,
            repayAmount,
            scaledRepay,
            repayValue
        );

        emit Repay(marketId, beneficiary, repayAmount);
    }

    /// @notice Health factor: (collateral at threshold) / borrowValue, in SCALE (1e18 = healthy).
    /// @param liquidationThreshold Fraction in SCALE (e.g. 0.8e18 for 80%), not BPS.
    function _calculateUserHealth(
        uint256 collateralValue,
        uint256 borrowValue,
        uint256 liquidationThreshold
    ) internal pure returns (uint256) {
        if (borrowValue == 0) return type(uint256).max;
        return (collateralValue * liquidationThreshold) / borrowValue;
    }

    /// @notice Liquidate unhealthy position - repay debt, seize collateral
    function liquidateCrossMarket(
        address user,
        uint64 debtMarketId,
        uint64 collateralMarketId,
        uint256 repayAmount,
        uint256 minCollateralReceived
    ) external whenNotPaused {
        _ensurePaymentForFetchPriceFeed(msg.sender, 2);
        _accrueInterest(debtMarketId);
        _accrueInterest(collateralMarketId);
        _updateUserGlobalValuesForPriceChange(user, debtMarketId);
        _updateUserGlobalValuesForPriceChange(user, collateralMarketId);
        _resolveAccumulatedDepositInterest(user, debtMarketId);
        _resolveAccumulatedBorrowInterest(user, debtMarketId);
        _resolveAccumulatedDepositInterest(user, collateralMarketId);
        _resolveAccumulatedBorrowInterest(user, collateralMarketId);
        _liquidateCrossMarket(
            user,
            msg.sender,
            debtMarketId,
            collateralMarketId,
            repayAmount,
            minCollateralReceived
        );
    }

    /// @notice Internal liquidate cross market: repay debt, seize collateral
    function _liquidateCrossMarket(
        address user,
        address liquidator,
        uint64 debtMarketId,
        uint64 collateralMarketId,
        uint256 repayAmount,
        uint256 minCollateralReceived
    ) internal {
        if (_isStokenMarket(collateralMarketId)) revert StokenMarketCannotBeCollateral();

        if (user == liquidator) revert Unauthorized();

        MarketData storage debtM = markets[debtMarketId];
        MarketData storage collM = markets[collateralMarketId];
        if (!debtM.exists || !collM.exists) revert MarketNotFound();
        if (debtM.paused || collM.paused) revert MarketPaused();
        if (repayAmount == 0) revert InvalidAmount();

        GlobalUserData storage g = globalUsers[user];

        if (g.totalBorrowValue == 0) revert NotLiquidatable();

        uint256 health = _getHealthFactorForMarket(user, collateralMarketId);
        if (health >= SCALE) revert NotLiquidatable();

        uint256 userDebt = (userMarketData[debtMarketId][user].scaledBorrows *
            debtM.borrowIndex) / SCALE;
        uint256 closeFactor = debtM.params.closeFactorBps;
        uint256 maxLiquidatable = (userDebt * closeFactor) / BPS;

        if (repayAmount > maxLiquidatable) revert InvalidAmount();
        if (repayAmount > userDebt) revert InvalidAmount();

        uint256 scaledRepay = _getMarketScaledBorrow(debtMarketId, repayAmount);
        if (scaledRepay > userMarketData[debtMarketId][user].scaledBorrows)
            revert InvalidAmount();

        uint256 repayValue = _getValueInUsd8(
            repayAmount,
            debtM.lastPrice,
            debtMarketId
        );
        uint256 bonusValue = (repayValue * collM.params.liquidationBonusBps) /
            BPS;
        uint256 collateralValue = repayValue + bonusValue;

        uint8 collDecimals = _getTokenDecimals(collateralMarketId);
        uint256 collateralAmount = (collateralValue * (10 ** collDecimals)) /
            collM.lastPrice;
        uint256 scaledCollateral = (collateralAmount * SCALE) /
            collM.depositIndex;

        if (
            scaledCollateral >
            userMarketData[collateralMarketId][user].scaledDeposits
        ) revert InvalidAmount();

        if (collateralAmount < minCollateralReceived) revert InvalidAmount();

        _debtRepay(
            liquidator,
            user,
            debtMarketId,
            repayAmount,
            scaledRepay,
            repayValue
        );

        _collateralWithdraw(
            user,
            liquidator,
            collateralMarketId,
            collateralAmount,
            scaledCollateral,
            collateralValue
        );

        emit Liquidate(
            debtMarketId,
            collateralMarketId,
            user,
            liquidator,
            repayAmount,
            collateralAmount
        );
    }

    /// @notice Sync price cache for markets where user has positions (excludes excludeMarketId, already synced)
    function _syncPricesForUser(address user, uint64 excludeMarketId) internal {
        for (uint64 i = 0; i < totalMarkets; i++) {
            if (i == excludeMarketId) continue;
            MarketData storage m = markets[i];
            if (!m.exists) continue;
            uint256 depositBalance = (userMarketData[i][user].scaledDeposits *
                m.depositIndex) / SCALE;
            uint256 borrowBalance = (userMarketData[i][user].scaledBorrows *
                m.borrowIndex) / SCALE;
            if (depositBalance > 0 || borrowBalance > 0) {
                (m.lastPrice, ) = oracle.getPrice(i);
            }
        }
    }

    /// @notice Accrue interest for a market
    function _accrueInterest(uint64 marketId) internal {
        MarketData storage m = markets[marketId];
        (m.lastPrice, ) = oracle.getPrice(marketId); // Always sync price (1 call per operation market)
        uint256 elapsed = block.timestamp - m.lastUpdateTime;
        if (elapsed == 0) return;

        uint256 totalBorrows = (m.totalScaledBorrows * m.borrowIndex) / SCALE;
        uint256 totalDeposits = (m.totalScaledDeposits * m.depositIndex) /
            SCALE;

        uint256 utilization;
        uint256 toReserves;
        uint256 toDepositors;
        if (_isStokenMarket(marketId)) {
            utilization = SCALE; // 100% for borrow-only market
            uint256 rate = m.params.borrowRate +
                (m.params.slope * utilization) / SCALE;
            uint256 interest = (rate * totalBorrows * elapsed) /
                (SECONDS_PER_YEAR * SCALE);
            toReserves = interest;
            toDepositors = 0;
        } else {
            utilization = totalDeposits == 0
                ? 0
                : (totalBorrows * SCALE) / totalDeposits;
            uint256 rate = m.params.borrowRate +
                (m.params.slope * utilization) / SCALE;
            uint256 interest = (rate * totalBorrows * elapsed) /
                (SECONDS_PER_YEAR * SCALE);
            toReserves = (interest * m.params.reserveFactor) / SCALE;
            toDepositors = interest - toReserves;
        }

        m.reserves += toReserves;
        if (m.totalScaledBorrows > 0) {
            m.borrowIndex += ((toReserves + toDepositors) * SCALE) / m.totalScaledBorrows;
        }
        if (m.totalScaledDeposits > 0 && toDepositors > 0) {
            m.depositIndex += (toDepositors * SCALE) / m.totalScaledDeposits;
        }
        m.lastUpdateTime = block.timestamp;
    }

    function _updateUserMarketSnapshot(uint64 marketId, address user) internal {
        MarketData storage m = markets[marketId];
        UserMarketData storage u = userMarketData[marketId][user];
        u.depositIndex = m.depositIndex;
        u.borrowIndex = m.borrowIndex;
        u.lastUpdateTime = uint64(block.timestamp);
        u.lastPrice = m.lastPrice; // Use cached price from _accrueInterest (no extra oracle call)
    }

    /// @notice Returns GlobalUserData for a user (default/zeros if no entry)
    function getGlobalUser(
        address user
    ) external view returns (GlobalUserData memory) {
        return globalUsers[user];
    }

    /// @notice Returns the default GlobalUserData struct (zeros)
    function getGlobalUserDefault()
        public
        pure
        returns (GlobalUserData memory)
    {
        return
            GlobalUserData({
                totalCollateralValue: 0,
                totalBorrowValue: 0,
                lastUpdateTime: 0
            });
    }

    /// @notice Update global collateral using old/new value pattern (supports deltas, avoids double-counting)
    function _updateGlobalCollateral(
        address user,
        uint256 oldValue,
        uint256 newValue
    ) internal {
        GlobalUserData storage g = globalUsers[user];
        if (oldValue > g.totalCollateralValue) {
            g.totalCollateralValue = newValue;
        } else {
            g.totalCollateralValue =
                g.totalCollateralValue -
                oldValue +
                newValue;
        }
        g.lastUpdateTime = uint64(block.timestamp);
        emit UserHealth(user, g.totalCollateralValue, g.totalBorrowValue);
    }

    /// @notice Update global borrows using old/new value pattern
    function _updateGlobalBorrows(
        address user,
        uint256 oldValue,
        uint256 newValue
    ) internal {
        GlobalUserData storage g = globalUsers[user];
        if (oldValue > g.totalBorrowValue) {
            g.totalBorrowValue = newValue;
        } else {
            g.totalBorrowValue = g.totalBorrowValue - oldValue + newValue;
        }
        g.lastUpdateTime = uint64(block.timestamp);
        emit UserHealth(user, g.totalCollateralValue, g.totalBorrowValue);
    }

    /// @notice Collateral value in USD (SCALE) for a user in a specific market
    function _getCollateralValueInMarket(
        address user,
        uint64 marketId,
        bool useCache
    ) internal view returns (uint256) {
        MarketData storage m = markets[marketId];
        if (!m.exists) return 0;
        uint256 depositBalance = (userMarketData[marketId][user]
            .scaledDeposits * m.depositIndex) / SCALE;
        if (depositBalance == 0) return 0;
        uint256 price = _getPriceForMarket(marketId, useCache);
        return _getValueInUsd8(depositBalance, price, marketId);
    }

    /// @notice Borrow value in USD (8 decimals) for a user in a specific market
    function _getBorrowValueInMarket(
        address user,
        uint64 marketId,
        bool useCache
    ) internal view returns (uint256) {
        MarketData storage m = markets[marketId];
        if (!m.exists) return 0;
        uint256 borrowBalance = (userMarketData[marketId][user].scaledBorrows *
            m.borrowIndex) / SCALE;
        if (borrowBalance == 0) return 0;
        uint256 price = _getPriceForMarket(marketId, useCache);
        return _getValueInUsd8(borrowBalance, price, marketId);
    }

    function _getRawCollateralValue(
        address user,
        bool useCache
    ) internal view returns (uint256) {
        uint256 total = 0;
        for (uint64 i = 0; i < totalMarkets; i++) {
            MarketData storage m = markets[i];
            if (!m.exists) continue;
            uint256 depositBalance = (userMarketData[i][user].scaledDeposits *
                m.depositIndex) / SCALE;
            if (depositBalance == 0) continue;
            uint256 price = _getPriceForMarket(i, useCache);
            total += _getValueInUsd8(depositBalance, price, i);
        }
        return total;
    }

    function _pull(uint64 marketId, address from, uint256 amount) internal {
        if (!markets[marketId].token.transferFrom(from, address(this), amount))
            revert TransferFailed();
    }

    function _push(uint64 marketId, address to, uint256 amount) internal {
        if (amount > 0 && !markets[marketId].token.transfer(to, amount))
            revert TransferFailed();
    }

    /// @notice Get token decimals from cached storage (saves gas vs external call)
    function _getTokenDecimals(uint64 marketId) internal view returns (uint8) {
        return markets[marketId].decimals;
    }

    /// @notice Get price for market - useCache=true uses lastPrice when set (during state-changing ops), false always fetches (for view accuracy)
    function _getPriceForMarket(
        uint64 marketId,
        bool useCache
    ) internal view returns (uint256) {
        if (useCache) {
            MarketData storage m = markets[marketId];
            if (m.lastPrice != 0) return m.lastPrice;
        }
        (uint256 price, ) = oracle.getPrice(marketId);
        return price;
    }

    /// @notice Value in USD 8 decimals: (balance * price) / 10^tokenDecimals. Normalizes mixed token decimals.
    function _getValueInUsd8(
        uint256 balance,
        uint256 price,
        uint64 marketId
    ) internal view returns (uint256) {
        if (balance == 0) return 0;
        uint8 decimals = _getTokenDecimals(marketId);
        return (balance * price) / (10 ** decimals);
    }

    function _getCollateralValueAtThreshold(
        address user,
        bool useCache
    ) internal view returns (uint256) {
        uint256 total = 0;
        for (uint64 i = 0; i < totalMarkets; i++) {
            MarketData storage m = markets[i];
            if (!m.exists) continue;
            uint256 depositBalance = (userMarketData[i][user].scaledDeposits *
                m.depositIndex) / SCALE;
            if (depositBalance == 0) continue;
            uint256 price = _getPriceForMarket(i, useCache);
            uint256 value = _getValueInUsd8(depositBalance, price, i);
            total += (value * m.params.liquidationThresholdBps) / BPS;
        }
        return total;
    }

    function _getBorrowValue(
        address user,
        bool useCache
    ) internal view returns (uint256) {
        uint256 total = 0;
        for (uint64 i = 0; i < totalMarkets; i++) {
            MarketData storage m = markets[i];
            if (!m.exists) continue;
            uint256 borrowBalance = (userMarketData[i][user].scaledBorrows *
                m.borrowIndex) / SCALE;
            if (borrowBalance == 0) continue;
            uint256 price = _getPriceForMarket(i, useCache);
            total += _getValueInUsd8(borrowBalance, price, i);
        }
        return total;
    }

    /// @notice Collateral at liquidation threshold: sum over markets of (collateral value in market * that market's liquidationThresholdBps).
    /// @dev Uses cached prices when useCache true (state-changing ops); each collateral market's own threshold.
    function _getCollateralAtThresholdFromMarkets(
        address user,
        bool useCache
    ) internal view returns (uint256) {
        return _getCollateralValueAtThreshold(user, useCache);
    }

    /// @notice HF after withdraw: uses global borrow value + collateral-at-threshold from markets (each market's threshold)
    /// @dev State already updated; collateral-at-threshold recomputed from balances and cached prices
    function _getHealthFactorFromGlobalAfterWithdraw(
        address user
    ) internal view returns (uint256) {
        GlobalUserData storage g = globalUsers[user];
        if (g.totalBorrowValue == 0) return type(uint256).max;
        uint256 collAtThreshold = _getCollateralAtThresholdFromMarkets(
            user,
            true
        );
        return (collAtThreshold * SCALE) / g.totalBorrowValue;
    }

    /// @notice HF after borrow: uses global borrow value + new borrow + collateral-at-threshold from markets (each market's threshold)
    function _getHealthFactorFromGlobalAfterBorrow(
        address user,
        uint64 marketId,
        uint256 borrowAmount
    ) internal view returns (uint256) {
        GlobalUserData storage g = globalUsers[user];
        uint256 borrowValue = g.totalBorrowValue +
            _getValueInUsd8(
                borrowAmount,
                markets[marketId].lastPrice,
                marketId
            );
        if (borrowValue == 0) return type(uint256).max;
        uint256 collAtThreshold = _getCollateralAtThresholdFromMarkets(
            user,
            true
        );
        return (collAtThreshold * SCALE) / borrowValue;
    }

    /// @notice Get user's health factor (1e18 = healthy, < 1e18 = liquidatable).
    /// @dev Uses synced global data and cached prices; efficient for UI/frequent queries.
    function getHealthFactor(address user) public view returns (uint256) {
        GlobalUserData storage g = globalUsers[user];
        if (g.totalBorrowValue == 0) return type(uint256).max;
        uint256 collAtThreshold = _getCollateralAtThresholdFromMarkets(
            user,
            true
        );
        return (collAtThreshold * SCALE) / g.totalBorrowValue;
    }

    /// @notice Health factor using a specific market's liquidation threshold (e.g. for liquidation UI).
    /// @dev Same as getHealthFactor but applies the given market's LT to total collateral; use for liquidation context.
    function getHealthFactorForMarket(
        address user,
        uint64 marketId
    ) public view returns (uint256) {
        return _getHealthFactorForMarket(user, marketId);
    }

    function _getHealthFactorForMarket(
        address user,
        uint64 marketId
    ) internal view returns (uint256) {
        GlobalUserData storage g = globalUsers[user];
        if (g.totalBorrowValue == 0) return type(uint256).max;
        MarketData storage m = markets[marketId];
        if (!m.exists) revert MarketNotFound();
        if (m.paused) revert MarketPaused();
        uint256 collAtThreshold = (g.totalCollateralValue *
            m.params.liquidationThresholdBps) / BPS;
        return (collAtThreshold * SCALE) / g.totalBorrowValue;
    }

    /// @notice Get user's total collateral value (USD 8 decimals) using fresh oracle data (expensive, for validation/audits).
    function getTotalCollateralRealtime(
        address user
    ) public view returns (uint256) {
        return _getRawCollateralValue(user, false);
    }

    /// @notice Get user's total borrow value (USD 8 decimals) using fresh oracle data (expensive, for validation/audits).
    function getTotalBorrowsRealtime(
        address user
    ) public view returns (uint256) {
        return _getBorrowValue(user, false);
    }

    /// @notice Get user's health factor using fresh oracle data (expensive, for validation/audits).
    function getHealthFactorRealtime(
        address user
    ) public view returns (uint256) {
        uint256 borrowValue = _getBorrowValue(user, false);
        if (borrowValue == 0) return type(uint256).max;
        uint256 collValue = _getCollateralValueAtThreshold(user, false);
        return (collValue * SCALE) / borrowValue;
    }

    /// @notice Get max borrow for a user in a specific market.
    /// @dev Uses synced global borrow value and cached prices; efficient for UI/frequent queries.
    function getMaxBorrow(
        address user,
        uint64 marketId
    ) public view returns (uint256) {
        uint256 totalCollateralValue = 0;
        for (uint64 i = 0; i < totalMarkets; i++) {
            MarketData storage m = markets[i];
            if (!m.exists) continue;
            uint256 depositBalance = (userMarketData[i][user].scaledDeposits *
                m.depositIndex) / SCALE;
            if (depositBalance == 0) continue;
            uint256 price = _getPriceForMarket(i, true);
            uint256 value = _getValueInUsd8(depositBalance, price, i);
            totalCollateralValue +=
                (value * m.params.collateralFactorBps) /
                BPS;
        }

        uint256 totalBorrowValue = globalUsers[user].totalBorrowValue;
        if (totalBorrowValue >= totalCollateralValue) return 0;

        MarketData storage borrowM = markets[marketId];
        if (!borrowM.exists) return 0;
        uint256 borrowPrice = _getPriceForMarket(marketId, true);
        if (borrowPrice == 0) return 0;
        uint256 maxBorrowValue = totalCollateralValue - totalBorrowValue;
        uint8 borrowDecimals = _getTokenDecimals(marketId);
        return (maxBorrowValue * (10 ** borrowDecimals)) / borrowPrice;
    }

    /// @notice Get max borrow using fresh oracle data (expensive, for validation/audits).
    function getMaxBorrowRealtime(
        address user,
        uint64 marketId
    ) public view returns (uint256) {
        uint256 totalCollateralValue = 0;
        for (uint64 i = 0; i < totalMarkets; i++) {
            MarketData storage m = markets[i];
            if (!m.exists) continue;
            uint256 depositBalance = (userMarketData[i][user].scaledDeposits *
                m.depositIndex) / SCALE;
            if (depositBalance == 0) continue;
            uint256 price = _getPriceForMarket(i, false);
            uint256 value = _getValueInUsd8(depositBalance, price, i);
            totalCollateralValue +=
                (value * m.params.collateralFactorBps) /
                BPS;
        }

        uint256 totalBorrowValue = _getBorrowValue(user, false);
        if (totalBorrowValue >= totalCollateralValue) return 0;

        MarketData storage borrowM = markets[marketId];
        if (!borrowM.exists) return 0;
        uint256 borrowPrice = _getPriceForMarket(marketId, false);
        if (borrowPrice == 0) return 0;
        uint256 maxBorrowValue = totalCollateralValue - totalBorrowValue;
        uint8 borrowDecimals = _getTokenDecimals(marketId);
        return (maxBorrowValue * (10 ** borrowDecimals)) / borrowPrice;
    }

    /// @notice Manually refresh a user's synced global data (prices + totalCollateralValue, totalBorrowValue).
    /// @dev Call when the user has not interacted recently but synced views (getMaxBorrow, getHealthFactor) should reflect current prices.
    /// @dev Can be called by anyone. Updates lastPrice for all markets where the user has a position, then recomputes global totals.
    function syncUserData(address user) external {
        for (uint64 i = 0; i < totalMarkets; i++) {
            MarketData storage m = markets[i];
            if (!m.exists) continue;
            uint256 depositBalance = (userMarketData[i][user].scaledDeposits *
                m.depositIndex) / SCALE;
            uint256 borrowBalance = (userMarketData[i][user].scaledBorrows *
                m.borrowIndex) / SCALE;
            if (depositBalance > 0 || borrowBalance > 0) {
                (m.lastPrice, ) = oracle.getPrice(i);
            }
        }

        uint256 newCollateralValue = 0;
        for (uint64 i = 0; i < totalMarkets; i++) {
            MarketData storage m = markets[i];
            if (!m.exists) continue;
            uint256 depositBalance = (userMarketData[i][user].scaledDeposits *
                m.depositIndex) / SCALE;
            if (depositBalance == 0) continue;
            newCollateralValue += _getValueInUsd8(
                depositBalance,
                m.lastPrice,
                i
            );
        }

        uint256 newBorrowValue = 0;
        for (uint64 i = 0; i < totalMarkets; i++) {
            MarketData storage m = markets[i];
            if (!m.exists) continue;
            uint256 borrowBalance = (userMarketData[i][user].scaledBorrows *
                m.borrowIndex) / SCALE;
            if (borrowBalance == 0) continue;
            newBorrowValue += _getValueInUsd8(borrowBalance, m.lastPrice, i);
        }

        GlobalUserData storage g = globalUsers[user];
        g.totalCollateralValue = newCollateralValue;
        g.totalBorrowValue = newBorrowValue;
        g.lastUpdateTime = uint64(block.timestamp);
    }

    /// @notice Get deposit index for a market (used by NToken for balanceOf).
    function getDepositIndex(uint64 marketId) external view returns (uint256) {
        MarketData storage m = markets[marketId];
        if (!m.exists) return 0;
        return m.depositIndex;
    }

    /// @notice Get NToken address for a market
    function getNToken(uint64 marketId) external view returns (address) {
        MarketData storage m = markets[marketId];
        if (!m.exists) return address(0);
        return address(m.nToken);
    }

    /// @notice Get user's supply balance in a market
    function getSupplyBalance(
        address user,
        uint64 marketId
    ) external view returns (uint256) {
        MarketData storage m = markets[marketId];
        if (!m.exists) return 0;
        return
            (userMarketData[marketId][user].scaledDeposits * m.depositIndex) /
            SCALE;
    }

    /// @notice Get user's scaled deposits (for NToken compatibility)
    function getScaledDeposits(
        address user,
        uint64 marketId
    ) external view returns (uint256) {
        MarketData storage m = markets[marketId];
        if (!m.exists) return 0;
        return userMarketData[marketId][user].scaledDeposits;
    }

    /// @notice Get total scaled deposits in a market (for NToken compatibility)
    function getTotalScaledDeposits(
        uint64 marketId
    ) external view returns (uint256) {
        MarketData storage m = markets[marketId];
        if (!m.exists) return 0;
        return m.totalScaledDeposits;
    }

    /// @notice Increment market total scaled borrows by the given amount.
    function _incrementMarketTotalScaledBorrows(
        uint64 marketId,
        uint256 amount
    ) internal {
        MarketData storage m = markets[marketId];
        m.totalScaledBorrows += amount;
    }

    /// @notice Decrement market total scaled borrows by the given amount.
    function _decrementMarketTotalScaledBorrows(
        uint64 marketId,
        uint256 amount
    ) internal {
        MarketData storage m = markets[marketId];
        if (m.totalScaledBorrows < amount) revert InsufficientBalance();
        m.totalScaledBorrows -= amount;
    }

    /// @notice Get user's borrow balance in a market
    function getBorrowBalance(
        address user,
        uint64 marketId
    ) external view returns (uint256) {
        MarketData storage m = markets[marketId];
        if (!m.exists) return 0;
        return
            (userMarketData[marketId][user].scaledBorrows * m.borrowIndex) /
            SCALE;
    }

    /// @notice Get total deposits (actual) in a market
    function getMarketTotalDeposits(
        uint64 marketId
    ) external view returns (uint256) {
        MarketData storage m = markets[marketId];
        if (!m.exists) return 0;
        return (m.totalScaledDeposits * m.depositIndex) / SCALE;
    }

    /// @notice Get total borrows (actual) in a market
    function getMarketTotalBorrows(
        uint64 marketId
    ) external view returns (uint256) {
        MarketData storage m = markets[marketId];
        if (!m.exists) return 0;
        return (m.totalScaledBorrows * m.borrowIndex) / SCALE;
    }

    /// @notice Get available liquidity in a market
    function getAvailableLiquidity(
        uint64 marketId
    ) external view returns (uint256) {
        MarketData storage m = markets[marketId];
        if (!m.exists) return 0;
        uint256 totalDeposits = (m.totalScaledDeposits * m.depositIndex) /
            SCALE;
        uint256 totalBorrows = (m.totalScaledBorrows * m.borrowIndex) / SCALE;
        return totalDeposits - totalBorrows;
    }

    function setOracle(address newOracle) external onlyOwner {
        oracle = IOracleRouter(newOracle);
    }
}