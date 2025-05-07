// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {FeeManager} from "../../src/FeeManager.sol";

/// @title MockFeeManager
/// @notice Mock implementation of FeeManager for testing
contract MockFeeManager is FeeManager {
    /// @notice Initialize the contract
    /// @param _tradingFeeRate Trading fee rate in basis points
    /// @param _fundingFeeRate Funding fee rate in basis points
    /// @param _liquidationFeeRate Liquidation fee rate in basis points
    function initialize(
        uint256 _tradingFeeRate,
        uint256 _fundingFeeRate,
        uint256 _liquidationFeeRate
    ) external {
        __Ownable_init(msg.sender);
        __Pausable_init();
        feeRecipient = address(this);
        tradingFeeRate = _tradingFeeRate;
        liquidationFeeRate = _liquidationFeeRate;
    }

    /// @notice Distribute collected fees to treasury, insurance, and stakers
    function distributeFees() external override {
        // Mock implementation does nothing
    }

    /// @notice Set fee parameters
    /// @param tradingFeeBps Trading fee in basis points
    /// @param fundingFeeBps Funding fee in basis points
    /// @param liquidationFeeBps Liquidation fee in basis points
    function setFeeParameters(
        uint256 tradingFeeBps,
        uint256 fundingFeeBps,
        uint256 liquidationFeeBps
    ) external override {
        tradingFeeRate = tradingFeeBps;
        liquidationFeeRate = liquidationFeeBps;
    }

    /// @notice Get current fee parameters
    /// @return tradingFeeBps Trading fee in basis points
    /// @return fundingFeeBps Funding fee in basis points
    /// @return liquidationFeeBps Liquidation fee in basis points
    function getFeeParameters()
        external
        view
        override
        returns (
            uint256 tradingFeeBps,
            uint256 fundingFeeBps,
            uint256 liquidationFeeBps
        )
    {
        return (tradingFeeRate, 0, liquidationFeeRate);
    }
}
