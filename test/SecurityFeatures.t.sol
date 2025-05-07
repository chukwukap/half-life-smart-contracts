// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test} from "forge-std/Test.sol";
import {PerpetualIndexMarket} from "../src/PerpetualIndexMarket.sol";
import {MockFundingRateEngine} from "./mocks/MockFundingRateEngine.sol";
import {MockOracleAdapter} from "./mocks/MockOracleAdapter.sol";
import {MockLiquidationEngine} from "./mocks/MockLiquidationEngine.sol";
import {MockFeeManager} from "./mocks/MockFeeManager.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockReentrantContract} from "./mocks/MockReentrantContract.sol";

contract SecurityFeaturesTest is Test {
    PerpetualIndexMarket public market;
    MockFundingRateEngine public fundingRateEngine;
    MockOracleAdapter public oracleAdapter;
    MockLiquidationEngine public liquidationEngine;
    MockFeeManager public feeManager;
    MockERC20 public marginToken;
    MockReentrantContract public reentrantContract;

    address public admin = makeAddr("admin");
    address public operator = makeAddr("operator");
    address public user = makeAddr("user");
    address public attacker = makeAddr("attacker");

    // Events
    event CircuitBreakerTriggered(string reason);
    event EmergencyShutdown(address indexed admin);
    event MarketResumed(address indexed admin);

    function setUp() public {
        vm.startPrank(admin);

        // Deploy contracts
        marginToken = new MockERC20("Margin Token", "MARGIN", 18);
        fundingRateEngine = new MockFundingRateEngine();
        oracleAdapter = new MockOracleAdapter();
        liquidationEngine = new MockLiquidationEngine();
        feeManager = new MockFeeManager();
        market = new PerpetualIndexMarket();
        reentrantContract = new MockReentrantContract(
            address(market),
            address(marginToken)
        );

        // Initialize contracts
        fundingRateEngine.initialize(0.0001e18);
        oracleAdapter.initialize(address(market));
        liquidationEngine.initialize(address(market));
        feeManager.initialize(0.001e18, 0.001e18, 0.001e18);

        market.initialize(
            address(market),
            address(fundingRateEngine),
            address(oracleAdapter),
            address(liquidationEngine),
            address(feeManager),
            address(marginToken),
            1000e18,
            1 hours
        );

        // Setup roles
        market.grantOperator(operator);

        vm.stopPrank();

        // Fund accounts
        marginToken.mint(user, 10000e18);
        marginToken.mint(attacker, 10000e18);
        marginToken.mint(address(reentrantContract), 10000e18);
    }

    function test_AdminRole() public {
        // Only admin should be able to pause
        vm.prank(attacker);
        vm.expectRevert("AccessControl: account 0x... is missing role 0x...");
        market.pause();

        // Admin should be able to pause
        vm.prank(admin);
        market.pause();
        assertTrue(market.paused());

        // Admin should be able to unpause
        vm.prank(admin);
        market.unpause();
        assertFalse(market.paused());
    }

    function test_OperatorRole() public {
        vm.startPrank(admin);
        // Grant operator role
        market.grantOperator(operator);
        assertTrue(market.hasRole(market.OPERATOR_ROLE(), operator));

        // Revoke operator role
        market.revokeOperator(operator);
        assertFalse(market.hasRole(market.OPERATOR_ROLE(), operator));
        vm.stopPrank();
    }

    function test_CircuitBreaker_PriceChange() public {
        // Setup initial price
        vm.prank(address(oracleAdapter));
        oracleAdapter.setLatestIndexValue(1000e18);

        // Trigger circuit breaker with large price change
        vm.prank(address(oracleAdapter));
        oracleAdapter.setLatestIndexValue(1200e18); // 20% increase

        // Try to open position
        vm.startPrank(user);
        marginToken.approve(address(market), 1000e18);
        vm.expectRevert("Price change exceeds threshold");
        market.openPosition(true, 100e18, 2, 1000e18);
        vm.stopPrank();
    }

    function test_CircuitBreaker_FundingRate() public {
        // Set high funding rate
        vm.prank(address(fundingRateEngine));
        fundingRateEngine.setFundingRate(0.2e18); // 20% funding rate

        // Try to open position
        vm.startPrank(user);
        marginToken.approve(address(market), 1000e18);
        vm.expectRevert("Funding rate exceeds threshold");
        market.openPosition(true, 100e18, 2, 1000e18);
        vm.stopPrank();
    }

    function test_PositionSizeLimits() public {
        vm.startPrank(user);
        marginToken.approve(address(market), 1000e18);

        // Try to open position with size exceeding limit
        vm.expectRevert("Position size too large");
        market.openPosition(true, 2000000e18, 2, 1000e18);
        vm.stopPrank();
    }

    function test_LeverageLimits() public {
        vm.startPrank(user);
        marginToken.approve(address(market), 1000e18);

        // Try to open position with leverage exceeding limit
        vm.expectRevert("Leverage too high");
        market.openPosition(true, 100e18, 51, 1000e18);
        vm.stopPrank();
    }

    function test_ReentrancyProtection() public {
        // Test would require a malicious contract attempting reentrancy
        // Implementation depends on specific attack vector being tested
    }

    function test_EmergencyShutdown() public {
        // Admin pauses the market
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit EmergencyShutdown(admin);
        market.pause();

        // Verify operations are blocked
        vm.startPrank(user);
        marginToken.approve(address(market), 1000e18);
        vm.expectRevert("Pausable: paused");
        market.openPosition(true, 100e18, 2, 1000e18);
        vm.stopPrank();

        // Admin resumes the market
        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit MarketResumed(admin);
        market.unpause();

        // Verify operations are allowed
        vm.startPrank(user);
        marginToken.approve(address(market), 1000e18);
        uint256 positionId = market.openPosition(true, 100e18, 2, 1000e18);
        assertGt(positionId, 0);
        vm.stopPrank();
    }

    function test_ReentrancyProtection_Deposit() public {
        vm.startPrank(address(reentrantContract));
        marginToken.approve(address(market), 1000e18);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        reentrantContract.depositAndReenter(1000e18);
        vm.stopPrank();
    }

    function test_ReentrancyProtection_OpenPosition() public {
        vm.startPrank(address(reentrantContract));
        marginToken.approve(address(market), 1000e18);
        vm.expectRevert("ReentrancyGuard: reentrant call");
        reentrantContract.openPositionAndReenter(true, 100e18, 2, 1000e18);
        vm.stopPrank();
    }

    function test_ReentrancyProtection_ClosePosition() public {
        // First open a position
        vm.startPrank(address(reentrantContract));
        marginToken.approve(address(market), 1000e18);
        uint256 positionId = market.openPosition(true, 100e18, 2, 1000e18);
        vm.stopPrank();

        // Then try to reenter during close
        vm.startPrank(address(reentrantContract));
        vm.expectRevert("ReentrancyGuard: reentrant call");
        reentrantContract.closePositionAndReenter(positionId);
        vm.stopPrank();
    }

    function test_ReentrancyProtection_Withdraw() public {
        // First deposit margin
        vm.startPrank(address(reentrantContract));
        marginToken.approve(address(market), 1000e18);
        market.depositMargin(1000e18);
        vm.stopPrank();

        // Then try to reenter during withdraw
        vm.startPrank(address(reentrantContract));
        vm.expectRevert("ReentrancyGuard: reentrant call");
        reentrantContract.withdrawAndReenter(1000e18);
        vm.stopPrank();
    }
}
