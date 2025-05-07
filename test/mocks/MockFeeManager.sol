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
        super.initialize(address(this), _tradingFeeRate, _liquidationFeeRate);
    }
}
