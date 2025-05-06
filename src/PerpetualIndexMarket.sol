// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title PerpetualIndexMarket
/// @notice Main contract for Half-Life perpetual index betting market
/// @dev Upgradeable, Ownable, Pausable, ReentrancyGuard. All business logic to be implemented in future iterations.
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

    /// @notice Address of the PositionManager contract
    address public positionManager;
    /// @notice Address of the FundingRateEngine contract
    address public fundingRateEngine;
    /// @notice Address of the OracleAdapter contract
    address public oracleAdapter;
    /// @notice Address of the LiquidationEngine contract
    address public liquidationEngine;
    /// @notice Address of the FeeManager contract
    address public feeManager;
    /// @notice Address of the ComplianceModule contract (optional)
    address public complianceModule;

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

    /// @notice Modifier to restrict to only the compliance module (if set)
    modifier onlyCompliance() {
        if (complianceModule != address(0) && msg.sender != complianceModule)
            revert NotAuthorized();
        _;
    }

    /// @notice Initializer for upgradeable contract
    /// @param _positionManager Address of PositionManager
    /// @param _fundingRateEngine Address of FundingRateEngine
    /// @param _oracleAdapter Address of OracleAdapter
    /// @param _liquidationEngine Address of LiquidationEngine
    /// @param _feeManager Address of FeeManager
    /// @param _complianceModule Address of ComplianceModule (optional)
    /// @param _marginRequirement Initial margin requirement
    /// @param _fundingInterval Funding interval in seconds
    function initialize(
        address _positionManager,
        address _fundingRateEngine,
        address _oracleAdapter,
        address _liquidationEngine,
        address _feeManager,
        address _complianceModule,
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
        complianceModule = _complianceModule;
        marginRequirement = _marginRequirement;
        fundingInterval = _fundingInterval;
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

    // --- Business logic functions to be implemented in future iterations ---
    // openPosition, closePosition, settleFunding, liquidate, etc.
}
