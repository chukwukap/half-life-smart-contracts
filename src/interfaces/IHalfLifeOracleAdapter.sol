// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

interface IHalfLifeOracleAdapter {
    // View functions
    function latestTLI() external view returns (uint256);
    function lastUpdate() external view returns (uint256);
    function circuitBreaker() external view returns (bool);
    function state()
        external
        view
        returns (
            uint256 latestTLI,
            uint256 lastUpdate,
            uint256 minValidTLI,
            uint256 maxValidTLI
        );
    function oracles(
        address oracle
    )
        external
        view
        returns (
            address oracleAddr,
            bool isActive,
            uint256 lastUpdate,
            uint256 heartbeat,
            uint256 deviationThreshold,
            uint256 reputation,
            uint256 totalUpdates,
            uint256 successfulUpdates,
            uint256 lastDeviation
        );

    // State changing functions
    function updateTLI(uint256 _tli) external;
    function addOracle(
        address _oracle,
        uint256 _heartbeat,
        uint256 _deviationThreshold
    ) external;
    function removeOracle(address _oracle) external;
    function updateOracle(
        address _oracle,
        uint256 _heartbeat,
        uint256 _deviationThreshold
    ) external;
    function updateAggregationConfig(
        uint256 _minOracles,
        uint256 _maxDeviation,
        uint256 _aggregationWindow,
        uint256 _reputationThreshold
    ) external;

    // Events
    event OracleAdded(
        address indexed oracle,
        uint256 heartbeat,
        uint256 deviationThreshold
    );
    event OracleRemoved(address indexed oracle);
    event OracleUpdated(
        address indexed oracle,
        uint256 heartbeat,
        uint256 deviationThreshold
    );
    event TLIUpdated(uint256 tli, uint256 timestamp);
    event CircuitBreakerTriggered(uint256 timestamp);
    event AggregationConfigUpdated(
        uint256 minOracles,
        uint256 maxDeviation,
        uint256 aggregationWindow,
        uint256 reputationThreshold
    );
}
