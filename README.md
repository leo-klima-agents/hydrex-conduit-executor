<!--
SPDX-FileCopyrightText: 2026 Klima Protocol
SPDX-License-Identifier: MIT
-->

# KlimaConduitExecutor

A 65-line immutable Safe module that lets one HSM-held keeper key call two functions on Hydrex's Klima "Carbon
Impact" conduit on behalf of the Klima Safe, and nothing else. Hydrex grants the conduit's `EXECUTOR_ROLE` to
the Safe rather than to a key; a Safe cannot be driven by an EOA on a schedule; this contract is the bridge.
It holds no funds, has no storage, no owner, no setters and no upgrade path.

The whole mechanism is `_exec` in [`src/KlimaConduitExecutor.sol`](src/KlimaConduitExecutor.sol): check
`msg.sender == KEEPER`, ABI-encode the identical call to `CONDUIT`, and hand it to
`SAFE.execTransactionFromModuleReturnData(CONDUIT, 0, data, Call)`. A failed call re-raises the conduit's own
revert data so the keeper sees the real reason.

## What it can do to the Safe

It asks the Safe for exactly two calls, both plain `Call`s to the one fixed `CONDUIT` with zero value.

- `vote(pools, weights)`, which the conduit forwards to Hydrex's Voter as `Voter.vote(pools, weights)`. The
  Voter reads the conduit's delegated earning power at the epoch start, rejects dead gauges and votes that
  exceed that power, and attributes every reward to the delegators' veNFTs.
- `claimSwapAndDistribute(tokenId, targets, swaps, fees, bribes, claimTokens, retireTonnes, maxKvcmIn)`, which
  claims one delegator's rewards into the conduit, swaps them through the conduit's approved routers into its
  distribution tokens, optionally retires carbon, and pays the veNFT owner or their configured payout
  recipient. The conduit checks the routers, requires an output-token balance increase per swap and bounds
  the retirement; nothing passes through this contract or the Safe.

Both entrypoints revert with `NotKeeper()` for any other caller. The module is bound to the conduit twice:
by the `CONDUIT` immutable and by the eight-argument `KlimaVeTokenConduit` claim signature.

## What it cannot do

- **Call anything else.** `to` is always `CONDUIT`, `value` is always zero, `operation` is always `Call`,
  and the calldata is one of two selectors this contract encodes itself. The Safe's owners, its other
  assets and the Safe configuration are out of reach; there is no `delegatecall` path.
- **Be administered or upgraded.** No owner, no setters, no proxy, no `receive`, no `fallback`, no storage.
  The three addresses are immutables set once by the constructor, which rejects zeros.
- **Widen its own permissions.** Whether the Safe may call the conduit is the conduit's `EXECUTOR_ROLE`,
  granted and revoked by Hydrex's `DEFAULT_ADMIN_ROLE`. Whether this module may act for the Safe is the
  Safe's module list, changed only by a Safe transaction. Either side can cut it off; the module cannot
  restore itself.
- **Lose the keeper's reason.** A conduit or Voter revert comes back with its original data. A failure without
  data becomes `ExecutionFailed()`. The Safe's own reverts, such as `GS104` when the module is not enabled,
  propagate unchanged.
- **Be reentered to any effect.** There is no lock because there is nothing to protect: both entrypoints
  are keeper-gated, a hostile token reached through a swap cannot call as the keeper, and the module has no
  state.
- **Hold ETH or tokens.** Plain transfers and value-carrying calls revert. Rewards flow from the bribe
  contracts to the conduit to the recipient; the module and the Safe never touch them.

## Trust boundaries that stay with Hydrex

The conduit's admin can change distribution tokens, routers, retirement config, treasury fee (at most 1%),
payout recipients and can withdraw stray balances. None of that runs through this module, and none of it is
reachable from the keeper. The keeper key can only choose *which pools to vote for* and *when to run a claim
with which swap calldata*, both within the conduit's and Voter's own checks.

## Deployment

| | |
|---|---|
| Network | Base |
| `SAFE` | [`0xa79cd47655156b299762DFE92A67980805ce5a31`](https://basescan.org/address/0xa79cd47655156b299762DFE92A67980805ce5a31), Klima Safe, 3-of-5, Safe 1.3.0 L2 |
| `CONDUIT` | [`0xde91885cf35ac57df0c4a75c16862127dbe8317c`](https://basescan.org/address/0xde91885cf35ac57df0c4a75c16862127dbe8317c#code), `KlimaVeTokenConduit`, verified, not upgradeable |
| `KEEPER` | **placeholder** `0x000000000000000000000000000000000000dEaD` until the HSM key exists, see below |
| Method | CREATE2 through the default deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C` |
| Salt | `keccak256("klimaprotocol.com/KlimaConduitExecutor/v1")` |

Not deployed yet. `KEEPER` is an immutable, so the HSM key must exist first. When it does: set `KEEPER` in
`script/Deploy.s.sol`, run `forge build && forge script script/Hashes.s.sol` to refresh `verification/`,
commit, then

```
forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --broadcast --ledger   # or --private-key
forge verify-contract <address> src/KlimaConduitExecutor.sol:KlimaConduitExecutor --chain base --watch
forge verify-contract <address> src/KlimaConduitExecutor.sol:KlimaConduitExecutor --chain base --verifier sourcify
```

A module deployed with the placeholder is inert, since no one holds that key, and would simply be redeployed
under a new salt. The address is recorded in `verification/bytecode-hashes.json`, and `test/Deploy.t.sol` pins
it to the constants in `script/Deploy.s.sol`.

## Wiring, outside this repo

1. **Hydrex** grants the role: `conduit.grantRole(EXECUTOR_ROLE, SAFE)` from the admin EOA
   `0x74266f2b206d1359b83fc74949ef07176fb3ae03`. `EXECUTOR_ROLE` is `keccak256("EXECUTOR_ROLE")`. Hydrex may
   also revoke its outgoing keeper `0x1681b1d40ab2fb81f8a1dd28b56baffbb869a214`.
2. **The Safe owners** send one Safe transaction: `enableModule(<module address>)` to the Safe itself.
3. **The keeper** casts the first vote through the module with a human watching `Voter.poolVote(CONDUIT, i)`
   and `Voter.votes(CONDUIT, pool)`. Votes are per epoch, Thursday 00:00 UTC, and do not carry over.

Undo is symmetric: Hydrex revokes the role, or the Safe owners send `disableModule(prevModule, module)`.

## Upstream pins

- Conduit: the Sourcify exact-match source of the live contract is vendored under `test/upstream/hydrex/`.
  `src/interfaces/IKlimaVeTokenConduit.sol` re-declares its two `EXECUTOR_ROLE` members and imports nothing.
  `test/Fork.t.sol` pins the conduit's runtime code hash on Base.
- Safe: `ModuleManager.sol` and its three dependencies from safe-smart-account `v1.3.0` are vendored under
  `test/upstream/safe/`. `src/interfaces/ISafeModuleManager.sol` re-declares the one member it calls.
  `test/Fork.t.sol` pins the Safe's singleton, `GnosisSafeL2` 1.3.0 at `0xfb1bffC9d739B8D520DaF37dF666da4C687191EA`.
- `test/Selectors.t.sol` asserts `0x6f816a20` (`vote`), `0x786fb402` (`claimSwapAndDistribute`) and
  `0x5229073f` (`execTransactionFromModuleReturnData`) against literals, `keccak256` of the signatures, the
  vendored files and the table in `test/upstream/UPSTREAM.md`, and that the conduit gates exactly two members
  on `EXECUTOR_ROLE`.

If Hydrex deploys a new conduit or the Safe migrates to another singleton, the pins fail CI and a corrected
contract is deployed under a new salt.

## Reviewing

- `src/KlimaConduitExecutor.sol` and `src/interfaces/` are the whole surface; the rest is tests, tooling and
  records.
- `forge test` runs 46 tests against `test/mocks/`, which mirror the Safe's `GS104` module gate and return-data
  path and the conduit's OpenZeppelin v5 role gate: the keeper reaches the conduit with exact calldata, fuzzed
  over arrays; every other caller reverts; conduit reverts bubble with their original data, fuzzed; a Safe
  returning `false` reverts; ETH and unknown selectors are rejected; no storage is written.
- `BASE_RPC_URL=<archive rpc> forge test --match-path test/Fork.t.sol` runs 13 more on Base at pinned blocks:
  Hydrex's grant and the Safe's `enableModule` are pranked, then the keeper votes through the module and the
  live Voter records it; the keeper's own 2026-09-09 vote
  ([tx](https://basescan.org/tx/0x6766749800fbc54c5cf134b3fd15a2456a57115b8319be995a48693406121607)) is replayed
  one block earlier through the module and produces the same three `Voted` weights; a claim for a Safe-owned
  veNFT completes; the module fails before Hydrex's grant, before the Safe enables it, and for any other caller.
  CI runs this job only when the `BASE_RPC_URL` secret is set.
- `forge build --sizes` gives a 2,477-byte runtime. Two clean builds are byte-identical, and `verification/`
  holds the standard JSON input and the bytecode hashes CI checks on every commit.
- Compiler: solc 0.8.36, `prague`, optimizer at 1,000,000 runs, via-IR, ipfs metadata. Via-IR because the
  eight-argument claim signature is too deep for the legacy codegen; Hydrex built the conduit via-IR for the
  same reason.

## Known limitations

- One keeper, fixed at deployment. Rotating the HSM key means a new module (new salt), one Safe transaction
  to enable it and one to disable the old one.
- The module does not check epochs, pools or weights; the Voter does. A keeper bug votes wrong, not more.
- The keeper can call `claimSwapAndDistribute` for any delegator's veNFT with any swap calldata the conduit's
  routers accept. The conduit's output-token check bounds the damage of a bad route to a bad price, and
  rewards still go to that delegator, never to the keeper.
- Only the `KlimaVeTokenConduit` claim signature is supported; other Hydrex conduit types would need their own
  module.

## License

MIT, REUSE compliant. The vendored conduit source is MIT and the vendored Safe files are LGPL-3.0-only, all
reproduced unmodified, with their copyright holders recorded in `REUSE.toml`.
