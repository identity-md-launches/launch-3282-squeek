# Squeek (SQK)

A fixed-supply ERC-20 token for launch on Ethereum mainnet (chain id 1).

| Property        | Value                                                  |
| --------------- | ------------------------------------------------------ |
| Contract        | `SqueekToken` (`src/SqueekToken.sol`)                  |
| Name            | Squeek                                                 |
| Symbol          | SQK                                                    |
| Decimals        | 18                                                     |
| Total supply    | 1,000,000,000 SQK = `1000000000000000000000000000` minor units (1e27) |
| Mint            | Once, in the constructor, all of it to `msg.sender` (the deployer) |
| Constructor args| None                                                   |
| Owner / admin   | None                                                   |

## Behaviour

`SqueekToken` is a thin wrapper over OpenZeppelin's `ERC20` (v5.4.0, vendored in
`lib/openzeppelin/`). It adds only the constants for name, symbol, decimals and supply, and the
one-time mint in the constructor.

- Every `transfer` and `transferFrom` moves exactly the amount requested. There is no fee, tax,
  reflection or burn on transfer, so the launch flows (factory to distributor, distributor to
  claimant, factory to pool, pool to trader, trader to pool) all arrive whole.
- `transferFrom` moves tokens only from the `from` account and only within the allowance that
  account granted to `msg.sender`. An allowance of `type(uint256).max` is never decreased.
- There is no `mint`, `burn`, `burnFrom`, `pause`, blocklist, freeze, seize, upgrade or ownership
  function. The supply cannot grow or shrink and no address can move or lock another holder's
  balance. These absences are tested, not just asserted.
- The runtime bytecode contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT` (tested by an
  opcode scan of the deployed code).
- Transfers to the zero address, approvals to the zero spender, transfers above balance and
  `transferFrom` above allowance revert with the ERC-6093 custom errors
  (`ERC20InvalidReceiver`, `ERC20InvalidSpender`, `ERC20InsufficientBalance`,
  `ERC20InsufficientAllowance`).

## Assumptions

- The deployer is whichever account sends the creation transaction. At launch that is the project
  factory, which pays the whole supply out (the swarm's 10% to the launch's MerkleDistributor, 85%
  into the Uniswap v4 pool paired with IMD, and the remaining 5% to the requester's
  `remainderTo` address). The token does not know or care which address deployed it and has no
  exemption logic, because nothing in it needs exempting.
- The supply, name, symbol and decimals are compile-time constants. Changing any of them means
  deploying a new contract; there is no setter.
- No contract here holds user funds after launch. There is no "After launch" configuration: nothing
  has to be set by an owner, because there is no owner.
- The constructor makes no external calls and requires no other contract to exist, so it deploys on
  an empty chain exactly as it does on mainnet.

## Deployment parameters

- Compiler: `solc 0.8.26`, optimizer on with 200 runs, `via_ir = false`, `evm_version = cancun`,
  `bytecode_hash = "none"` (see `foundry.toml`). The launch compares deployed bytes without the
  metadata hash, so the build is reproducible from this configuration.
- Constructor arguments: none.
- Manifest values for the launch step (not written here; the manifest step writes `launch.json`):
  - `token.contract`: `SqueekToken`
  - `token.name`: `Squeek`
  - `token.symbol`: `SQK`
  - `token.decimals`: `18`
  - `token.totalSupply`: `1000000000000000000000000000`
  - `token.constructorArgs`: `[]`
  - `contracts`: `[]` (no application contracts)
- Pool and economics come from the launch policy and the requester's order, and are copied into
  the manifest by the manifest step: pair IMD (`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`), fee
  `12500`, tick spacing `60`, `poolBps` 8500, `initialMarketCapWei` 3,600 IMD, `remainderTo`
  `0x612a9bb008e16ef2d24f41dae9fc661831d93367`.

### Reference deploy script

`script/DeploySqueek.s.sol` is a reviewable reference for a manual deployment. Its `deploy()`
function takes no configuration (there is none) and is exercised directly by
`test/DeploySqueek.t.sol`. Its `run()` wraps `deploy()` in a broadcast and reads nothing from the
environment; the broadcaster is whatever account `forge script` is given on the command line. The
production launch is performed by the factory from the built bytecode, not by this script.

## Operational responsibilities

- **Holders** are responsible for their own keys. There is no recovery, freeze or clawback path for
  anyone, including the deployer.
- **The deployer** (the factory at launch) holds the entire supply the moment the constructor
  returns, and is responsible for distributing it. After it has transferred the tokens out it has no
  further power over the contract.
- **Nobody** can change the supply, the metadata or the transfer rules after deployment. Any such
  change requires a new token contract and a migration, which this project does not provide.
- **Explorer verification** of the deployed source belongs to the launch's deployer. Verify with
  `forge verify-contract` using this repository's `foundry.toml` so the compiler settings match.
- Tests passing is not a security audit. The token is a minimal wrapper over an audited library,
  but an independent adversarial review before release remains good practice.

## Layout

```
foundry.toml              compiler pins and build settings
remappings.txt            forge-std/ and @openzeppelin/contracts/ remappings
src/SqueekToken.sol       the token
script/DeploySqueek.s.sol reference deploy script
test/SqueekToken.t.sol    behaviour, failure and fuzz tests
test/DeploySqueek.t.sol   deploy script test
lib/forge-std/            forge-std v1.11.0 (vendored as plain files)
lib/openzeppelin/         OpenZeppelin Contracts v5.4.0 (vendored as plain files)
```

Dependencies are committed as ordinary files, not git submodules, so the project builds offline.
`lib/openzeppelin-contracts/` is an empty leftover of the upstream clone that the build sandbox
could not remove; it is git-ignored and not referenced by any remapping.

## Checks

```
forge build
forge test
forge fmt --check
```

All three pass locally with `solc 0.8.26`. The fuzz tests were also run with the verifier's seed
(`FOUNDRY_FUZZ_SEED=0xd9bf38ed2d4d1d22479120a6a4e15e525483ce57d8f07a4bde73e18844c9d3c7`). Slither
was not run on this machine because it is not provided here.
