// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import {Initializable} from "@openzeppelin/[email protected]/proxy/utils/Initializable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
// import {OwnableUpgradeable} from "@openzeppelin/[email protected]/access/OwnableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
// import {PausableUpgradeable} from "@openzeppelin/[email protected]/security/PausableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IFundingRateEngine} from "./interfaces/IFundingRateEngine.sol";

/// @title FundingRateEngine
/// @author Half-Life Protocol
/// @notice Calculates and settles funding payments for the Half-Life protocol
/// @dev Upgradeable, Ownable, Pausable. Funding logic is handled here.
contract FundingRateEngine is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    IFundingRateEngine
{
    /// @dev Custom errors for gas efficiency
    error NotAuthorized();
    error InvalidInput();

    /// @notice Funding multiplier for rate calculation (e.g., 1e18 = 1.0)
    uint256 private fundingMultiplier;
    /// @notice Only the market contract can call restricted functions
    address public market;
    /// @notice Last funding settlement timestamp
    uint256 public lastSettledTimestamp;

    /// @dev Constants
    uint256 private constant BASIS_POINTS_DENOMINATOR = 10_000;
    uint256 private constant FUNDING_RATE_SCALE = 1e18;

    /// @notice Restrict to only the market contract
    modifier onlyMarket() {
        if (msg.sender != market) revert NotAuthorized();
        _;
    }

    /// @notice Initializer for upgradeable contract
    /// @param _market The address of the PerpetualIndexMarket contract
    /// @param _fundingMultiplier The initial funding multiplier
    function initialize(
        address _market,
        uint256 _fundingMultiplier
    ) external initializer {
        __Ownable_init();
        __Pausable_init();
        market = _market;
        fundingMultiplier = _fundingMultiplier;
    }

    /// @inheritdoc IFundingRateEngine
    /// @notice Calculate the current funding rate
    /// @param marketPrice The current market price (index value)
    /// @param indexValue The reference index value
    /// @return fundingRate The calculated funding rate (signed integer, can be positive or negative)
    function calculateFundingRate(
        uint256 marketPrice,
        uint256 indexValue
    ) external view override returns (int256 fundingRate) {
        if (indexValue == 0) revert InvalidInput();
        // fundingRate = (marketPrice - indexValue) / indexValue * fundingMultiplier
        int256 premium = int256(marketPrice) - int256(indexValue);
        fundingRate =
            (premium * int256(fundingMultiplier)) /
            int256(indexValue);
    }

    /// @inheritdoc IFundingRateEngine
    /// @notice Settle funding payments between longs and shorts
    /// @param timestamp The timestamp for the funding interval
    function settleFunding(
        uint256 timestamp
    ) external override onlyMarket whenNotPaused {
        // For MVP, just store the last settled timestamp and emit event
        lastSettledTimestamp = timestamp;
        emit FundingSettled(timestamp);
        // In production, iterate over all positions and apply funding payments
    }

    /// @inheritdoc IFundingRateEngine
    /// @notice Set funding parameters (onlyOwner or market)
    /// @param _fundingMultiplier The multiplier for funding rate calculation
    function setFundingMultiplier(
        uint256 _fundingMultiplier
    ) external override onlyOwner {
        fundingMultiplier = _fundingMultiplier;
    }

    /// @inheritdoc IFundingRateEngine
    /// @notice Get the current funding multiplier
    /// @return The funding multiplier
    function getFundingMultiplier() external view override returns (uint256) {
        return fundingMultiplier;
    }
}
