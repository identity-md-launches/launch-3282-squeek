// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SqueekToken} from "src/SqueekToken.sol";

contract SqueekCreatingContract {
    function create() external returns (SqueekToken) {
        return new SqueekToken();
    }
}

/// @notice Complements the existing suite with boundary inputs, aliasing and atomicity properties.
/// forge-config: default.fuzz.runs = 1000
contract SqueekTokenEdgesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 ether;
    SqueekToken private token;
    address private holder;
    address private spender;
    address private recipient;
    address private otherSpender;

    function setUp() public {
        holder = makeAddr("edge holder");
        spender = makeAddr("edge spender");
        recipient = makeAddr("edge recipient");
        otherSpender = makeAddr("edge other spender");
        vm.prank(holder);
        token = new SqueekToken();
    }

    function test_constructorMintsOnceToCreatingContractInsteadOfOrigin() public {
        SqueekCreatingContract creator = new SqueekCreatingContract();
        vm.recordLogs();
        vm.prank(holder, holder);
        SqueekToken created = creator.create();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(created.balanceOf(address(creator)), SUPPLY);
        assertEq(created.balanceOf(holder), 0, "tx.origin must not receive a factory's mint");
        assertEq(created.balanceOf(address(created)), 0);
        assertEq(created.totalSupply(), SUPPLY);
        assertEq(logs.length, 1, "constructor must emit exactly one mint");
        assertEq(logs[0].emitter, address(created));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(creator)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function test_oneMinorUnitCanMoveAndReturnWithoutRounding() public {
        vm.prank(holder);
        assertTrue(token.transfer(recipient, 1));
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, 1));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_zeroTransferFromNeedsNoApprovalAndEmitsTransfer() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 0));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_zeroTransferFromEmptyHolderEmitsTransfer() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(recipient, otherSpender, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(recipient, otherSpender, 0));
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.allowance(recipient, spender), 0);
    }

    function test_zeroTransferToZeroAddressStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(holder);
        token.transfer(address(0), 0);
        _assertInitialBalances();
    }

    function test_zeroTransferFromToZeroAddressStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);
        assertEq(token.allowance(holder, spender), 0);
        _assertInitialBalances();
    }

    function test_zeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 0);
        assertEq(token.allowance(holder, address(0)), 0);
        _assertInitialBalances();
    }

    function test_zeroFromCannotBeUsedAsAMintPathEvenForZeroAmount() public {
        vm.prank(spender);
        (bool ok,) = address(token).call(abi.encodeCall(token.transferFrom, (address(0), recipient, 0)));
        assertFalse(ok);
        _assertInitialBalances();
    }

    function test_maximumTransferRevertsWithBalanceErrorWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        vm.prank(holder);
        token.transfer(recipient, type(uint256).max);
        _assertInitialBalances();
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, SUPPLY + 1)
        );
        vm.prank(holder);
        token.transfer(holder, SUPPLY + 1);
        _assertInitialBalances();
    }

    function test_wholeSupplySelfTransferEmitsWithoutChangingBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(holder, holder, SUPPLY);
        vm.prank(holder);
        assertTrue(token.transfer(holder, SUPPLY));
        _assertInitialBalances();
    }

    function test_selfTransferFromConsumesAllowanceDespiteUnchangedBalance() public {
        _approve(holder, spender, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, 1));
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.allowance(holder, spender), 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, holder, 1));
        assertEq(token.allowance(holder, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, holder, 1);
        _assertInitialBalances();
    }

    function test_ownerCallingTransferFromRequiresSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        vm.prank(holder);
        token.transferFrom(holder, recipient, 1);
        _approve(holder, holder, 1);
        vm.prank(holder);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.allowance(holder, holder), 0);
    }

    function test_maximumFiniteAllowanceDecreasesOnEverySpend() public {
        _approve(holder, spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), type(uint256).max - 3);
        assertEq(token.balanceOf(recipient), 2);
    }

    function test_infiniteAllowanceSurvivesRepeatedSpendsAndCanBeRevoked() public {
        _approve(holder, spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), type(uint256).max);

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(holder, spender, 0);
        _approve(holder, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), SUPPLY - 2);
        assertEq(token.balanceOf(recipient), 2);
    }

    function test_replacingInfiniteAllowanceWithFiniteLimitsSubsequentSpends() public {
        _approve(holder, spender, type(uint256).max);
        _approve(holder, spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_fullSupplyDelegatedSpendExhaustsBalanceAndAllowance() public {
        _approve(holder, spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, SUPPLY));
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
    }

    function test_approvalFromEmptyHolderDoesNotCreateTokens() public {
        _approve(recipient, spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, recipient, 0, 1));
        vm.prank(spender);
        token.transferFrom(recipient, spender, 1);
        assertEq(token.allowance(recipient, spender), type(uint256).max);
        _assertInitialBalances();
    }

    function test_approvedAmountAboveSupplyDoesNotPermitMinting() public {
        _approve(holder, spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        vm.prank(spender);
        token.transferFrom(holder, recipient, type(uint256).max);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        _assertInitialBalances();
    }

    function test_allowanceForOneSpenderDoesNotAuthorizeAnother() public {
        _approve(holder, spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1));
        vm.prank(otherSpender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.allowance(holder, spender), type(uint256).max);
        assertEq(token.allowance(holder, otherSpender), 0);
        _assertInitialBalances();
    }

    function test_approvalsAreScopedToOwnerAndSpenderPair() public {
        _approve(holder, spender, 11);
        _approve(holder, otherSpender, 22);
        _approve(recipient, spender, 33);
        _approve(holder, spender, 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.allowance(holder, otherSpender), 22);
        assertEq(token.allowance(recipient, spender), 33);
        assertEq(token.allowance(spender, holder), 0);
        _assertInitialBalances();
    }

    function test_tokensSentToTokenContractRemainInSupply() public {
        vm.prank(holder);
        assertTrue(token.transfer(address(token), 1));
        assertEq(token.balanceOf(address(token)), 1);
        assertEq(token.balanceOf(holder), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_directEtherAndValueAttachedToApprovalAreRejected() public {
        vm.deal(holder, 2);
        vm.prank(holder);
        (bool received,) = address(token).call{value: 1}("");
        assertFalse(received);
        vm.prank(holder);
        (bool approved,) = address(token).call{value: 1}(abi.encodeCall(token.approve, (spender, 1)));
        assertFalse(approved);
        assertEq(address(token).balance, 0);
        assertEq(holder.balance, 2);
        assertEq(token.allowance(holder, spender), 0);
        _assertInitialBalances();
    }

    function testFuzz_balanceFailureRollsBackFiniteAllowance(uint256 held, uint256 extra) public {
        held = bound(held, 0, SUPPLY - 1);
        uint256 amount = held + bound(extra, 1, SUPPLY - held);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, held));
        _approve(recipient, spender, amount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, recipient, held, amount));
        vm.prank(spender);
        token.transferFrom(recipient, otherSpender, amount);
        assertEq(token.allowance(recipient, spender), amount, "failed spend consumed approval");
        assertEq(token.balanceOf(recipient), held);
        assertEq(token.balanceOf(holder), SUPPLY - held);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_invalidRecipientRollsBackAllowance(uint256 amount, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        uint256 approved = unlimited ? type(uint256).max : amount;
        _approve(holder, spender, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), amount);
        assertEq(token.allowance(holder, spender), approved);
        _assertInitialBalances();
    }

    function testFuzz_splitSpendingCannotExceedFiniteApproval(uint256 approved, uint256 first) public {
        approved = bound(approved, 0, SUPPLY);
        first = bound(first, 0, approved);
        _approve(holder, spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, first));
        assertEq(token.allowance(holder, spender), approved - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, approved - first));
        assertEq(token.allowance(holder, spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 1);
        assertEq(token.balanceOf(holder), SUPPLY - approved);
        assertEq(token.balanceOf(recipient), approved);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalOverwriteIsIdempotentAndDoesNotMoveTokens(uint256 first, uint256 replacement) public {
        _approve(holder, spender, first);
        _approve(holder, spender, replacement);
        _approve(holder, spender, replacement);
        assertEq(token.allowance(holder, spender), replacement);
        _assertInitialBalances();
    }

    function testFuzz_roundTripPreservesBothPreexistingBalances(uint256 initial, uint256 amount, uint8 cycles) public {
        initial = bound(initial, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY - initial);
        cycles = uint8(bound(cycles, 1, 8));
        vm.prank(holder);
        assertTrue(token.transfer(recipient, initial));
        for (uint256 i; i < cycles; ++i) {
            vm.prank(holder);
            assertTrue(token.transfer(recipient, amount));
            assertEq(token.balanceOf(recipient), initial + amount);
            vm.prank(recipient);
            assertTrue(token.transfer(holder, amount));
            assertEq(token.balanceOf(holder), SUPPLY - initial);
            assertEq(token.balanceOf(recipient), initial);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_directTransferDoesNotConsumeAnyApproval(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        _approve(holder, spender, approved);
        _approve(holder, recipient, type(uint256).max);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.allowance(holder, spender), approved);
        assertEq(token.allowance(holder, recipient), type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY - amount);
        assertEq(token.balanceOf(recipient), amount);
    }

    function testFuzz_revokedApprovalCannotSpendAfterBalanceIsRefilled(uint256 initial, uint256 refill) public {
        initial = bound(initial, 1, SUPPLY);
        refill = bound(refill, 1, initial);
        _approve(holder, spender, type(uint256).max);
        vm.prank(holder);
        assertTrue(token.transfer(recipient, initial));
        _approve(holder, spender, 0);
        vm.prank(recipient);
        assertTrue(token.transfer(holder, refill));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, refill));
        vm.prank(spender);
        token.transferFrom(holder, spender, refill);
        assertEq(token.balanceOf(holder), SUPPLY - initial + refill);
        assertEq(token.balanceOf(recipient), initial - refill);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(holder, spender), 0);
    }

    function _approve(address owner, address approvedSpender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(approvedSpender, amount));
    }

    function _assertInitialBalances() private view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }
}
