// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Test, console2} from "forge-std/Test.sol";
import {PerpetualIndexMarket} from "../src/PerpetualIndexMarket.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {FundingRateEngine} from "../src/FundingRateEngine.sol";
import {OracleAdapter} from "../src/OracleAdapter.sol";
import {LiquidationEngine} from "../src/LiquidationEngine.sol";
import {FeeManager} from "../src/FeeManager.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @title PerpetualIndexMarketTest
/// @notice Test suite for PerpetualIndexMarket contract
/// @dev Uses Forge's testing framework
contract PerpetualIndexMarketTest is Test {
    // --- Events ---
    event PositionOpened(
        address indexed user,
        uint256 positionId,
        bool isLong,
        uint256 amount,
        uint256 leverage
    );
    event PositionClosed(address indexed user, uint256 positionId, int256 pnl);
    event MarginDeposited(address indexed user, uint256 amount);
    event MarginWithdrawn(address indexed user, uint256 amount);

    // --- State Variables ---
    PerpetualIndexMarket public market;
    PositionManager public positionManager;
    FundingRateEngine public fundingRateEngine;
    OracleAdapter public oracleAdapter;
    LiquidationEngine public liquidationEngine;
    FeeManager public feeManager;
    MockERC20 public marginToken;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public owner = makeAddr("owner");

    // --- Constants ---
    uint256 public constant INITIAL_MARGIN_REQUIREMENT = 1000e18;
    uint256 public constant FUNDING_INTERVAL = 1 hours;
    uint256 public constant INITIAL_INDEX_VALUE = 1000e18;

    // --- Setup ---
    function setUp() public {
        // Deploy mock token
        marginToken = new MockERC20("Margin Token", "MARGIN", 18);

        // Deploy core contracts
        positionManager = new PositionManager();
        fundingRateEngine = new FundingRateEngine();
        oracleAdapter = new OracleAdapter();
        liquidationEngine = new LiquidationEngine();
        feeManager = new FeeManager();

        // Deploy main market contract
        market = new PerpetualIndexMarket();

        // Initialize contracts
        vm.startPrank(owner);
        positionManager.initialize();
        fundingRateEngine.initialize();
        oracleAdapter.initialize();
        liquidationEngine.initialize(positionManager);
        feeManager.initialize();

        market.initialize(
            address(positionManager),
            address(fundingRateEngine),
            address(oracleAdapter),
            address(liquidationEngine),
            address(feeManager),
            address(marginToken),
            INITIAL_MARGIN_REQUIREMENT,
            FUNDING_INTERVAL
        );
        vm.stopPrank();

        // Setup test accounts with margin tokens
        marginToken.mint(alice, 10000e18);
        marginToken.mint(bob, 10000e18);
        marginToken.mint(charlie, 10000e18);

        // Set initial index value
        vm.prank(address(oracleAdapter));
        market.updateIndexValue(INITIAL_INDEX_VALUE);
    }

    // --- Helper Functions ---
    function _depositMargin(address user, uint256 amount) internal {
        vm.startPrank(user);
        marginToken.approve(address(market), amount);
        market.depositMargin(amount);
        vm.stopPrank();
    }

    function _openPosition(
        address user,
        bool isLong,
        uint256 amount,
        uint256 leverage,
        uint256 margin
    ) internal returns (uint256) {
        vm.startPrank(user);
        marginToken.approve(address(market), margin);
        uint256 positionId = market.openPosition(
            isLong,
            amount,
            leverage,
            margin
        );
        vm.stopPrank();
        return positionId;
    }

    // --- Test Cases ---
    function test_Initialization() public {
        assertEq(address(market.positionManager()), address(positionManager));
        assertEq(
            address(market.fundingRateEngine()),
            address(fundingRateEngine)
        );
        assertEq(address(market.oracleAdapter()), address(oracleAdapter));
        assertEq(
            address(market.liquidationEngine()),
            address(liquidationEngine)
        );
        assertEq(address(market.feeManager()), address(feeManager));
        assertEq(address(market.marginToken()), address(marginToken));
        assertEq(market.marginRequirement(), INITIAL_MARGIN_REQUIREMENT);
        assertEq(market.fundingInterval(), FUNDING_INTERVAL);
    }

    function test_DepositMargin() public {
        uint256 depositAmount = 1000e18;

        vm.startPrank(alice);
        marginToken.approve(address(market), depositAmount);

        vm.expectEmit(true, false, false, true);
        emit MarginDeposited(alice, depositAmount);

        market.depositMargin(depositAmount);
        vm.stopPrank();

        assertEq(market.userMarginBalances(alice), depositAmount);
    }

    function test_OpenPosition() public {
        uint256 margin = 1000e18;
        uint256 amount = 100e18;
        uint256 leverage = 2;

        _depositMargin(alice, margin);

        vm.startPrank(alice);
        marginToken.approve(address(market), margin);

        vm.expectEmit(true, true, false, true);
        emit PositionOpened(alice, 1, true, amount, leverage);

        uint256 positionId = market.openPosition(
            true,
            amount,
            leverage,
            margin
        );
        vm.stopPrank();

        assertEq(positionId, 1);
    }

    function testFail_OpenPositionInsufficientMargin() public {
        uint256 margin = 100e18; // Less than required
        uint256 amount = 100e18;
        uint256 leverage = 2;

        _depositMargin(alice, margin);

        vm.startPrank(alice);
        marginToken.approve(address(market), margin);
        market.openPosition(true, amount, leverage, margin);
        vm.stopPrank();
    }

    function test_ClosePosition() public {
        uint256 margin = 1000e18;
        uint256 amount = 100e18;
        uint256 leverage = 2;

        _depositMargin(alice, margin);
        uint256 positionId = _openPosition(
            alice,
            true,
            amount,
            leverage,
            margin
        );

        // Update index value to create some PnL
        vm.prank(address(oracleAdapter));
        market.updateIndexValue(INITIAL_INDEX_VALUE + 100e18);

        vm.startPrank(alice);
        vm.expectEmit(true, true, false, true);
        emit PositionClosed(alice, positionId, 2000e18); // Expected PnL
        market.closePosition(positionId);
        vm.stopPrank();
    }

    function testFail_ClosePositionNotOwner() public {
        uint256 margin = 1000e18;
        uint256 amount = 100e18;
        uint256 leverage = 2;

        _depositMargin(alice, margin);
        uint256 positionId = _openPosition(
            alice,
            true,
            amount,
            leverage,
            margin
        );

        vm.startPrank(bob);
        market.closePosition(positionId);
        vm.stopPrank();
    }

    function test_WithdrawMargin() public {
        uint256 depositAmount = 1000e18;
        _depositMargin(alice, depositAmount);

        vm.startPrank(alice);
        vm.expectEmit(true, false, false, true);
        emit MarginWithdrawn(alice, depositAmount);
        market.withdrawMargin(depositAmount);
        vm.stopPrank();

        assertEq(market.userMarginBalances(alice), 0);
    }

    function testFail_WithdrawMarginInsufficientBalance() public {
        uint256 depositAmount = 1000e18;
        _depositMargin(alice, depositAmount);

        vm.startPrank(alice);
        market.withdrawMargin(depositAmount + 1);
        vm.stopPrank();
    }

    function testFail_WithdrawMarginWithOpenPosition() public {
        uint256 margin = 1000e18;
        uint256 amount = 100e18;
        uint256 leverage = 2;

        _depositMargin(alice, margin);
        _openPosition(alice, true, amount, leverage, margin);

        vm.startPrank(alice);
        market.withdrawMargin(margin);
        vm.stopPrank();
    }
}
