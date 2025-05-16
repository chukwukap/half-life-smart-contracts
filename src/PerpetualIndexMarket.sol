// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {IFundingRateEngine} from "./interfaces/IFundingRateEngine.sol";
import {IOracleAdapter} from "./interfaces/IOracleAdapter.sol";
import {ILiquidationEngine} from "./interfaces/ILiquidationEngine.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPerpetualIndexMarket} from "./interfaces/IPerpetualIndexMarket.sol";

/// @title PerpetualIndexMarket
/// @author Half-Life Protocol
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

    // --- Constants ---
    uint256 private constant BASIS_POINTS_DENOMINATOR = 10_000;
    uint256 private constant FUNDING_RATE_SCALE = 1e18;

    // --- Errors ---
    error NotAuthorized();
    error InvalidInput();
    error MarketPausedError();
    error PositionNotFound();
    error InsufficientMargin();
    error NotCompliant();

    // --- Modifiers ---
    modifier onlyOracle() {
        if (msg.sender != oracleAdapter) revert NotAuthorized();
        _;
    }
    modifier onlyLiquidationEngine() {
        if (msg.sender != liquidationEngine) revert NotAuthorized();
        _;
    }

    // --- State Variables ---
    address public positionManager;
    address public fundingRateEngine;
    address public oracleAdapter;
    address public liquidationEngine;
    address public feeManager;
    IPositionManager private _pm;
    IFundingRateEngine private _fre;
    IOracleAdapter private _oa;
    ILiquidationEngine private _le;
    IFeeManager private _fm;
    uint256 public marginRequirement;
    uint256 public fundingInterval;
    uint256 public lastIndexValue;
    uint256 public lastIndexTimestamp;
    IERC20 public marginToken;
    mapping(address => uint256) public userMarginBalances;

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
        __Ownable_init(msg.sender);
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
    /// @dev Emits IndexValueUpdated
    /// @param newValue The new index value
    function updateIndexValue(uint256 newValue) external whenNotPaused {
        if (msg.sender != oracleAdapter) revert NotAuthorized();
        if (newValue == 0) revert InvalidInput();
        lastIndexValue = newValue;
        lastIndexTimestamp = block.timestamp;
        emit IndexValueUpdated(newValue, block.timestamp, msg.sender);
    }

    /// @notice Pause the market (onlyOwner)
    /// @dev Emits MarketPaused
    function pauseMarket() external onlyOwner {
        _pause();
        emit MarketPaused(msg.sender);
    }

    /// @notice Unpause the market (onlyOwner)
    /// @dev Emits MarketUnpaused
    function unpauseMarket() external onlyOwner {
        _unpause();
        emit MarketUnpaused(msg.sender);
    }

    /// @notice Open a new position (long or short)
    /// @dev Transfers margin, collects fee, and opens position in PositionManager
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
    ) external whenNotPaused nonReentrant returns (uint256 positionId) {
        if (amount == 0 || leverage == 0) revert InvalidInput();
        if (marginAmount < marginRequirement) revert InsufficientMargin();
        marginToken.safeTransferFrom(msg.sender, address(this), marginAmount);
        uint256 tradingFee = _fm.calculateTradingFee(amount);
        if (marginAmount <= tradingFee) revert InsufficientMargin();
        marginToken.approve(address(_fm), tradingFee);
        _fm.collectFee(msg.sender, tradingFee, "trading");
        (uint256 indexValue, ) = _oa.getLatestIndexValue();
        positionId = _pm.openPosition(
            msg.sender,
            isLong,
            amount,
            leverage,
            indexValue,
            marginAmount - tradingFee
        );
        emit PositionOpened(msg.sender, positionId, isLong, amount, leverage);
    }

    /// @notice Close an existing position
    /// @dev Transfers payout, collects fee, and closes position in PositionManager
    /// @param positionId The ID of the position
    function closePosition(
        uint256 positionId
    ) external whenNotPaused nonReentrant {
        IPositionManager.Position memory pos = _pm.getPosition(positionId);
        if (!pos.isOpen) revert PositionNotFound();
        if (pos.user != msg.sender) revert NotAuthorized();
        (uint256 indexValue, ) = _oa.getLatestIndexValue();
        int256 pnl = _pm.closePosition(positionId, indexValue);
        uint256 tradingFee = _fm.calculateTradingFee(pos.amount);
        marginToken.approve(address(_fm), tradingFee);
        _fm.collectFee(msg.sender, tradingFee, "trading");
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

    /// @notice Deposit margin to the contract and update user balance
    /// @dev Emits MarginDeposited
    /// @param amount The amount to deposit
    function depositMargin(uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidInput();
        marginToken.safeTransferFrom(msg.sender, address(this), amount);
        userMarginBalances[msg.sender] += amount;
        emit MarginDeposited(msg.sender, amount);
    }

    /// @notice Withdraw margin from the contract (if tracked)
    /// @dev Prevents withdrawal if it would undercollateralize any open position. Emits MarginWithdrawn or WithdrawalBlocked.
    /// @param amount The amount to withdraw
    function withdrawMargin(
        uint256 amount
    ) external whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidInput();
        if (userMarginBalances[msg.sender] < amount)
            revert InsufficientMargin();
        uint256[] memory userOpenIds = _pm.getUserOpenPositionIds(msg.sender);
        (uint256 indexValue, ) = _oa.getLatestIndexValue();
        for (uint256 i = 0; i < userOpenIds.length; i++) {
            IPositionManager.Position memory pos = _pm.getPosition(
                userOpenIds[i]
            );
            int256 direction = pos.isLong ? int256(1) : int256(-1);
            int256 pnl = direction *
                int256(indexValue) -
                direction *
                int256(pos.entryIndexValue);
            pnl = pnl * int256(pos.amount) * int256(pos.leverage);
            int256 marginAfterPnL = int256(pos.margin) + pnl;
            if (marginAfterPnL < int256(marginRequirement)) {
                emit WithdrawalBlocked(
                    msg.sender,
                    amount,
                    "Open position would be undercollateralized"
                );
                revert("Withdrawal would undercollateralize open position");
            }
        }
        userMarginBalances[msg.sender] -= amount;
        marginToken.safeTransfer(msg.sender, amount);
        emit MarginWithdrawn(msg.sender, amount);
    }

    /// @notice Settle funding payments between longs and shorts
    /// @dev Iterates over all open positions and applies funding payments. Emits FundingPaymentApplied.
    function settleFunding() external whenNotPaused nonReentrant {
        uint256 timestamp = block.timestamp;
        uint256[] memory openIds = _pm.getAllOpenPositionIds();
        (uint256 marketPrice, ) = _oa.getLatestIndexValue();
        for (uint256 i = 0; i < openIds.length; i++) {
            IPositionManager.Position memory pos = _pm.getPosition(openIds[i]);
            int256 fundingRate = _fre.calculateFundingRate(
                marketPrice,
                pos.entryIndexValue
            );
            int256 payment = (int256(pos.amount) *
                int256(pos.leverage) *
                fundingRate) / int256(FUNDING_RATE_SCALE);
            uint256 newMargin;
            if (payment < 0) {
                newMargin = pos.margin + uint256(-payment);
            } else {
                newMargin = (uint256(payment) >= pos.margin)
                    ? 0
                    : pos.margin - uint256(payment);
            }
            _pm.updateMargin(openIds[i], newMargin);
            emit FundingPaymentApplied(
                openIds[i],
                pos.user,
                payment,
                newMargin
            );
        }
        _fre.settleFunding(timestamp);
    }

    /// @notice Trigger liquidation of a position if eligible
    /// @dev Calls LiquidationEngine and FeeManager. Emits PositionLiquidated.
    /// @param positionId The ID of the position
    function liquidate(uint256 positionId) external whenNotPaused nonReentrant {
        IPositionManager.Position memory pos = _pm.getPosition(positionId);
        if (!pos.isOpen) revert PositionNotFound();
        (uint256 indexValue, ) = _oa.getLatestIndexValue();
        bool canLiquidate = _le.canLiquidate(
            positionId,
            indexValue,
            marginRequirement
        );
        if (!canLiquidate) revert NotAuthorized();
        (, uint256 penalty) = _le.liquidate(
            positionId,
            indexValue,
            marginRequirement
        );
        _fm.collectFee(pos.user, penalty, "liquidation");
        emit PositionLiquidated(pos.user, positionId, msg.sender);
    }

    /// @notice Get the margin balance for a trader
    /// @param trader The address of the trader
    /// @return margin The margin balance
    function getMargin(
        address trader
    ) external view override returns (uint256) {
        return userMarginBalances[trader];
    }

    /// @notice Get the funding rate from the funding rate engine
    /// @return fundingRate The funding rate (can be negative)
    function getFundingRate() external view override returns (int256) {
        (uint256 marketPrice, ) = _oa.getLatestIndexValue();
        // For security, always use the latest oracle price
        return _fre.calculateFundingRate(marketPrice, lastIndexValue);
    }

    /// @notice Get the latest oracle price
    /// @return oraclePrice The oracle price
    function getOraclePrice() external view override returns (uint256) {
        (uint256 marketPrice, ) = _oa.getLatestIndexValue();
        return marketPrice;
    }
}
