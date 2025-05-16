# Half-Life Perpetual Index Betting Protocol

## Developer Documentation (2025)

---

## Table of Contents

1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Component Responsibilities](#component-responsibilities)
4. [Workflow: End-to-End](#workflow-end-to-end)
5. [Smart Contract Details](#smart-contract-details)
6. [Uniswap v4 and Hooks Integration](#uniswap-v4-and-hooks-integration)
7. [Oracle and Off-chain Index Engine](#oracle-and-off-chain-index-engine)
8. [Security Considerations](#security-considerations)
9. [Extensibility & Customization](#extensibility--customization)
10. [Frontend/Backend Integration](#frontendbackend-integration)
11. [Testing & Deployment](#testing--deployment)
12. [Glossary](#glossary)
13. [Appendix: Example Flows](#appendix-example-flows)
14. [Project Structure](#project-structure)

---

## 1. Overview

**Half-Life** is a DeFi protocol for betting on the "lifespan" of tokens, using a custom Token Lifespan Index (TLI) as the underlying.  
Users can take **long** (betting on longevity) or **short** (betting on decay) positions on a token's TLI, with PnL and funding rates handled virtually.  
The protocol leverages **Uniswap v4** for liquidity and order routing, and **Uniswap v4 Hooks** for custom margin, funding, and settlement logic.

---

## 2. System Architecture

**Key Components:**

- **User**: Trader interacting via dApp.
- **Frontend dApp**: UI for trading, margin management, and position monitoring.
- **Margin Vault**: Holds user collateral (e.g., USDC), manages deposits, withdrawals, and margin accounting.
- **Uniswap v4 Pool**: The trading venue for each token's TLI market.
- **Uniswap v4 Hook**: Custom logic for margin checks, funding payments, and settlement, triggered on every trade.
- **Perpetual Pool**: Core contract for virtual position management, PnL, and funding.
- **Oracle Adapter**: Receives and stores the latest TLI value from a trusted off-chain oracle.
- **Off-chain Index Engine**: Aggregates data, computes TLI, and pushes updates to the Oracle Adapter.

---

## 3. Component Responsibilities

### 3.1. User

- Deposits collateral (e.g., USDC) into the Margin Vault.
- Opens/closes long or short positions via the dApp.
- Monitors positions, margin, and PnL.

### 3.2. Frontend dApp

- Provides UI for all user actions.
- Displays real-time TLI, funding rates, and position data.
- Interacts with smart contracts and backend APIs.

### 3.3. Margin Vault

- Holds and tracks user collateral.
- Handles deposits, withdrawals, and slashing (liquidations).
- Only the Perpetual Pool can slash margin.

### 3.4. Uniswap v4 Pool

- Provides the trading interface for each TLI market.
- Handles order matching and routing.
- Calls the custom Hook on every trade.

### 3.5. Uniswap v4 Hook

- Enforces custom logic on every trade:
  - Checks user margin before allowing trade.
  - Triggers funding payments.
  - Updates virtual positions in the Perpetual Pool.
  - Can reject trades if margin is insufficient.

### 3.6. Perpetual Pool

- Manages all user positions (virtual, not real token swaps).
- Calculates PnL and funding payments.
- Handles position opening, closing, and liquidation.
- Interacts with the Margin Vault for margin management.

### 3.7. Oracle Adapter

- Stores the latest TLI value for each token.
- Only updatable by a trusted oracle (e.g., Chainlink EA).
- Provides TLI to the Perpetual Pool for PnL/funding calculations.

### 3.8. Off-chain Index Engine

- Aggregates market, volume, social, and on-chain data.
- Calculates the TLI using the geometric mean and custom weighting.
- Pushes TLI updates to the Oracle Adapter on-chain.

---

## 4. Workflow: End-to-End

### 4.1. User Onboarding

1. User connects wallet to dApp.
2. User deposits USDC (or other collateral) into the Margin Vault.

### 4.2. Opening a Position

1. User selects a token's TLI market and chooses long or short.
2. User specifies position size and margin.
3. dApp sends a transaction to the Uniswap v4 Pool to open the position.
4. Uniswap v4 Pool calls the Hook.
5. Hook checks margin, triggers funding, and updates the Perpetual Pool.
6. If all checks pass, the position is opened; otherwise, the trade is rejected.

### 4.3. Funding Rate Payments

- At regular intervals (e.g., hourly), the Hook or Perpetual Pool calculates funding payments between longs and shorts, based on the difference between the market price and the TLI.
- Funding is paid/received by updating virtual balances and margin.

### 4.4. Closing a Position

1. User initiates a close position action via the dApp.
2. dApp sends a transaction to the Uniswap v4 Pool.
3. Pool calls the Hook, which settles PnL and funding, and updates the Perpetual Pool.
4. Margin and PnL are released back to the user's Margin Vault balance.

### 4.5. Liquidation

- If a user's margin falls below the maintenance threshold (due to losses or funding payments), anyone can trigger a liquidation.
- The Perpetual Pool slashes the user's margin in the Vault, closes the position, and may pay a liquidation fee to the liquidator.

### 4.6. Oracle Updates

- The Off-chain Index Engine computes the latest TLI and pushes it to the Oracle Adapter.
- The Perpetual Pool uses the latest TLI for all PnL and funding calculations.

---

## 5. Smart Contract Details

### 5.1. HalfLifeOracleAdapter

- Stores the latest TLI value and timestamp.
- Only the trusted oracle can update the TLI.
- Emits events for every update.

### 5.2. HalfLifeMarginVault

- ERC20-based vault for user collateral.
- Handles deposits, withdrawals, and slashing.
- Only the Perpetual Pool can slash margin for liquidations.

### 5.3. HalfLifePerpetualPool

- Manages all user positions (size, entry TLI, margin, last funding time).
- Calculates PnL:
  - **Long:** (Exit TLI - Entry TLI) \* Position Size
  - **Short:** (Entry TLI - Exit TLI) \* Position Size
- Calculates and applies funding payments.
- Handles position opening, closing, and liquidation.
- Interacts with the Margin Vault for margin management.

### 5.4. HalfLifeUniswapV4Hook

- Implements Uniswap v4 hook interface.
- On every trade, checks margin, triggers funding, and updates positions.
- Can reject trades if margin is insufficient.

---

## 6. Uniswap v4 and Hooks Integration

- **Uniswap v4 Pool**: Each TLI market is a Uniswap v4 pool (e.g., TLI/USDC).
- **Custom Hook**: Registered with the pool, the hook is called on every swap, mint, or burn.
- **Hook Logic**:
  - Checks if the user has enough margin in the Vault.
  - Calls the Perpetual Pool to update positions and funding.
  - Can revert the transaction if checks fail.
- **Benefits**:
  - Leverages Uniswap's liquidity and security.
  - Allows custom logic for perpetuals without modifying Uniswap core.

---

## 7. Oracle and Off-chain Index Engine

### 7.1. Off-chain Index Engine

- Aggregates data from multiple APIs (market cap, volume, social, on-chain).
- Normalizes and weights data using the geometric mean.
- Calculates the TLI for each token.
- Pushes the TLI to the Oracle Adapter on-chain at regular intervals.

### 7.2. Oracle Adapter

- Receives TLI updates from the trusted oracle (e.g., Chainlink External Adapter).
- Stores the latest TLI and timestamp.
- Only the oracle can update the TLI (admin can change oracle address if needed).

### 7.3. Security

- Only the whitelisted oracle can update the TLI.
- TLI updates are timestamped and can be rate-limited to prevent manipulation.

---

## 8. Security Considerations

- **Reentrancy**: All external functions are protected with reentrancy guards.
- **Access Control**: Only the trusted oracle can update TLI; only the Perpetual Pool can slash margin.
- **Overflow/Underflow**: All math uses Solidity 0.8+ checked arithmetic.
- **Oracle Manipulation**: Use multiple data sources, rate limits, and off-chain validation.
- **Liquidation**: Only allowed if margin falls below maintenance; all actions are logged.
- **Emergency Controls**: Admin can pause contracts or change oracle in emergencies.

---

## 9. Extensibility & Customization

- **Leverage**: Add leverage by allowing users to open positions larger than their margin, with stricter liquidation rules.
- **Insurance Fund**: Add a fund to cover losses from extreme events or failed liquidations.
- **Multiple Collateral Types**: Support other stablecoins or assets as collateral.
- **Advanced Funding Logic**: Use more sophisticated funding rate calculations.
- **Gamification**: Add badges, leaderboards, and social features at the dApp layer.

---

## 10. Frontend/Backend Integration

- **Frontend**:

  - Connects to user wallet (e.g., MetaMask).
  - Calls contract functions for deposit, withdraw, open/close position.
  - Displays real-time TLI, funding rates, and position data.
  - Handles error messages and transaction confirmations.

- **Backend**:
  - Runs the Off-chain Index Engine.
  - Aggregates and normalizes data from APIs.
  - Pushes TLI updates to the Oracle Adapter.
  - Monitors contract events for analytics and notifications.

---

## 11. Testing & Deployment

- **Unit Tests**: For all contract functions, especially margin, funding, and liquidation logic.
- **Integration Tests**: Simulate full user flows (deposit, open, funding, close, liquidation).
- **Oracle Simulation**: Test with mock TLI updates and edge cases (stale data, manipulation attempts).
- **Security Audits**: Mandatory before mainnet deployment.
- **Deployment**:
  - Deploy Margin Vault, Oracle Adapter, Perpetual Pool, and Hook.
  - Register Hook with Uniswap v4 Pool.
  - Set up Off-chain Index Engine and Oracle.

---

## 12. Glossary

- **TLI (Token Lifespan Index)**: Composite score representing a token's "life" based on market, volume, social, and on-chain data.
- **Long Position**: Bet that the TLI will go up (token will survive/thrive).
- **Short Position**: Bet that the TLI will go down (token will decay/die).
- **Funding Rate**: Periodic payment between longs and shorts to keep the market price close to the TLI.
- **PnL (Profit and Loss)**: The gain or loss on a position, based on TLI movement.
- **Margin**: Collateral locked to cover potential losses.
- **Liquidation**: Forced closure of a position if margin is insufficient.

---

## 13. Appendix: Example Flows

### **A. Open Long Position**

1. User deposits 1000 USDC to Margin Vault.
2. User opens a long position of size 10 on TLI/USDC market.
3. Uniswap v4 Pool calls Hook.
4. Hook checks user has enough margin, triggers funding, and updates Perpetual Pool.
5. Position is opened; user's margin is locked.

### **B. Funding Payment**

1. Funding interval passes.
2. Hook or Perpetual Pool calculates funding based on TLI and market price.
3. Funding is paid from longs to shorts (or vice versa), updating virtual balances.

### **C. Close Position**

1. User closes position.
2. Hook settles PnL and funding, updates Perpetual Pool.
3. Margin and PnL are released to user's Margin Vault balance.

### **D. Oracle Update**

1. Off-chain Index Engine calculates new TLI.
2. Oracle Adapter is updated on-chain.
3. Perpetual Pool uses new TLI for PnL/funding calculations.

---

## 14. Project Structure

Below is a recommended project structure for a Foundry-based smart contract project for Half-Life:

```
/half-life-protocol
│
├── contracts/                # All Solidity smart contracts
│   ├── HalfLifeOracleAdapter.sol
│   ├── HalfLifeMarginVault.sol
│   ├── HalfLifePerpetualPool.sol
│   ├── HalfLifeUniswapV4Hook.sol
│   └── interfaces/           # Interface definitions
│
├── scripts/                  # Deployment and utility scripts (in Solidity or JS/TS)
│   └── Deploy.s.sol
│
├── test/                     # Foundry test files (in Solidity)
│   ├── HalfLifeOracleAdapter.t.sol
│   ├── HalfLifeMarginVault.t.sol
│   ├── HalfLifePerpetualPool.t.sol
│   └── HalfLifeUniswapV4Hook.t.sol
│
├── lib/                      # External dependencies (e.g., OpenZeppelin, Uniswap v4)
│
├── out/                      # Foundry build output (auto-generated)
│
├── script/                   # Foundry deployment scripts
│
├── docs/                     # Documentation
│   └── README.md             # This documentation file
│
├── .env                      # Environment variables (private keys, RPC URLs, etc.)
├── foundry.toml              # Foundry configuration
├── package.json              # For JS/TS scripts (optional)
├── pnpm-lock.yaml            # pnpm lockfile (if using JS/TS)
└── README.md                 # Project overview
```

**Notes:**

- All smart contracts go in `contracts/`.
- All tests go in `test/` and should use Foundry's test framework.
- Use `lib/` for external libraries (add via `forge install`).
- Use `scripts/` and `script/` for deployment and utility scripts.
- All documentation, including this file, goes in `docs/`.
- Use `foundry.toml` for Foundry configuration.
- Use `pnpm` for JS/TS package management if needed for off-chain scripts.

---

**For further details, see the contract files and test cases.**
