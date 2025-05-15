// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {PerpetualIndexMarket} from "../src/PerpetualIndexMarket.sol";
import {OracleAdapter} from "../src/OracleAdapter.sol";
import {FundingRateEngine} from "../src/FundingRateEngine.sol";
import {LiquidationEngine} from "../src/LiquidationEngine.sol";
import {FeeManager} from "../src/FeeManager.sol";

/// @title DeployScript
/// @notice Professional deployment script for Half-Life protocol core contracts (2025)
contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy protocol modules
        OracleAdapter oracleAdapter = new OracleAdapter();
        FundingRateEngine fundingRateEngine = new FundingRateEngine();
        LiquidationEngine liquidationEngine = new LiquidationEngine();
        FeeManager feeManager = new FeeManager();

        // Deploy main market contract
        PerpetualIndexMarket market = new PerpetualIndexMarket();

        // Initialize protocol modules
        oracleAdapter.initialize(address(market));
        fundingRateEngine.initialize();
        liquidationEngine.initialize(address(market));
        feeManager.initialize(0.001e18, 0.001e18, 0.001e18); // 0.1% fees

        // Initialize market (compliance module address removed)
        market.initialize(
            address(market),
            address(fundingRateEngine),
            address(oracleAdapter),
            address(liquidationEngine),
            address(feeManager),
            1000e18, // Initial margin requirement
            1 hours // Funding interval
        );

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("Deployed contracts:");
        console.log("OracleAdapter:", address(oracleAdapter));
        console.log("FundingRateEngine:", address(fundingRateEngine));
        console.log("LiquidationEngine:", address(liquidationEngine));
        console.log("FeeManager:", address(feeManager));
        console.log("PerpetualIndexMarket:", address(market));
    }
}
