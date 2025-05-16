// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IPerpetualIndexMarket
/// @notice Interface for the PerpetualIndexMarket contract in Half-Life protocol
interface IPerpetualIndexMarket {
    /// @notice Emitted when a new position is opened
    event PositionOpened(
        address indexed trader,
        uint256 positionId,
        bool isLong,
        uint256 amount,
        uint256 leverage
    );
    /// @notice Emitted when a position is closed
    event PositionClosed(
        address indexed trader,
        uint256 positionId,
        int256 pnl
    );
    /// @notice Emitted when funding payment is applied
    event FundingPaymentApplied(
        uint256 indexed positionId,
        address indexed user,
        int256 fundingPayment,
        uint256 newMargin
    );
    /// @notice Emitted when a position is liquidated
    event PositionLiquidated(
        address indexed trader,
        uint256 positionId,
        address liquidator
    );
    /// @notice Emitted when the market is paused or unpaused
    event MarketPaused(address indexed admin);
    event MarketUnpaused(address indexed admin);
    /// @notice Emitted when the index value is updated by the oracle
    event IndexValueUpdated(
        uint256 newValue,
        uint256 timestamp,
        address updater
    );
    /// @notice Emitted when margin is deposited
    event MarginDeposited(address indexed user, uint256 amount);
    /// @notice Emitted when margin is withdrawn
    event MarginWithdrawn(address indexed user, uint256 amount);
    /// @notice Emitted when a withdrawal is blocked
    event WithdrawalBlocked(
        address indexed user,
        uint256 requested,
        string reason
    );

    /// @notice Open a new position (long or short)
    /// @param isLong True for long, false for short
    /// @param amount The position size (in index units)
    /// @param leverage The leverage to use
    /// @param marginAmount The margin to deposit (in marginToken)
    /// @return positionId The ID of the new position
    function openPosition(
        bool isLong,
        uint256 amount,
        uint256 leverage,
        uint256 marginAmount
    ) external returns (uint256 positionId);

    /// @notice Close an existing position
    /// @param positionId The ID of the position
    function closePosition(uint256 positionId) external;

    /// @notice Settle funding payments between longs and shorts
    function settleFunding() external;

    /// @notice Trigger liquidation of a position if eligible
    /// @param positionId The ID of the position
    function liquidate(uint256 positionId) external;

    /// @notice Update the index value (only callable by oracle)
    /// @param newValue The new index value
    function updateIndexValue(uint256 newValue) external;

    /// @notice Pause the market (onlyOwner)
    function pauseMarket() external;

    /// @notice Unpause the market (onlyOwner)
    function unpauseMarket() external;

    /// @notice Deposit margin to the contract
    /// @param amount The amount to deposit
    function depositMargin(uint256 amount) external;

    /// @notice Withdraw margin from the contract (if tracked)
    /// @param amount The amount to withdraw
    function withdrawMargin(uint256 amount) external;

    /// @notice Get the margin balance for a trader
    /// @param trader The address of the trader
    /// @return margin The margin balance
    function getMargin(address trader) external view returns (uint256);

    /// @notice Get the funding rate from the funding rate engine
    /// @return fundingRate The funding rate (can be negative)
    function getFundingRate() external view returns (int256);

    /// @notice Get the latest oracle price
    /// @return oraclePrice The oracle price
    function getOraclePrice() external view returns (uint256);
}
