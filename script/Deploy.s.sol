// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/HalfLifeOracleAdapter.sol";
import "../src/HalfLifeMarginVault.sol";
import "../src/HalfLifePerpetualPool.sol";
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
        HalfLifeMarginVault vault = new HalfLifeMarginVault();
        console.log("Margin Vault deployed at:", address(vault));

        // Deploy Perpetual Pool
        HalfLifePerpetualPool pool = new HalfLifePerpetualPool(
            address(oracle),
            address(vault)
        );
        console.log("Perpetual Pool deployed at:", address(pool));

        // Deploy Uniswap Hook
        HalfLifeUniswapV4Hook hook = new HalfLifeUniswapV4Hook(address(pool));
        console.log("Uniswap Hook deployed at:", address(hook));

        // Initialize contracts
        vault.setPerpetualPool(address(pool));
        pool.setHook(address(hook));

        // Set initial parameters
        oracle.updateAggregationConfig(2, 5e16, 1 hours, 7e17); // minOracles, maxDeviation, window, threshold
        vault.updateRiskParameters(1 days, 5e16, 8e17); // cooldown, insuranceFundRatio, maxUtilizationRate
        pool.updateRiskParameters(5e16, 1e17, 5e16, 1e17); // maintenanceMargin, liquidationFee, maxDrawdown, fundingRateCap

        vm.stopBroadcast();

        // Log deployment addresses
        console.log("\nDeployment Summary:");
        console.log("-------------------");
        console.log("Oracle Adapter:", address(oracle));
        console.log("Margin Vault:", address(vault));
        console.log("Perpetual Pool:", address(pool));
        console.log("Uniswap Hook:", address(hook));
    }
}
