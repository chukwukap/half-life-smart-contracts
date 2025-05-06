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
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPerpetualIndexMarket} from "./interfaces/IPerpetualIndexMarket.sol";

/// @title PerpetualIndexMarket
/// @notice Main contract for Half-Life perpetual index betting market
/// @dev Integrates all modules and implements business logic for perpetual trading
contract PerpetualIndexMarket is
    IPerpetualIndexMarket,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

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

    /// @notice The ERC20 token used for margin (e.g., USDC)
    IERC20 public marginToken;

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
    /// @param _marginToken Address of ERC20 token for margin
    /// @param _marginRequirement Initial margin requirement
    /// @param _fundingInterval Funding interval in seconds
    function initialize(
        address _positionManager,
        address _fundingRateEngine,
        address _oracleAdapter,
        address _liquidationEngine,
        address _feeManager,
        address _marginToken,
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
        marginToken = IERC20(_marginToken);
        marginRequirement = _marginRequirement;
        fundingInterval = _fundingInterval;
        _pm = IPositionManager(_positionManager);
        _fre = IFundingRateEngine(_fundingRateEngine);
        _oa = IOracleAdapter(_oracleAdapter);
        _le = ILiquidationEngine(_liquidationEngine);
        _fm = IFeeManager(_feeManager);
    }

    /// @notice Update the index value (only callable by oracle)
    /// @param newValue The new index value
    function updateIndexValue(uint256 newValue) external whenNotPaused {
        if (msg.sender != oracleAdapter) revert NotAuthorized();
        if (newValue == 0) revert InvalidInput();
        lastIndexValue = newValue;
        lastIndexTimestamp = block.timestamp;
        emit IndexValueUpdated(newValue, block.timestamp);
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

    /// @notice Open a new position (long or short)
    /// @param isLong True for long, false for short
    /// @param amount The position size (in index units)
    /// @param leverage The leverage to use
    /// @param margin The margin to deposit (in marginToken)
    function openPosition(
        bool isLong,
        uint256 amount,
        uint256 leverage,
        uint256 margin
    ) external whenNotPaused nonReentrant returns (uint256 positionId) {
        if (amount == 0 || leverage == 0) revert InvalidInput();
        if (margin < marginRequirement) revert InsufficientMargin();
        // Transfer margin from user to contract
        marginToken.safeTransferFrom(msg.sender, address(this), margin);
        // Calculate trading fee and collect
        uint256 tradingFee = _fm.calculateTradingFee(amount);
        if (margin <= tradingFee) revert InsufficientMargin();
        marginToken.safeApprove(address(_fm), tradingFee);
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
        marginToken.safeApprove(address(_fm), tradingFee);
        _fm.collectFee(msg.sender, tradingFee, "trading");
        // Payout: margin + pnl - fee
        uint256 payout = pos.margin;
        if (pnl > 0) {
            payout += uint256(pnl);
        } else if (uint256(-pnl) < payout) {
            payout -= uint256(-pnl);
        } else {
            payout = 0;
        }
        if (payout > tradingFee) {
            payout -= tradingFee;
        } else {
            payout = 0;
        }
        if (payout > 0) {
            marginToken.safeTransfer(msg.sender, payout);
        }
        emit PositionClosed(msg.sender, positionId, pnl);
    }

    /// @notice Deposit margin to the contract
    /// @param amount The amount to deposit
    function depositMargin(uint256 amount) external whenNotPaused nonReentrant {
        marginToken.safeTransferFrom(msg.sender, address(this), amount);
        // Optionally track user balances for withdrawals
    }

    /// @notice Withdraw margin from the contract (if tracked)
    /// @param amount The amount to withdraw
    function withdrawMargin(
        uint256 amount
    ) external whenNotPaused nonReentrant {
        // Optionally check user balance
        marginToken.safeTransfer(msg.sender, amount);
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
