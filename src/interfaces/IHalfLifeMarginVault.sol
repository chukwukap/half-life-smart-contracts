// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IHalfLifeMarginVault {
    // View functions
    function margin(address user) external view returns (uint256);
    function totalCollateral() external view returns (uint256);
    function insuranceFund() external view returns (uint256);
    function utilizationRate() external view returns (uint256);
    function withdrawalCooldown() external view returns (uint256);
    function insuranceFundRatio() external view returns (uint256);
    function maxUtilizationRate() external view returns (uint256);
    function isBlacklisted(address user) external view returns (bool);
    function collateralConfigs(
        address token
    )
        external
        view
        returns (uint256 minDeposit, uint256 maxDeposit, uint256 depositFee, uint256 withdrawalFee, bool isWhitelisted);

    // State changing functions
    function deposit(address token, uint256 amount) external;
    function withdraw(address token, uint256 amount) external;
    function slash(address user, uint256 amount) external;
    function blacklistUser(address user) external;
    function whitelistToken(address token) external;
    function setPerpetualPool(address _perpetualPool) external;
    function updateRiskParameters(
        uint256 _withdrawalCooldown,
        uint256 _insuranceFundRatio,
        uint256 _maxUtilizationRate
    ) external;
    function updateCollateralConfig(
        address token,
        uint256 _minDeposit,
        uint256 _maxDeposit,
        uint256 _depositFee,
        uint256 _withdrawalFee
    ) external;

    // // Events
    // event Deposit(address indexed user, address indexed token, uint256 amount, uint256 fee);
    // event Withdraw(address indexed user, address indexed token, uint256 amount, uint256 fee);
    // event Slashed(address indexed user, uint256 amount);
    // event UserBlacklisted(address indexed user);
    // event TokenWhitelisted(address indexed token);
    // event RiskParametersUpdated(uint256 withdrawalCooldown, uint256 insuranceFundRatio, uint256 maxUtilizationRate);
    // event CollateralConfigUpdated(
    //     address indexed token,
    //     uint256 minDeposit,
    //     uint256 maxDeposit,
    //     uint256 depositFee,
    //     uint256 withdrawalFee
    // );

    event Deposit(address indexed user, address indexed token, uint256 amount, uint256 fee);
    event Withdraw(address indexed user, address indexed token, uint256 amount, uint256 fee);
    event Slashed(address indexed user, uint256 amount);
    event InsuranceFundUpdated(uint256 newAmount);
    event UserBlacklisted(address indexed user);
    event UserUnblacklisted(address indexed user);
    event TokenWhitelisted(address indexed token);
    event TokenUnwhitelisted(address indexed token);
    event CollateralConfigUpdated(
        address indexed token,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 depositFee,
        uint256 withdrawalFee
    );
    event UtilizationRateUpdated(uint256 newRate);
    event DynamicFeeUpdated(uint256 newMultiplier);
}
