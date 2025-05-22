// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../src/HalfLifeUniswapV4Hook.sol";
import "../src/interfaces/IHalfLifeMarginVault.sol";
import "../src/interfaces/IHalfLifeOracleAdapter.sol";
import { Currency } from "../lib/v4-core/src/types/Currency.sol";

// Mock Vault
contract MockVault is IHalfLifeMarginVault {
    mapping(address => uint256) public override margin;
    function totalCollateral() external pure override returns (uint256) {
        return 0;
    }
    function insuranceFund() external pure override returns (uint256) {
        return 0;
    }
    function utilizationRate() external pure override returns (uint256) {
        return 0;
    }
    function withdrawalCooldown() external pure override returns (uint256) {
        return 0;
    }
    function insuranceFundRatio() external pure override returns (uint256) {
        return 0;
    }
    function maxUtilizationRate() external pure override returns (uint256) {
        return 0;
    }
    function isBlacklisted(address) external pure override returns (bool) {
        return false;
    }
    function deposit(address, uint256) external override {}
    function withdraw(address, uint256) external override {}
    function slash(address, uint256) external override {}
    function blacklistUser(address) external override {}
    function whitelistToken(address) external override {}
    function setPerpetualPool(address) external override {}
    function updateRiskParameters(uint256, uint256, uint256) external override {}
    function updateCollateralConfig(address, uint256, uint256, uint256, uint256) external override {}
    function transfer(address, uint256) external override {}
    function getCollateralConfig(
        address
    ) external pure override returns (bool, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        return (true, 0, 0, 0, 0, 0, 0, 0);
    }
    function setMargin(address user, uint256 amount) external {
        margin[user] = amount;
    }
}

// Mock Oracle
contract MockOracle is IHalfLifeOracleAdapter {
    uint256 public tli = 1e18;
    uint256 public lastUpdateTime = block.timestamp;
    function latestTLI() external view override returns (uint256) {
        return tli;
    }
    function lastUpdate() external view override returns (uint256) {
        return lastUpdateTime;
    }
    function circuitBreaker() external pure override returns (bool) {
        return false;
    }
    function oracles(
        address
    ) external pure override returns (address, bool, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        return (address(0), true, 0, 0, 0, 0, 0, 0, 0);
    }
    function updateTLI(uint256 _tli) external override {
        tli = _tli;
        lastUpdateTime = block.timestamp;
    }
    function addOracle(address, uint256, uint256) external override {}
    function removeOracle(address) external override {}
    function updateOracle(address, uint256, uint256) external override {}
    function updateAggregationConfig(uint256, uint256, uint256, uint256) external override {}
    function getState() external view override returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        return (tli, lastUpdateTime, 1 hours, 0.1e18, 0.1e18, 10e18);
    }
    function getOracle(
        address
    ) external pure override returns (address, bool, uint256, uint256, uint256, uint256, uint256, uint256, uint256) {
        return (address(0), true, 0, 0, 0, 0, 0, 0, 0);
    }
}

contract HalfLifeUniswapV4HookTest is Test {
    HalfLifeUniswapV4Hook hook;
    MockVault vault;
    MockOracle oracle;
    address user = address(0x1234);

    function setUp() public {
        vault = new MockVault();
        oracle = new MockOracle();
        hook = new HalfLifeUniswapV4Hook(address(vault), address(oracle));
        vault.setMargin(user, 1000 ether);
    }

    function testMarginCheck() public {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0)),
            fee: 0,
            tickSpacing: 0,
            hooks: IHooks(address(0))
        });
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 0,
            sqrtPriceLimitX96: 0
        });
        vm.expectRevert("Cooldown active");
        hook.beforeSwap(user, key, params, "");
    }

    // Add more tests for PnL, funding, liquidation, cooldown, leverage, etc.
}
