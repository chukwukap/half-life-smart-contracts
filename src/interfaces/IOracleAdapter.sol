// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

/// @title IOracleAdapter
/// @notice Interface for the OracleAdapter contract in Half-Life protocol
interface IOracleAdapter {
    /// @notice Emitted when the index value is updated
    event IndexValueUpdated(uint256 newValue, uint256 timestamp);

    /// @notice Update the index value (only callable by trusted oracle)
    /// @param newValue The new index value
    function updateIndexValue(uint256 newValue) external;

    /// @notice Get the latest index value and timestamp
    /// @return value The latest index value
    /// @return timestamp The timestamp of the last update
    function getLatestIndexValue()
        external
        view
        returns (uint256 value, uint256 timestamp);

    /// @notice Set the trusted oracle address (onlyOwner)
    /// @param oracle The address of the trusted oracle
    function setOracle(address oracle) external;

    /// @notice Get the trusted oracle address
    /// @return oracle The address of the trusted oracle
    function getOracle() external view returns (address oracle);
}
