// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SqueekToken} from "../src/SqueekToken.sol";

/// @title Squeek deployment script
/// @notice Reviewable reference for a manual deployment. The production launch is performed by the
///         project factory from the built bytecode, not by this script. The token takes no constructor
///         arguments, so there is nothing to configure: whoever sends the creation transaction receives
///         the whole supply.
contract DeploySqueek is Script {
    /// @notice Deploys the token. The caller of this function (the broadcasting account when run through
    ///         `forge script`) becomes the holder of the entire supply.
    function deploy() public returns (SqueekToken token) {
        token = new SqueekToken();
    }

    /// @notice Entry point for `forge script`. Reads nothing from the environment; the broadcaster is
    ///         whatever account `forge script` was given on the command line.
    function run() external returns (SqueekToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
