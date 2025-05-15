// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// NOTE: For documentation, use explicit versioned imports in deployment scripts and documentation.
// import {OwnableUpgradeable} from "@openzeppelin/[email protected]/access/OwnableUpgradeable.sol";
// import {PausableUpgradeable} from "@openzeppelin/[email protected]/security/PausableUpgradeable.sol";
// import {Initializable} from "@openzeppelin/[email protected]/proxy/utils/Initializable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IOracleAdapter} from "./interfaces/IOracleAdapter.sol";

/// @title OracleAdapter
/// @author Half-Life Protocol
/// @notice Handles index value updates and retrieval for the perpetual index market
/// @dev Upgradeable and pausable contract
contract OracleAdapter is
    IOracleAdapter,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    // --- Events ---
    event IndexValueUpdated(
        uint256 newValue,
        uint256 timestamp,
        address updater
    );
    event OracleUpdated(address oracle);

    // --- Errors ---
    error NotAuthorized();
    error InvalidInput();

    // --- State Variables ---
    address public updater;
    uint256 public lastIndexValue;
    uint256 public lastUpdateTimestamp;

    /// @notice Initializer for upgradeable contract
    /// @param _updater Address authorized to push index values
    function initialize(address _updater) external virtual initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        updater = _updater;
    }

    /// @notice Update the index value (onlyUpdater)
    /// @param newValue The new index value
    function updateIndexValue(
        uint256 newValue
    ) external override whenNotPaused {
        if (msg.sender != updater) revert NotAuthorized();
        if (newValue == 0) revert InvalidInput();
        lastIndexValue = newValue;
        lastUpdateTimestamp = block.timestamp;
        emit IndexValueUpdated(newValue, block.timestamp, msg.sender);
    }

    /// @notice Get the latest index value
    /// @return value The current index value
    /// @return timestamp The timestamp of the last update
    function getLatestIndexValue()
        external
        view
        virtual
        override
        returns (uint256 value, uint256 timestamp)
    {
        return (lastIndexValue, lastUpdateTimestamp);
    }

    /// @notice Get the current oracle address
    /// @return oracle The current oracle address
    function getOracle() external view override returns (address oracle) {
        return updater;
    }

    /// @notice Set the oracle address (onlyOwner)
    /// @param oracle The new oracle address
    function setOracle(address oracle) external override onlyOwner {
        if (oracle == address(0)) revert InvalidInput();
        updater = oracle;
        emit OracleUpdated(oracle);
    }
}
