// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {LiquidationEngine} from "../../src/LiquidationEngine.sol";

/// @title MockLiquidationEngine
/// @notice Mock implementation of LiquidationEngine for testing
contract MockLiquidationEngine is LiquidationEngine {
    /// @notice Initialize the contract
    /// @param _positionManager The PositionManager contract address
    function initialize(address _positionManager) external {
        super.initialize(_positionManager);
        liquidationPenalty = 500; // 5% penalty
    }
}
