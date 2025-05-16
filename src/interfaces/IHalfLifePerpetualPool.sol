// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IHalfLifePerpetualPool {
    // Structs
    struct Position {
        int256 size;
        uint256 entryTLI;
        uint256 margin;
        uint256 lastFundingTime;
    }

    struct PoolState {
        uint256 totalLongSize;
        uint256 totalShortSize;
        uint256 totalMargin;
        uint256 totalFees;
        uint256 lastFundingTime;
    }

    // View functions
    function positions(
        address user
    )
        external
        view
        returns (
            int256 size,
            uint256 entryTLI,
            uint256 margin,
            uint256 lastFundingTime
        );
    function poolState()
        external
        view
        returns (
            uint256 totalLongSize,
            uint256 totalShortSize,
            uint256 totalMargin,
            uint256 totalFees,
            uint256 lastFundingTime
        );
    function circuitBreaker() external view returns (bool);
    function maintenanceMarginRatio() external view returns (uint256);
    function liquidationFee() external view returns (uint256);
    function maxDrawdown() external view returns (uint256);
    function fundingRateCap() external view returns (uint256);
    function fundingInterval() external view returns (uint256);
    function tradingFee() external view returns (uint256);

    // State changing functions
    function openPosition(int256 size, uint256 marginAmount) external;
    function closePosition() external;
    function payFunding(address user) external;
    function liquidate(address user) external;
    function setHook(address _hook) external;
    function updateRiskParameters(
        uint256 _maintenanceMargin,
        uint256 _liquidationFee,
        uint256 _maxDrawdown,
        uint256 _fundingRateCap
    ) external;

    // Events
    event PositionOpened(
        address indexed user,
        int256 size,
        uint256 margin,
        uint256 entryTLI
    );
    event PositionClosed(address indexed user, int256 pnl, uint256 funding);
    event PositionLiquidated(
        address indexed user,
        address indexed liquidator,
        uint256 reward
    );
    event FundingPaid(address indexed user, int256 amount, uint256 timestamp);
    event CircuitBreakerTriggered(uint256 timestamp);
    event RiskParametersUpdated(
        uint256 maintenanceMargin,
        uint256 liquidationFee,
        uint256 maxDrawdown,
        uint256 fundingRateCap
    );
}
