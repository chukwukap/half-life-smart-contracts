// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

/// @title FeeManager
/// @notice Handles fee calculation, collection, and distribution for the Half-Life protocol
/// @dev Upgradeable, Ownable, Pausable. All fee logic is handled here.
contract FeeManager is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    IFeeManager
{
    /// @dev Custom errors for gas efficiency
    error NotAuthorized();
    error InvalidInput();

    /// @notice Fee parameters in basis points (1e4 = 100%)
    uint256 private tradingFeeBps;
    uint256 private fundingFeeBps;
    uint256 private liquidationFeeBps;

    /// @notice Fee balances
    uint256 public treasuryBalance;
    uint256 public insuranceBalance;
    uint256 public stakersBalance;

    /// @notice Only the market contract can call restricted functions
    address public market;

    modifier onlyMarket() {
        if (msg.sender != market) revert NotAuthorized();
        _;
    }

    /// @notice Initializer for upgradeable contract
    /// @param _market The address of the PerpetualIndexMarket contract
    /// @param _tradingFeeBps Trading fee in basis points
    /// @param _fundingFeeBps Funding fee in basis points
    /// @param _liquidationFeeBps Liquidation fee in basis points
    function initialize(
        address _market,
        uint256 _tradingFeeBps,
        uint256 _fundingFeeBps,
        uint256 _liquidationFeeBps
    ) external initializer {
        __Ownable_init();
        __Pausable_init();
        market = _market;
        tradingFeeBps = _tradingFeeBps;
        fundingFeeBps = _fundingFeeBps;
        liquidationFeeBps = _liquidationFeeBps;
    }

    /// @inheritdoc IFeeManager
    function calculateTradingFee(
        uint256 amount
    ) external view override returns (uint256 fee) {
        fee = (amount * tradingFeeBps) / 1e4;
    }

    /// @inheritdoc IFeeManager
    function collectFee(
        address user,
        uint256 amount,
        string calldata feeType
    ) external override onlyMarket whenNotPaused {
        // For simplicity, all fees go to treasury in this version
        treasuryBalance += amount;
        emit FeeCollected(user, amount, feeType);
    }

    /// @inheritdoc IFeeManager
    function distributeFees() external override onlyOwner whenNotPaused {
        // For now, just emit event and reset balances (expand as needed)
        emit FeesDistributed(treasuryBalance, insuranceBalance, stakersBalance);
        treasuryBalance = 0;
        insuranceBalance = 0;
        stakersBalance = 0;
    }

    /// @inheritdoc IFeeManager
    function setFeeParameters(
        uint256 _tradingFeeBps,
        uint256 _fundingFeeBps,
        uint256 _liquidationFeeBps
    ) external override onlyOwner {
        tradingFeeBps = _tradingFeeBps;
        fundingFeeBps = _fundingFeeBps;
        liquidationFeeBps = _liquidationFeeBps;
    }

    /// @inheritdoc IFeeManager
    function getFeeParameters()
        external
        view
        override
        returns (uint256, uint256, uint256)
    {
        return (tradingFeeBps, fundingFeeBps, liquidationFeeBps);
    }
}
