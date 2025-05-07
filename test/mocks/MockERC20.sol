// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockERC20
/// @notice A mock ERC20 token for testing purposes
/// @dev Inherits from OpenZeppelin's ERC20 implementation
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    /// @notice Creates a new mock ERC20 token
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    /// @param decimals The number of decimals the token uses
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    /// @notice Mints tokens to an address
    /// @param to The address to mint tokens to
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Returns the number of decimals used to get its user representation
    /// @return The number of decimals
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
