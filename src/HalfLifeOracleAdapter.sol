// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title HalfLifeOracleAdapter
/// @notice Stores the latest Token Lifespan Index (TLI) value for a token, updatable only by a trusted oracle.
contract HalfLifeOracleAdapter is Ownable, ReentrancyGuard {
    struct OracleState {
        uint256 latestTLI;
        uint256 lastUpdate;
        uint256 heartbeat;
        uint256 deviationThreshold;
        uint256 minValidTLI;
        uint256 maxValidTLI;
        uint256[] recentTLIs;
        uint256 recentTLIsIndex;
    }

    struct OracleConfig {
        address oracle;
        bool isActive;
        uint256 lastUpdate;
        uint256 heartbeat;
        uint256 deviationThreshold;
        uint256 reputation;
        uint256 totalUpdates;
        uint256 successfulUpdates;
        uint256 lastDeviation;
    }

    struct AggregationConfig {
        uint256 minOracles;
        uint256 maxDeviation;
        uint256 aggregationWindow;
        uint256 reputationThreshold;
    }

    OracleState public state;
    mapping(address => OracleConfig) public oracles;
    address[] public oracleList;
    AggregationConfig public aggregationConfig;

    // Circuit breaker
    bool public circuitBreaker;
    uint256 public lastCircuitBreakerTime;
    uint256 public circuitBreakerCooldown = 1 hours;

    // Events
    event OracleAdded(address indexed oracle, uint256 heartbeat, uint256 deviationThreshold);
    event OracleRemoved(address indexed oracle);
    event OracleUpdated(address indexed oracle, uint256 heartbeat, uint256 deviationThreshold);
    event TLIUpdated(uint256 indexed newTLI, uint256 timestamp, address indexed oracle);
    event CircuitBreakerTriggered(uint256 timestamp);
    event CircuitBreakerReset(uint256 timestamp);
    event StateUpdated(uint256 heartbeat, uint256 deviationThreshold, uint256 minValidTLI, uint256 maxValidTLI);
    event OracleReputationUpdated(
        address indexed oracle,
        uint256 newReputation,
        uint256 totalUpdates,
        uint256 successfulUpdates
    );
    event AggregationConfigUpdated(
        uint256 minOracles,
        uint256 maxDeviation,
        uint256 aggregationWindow,
        uint256 reputationThreshold
    );

    constructor() Ownable(msg.sender) {
        state.heartbeat = 1 hours;
        state.deviationThreshold = 0.1e18; // 10% deviation threshold
        state.minValidTLI = 0.1e18; // Minimum valid TLI
        state.maxValidTLI = 10e18; // Maximum valid TLI
        state.recentTLIs = new uint256[](10); // Store last 10 TLIs
        state.recentTLIsIndex = 0;

        aggregationConfig = AggregationConfig({
            minOracles: 3,
            maxDeviation: 0.05e18, // 5% max deviation between oracles
            aggregationWindow: 5 minutes,
            reputationThreshold: 0.7e18 // 70% reputation required
        });
    }

    /// @notice Add a new oracle
    function addOracle(address _oracle, uint256 _heartbeat, uint256 _deviationThreshold) external onlyOwner {
        require(_oracle != address(0), "Invalid oracle address");
        require(!oracles[_oracle].isActive, "Oracle already exists");
        require(_heartbeat > 0, "Invalid heartbeat");
        require(_deviationThreshold <= 0.5e18, "Deviation too high");

        oracles[_oracle] = OracleConfig({
            oracle: _oracle,
            isActive: true,
            lastUpdate: 0,
            heartbeat: _heartbeat,
            deviationThreshold: _deviationThreshold,
            reputation: 1e18, // Start with full reputation
            totalUpdates: 0,
            successfulUpdates: 0,
            lastDeviation: 0
        });
        oracleList.push(_oracle);

        emit OracleAdded(_oracle, _heartbeat, _deviationThreshold);
    }

    /// @notice Remove an oracle
    function removeOracle(address _oracle) external onlyOwner {
        require(oracles[_oracle].isActive, "Oracle not found");
        oracles[_oracle].isActive = false;

        // Remove from list
        for (uint256 i = 0; i < oracleList.length; i++) {
            if (oracleList[i] == _oracle) {
                oracleList[i] = oracleList[oracleList.length - 1];
                oracleList.pop();
                break;
            }
        }

        emit OracleRemoved(_oracle);
    }

    /// @notice Update oracle configuration
    function updateOracle(address _oracle, uint256 _heartbeat, uint256 _deviationThreshold) external onlyOwner {
        require(oracles[_oracle].isActive, "Oracle not found");
        require(_heartbeat > 0, "Invalid heartbeat");
        require(_deviationThreshold <= 0.5e18, "Deviation too high");

        oracles[_oracle].heartbeat = _heartbeat;
        oracles[_oracle].deviationThreshold = _deviationThreshold;

        emit OracleUpdated(_oracle, _heartbeat, _deviationThreshold);
    }

    /// @notice Update TLI value
    function updateTLI(uint256 _tli) external nonReentrant {
        require(!circuitBreaker, "Circuit breaker active");
        require(oracles[msg.sender].isActive, "Not authorized");
        require(
            block.timestamp <= oracles[msg.sender].lastUpdate + oracles[msg.sender].heartbeat,
            "Heartbeat exceeded"
        );
        require(_tli >= state.minValidTLI && _tli <= state.maxValidTLI, "TLI out of range");

        // Check deviation from current TLI
        uint256 deviation = 0;
        if (state.latestTLI > 0) {
            deviation = _calculateDeviation(_tli, state.latestTLI);
            require(deviation <= oracles[msg.sender].deviationThreshold, "Deviation too high");
        }

        // Update oracle stats
        OracleConfig storage config = oracles[msg.sender];
        config.totalUpdates++;
        config.lastDeviation = deviation;

        // Update reputation based on deviation
        if (deviation <= config.deviationThreshold / 2) {
            config.successfulUpdates++;
            config.reputation = (config.reputation * 99 + 1e18) / 100; // Increase reputation
        } else {
            config.reputation = (config.reputation * 95) / 100; // Decrease reputation
        }

        // Check if oracle meets reputation threshold
        require(config.reputation >= aggregationConfig.reputationThreshold, "Oracle reputation too low");

        // Update state
        state.latestTLI = _tli;
        state.lastUpdate = block.timestamp;
        config.lastUpdate = block.timestamp;

        // Update recent TLIs
        state.recentTLIs[state.recentTLIsIndex] = _tli;
        state.recentTLIsIndex = (state.recentTLIsIndex + 1) % 10;

        // Check circuit breaker
        _checkCircuitBreaker();

        emit TLIUpdated(_tli, block.timestamp, msg.sender);
        emit OracleReputationUpdated(msg.sender, config.reputation, config.totalUpdates, config.successfulUpdates);
    }

    /// @notice Update global state parameters
    function updateState(
        uint256 _heartbeat,
        uint256 _deviationThreshold,
        uint256 _minValidTLI,
        uint256 _maxValidTLI
    ) external onlyOwner {
        require(_heartbeat > 0, "Invalid heartbeat");
        require(_deviationThreshold <= 0.5e18, "Deviation too high");
        require(_minValidTLI < _maxValidTLI, "Invalid TLI range");

        state.heartbeat = _heartbeat;
        state.deviationThreshold = _deviationThreshold;
        state.minValidTLI = _minValidTLI;
        state.maxValidTLI = _maxValidTLI;

        emit StateUpdated(_heartbeat, _deviationThreshold, _minValidTLI, _maxValidTLI);
    }

    /// @notice Update aggregation configuration
    function updateAggregationConfig(
        uint256 _minOracles,
        uint256 _maxDeviation,
        uint256 _aggregationWindow,
        uint256 _reputationThreshold
    ) external onlyOwner {
        require(_minOracles > 0, "Invalid min oracles");
        require(_maxDeviation <= 0.1e18, "Max deviation too high");
        require(_aggregationWindow <= 1 hours, "Window too long");
        require(_reputationThreshold <= 1e18, "Invalid threshold");

        aggregationConfig = AggregationConfig({
            minOracles: _minOracles,
            maxDeviation: _maxDeviation,
            aggregationWindow: _aggregationWindow,
            reputationThreshold: _reputationThreshold
        });

        emit AggregationConfigUpdated(_minOracles, _maxDeviation, _aggregationWindow, _reputationThreshold);
    }

    /// @notice Reset circuit breaker after cooldown period
    function resetCircuitBreaker() external onlyOwner {
        require(circuitBreaker, "Circuit breaker not active");
        require(block.timestamp >= lastCircuitBreakerTime + circuitBreakerCooldown, "Cooldown not finished");
        circuitBreaker = false;
        emit CircuitBreakerReset(block.timestamp);
    }

    /// @notice Get the latest TLI value
    function latestTLI() external view returns (uint256) {
        require(state.latestTLI > 0, "No TLI available");
        require(block.timestamp <= state.lastUpdate + state.heartbeat, "TLI too old");
        return state.latestTLI;
    }

    /// @notice Get the number of active oracles
    function getActiveOracleCount() external view returns (uint256) {
        uint256 count = 0;
        for (uint256 i = 0; i < oracleList.length; i++) {
            if (oracles[oracleList[i]].isActive) {
                count++;
            }
        }
        return count;
    }

    /// @notice Get oracle reputation
    function getOracleReputation(address oracle) external view returns (uint256) {
        return oracles[oracle].reputation;
    }

    /// @notice Get recent TLIs
    function getRecentTLIs() external view returns (uint256[] memory) {
        return state.recentTLIs;
    }

    /// @dev Calculate deviation between two values
    function _calculateDeviation(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0 || b == 0) return 0;
        return a > b ? ((a - b) * 1e18) / b : ((b - a) * 1e18) / a;
    }

    /// @dev Check if circuit breaker should be triggered
    function _checkCircuitBreaker() internal {
        if (circuitBreaker) return;

        uint256 activeOracles = 0;
        uint256 validUpdates = 0;
        uint256 highReputationOracles = 0;

        for (uint256 i = 0; i < oracleList.length; i++) {
            OracleConfig storage config = oracles[oracleList[i]];
            if (config.isActive) {
                activeOracles++;
                if (block.timestamp <= config.lastUpdate + config.heartbeat) {
                    validUpdates++;
                }
                if (config.reputation >= aggregationConfig.reputationThreshold) {
                    highReputationOracles++;
                }
            }
        }

        // Trigger circuit breaker if:
        // 1. Less than 50% of oracles are valid
        // 2. Less than minOracles have high reputation
        if (
            (activeOracles > 0 && (validUpdates * 1e18) / activeOracles < 0.5e18) ||
            highReputationOracles < aggregationConfig.minOracles
        ) {
            circuitBreaker = true;
            lastCircuitBreakerTime = block.timestamp;
            emit CircuitBreakerTriggered(block.timestamp);
        }
    }
}
