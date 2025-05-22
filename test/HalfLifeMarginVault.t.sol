// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "forge-std/Test.sol";
import "../src/HalfLifeMarginVault.sol";
import "../src/interfaces/IHalfLifeMarginVault.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1_000_000 ether);
    }
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract HalfLifeMarginVaultTest is Test {
    HalfLifeMarginVault vault;
    MockERC20 token;
    address user = address(0x1234);
    address perpPool = address(0xBEEF);

    function setUp() public {
        token = new MockERC20();
        vault = new HalfLifeMarginVault(address(token));
        token.approve(address(vault), type(uint256).max);
        token.mint(user, 1000 ether);
    }

    function testDepositAndWithdraw() public {
        vm.startPrank(user);
        token.approve(address(vault), 1000 ether);
        vault.deposit(address(token), 1000 ether);
        assertEq(
            vault.margin(user),
            1000 ether - ((1000 ether * vault.insuranceFundRatio()) / 1e18) - ((1000 ether * 0.001e18) / 1e18)
        );
        vm.warp(block.timestamp + vault.withdrawalCooldown());
        vault.withdraw(address(token), 100 ether);
        vm.stopPrank();
    }

    function testBlacklistAndWhitelist() public {
        vault.blacklistUser(user);
        assertTrue(vault.isBlacklisted(user));
        vault.unblacklistUser(user);
        assertFalse(vault.isBlacklisted(user));
        vault.whitelistToken(address(0xDEAD));
        assertTrue(vault.whitelistedTokens(address(0xDEAD)));
        vault.unwhitelistToken(address(0xDEAD));
        assertFalse(vault.whitelistedTokens(address(0xDEAD)));
    }

    function testSetPerpetualPool() public {
        vault.setPerpetualPool(perpPool);
        assertEq(vault.perpetualPool(), perpPool);
    }

    function testUpdateCollateralConfig() public {
        vault.updateCollateralConfig(address(token), 10 ether, 10000 ether, 0.001e18, 0.001e18);
        (bool isActive, uint256 minDeposit, , uint256 depositFee, uint256 withdrawalFee, , , ) = vault
            .getCollateralConfig(address(token));
        assertTrue(isActive);
        assertEq(minDeposit, 10 ether);
        assertEq(depositFee, 0.001e18);
        assertEq(withdrawalFee, 0.001e18);
    }

    function testUpdateRiskParameters() public {
        vault.updateRiskParameters(2 days, 0.02e18, 0.7e18);
        assertEq(vault.withdrawalCooldown(), 2 days);
        assertEq(vault.insuranceFundRatio(), 0.02e18);
        assertEq(vault.maxUtilizationRate(), 0.7e18);
    }

    function testSlashAndTransfer() public {
        vault.setPerpetualPool(address(this));
        vm.startPrank(user);
        token.approve(address(vault), 100 ether);
        vault.deposit(address(token), 100 ether);
        vm.stopPrank();
        vault.slash(user, 10 ether);
        vault.transfer(address(0xBEEF), 5 ether);
    }
}
