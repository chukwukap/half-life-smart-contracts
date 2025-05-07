// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPerpetualIndexMarket} from "../../src/interfaces/IPerpetualIndexMarket.sol";

/// @title MockReentrantContract
/// @notice Mock contract that attempts to reenter the market contract
contract MockReentrantContract {
    IPerpetualIndexMarket public market;
    IERC20 public marginToken;
    bool public isReentering;

    constructor(address _market, address _marginToken) {
        market = IPerpetualIndexMarket(_market);
        marginToken = IERC20(_marginToken);
    }

    /// @notice Attempt to reenter during deposit
    function depositAndReenter(uint256 amount) external {
        marginToken.approve(address(market), amount);
        isReentering = true;
        market.depositMargin(amount);
        isReentering = false;
    }

    /// @notice Attempt to reenter during position opening
    function openPositionAndReenter(
        bool isLong,
        uint256 amount,
        uint256 leverage,
        uint256 margin
    ) external {
        marginToken.approve(address(market), margin);
        isReentering = true;
        market.openPosition(isLong, amount, leverage, margin);
        isReentering = false;
    }

    /// @notice Attempt to reenter during position closing
    function closePositionAndReenter(uint256 positionId) external {
        isReentering = true;
        market.closePosition(positionId);
        isReentering = false;
    }

    /// @notice Attempt to reenter during margin withdrawal
    function withdrawAndReenter(uint256 amount) external {
        isReentering = true;
        market.withdrawMargin(amount);
        isReentering = false;
    }
}
