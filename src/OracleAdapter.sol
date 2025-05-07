// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// NOTE: For documentation, use explicit versioned imports in deployment scripts and documentation.
// import {OwnableUpgradeable} from "@openzeppelin/[email protected]/access/OwnableUpgradeable.sol";
// import {PausableUpgradeable} from "@openzeppelin/[email protected]/security/PausableUpgradeable.sol";
// import {Initializable} from "@openzeppelin/[email protected]/proxy/utils/Initializable.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable@5.0.1/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable@5.0.1/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable@5.0.1/security/PausableUpgradeable.sol";
import {IOracleAdapter} from "./interfaces/IOracleAdapter.sol";

/// @title OracleAdapter
/// @author Half-Life Protocol
/// @notice Adapter for pushing off-chain index values on-chain
/// @dev Handles index value storage and access control for updates
contract OracleAdapter is
    IOracleAdapter,
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable
{
    // --- Events ---
    event IndexValuePushed(uint256 newValue, uint256 timestamp);

    // --- Errors ---
    error NotAuthorized();
    error InvalidInput();

    // --- State Variables ---
    uint256 public latestIndexValue;
    uint256 public latestTimestamp;
    address public updater;

    /// @notice Initializer for upgradeable contract
    /// @param _updater Address authorized to push index values
    function initialize(address _updater) external initializer {
        __Ownable_init();
        __Pausable_init();
        updater = _updater;
    }

    /// @notice Push a new index value (only updater)
    /// @param newValue The new index value
    function pushIndexValue(uint256 newValue) external whenNotPaused {
        if (msg.sender != updater) revert NotAuthorized();
        if (newValue == 0) revert InvalidInput();
        latestIndexValue = newValue;
        latestTimestamp = block.timestamp;
        emit IndexValuePushed(newValue, block.timestamp);
    }

    /// @notice Get the latest index value and timestamp
    /// @return value The latest index value
    /// @return timestamp The timestamp of the latest value
    function getLatestIndexValue()
        external
        view
        override
        returns (uint256 value, uint256 timestamp)
    {
        value = latestIndexValue;
        timestamp = latestTimestamp;
    }
}
