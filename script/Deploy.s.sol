// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Script.sol";
import "../src/HalfLifeOracleAdapter.sol";
import "../src/HalfLifeMarginVault.sol";
import "../src/HalfLifeUniswapV4Hook.sol";

/// @title DeployScript
/// @notice Deploys all core Half-Life contracts and prints their addresses
contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy Oracle Adapter
        HalfLifeOracleAdapter oracle = new HalfLifeOracleAdapter();
        console.log("Oracle Adapter deployed at:", address(oracle));

        // Deploy Margin Vault
        // TODO: Replace address(0x1234567890123456789012345678901234567890) with actual collateral token address
        HalfLifeMarginVault vault = new HalfLifeMarginVault(address(0x1234567890123456789012345678901234567890));
        console.log("Margin Vault deployed at:", address(vault));

        // Deploy Uniswap Hook
        HalfLifeUniswapV4Hook hook = new HalfLifeUniswapV4Hook(address(vault), address(oracle));
        console.log("Uniswap Hook deployed at:", address(hook));

        // Initialize contracts
        vault.setPerpetualPool(address(vault));
        hook.setVault(address(vault));

        // Set initial parameters
        oracle.updateAggregationConfig(2, 5e16, 1 hours, 7e17); // minOracles, maxDeviation, window, threshold
        vault.updateRiskParameters(1 days, 5e16, 8e17); // cooldown, insuranceFundRatio, maxUtilizationRate
        hook.updateRiskParameters(5e16, 1e17, 5e16, 1e17); // maintenanceMargin, liquidationFee, maxDrawdown, fundingRateCap

        vm.stopBroadcast();

        // Log deployment addresses
        console.log("\nDeployment Summary:");
        console.log("-------------------");
        console.log("Oracle Adapter:", address(oracle));
        console.log("Margin Vault:", address(vault));
        console.log("Uniswap Hook:", address(hook));
    }
}
