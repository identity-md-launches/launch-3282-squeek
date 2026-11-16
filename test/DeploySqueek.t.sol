// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {DeploySqueek} from "../script/DeploySqueek.s.sol";
import {SqueekToken} from "../src/SqueekToken.sol";

/// @notice The deploy script's `deploy()` is called directly, with no environment and no broadcast,
///         and must hand the whole supply to the account that created the token.
contract DeploySqueekTest is Test {
    function test_deployMintsWholeSupplyToTheCreatingAccount() public {
        DeploySqueek deployer = new DeploySqueek();
        SqueekToken token = deployer.deploy();
        assertEq(token.name(), "Squeek");
        assertEq(token.symbol(), "SQK");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        // `new` inside the script contract makes the script contract the deployer.
        assertEq(token.balanceOf(address(deployer)), 1_000_000_000 ether);
    }

    function test_deployTwiceGivesIndependentTokens() public {
        DeploySqueek deployer = new DeploySqueek();
        SqueekToken first = deployer.deploy();
        SqueekToken second = deployer.deploy();
        assertTrue(address(first) != address(second));
        assertEq(first.totalSupply(), second.totalSupply());
        assertEq(first.balanceOf(address(deployer)), 1_000_000_000 ether);
        assertEq(second.balanceOf(address(deployer)), 1_000_000_000 ether);
    }
}
