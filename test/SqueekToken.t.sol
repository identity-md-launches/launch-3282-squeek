// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SqueekToken} from "../src/SqueekToken.sol";

/// @notice Behavioural tests for the Squeek token: metadata, the one-time mint, exact transfers,
///         allowances, the absence of any privileged path, and the launch flows the factory performs.
contract SqueekTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    address internal constant DEPLOYER = address(0xFAC7);
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);
    address internal constant STRANGER = address(0xBEEF);

    SqueekToken internal token;

    function setUp() public {
        vm.prank(DEPLOYER);
        token = new SqueekToken();
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and supply
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "Squeek");
        assertEq(token.symbol(), "SQK");
        assertEq(token.decimals(), 18);
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyConstantIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.TOTAL_SUPPLY(), 1e27);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), ALICE, SUPPLY);
        vm.prank(ALICE);
        SqueekToken fresh = new SqueekToken();
        assertEq(fresh.balanceOf(ALICE), SUPPLY);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_deployerIsWhoeverCreatesTheContract() public {
        vm.prank(CAROL);
        SqueekToken fresh = new SqueekToken();
        assertEq(fresh.balanceOf(CAROL), SUPPLY);
        assertEq(fresh.balanceOf(DEPLOYER), 0);
    }

    // ---------------------------------------------------------------------------------------------
    // transfer
    // ---------------------------------------------------------------------------------------------

    function test_transferMovesExactAmountAndEmits() public {
        uint256 amount = 1_234 ether;
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(DEPLOYER, ALICE, amount);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferZeroAmountSucceeds() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferWholeBalanceLeavesZero() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, SUPPLY);
        assertEq(token.balanceOf(DEPLOYER), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(DEPLOYER, 5 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_RevertWhen_transferExceedsBalance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10 ether, 11 ether)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 11 ether);
    }

    function test_RevertWhen_transferFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, STRANGER, 0, 1));
        vm.prank(STRANGER);
        token.transfer(BOB, 1);
    }

    function test_RevertWhen_transferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(DEPLOYER);
        token.transfer(address(0), 1);
    }

    // ---------------------------------------------------------------------------------------------
    // approve / allowance / transferFrom
    // ---------------------------------------------------------------------------------------------

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(DEPLOYER, BOB, 42);
        vm.prank(DEPLOYER);
        assertTrue(token.approve(BOB, 42));
        assertEq(token.allowance(DEPLOYER, BOB), 42);
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(DEPLOYER);
        token.approve(BOB, 100);
        token.approve(BOB, 7);
        vm.stopPrank();
        assertEq(token.allowance(DEPLOYER, BOB), 7);
    }

    function test_RevertWhen_approveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(DEPLOYER);
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowanceExactly() public {
        vm.prank(DEPLOYER);
        token.approve(BOB, 100 ether);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(DEPLOYER, CAROL, 60 ether);
        vm.prank(BOB);
        assertTrue(token.transferFrom(DEPLOYER, CAROL, 60 ether));

        assertEq(token.balanceOf(CAROL), 60 ether);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - 60 ether);
        assertEq(token.balanceOf(BOB), 0, "the spender must not receive anything");
        assertEq(token.allowance(DEPLOYER, BOB), 40 ether);
    }

    function test_transferFromWithMaxAllowanceDoesNotDecrease() public {
        vm.prank(DEPLOYER);
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        token.transferFrom(DEPLOYER, CAROL, 1 ether);
        assertEq(token.allowance(DEPLOYER, BOB), type(uint256).max);
    }

    function test_RevertWhen_transferFromWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, STRANGER, 0, 1));
        vm.prank(STRANGER);
        token.transferFrom(DEPLOYER, STRANGER, 1);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY);
    }

    function test_RevertWhen_transferFromExceedsAllowance() public {
        vm.prank(DEPLOYER);
        token.approve(BOB, 5);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 5, 6));
        vm.prank(BOB);
        token.transferFrom(DEPLOYER, CAROL, 6);
    }

    function test_RevertWhen_transferFromExceedsBalanceDespiteAllowance() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 10);
        vm.prank(ALICE);
        token.approve(BOB, 100);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 10, 11));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 11);
    }

    function test_RevertWhen_deployerUsesTransferFromOnHolderWithoutApproval() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, DEPLOYER, 0, 1));
        vm.prank(DEPLOYER);
        token.transferFrom(ALICE, DEPLOYER, 1);
        assertEq(token.balanceOf(ALICE), 1 ether);
    }

    // ---------------------------------------------------------------------------------------------
    // No privileged paths
    // ---------------------------------------------------------------------------------------------

    function test_noMintPathExists() public {
        string[6] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setMinter(address)",
            "initialize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], STRANGER, type(uint128).max);
            vm.prank(STRANGER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(DEPLOYER);
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(STRANGER), 0);
    }

    function test_noOwnerOrAdminSurface() public {
        string[9] memory signatures = [
            "owner()",
            "transferOwnership(address)",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "freeze(address)",
            "burnFrom(address,uint256)",
            "burn(uint256)",
            "upgradeTo(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], DEPLOYER, true);
            vm.prank(DEPLOYER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }
    }

    function test_holderStillTransfersAfterPrivilegedCallsAreAttempted() public {
        vm.prank(DEPLOYER);
        token.transfer(ALICE, 100 ether);
        string[4] memory signatures = ["pause()", "freeze(address)", "setBlocked(address,bool)", "seize(address)"];
        for (uint256 i; i < signatures.length; ++i) {
            vm.prank(DEPLOYER);
            (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], ALICE, true));
            ok;
        }
        assertEq(token.balanceOf(ALICE), 100 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 50 ether));
        assertEq(token.balanceOf(BOB), 50 ether);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "DELEGATECALL");
                assertTrue(op != 0xF2, "CALLCODE");
                assertTrue(op != 0xFF, "SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Launch flows: the factory pays out the swarm share, the remainder and the pool seed in full
    // ---------------------------------------------------------------------------------------------

    function test_launchFlowsArriveWhole() public {
        address distributor = address(0xD157);
        address claimant = address(0xC1A1);
        address remainderTo = 0x612a9bB008e16ef2D24f41DAe9Fc661831d93367;
        address poolManager = address(0x9001);

        uint256 swarm = SUPPLY * 1_000 / 10_000;
        uint256 pool = SUPPLY * 8_500 / 10_000;
        uint256 remainder = SUPPLY - swarm - pool;

        vm.startPrank(DEPLOYER);
        assertTrue(token.transfer(distributor, swarm));
        assertTrue(token.transfer(poolManager, pool));
        assertTrue(token.transfer(remainderTo, remainder));
        vm.stopPrank();

        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(poolManager), pool);
        assertEq(token.balanceOf(remainderTo), remainder);
        assertEq(token.balanceOf(DEPLOYER), 0);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(claimant), swarm);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz: conservation and exactness
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupplyAndIsExact(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != DEPLOYER);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(DEPLOYER);
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - amount);
        assertEq(token.balanceOf(to) + token.balanceOf(DEPLOYER), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRevertsAboveBalance(uint256 held, uint256 extra) public {
        held = bound(held, 0, SUPPLY - 1);
        extra = bound(extra, 1, SUPPLY - held);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, held);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, held + extra)
        );
        vm.prank(ALICE);
        token.transfer(BOB, held + extra);
    }

    function testFuzz_transferFromIsExactAndSpendsAllowance(address spender, uint256 allowed, uint256 spent) public {
        vm.assume(spender != address(0) && spender != DEPLOYER && spender != CAROL);
        allowed = bound(allowed, 0, SUPPLY);
        spent = bound(spent, 0, allowed);
        vm.prank(DEPLOYER);
        token.approve(spender, allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(DEPLOYER, CAROL, spent));
        assertEq(token.balanceOf(CAROL), spent);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - spent);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(DEPLOYER, spender), allowed - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromRevertsAboveAllowance(uint256 allowed, uint256 extra) public {
        allowed = bound(allowed, 0, SUPPLY - 1);
        extra = bound(extra, 1, SUPPLY - allowed);
        vm.prank(DEPLOYER);
        token.approve(BOB, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, allowed, allowed + extra)
        );
        vm.prank(BOB);
        token.transferFrom(DEPLOYER, CAROL, allowed + extra);
    }

    function testFuzz_chainOfTransfersConservesSupply(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, a);
        c = bound(c, 0, b);
        vm.prank(DEPLOYER);
        token.transfer(ALICE, a);
        vm.prank(ALICE);
        token.transfer(BOB, b);
        vm.prank(BOB);
        token.transfer(CAROL, c);
        assertEq(token.balanceOf(DEPLOYER), SUPPLY - a);
        assertEq(token.balanceOf(ALICE), a - b);
        assertEq(token.balanceOf(BOB), b - c);
        assertEq(token.balanceOf(CAROL), c);
        assertEq(
            token.balanceOf(DEPLOYER) + token.balanceOf(ALICE) + token.balanceOf(BOB) + token.balanceOf(CAROL), SUPPLY
        );
        assertEq(token.totalSupply(), SUPPLY);
    }
}
