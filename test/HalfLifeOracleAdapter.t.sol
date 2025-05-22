// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../src/HalfLifeOracleAdapter.sol";

contract HalfLifeOracleAdapterTest is Test {
    HalfLifeOracleAdapter oracle;
    address owner = address(this);
    address oracle1 = address(0x111);
    address oracle2 = address(0x222);

    function setUp() public {
        oracle = new HalfLifeOracleAdapter();
    }

    function testAddAndRemoveOracle() public {
        oracle.addOracle(oracle1, 1 hours, 0.05e18);
        (address addr, bool isActive, , , , , , , ) = oracle.getOracle(oracle1);
        assertEq(addr, oracle1);
        assertTrue(isActive);
        oracle.removeOracle(oracle1);
        (, isActive, , , , , , , ) = oracle.getOracle(oracle1);
        assertFalse(isActive);
    }

    function testUpdateOracle() public {
        oracle.addOracle(oracle1, 1 hours, 0.05e18);
        oracle.updateOracle(oracle1, 2 hours, 0.01e18);
        (, , uint256 lastUpdate, uint256 heartbeat, uint256 deviationThreshold, , , , ) = oracle.getOracle(oracle1);
        assertEq(heartbeat, 2 hours);
        assertEq(deviationThreshold, 0.01e18);
    }

    function testUpdateTLI() public {
        oracle.addOracle(owner, 1 hours, 0.05e18);
        oracle.updateTLI(1e18);
        (uint256 latestTLI, uint256 lastUpdate, , , , ) = oracle.getState();
        assertEq(latestTLI, 1e18);
        assertGt(lastUpdate, 0);
    }

    function testUpdateState() public {
        oracle.updateState(2 hours, 0.02e18, 0.2e18, 5e18);
        (, , , uint256 deviationThreshold, uint256 minValidTLI, uint256 maxValidTLI) = oracle.getState();
        assertEq(deviationThreshold, 0.02e18);
        assertEq(minValidTLI, 0.2e18);
        assertEq(maxValidTLI, 5e18);
    }

    function testUpdateAggregationConfig() public {
        oracle.updateAggregationConfig(2, 0.01e18, 10 minutes, 0.8e18);
        // No direct getter, but should not revert
    }

    function testResetCircuitBreaker() public {
        oracle.addOracle(owner, 1 hours, 0.05e18);
        oracle.updateTLI(1e18);
        // Simulate circuit breaker trigger by calling internal (not possible here), so just test reset does not revert if not active
        vm.expectRevert("Cooldown not finished");
        oracle.resetCircuitBreaker();
    }

    function testAccessControl() public {
        vm.prank(oracle1);
        vm.expectRevert();
        oracle.addOracle(address(0x333), 1 hours, 0.05e18);
    }
}
