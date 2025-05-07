// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {OracleAdapter} from "../../src/OracleAdapter.sol";

/// @title MockOracleAdapter
/// @notice Mock implementation of OracleAdapter for testing
contract MockOracleAdapter is OracleAdapter {
    uint256 private _latestIndexValue;
    uint256 private _latestTimestamp;

    /// @notice Initialize the contract
    /// @param _market The market contract address
    function initialize(address _market) external {
        __Ownable_init(msg.sender);
        __Pausable_init();
        market = _market;
    }

    /// @notice Set the latest index value (for testing)
    /// @param value The new index value
    function setLatestIndexValue(uint256 value) external {
        _latestIndexValue = value;
        _latestTimestamp = block.timestamp;
    }

    /// @notice Get the latest index value
    /// @return value The latest index value
    /// @return timestamp The timestamp of the latest value
    function getLatestIndexValue()
        external
        view
        override
        returns (uint256 value, uint256 timestamp)
    {
        return (_latestIndexValue, _latestTimestamp);
    }
}
