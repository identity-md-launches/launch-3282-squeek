// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Squeek (SQK)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 SQK (18 decimals) is minted
///         once, in the constructor, to the deployer. There is no owner, no mint, no burn, no pause,
///         no blocklist and no fee: every transfer moves exactly the amount requested.
/// @dev The contract is intentionally a thin wrapper over OpenZeppelin's audited ERC20 (v5.4.0).
///      The deployer is `msg.sender` of the creation transaction. At launch that is the project
///      factory, which pays the supply out; nothing in this contract depends on who the deployer is.
contract SqueekToken is ERC20 {
    /// @notice The token name returned by `name()`.
    string internal constant NAME = "Squeek";

    /// @notice The token symbol returned by `symbol()`.
    string internal constant SYMBOL = "SQK";

    /// @notice The number of decimals, as returned by `decimals()`.
    uint8 public constant DECIMALS = 18;

    /// @notice The whole supply in minor units: 1,000,000,000 * 10^18. Fixed for the life of the contract.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    /// @notice Mints the entire supply to the deployer. This is the only mint that ever happens.
    constructor() ERC20(NAME, SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
