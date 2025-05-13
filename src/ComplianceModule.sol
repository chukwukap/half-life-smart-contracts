// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IPerpetualIndexMarket} from "./interfaces/IPerpetualIndexMarket.sol";

/**
 * @title ComplianceModule
 * @notice Handles compliance checks for the perpetual market
 */
contract ComplianceModule {
    IPerpetualIndexMarket public market;
    bool public initialized;

    // Events
    event ComplianceCheckFailed(address indexed trader, string reason);
    event ComplianceModuleInitialized(address indexed market);

    // Modifiers
    modifier onlyMarket() {
        require(msg.sender == address(market), "Only market can call");
        _;
    }

    modifier onlyInitialized() {
        require(initialized, "Not initialized");
        _;
    }

    /**
     * @notice Initialize the compliance module
     * @param _market Address of the perpetual market
     */
    function initialize(address _market) external {
        require(!initialized, "Already initialized");
        require(_market != address(0), "Invalid market address");

        market = IPerpetualIndexMarket(_market);
        initialized = true;

        emit ComplianceModuleInitialized(_market);
    }

    /**
     * @notice Check if a trader is compliant
     * @param trader Address of the trader
     * @return bool True if compliant, false otherwise
     */
    function isCompliant(
        address trader
    ) external view onlyInitialized returns (bool) {
        // Basic compliance check - can be extended with more complex rules
        return trader != address(0);
    }

    /**
     * @notice Check if a position size is compliant
     * @param size Size of the position
     * @return bool True if compliant, false otherwise
     */
    function isPositionSizeCompliant(
        uint256 size
    ) external view onlyInitialized returns (bool) {
        // Basic size check - can be extended with more complex rules
        return size > 0;
    }
}
