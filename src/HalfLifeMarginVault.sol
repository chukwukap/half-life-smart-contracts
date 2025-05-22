// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IHalfLifeMarginVault.sol";

/// @title HalfLifeMarginVault
/// @notice Manages user collateral (e.g., USDC), margin, and liquidations.
contract HalfLifeMarginVault is ReentrancyGuard, Ownable, IHalfLifeMarginVault {
    using Math for uint256;

    struct UserState {
        uint256 margin;
        uint256 lastDepositTime;
        uint256 lastWithdrawTime;
        uint256 totalDeposits;
        uint256 totalWithdrawals;
        uint256 totalFeesPaid;
        bool isBlacklisted;
        mapping(address => uint256) collateralBalances;
    }

    struct CollateralConfig {
        bool isActive;
        uint256 minDeposit;
        uint256 maxDeposit;
        uint256 depositFee;
        uint256 withdrawalFee;
        uint256 priceDecimals;
        uint256 lastUpdateTime;
        uint256 price;
    }

    IERC20 public immutable primaryCollateral;
    address public perpetualPool;

    // Vault state
    uint256 public totalCollateral;
    uint256 public totalFees;
    uint256 public insuranceFund;
    uint256 public utilizationRate;
    uint256 public lastUtilizationUpdate;

    // Risk parameters
    uint256 public withdrawalCooldown = 1 days;
    uint256 public insuranceFundRatio = 0.01e18; // 1% of deposits go to insurance fund
    uint256 public maxUtilizationRate = 0.8e18; // 80% max utilization
    uint256 public dynamicFeeMultiplier = 1e18;

    mapping(address => UserState) public userStates;
    mapping(address => CollateralConfig) public collateralConfigs;
    mapping(address => bool) public whitelistedTokens;

    modifier onlyPerpetualPool() {
        require(msg.sender == perpetualPool, "Not authorized");
        _;
    }

    constructor(address _primaryCollateral) Ownable(msg.sender) {
        primaryCollateral = IERC20(_primaryCollateral);
        whitelistedTokens[_primaryCollateral] = true;

        // Initialize primary collateral config
        collateralConfigs[_primaryCollateral] = CollateralConfig({
            isActive: true,
            minDeposit: 100e18, // 100 USDC
            maxDeposit: 1000000e18, // 1,000,000 USDC
            depositFee: 0.001e18, // 0.1%
            withdrawalFee: 0.001e18, // 0.1%
            priceDecimals: 18,
            lastUpdateTime: block.timestamp,
            price: 1e18
        });
    }

    /// @notice Deposit collateral into the vault
    function deposit(address token, uint256 amount) external nonReentrant {
        require(whitelistedTokens[token], "Token not whitelisted");
        require(!userStates[msg.sender].isBlacklisted, "User blacklisted");

        CollateralConfig storage config = collateralConfigs[token];
        require(config.isActive, "Collateral not active");
        require(amount >= config.minDeposit, "Amount too small");
        require(amount <= config.maxDeposit, "Amount too large");

        // Calculate fees with dynamic multiplier
        uint256 depositFeeAmount = (amount * config.depositFee * dynamicFeeMultiplier) / 1e36;
        uint256 insuranceFundAmount = (amount * insuranceFundRatio) / 1e18;
        uint256 netAmount = amount - depositFeeAmount - insuranceFundAmount;

        // Update user state
        UserState storage user = userStates[msg.sender];
        user.margin += netAmount;
        user.lastDepositTime = block.timestamp;
        user.totalDeposits += amount;
        user.totalFeesPaid += depositFeeAmount;
        user.collateralBalances[token] += amount;

        // Update vault state
        totalCollateral += netAmount;
        totalFees += depositFeeAmount;
        insuranceFund += insuranceFundAmount;

        // Update utilization rate
        _updateUtilizationRate();

        // Transfer tokens
        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "Transfer failed");

        emit Deposit(msg.sender, token, amount, depositFeeAmount);
    }

    /// @notice Withdraw collateral from the vault
    function withdraw(address token, uint256 amount) external nonReentrant {
        UserState storage user = userStates[msg.sender];
        require(user.margin >= amount, "Insufficient margin");
        require(block.timestamp >= user.lastWithdrawTime + withdrawalCooldown, "Withdrawal cooldown active");
        require(!user.isBlacklisted, "User blacklisted");
        require(user.collateralBalances[token] >= amount, "Insufficient collateral");

        CollateralConfig storage config = collateralConfigs[token];
        require(config.isActive, "Collateral not active");

        // Calculate fees with dynamic multiplier
        uint256 withdrawalFeeAmount = (amount * config.withdrawalFee * dynamicFeeMultiplier) / 1e36;
        uint256 netAmount = amount - withdrawalFeeAmount;

        // Update user state
        user.margin -= amount;
        user.lastWithdrawTime = block.timestamp;
        user.totalWithdrawals += amount;
        user.totalFeesPaid += withdrawalFeeAmount;
        user.collateralBalances[token] -= amount;

        // Update vault state
        totalCollateral -= amount;
        totalFees += withdrawalFeeAmount;

        // Update utilization rate
        _updateUtilizationRate();

        // Transfer tokens
        require(IERC20(token).transfer(msg.sender, netAmount), "Transfer failed");

        emit Withdraw(msg.sender, token, amount, withdrawalFeeAmount);
    }

    /// @notice Only callable by the PerpetualPool for liquidations
    function slash(address user, uint256 amount) external onlyPerpetualPool {
        UserState storage userState = userStates[user];
        require(userState.margin >= amount, "Insufficient margin");

        userState.margin -= amount;
        totalCollateral -= amount;

        // Add slashed amount to insurance fund
        insuranceFund += amount;

        // Update utilization rate
        _updateUtilizationRate();

        emit Slashed(user, amount);
    }

    /// @notice Transfer funds to another address (e.g., for liquidator rewards)
    function transfer(address to, uint256 amount) external onlyPerpetualPool {
        require(amount <= totalCollateral, "Insufficient funds");
        totalCollateral -= amount;
        require(primaryCollateral.transfer(to, amount), "Transfer failed");
    }

    /// @notice Get user's margin balance
    function margin(address user) external view returns (uint256) {
        return userStates[user].margin;
    }

    /// @notice Set the perpetual pool address
    function setPerpetualPool(address _perpetualPool) external onlyOwner {
        require(_perpetualPool != address(0), "Invalid address");
        perpetualPool = _perpetualPool;
    }

    /// @notice Blacklist a user
    function blacklistUser(address user) external onlyOwner {
        require(!userStates[user].isBlacklisted, "Already blacklisted");
        userStates[user].isBlacklisted = true;
        emit UserBlacklisted(user);
    }

    /// @notice Unblacklist a user
    function unblacklistUser(address user) external onlyOwner {
        require(userStates[user].isBlacklisted, "Not blacklisted");
        userStates[user].isBlacklisted = false;
        emit UserUnblacklisted(user);
    }

    /// @notice Whitelist a token
    function whitelistToken(address token) external onlyOwner {
        require(!whitelistedTokens[token], "Already whitelisted");
        whitelistedTokens[token] = true;
        emit TokenWhitelisted(token);
    }

    /// @notice Unwhitelist a token
    function unwhitelistToken(address token) external onlyOwner {
        require(whitelistedTokens[token], "Not whitelisted");
        whitelistedTokens[token] = false;
        emit TokenUnwhitelisted(token);
    }

    /// @notice Update collateral configuration
    function updateCollateralConfig(
        address token,
        uint256 _minDeposit,
        uint256 _maxDeposit,
        uint256 _depositFee,
        uint256 _withdrawalFee,
        uint256 _priceDecimals,
        uint256 _price
    ) external onlyOwner {
        require(whitelistedTokens[token], "Token not whitelisted");
        require(_minDeposit > 0, "Invalid min deposit");
        require(_maxDeposit > _minDeposit, "Invalid max deposit");
        require(_depositFee <= 0.01e18, "Deposit fee too high");
        require(_withdrawalFee <= 0.01e18, "Withdrawal fee too high");
        require(_priceDecimals <= 18, "Invalid decimals");
        require(_price > 0, "Invalid price");

        CollateralConfig storage config = collateralConfigs[token];
        config.minDeposit = _minDeposit;
        config.maxDeposit = _maxDeposit;
        config.depositFee = _depositFee;
        config.withdrawalFee = _withdrawalFee;
        config.priceDecimals = _priceDecimals;
        config.lastUpdateTime = block.timestamp;
        config.price = _price;

        emit CollateralConfigUpdated(token, _minDeposit, _maxDeposit, _depositFee, _withdrawalFee);
    }

    /// @notice Update risk parameters
    function updateRiskParameters(
        uint256 _withdrawalCooldown,
        uint256 _insuranceFundRatio,
        uint256 _maxUtilizationRate
    ) external onlyOwner {
        require(_withdrawalCooldown <= 7 days, "Cooldown too long");
        require(_insuranceFundRatio <= 0.05e18, "Insurance ratio too high");
        require(_maxUtilizationRate <= 0.9e18, "Utilization rate too high");

        withdrawalCooldown = _withdrawalCooldown;
        insuranceFundRatio = _insuranceFundRatio;
        maxUtilizationRate = _maxUtilizationRate;
    }

    /// @notice Update insurance fund
    function updateInsuranceFund(uint256 newAmount) external onlyOwner {
        require(newAmount <= totalCollateral, "Amount too large");
        insuranceFund = newAmount;
        emit InsuranceFundUpdated(newAmount);
    }

    /// @notice Update dynamic fee multiplier
    function updateDynamicFeeMultiplier(uint256 _multiplier) external onlyOwner {
        require(_multiplier <= 2e18, "Multiplier too high");
        dynamicFeeMultiplier = _multiplier;
        emit DynamicFeeUpdated(_multiplier);
    }

    /// @notice Emergency withdraw from insurance fund
    function emergencyWithdraw(uint256 amount) external onlyOwner {
        require(amount <= insuranceFund, "Amount too large");
        insuranceFund -= amount;
        require(primaryCollateral.transfer(owner(), amount), "Transfer failed");
    }

    /// @dev Update utilization rate
    function _updateUtilizationRate() internal {
        if (totalCollateral == 0) {
            utilizationRate = 0;
        } else {
            utilizationRate = (totalFees * 1e18) / totalCollateral;
        }
        lastUtilizationUpdate = block.timestamp;
        emit UtilizationRateUpdated(utilizationRate);
    }
}
