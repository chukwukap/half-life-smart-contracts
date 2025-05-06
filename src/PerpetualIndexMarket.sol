// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {IFundingRateEngine} from "./interfaces/IFundingRateEngine.sol";
import {IOracleAdapter} from "./interfaces/IOracleAdapter.sol";
import {ILiquidationEngine} from "./interfaces/ILiquidationEngine.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

/// @title PerpetualIndexMarket
/// @notice Main contract for Half-Life perpetual index betting market
/// @dev Integrates all modules and implements business logic for perpetual trading
contract PerpetualIndexMarket is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /// @notice Emitted when a new position is opened
    event PositionOpened(
        address indexed user,
        uint256 positionId,
        bool isLong,
        uint256 amount,
        uint256 leverage
    );
    /// @notice Emitted when a position is closed
    event PositionClosed(address indexed user, uint256 positionId, int256 pnl);
    /// @notice Emitted when funding is settled
    event FundingSettled(uint256 indexed timestamp);
    /// @notice Emitted when a position is liquidated
    event PositionLiquidated(
        address indexed user,
        uint256 positionId,
        address liquidator
    );
    /// @notice Emitted when the market is paused or unpaused
    event MarketPaused(address indexed admin);
    event MarketUnpaused(address indexed admin);
    /// @notice Emitted when the index value is updated by the oracle
    event IndexValueUpdated(uint256 newValue, uint256 timestamp);

    /// @dev Custom errors for gas efficiency
    error NotAuthorized();
    error InvalidInput();
    error MarketPausedError();
    error PositionNotFound();
    error InsufficientMargin();
    error NotCompliant();

    /// @notice Module contract addresses
    address public positionManager;
    address public fundingRateEngine;
    address public oracleAdapter;
    address public liquidationEngine;
    address public feeManager;
    // address public complianceModule; // Omitted for now

    /// @notice Module interfaces
    IPositionManager private _pm;
    IFundingRateEngine private _fre;
    IOracleAdapter private _oa;
    ILiquidationEngine private _le;
    IFeeManager private _fm;

    /// @notice Market parameters (example, to be expanded)
    uint256 public marginRequirement;
    uint256 public fundingInterval;
    uint256 public lastIndexValue;
    uint256 public lastIndexTimestamp;

    /// @notice Modifier to restrict to only the oracle adapter
    modifier onlyOracle() {
        if (msg.sender != oracleAdapter) revert NotAuthorized();
        _;
    }

    /// @notice Modifier to restrict to only the liquidation engine
    modifier onlyLiquidationEngine() {
        if (msg.sender != liquidationEngine) revert NotAuthorized();
        _;
    }

    /// @notice Initializer for upgradeable contract
    /// @param _positionManager Address of PositionManager
    /// @param _fundingRateEngine Address of FundingRateEngine
    /// @param _oracleAdapter Address of OracleAdapter
    /// @param _liquidationEngine Address of LiquidationEngine
    /// @param _feeManager Address of FeeManager
    /// @param _marginRequirement Initial margin requirement
    /// @param _fundingInterval Funding interval in seconds
    function initialize(
        address _positionManager,
        address _fundingRateEngine,
        address _oracleAdapter,
        address _liquidationEngine,
        address _feeManager,
        uint256 _marginRequirement,
        uint256 _fundingInterval
    ) external initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        positionManager = _positionManager;
        fundingRateEngine = _fundingRateEngine;
        oracleAdapter = _oracleAdapter;
        liquidationEngine = _liquidationEngine;
        feeManager = _feeManager;
        marginRequirement = _marginRequirement;
        fundingInterval = _fundingInterval;
        _pm = IPositionManager(_positionManager);
        _fre = IFundingRateEngine(_fundingRateEngine);
        _oa = IOracleAdapter(_oracleAdapter);
        _le = ILiquidationEngine(_liquidationEngine);
        _fm = IFeeManager(_feeManager);
    }

    /// @notice Pause the market (onlyOwner)
    function pauseMarket() external onlyOwner {
        _pause();
        emit MarketPaused(msg.sender);
    }

    /// @notice Unpause the market (onlyOwner)
    function unpauseMarket() external onlyOwner {
        _unpause();
        emit MarketUnpaused(msg.sender);
    }

    /// @notice Update the index value (only callable by oracle)
    /// @param newValue The new index value
    function updateIndexValue(
        uint256 newValue
    ) external onlyOracle whenNotPaused {
        lastIndexValue = newValue;
        lastIndexTimestamp = block.timestamp;
        emit IndexValueUpdated(newValue, block.timestamp);
    }

    /// @notice Open a new position (long or short)
    /// @param isLong True for long, false for short
    /// @param amount The position size (in index units)
    /// @param leverage The leverage to use
    /// @dev User must send margin as msg.value (ETH) for simplicity
    function openPosition(
        bool isLong,
        uint256 amount,
        uint256 leverage
    ) external payable whenNotPaused nonReentrant returns (uint256 positionId) {
        if (amount == 0 || leverage == 0) revert InvalidInput();
        uint256 margin = msg.value;
        if (margin < marginRequirement) revert InsufficientMargin();
        // Calculate trading fee and collect
        uint256 tradingFee = _fm.calculateTradingFee(amount);
        if (margin <= tradingFee) revert InsufficientMargin();
        _fm.collectFee(msg.sender, tradingFee, "trading");
        // Get latest index value
        (uint256 indexValue, ) = _oa.getLatestIndexValue();
        // Open position in PositionManager
        positionId = _pm.openPosition(
            msg.sender,
            isLong,
            amount,
            leverage,
            indexValue,
            margin - tradingFee
        );
        emit PositionOpened(msg.sender, positionId, isLong, amount, leverage);
    }

    /// @notice Close an existing position
    /// @param positionId The ID of the position
    function closePosition(
        uint256 positionId
    ) external whenNotPaused nonReentrant {
        IPositionManager.Position memory pos = _pm.getPosition(positionId);
        if (!pos.isOpen) revert PositionNotFound();
        if (pos.user != msg.sender) revert NotAuthorized();
        // Get latest index value
        (uint256 indexValue, ) = _oa.getLatestIndexValue();
        // Close position in PositionManager and get P&L
        int256 pnl = _pm.closePosition(positionId, indexValue);
        // Calculate trading fee and collect
        uint256 tradingFee = _fm.calculateTradingFee(pos.amount);
        _fm.collectFee(msg.sender, tradingFee, "trading");
        // TODO: Transfer margin + P&L - fee back to user (ETH for now)
        emit PositionClosed(msg.sender, positionId, pnl);
    }

    /// @notice Settle funding payments between longs and shorts
    /// @dev Can be called by anyone, but only once per funding interval
    function settleFunding() external whenNotPaused nonReentrant {
        // Settle funding using FundingRateEngine
        uint256 timestamp = block.timestamp;
        _fre.settleFunding(timestamp);
        // For simplicity, collect a flat funding fee from all open positions (expand as needed)
        // In a real implementation, iterate over all positions and apply funding payments
        emit FundingSettled(timestamp);
    }

    /// @notice Trigger liquidation of a position if eligible
    /// @param positionId The ID of the position
    function liquidate(uint256 positionId) external whenNotPaused nonReentrant {
        IPositionManager.Position memory pos = _pm.getPosition(positionId);
        if (!pos.isOpen) revert PositionNotFound();
        // Get latest index value
        (uint256 indexValue, ) = _oa.getLatestIndexValue();
        // Check if position is eligible for liquidation
        bool canLiquidate = _le.canLiquidate(
            positionId,
            indexValue,
            marginRequirement
        );
        if (!canLiquidate) revert NotAuthorized();
        // Trigger liquidation in LiquidationEngine
        (int256 pnl, uint256 penalty) = _le.liquidate(
            positionId,
            indexValue,
            marginRequirement
        );
        // Collect liquidation fee (for now, treat penalty as fee)
        _fm.collectFee(pos.user, penalty, "liquidation");
        emit PositionLiquidated(pos.user, positionId, msg.sender);
    }

    // --- Additional business logic (settleFunding, liquidate, etc.) to be implemented next ---
}
