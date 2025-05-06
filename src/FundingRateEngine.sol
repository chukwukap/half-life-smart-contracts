// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IFundingRateEngine} from "./interfaces/IFundingRateEngine.sol";

/// @title FundingRateEngine
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
    function settleFunding(
        uint256 timestamp
    ) external override onlyMarket whenNotPaused {
        // For MVP, just store the last settled timestamp and emit event
        lastSettledTimestamp = timestamp;
        emit FundingSettled(timestamp);
        // In production, iterate over all positions and apply funding payments
    }

    /// @inheritdoc IFundingRateEngine
    function setFundingMultiplier(
        uint256 _fundingMultiplier
    ) external override onlyOwner {
        fundingMultiplier = _fundingMultiplier;
    }

    /// @inheritdoc IFundingRateEngine
    function getFundingMultiplier() external view override returns (uint256) {
        return fundingMultiplier;
    }
}
