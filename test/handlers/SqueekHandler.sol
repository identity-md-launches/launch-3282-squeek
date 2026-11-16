// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SqueekToken} from "src/SqueekToken.sol";

/// @notice Drives a closed set of holders through successful and rejected ERC-20 operations.
/// @dev Ghost accounting comes from the fixture and requested operations, never from token getters.
///      Unexpected call results latch a failure instead of reverting the handler: Foundry's default
///      invariant runner may discard a reverted handler, which must not hide a token regression.
contract SqueekHandler is Test {
    uint256 public constant ACTOR_COUNT = 5;
    uint256 private constant SUPPLY = 1_000_000_000 ether;

    SqueekToken public immutable token;
    address[5] public actors;
    mapping(address => uint256) public initialBalance;
    mapping(address => uint256) public received;
    mapping(address => uint256) public sent;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    bool public unexpectedOutcome;
    bytes public firstUnexpectedCall;
    bytes public firstUnexpectedReturn;
    uint256 public successfulCalls;
    uint256 public rejectedCalls;
    uint256 public positiveTransfers;

    constructor(SqueekToken token_, address[5] memory actors_, uint256[5] memory balances_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            initialBalance[actors_[i]] = balances_[i];
        }
    }

    function expectedBalance(address actor) public view returns (uint256) {
        return initialBalance[actor] + received[actor] - sent[actor];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), _amount(amountSeed, expectedBalance(from)));
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), expectedBalance(from));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        uint256 amount;
        if (mode % 4 == 1) amount = type(uint256).max;
        else if (mode % 4 == 2) amount = type(uint256).max - 1;
        else if (mode % 4 == 3) amount = bound(amountSeed, 0, SUPPLY);
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    /// @dev Uses an existing approval, so sequential calls exercise exhaustion and overwrites.
    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 available = expectedBalance(owner);
        uint256 allowed = expectedAllowance[owner][spender];
        if (allowed < available) available = allowed;
        _spend(owner, spender, _actor(toSeed), _amount(amountSeed, available));
    }

    /// @dev Ensures meaningful delegated transfers even before random standalone approvals line up.
    function approveAndSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed, bool unlimited)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(amountSeed, expectedBalance(owner));
        if (_approve(owner, spender, unlimited ? type(uint256).max : amount)) {
            _spend(owner, spender, _actor(toSeed), amount);
        }
    }

    function roundTrip(uint256 fromSeed, uint256 peerSeed, uint256 amountSeed) external {
        uint256 fromIndex = bound(fromSeed, 0, ACTOR_COUNT - 1);
        address from = actors[fromIndex];
        address peer = actors[(fromIndex + bound(peerSeed, 1, ACTOR_COUNT - 1)) % ACTOR_COUNT];
        uint256 amount = _amount(amountSeed, expectedBalance(from));
        if (_transfer(from, peer, amount)) _transfer(peer, from, amount);
    }

    function rejectOverspend(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance(from);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        _call(
            from,
            abi.encodeCall(token.transfer, (_actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function revokeAndRejectSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (!_approve(owner, spender, 0)) return;
        _call(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    /// @dev The allowance update inside transferFrom must roll back when the later balance check fails.
    function rejectInsufficientBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = expectedBalance(owner);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        if (!_approve(owner, spender, amount)) return;
        _call(
            spender,
            abi.encodeCall(token.transferFrom, (owner, _actor(toSeed), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount)
        );
    }

    function rejectZeroRecipient(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        address owner = _actor(ownerSeed);
        uint256 amount = _amount(amountSeed, expectedBalance(owner));
        bytes memory error = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            address spender = _actor(spenderSeed);
            if (!_approve(owner, spender, amount)) return;
            _call(spender, abi.encodeCall(token.transferFrom, (owner, address(0), amount)), error);
        } else {
            _call(owner, abi.encodeCall(token.transfer, (address(0), amount)), error);
        }
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        _call(
            _actor(ownerSeed),
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[bound(seed, 0, ACTOR_COUNT - 1)];
    }

    /// @dev Deliberately frequent zero, one-unit and entire-balance operations alongside general amounts.
    function _amount(uint256 seed, uint256 maximum) private pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return maximum == 0 ? 0 : 1;
        if (seed % 4 == 2) return maximum;
        return bound(seed, 0, maximum);
    }

    function _approve(address owner, address spender, uint256 amount) private returns (bool) {
        if (!_call(owner, abi.encodeCall(token.approve, (spender, amount)), "")) return false;
        expectedAllowance[owner][spender] = amount;
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private returns (bool) {
        if (!_call(from, abi.encodeCall(token.transfer, (to, amount)), "")) return false;
        _recordMovement(from, to, amount);
        return true;
    }

    function _spend(address owner, address spender, address to, uint256 amount) private {
        if (!_call(spender, abi.encodeCall(token.transferFrom, (owner, to, amount)), "")) return;
        if (expectedAllowance[owner][spender] != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        _recordMovement(owner, to, amount);
    }

    function _recordMovement(address from, address to, uint256 amount) private {
        sent[from] += amount;
        received[to] += amount;
        if (amount != 0) ++positiveTransfers;
        // Also check intermediate steps of round trips so a later transfer cannot mask an error.
        if (token.balanceOf(from) != expectedBalance(from) || token.balanceOf(to) != expectedBalance(to)) {
            unexpectedOutcome = true;
        }
    }

    function _call(address caller, bytes memory data, bytes memory expectedError) private returns (bool) {
        vm.prank(caller);
        (bool ok, bytes memory returned) = address(token).call(data);
        bool shouldSucceed = expectedError.length == 0;
        bytes memory expectedReturn = shouldSucceed ? abi.encode(true) : expectedError;
        bool matched = ok == shouldSucceed && keccak256(returned) == keccak256(expectedReturn);
        if (!matched) {
            if (!unexpectedOutcome) {
                firstUnexpectedCall = data;
                firstUnexpectedReturn = returned;
            }
            unexpectedOutcome = true;
        }
        if (ok) ++successfulCalls;
        else ++rejectedCalls;
        return matched && ok;
    }
}
