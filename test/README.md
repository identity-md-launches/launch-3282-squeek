# Squeek test coverage

The existing `SqueekToken.t.sol` and `DeploySqueek.t.sol` remain the baseline for
metadata, initial supply, standard transfers, launch payout transfers and absent
administrative methods. The added suites exercise the real `SqueekToken` through
its public interface; no token storage is patched or balances minted by cheatcode.

`SqueekTokenEdges.t.sol` adds deterministic boundary and failure tests and seven
fuzz properties, each with 1,000 runs. Cases include constructor event cardinality
and contract deployers, one minor unit, zero amounts, full supply, maximum integers,
self-transfers, repeated spending, approval replacement/revocation, allowance
isolation, rollback after failed transfers, and exact round trips. Fuzz inputs use
`bound`; approvals also exercise unrestricted `uint256` values.

## Stateful properties

`SqueekTokenInvariant.t.sol` targets only the eleven action selectors on
`handlers/SqueekHandler.sol`. Each of 256 sequences has 128 calls. Five holders
include the deployer, three funded recipients, and one initially empty account.
All destinations stay within this set, making the sum of balances exhaustive for
this campaign. Random roles may coincide, exercising self-approval, self-transfer,
and a spender receiving tokens. Transfers into the token itself are covered
separately by a unit test; they are not a burn.

The five discovery passes from the supplied invariant guidance yield these
properties, grounded in this token's fixed-supply and fee-free ERC-20 behavior:

| Review pass | Property and source basis | Checks |
| --- | --- | --- |
| Conservation | Constructor creates exactly `1e27` units (`src/SqueekToken.sol:24–28`); transfers neither mint nor burn (`ERC20.sol:159–206`). | Constant supply; sum of holder balances; each holder equals initial balance plus receipts minus sends. |
| State transitions | `approve` replaces only the caller's allowance (`ERC20.sol:120–123,273–284`); delegated spending consumes finite approval (`ERC20.sol:294–304`). | All 25 owner/spender pairs match ghost allowances, including overwrite, revocation and infinite approval. |
| Round trips | Exact integer transfers have no fee or conversion (`ERC20.sol:176–206`). | Forward and reverse transfers restore both balances; intermediate balances are also checked; repeated cycles are fuzzed separately. |
| Adversarial sequences | Transfers require balance and delegated authorization (`ERC20.sol:142–146,181–184,294–304`). | Overdraws, revoked approvals, zero destinations, and zero spenders fail; failed delegated transfers preserve their approval. Full-balance transfers remain possible. |
| Token semantics | Zero and self-transfers conserve value; zero address cannot receive transfers; maximum approval is not consumed. | Frequent zero/one/full-amount operations, exact call results/errors, zero-address balance, and immutable metadata. |

Ghost balances use cumulative requested receipts and sends, seeded from the known
fixture distribution. Ghost allowances use successful approvals and spending.
Neither is resynchronized from the token's getters. Bounds use the ghost state,
so an incorrect token balance cannot silently narrow subsequent test inputs.
Unexpected reverts, success, or return data latch a failure checked by an invariant;
the handler does not rely on `fail_on_revert` being enabled. A deterministic
handler sequence checks every action and proves that successful nonzero transfers
and expected failures are reached. The randomized campaign also reports its action
counts and discarded/reverted calls.

## Gas and scope

The token and its inherited `ERC20`/`Context` implementation contain no `gasleft()`
branches, fixed-gas external calls, or caught external-call failures. There is no
production entry point requiring the supplied wallet-gas helper. The handler's
low-level calls are test instrumentation, not production behavior.

No fork is needed or used. The supplied protected launch checks were reviewed for
their required token behavior; this suite does not claim to run their separate
factory/Uniswap infrastructure. The original launch-flow test checks exact token
movements among those roles.

## Reproduction

All dependencies are already vendored. Build artifacts can be kept in scratch:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0xd9bf38ed2d4d1d22479120a6a4e15e525483ce57d8f07a4bde73e18844c9d3c7 forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

The only inline settings are fuzz runs, invariant runs, and invariant depth. The
tests also run with ordinary `forge build` and `forge test` using repository defaults.
