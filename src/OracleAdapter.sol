// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IOracleAdapter} from "./interfaces/IOracleAdapter.sol";

/// @title OracleAdapter
/// @notice Receives and stores index values from a trusted oracle for the Half-Life protocol
/// @dev Upgradeable, Ownable, Pausable. Only the trusted oracle can update the index value.
contract OracleAdapter is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    IOracleAdapter
{
    /// @dev Custom errors for gas efficiency
    error NotAuthorized();
    error InvalidInput();

    /// @notice The trusted oracle address
    address private oracle;
    /// @notice The latest index value
    uint256 private latestIndexValue;
    /// @notice The timestamp of the last update
    uint256 private latestTimestamp;

    /// @notice Initializer for upgradeable contract
    /// @param _oracle The address of the trusted oracle
    function initialize(address _oracle) external initializer {
        __Ownable_init();
        __Pausable_init();
        oracle = _oracle;
    }

    /// @inheritdoc IOracleAdapter
    function updateIndexValue(
        uint256 newValue
    ) external override whenNotPaused {
        if (msg.sender != oracle) revert NotAuthorized();
        if (newValue == 0) revert InvalidInput();
        latestIndexValue = newValue;
        latestTimestamp = block.timestamp;
        emit IndexValueUpdated(newValue, block.timestamp);
    }

    /// @inheritdoc IOracleAdapter
    function getLatestIndexValue()
        external
        view
        override
        returns (uint256 value, uint256 timestamp)
    {
        value = latestIndexValue;
        timestamp = latestTimestamp;
    }

    /// @inheritdoc IOracleAdapter
    function setOracle(address _oracle) external override onlyOwner {
        oracle = _oracle;
    }

    /// @inheritdoc IOracleAdapter
    function getOracle() external view override returns (address) {
        return oracle;
    }
}
