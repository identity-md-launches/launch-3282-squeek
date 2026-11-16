// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {SqueekToken} from "src/SqueekToken.sol";
import {SqueekHandler} from "./handlers/SqueekHandler.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
contract SqueekTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    SqueekToken private token;
    SqueekHandler private handler;

    function setUp() public {
        address[5] memory actors;
        uint256[5] memory balances;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("invariant holder ", vm.toString(i)));
        }
        vm.prank(actors[0]);
        token = new SqueekToken();
        // Retain a funded deployer, three other funded holders, and one initially empty holder.
        balances[0] = SUPPLY * 2 / 5;
        for (uint256 i = 1; i < 4; ++i) {
            balances[i] = SUPPLY / 5;
            vm.prank(actors[0]);
            assertTrue(token.transfer(actors[i], balances[i]));
        }
        handler = new SqueekHandler(token, actors, balances);

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.transferAll.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.approveAndSpend.selector;
        selectors[5] = handler.roundTrip.selector;
        selectors[6] = handler.rejectOverspend.selector;
        selectors[7] = handler.revokeAndRejectSpend.selector;
        selectors[8] = handler.rejectInsufficientBalance.selector;
        selectors[9] = handler.rejectZeroRecipient.selector;
        selectors[10] = handler.rejectZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyIsFixedAndAllTokensAreAccountedFor() public view {
        uint256 sum;
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(token.totalSupply(), SUPPLY, "supply changed after constructor");
        assertEq(sum, SUPPLY, "tokens were created, lost, or diverted outside the holders");
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_balancesEqualInitialPlusReceivedMinusSent() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address actor = handler.actors(i);
            assertEq(token.balanceOf(actor), handler.expectedBalance(actor), "holder accounting mismatch");
        }
    }

    function invariant_onlyApprovedSpendingChangesAllowances() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address owner = handler.actors(i);
            assertEq(token.allowance(owner, address(0)), 0);
            for (uint256 j; j < handler.ACTOR_COUNT(); ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.expectedAllowance(owner, spender),
                    "allowance changed without its owner's approval or a successful spend"
                );
            }
        }
    }

    function invariant_callsSucceedOrRevertExactlyAsRequired() public view {
        assertFalse(handler.unexpectedOutcome(), "unexpected success, revert, return data, or intermediate balance");
    }

    function invariant_metadataNeverChanges() public view {
        assertEq(token.name(), "Squeek");
        assertEq(token.symbol(), "SQK");
        assertEq(token.decimals(), 18);
        assertEq(token.DECIMALS(), 18);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
    }

    /// @dev A pinned sequence proves the harness reaches real spending, rollback, revocation,
    ///      aliasing, full drains and round trips, without depending on a particular random seed.
    function test_handlerExercisesSuccessfulAndRejectedCalls() public {
        handler.transfer(0, 4, 1);
        handler.approve(0, 1, 10, 3);
        handler.transferFrom(0, 1, 2, 2);
        handler.approveAndSpend(1, 1, 1, 1, true);
        handler.approveAndSpend(2, 3, 4, 1, false);
        handler.roundTrip(3, 1, 2);
        handler.rejectOverspend(0, 1, type(uint256).max);
        handler.rejectInsufficientBalance(1, 2, 3, type(uint256).max - 1);
        handler.revokeAndRejectSpend(1, 2, 3);
        handler.rejectZeroRecipient(0, 1, 1, true);
        handler.rejectZeroRecipient(0, 1, 0, false);
        handler.rejectZeroSpender(0, type(uint256).max);
        handler.transferAll(4, 0);

        assertGt(handler.positiveTransfers(), 0);
        assertGt(handler.successfulCalls(), 0);
        assertEq(handler.rejectedCalls(), 6);
        invariant_supplyIsFixedAndAllTokensAreAccountedFor();
        invariant_balancesEqualInitialPlusReceivedMinusSent();
        invariant_onlyApprovedSpendingChangesAllowances();
        invariant_callsSucceedOrRevertExactlyAsRequired();
        invariant_metadataNeverChanges();
    }
}
