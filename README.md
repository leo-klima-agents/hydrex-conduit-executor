<!--
SPDX-FileCopyrightText: 2026 Léo de Souza
SPDX-License-Identifier: MIT
-->

# hydrex-conduit-executor

`KlimaVeTokenConduitExecutor` is an immutable Safe module that lets one HSM-held keeper key call two functions on
Hydrex's `KlimaVeTokenConduit` (the Klima "Carbon Impact" conduit) on behalf of the executor Safe, and nothing else.
Hydrex grants the conduit's `EXECUTOR_ROLE` to the Safe, and a Safe cannot be driven by an EOA on a schedule; this
contract bridges the two. It has no storage, owner, setters, funds or upgrade path.

The key lives in Google Cloud KMS, defined by [hydrex-keeper-key](https://github.com/ldeso/hydrex-keeper-key). The
keeper service that signs with it is `hydrex-keeper`.

The whole mechanism is `_exec` in [`src/KlimaVeTokenConduitExecutor.sol`](src/KlimaVeTokenConduitExecutor.sol):
check `msg.sender == KEEPER`, then `SAFE.execTransactionFromModuleReturnData(CONDUIT, 0, data, Call)` with calldata
the contract encodes itself. A failed call re-raises the conduit's revert data.

## What it can do

- `vote(pools, weights)`: the conduit forwards it to Hydrex's Voter, which checks gauge liveness and the conduit's
  delegated voting power.
- `claimSwapAndDistribute(tokenId, targets, swaps, fees, bribes, claimTokens, retireTonnes, maxKvcmIn)`: the conduit
  claims one delegator's rewards, swaps them through its approved routers, optionally retires carbon and pays the
  veNFT owner or their payout recipient. Nothing passes through this contract or the Safe.

Any other caller gets `NotKeeper()`.

## What it cannot do

- **Call anything else.** `to` is always `CONDUIT`, `value` zero, `operation` `Call`, and the calldata one of two
  selectors. No `delegatecall` path; the Safe's owners, assets and configuration are out of reach.
- **Be administered.** No owner, setters, proxy, `receive`, `fallback` or storage. The constructor rejects zero
  addresses and requires code at `SAFE` and `CONDUIT`, since a `Call` to an empty address succeeds silently.
- **Widen its permissions.** Hydrex controls `EXECUTOR_ROLE` on the conduit; the Safe owners control the module
  list. Either side can cut it off.
- **Hold funds.** Plain transfers and value-carrying calls revert.

Reentrancy needs no lock: both entrypoints are keeper-gated and the module has no state.

## Trust boundaries that stay with Hydrex

The conduit's admin can change distribution tokens, routers, retirement config, treasury fee (at most 1%) and
payout recipients, and can withdraw stray balances. None of that is reachable from the keeper, which only chooses
which pools to vote for and when to claim with which swap calldata, within the conduit's and Voter's checks.

## Deployment

| | |
|---|---|
| Network | Base |
| `SAFE` | [`0x17f513C024C1C67db050258ba569c714a9CF1B12`](https://basescan.org/address/0x17f513C024C1C67db050258ba569c714a9CF1B12), executor Safe, 2-of-3, Safe 1.4.1 L2 |
| `CONDUIT` | [`0xde91885cf35ac57df0c4a75c16862127dbe8317c`](https://basescan.org/address/0xde91885cf35ac57df0c4a75c16862127dbe8317c#code), `KlimaVeTokenConduit`, verified, not upgradeable |
| `KEEPER` | [`0x625CF6663d9D090535FBd57680bFFE6fA0262434`](https://basescan.org/address/0x625CF6663d9D090535FBd57680bFFE6fA0262434), Cloud KMS HSM key `hydrex-keeper-v1` version 1, from the [record](https://github.com/ldeso/hydrex-keeper-key/blob/cdb829a/record/keeper.json) |
| Method | CREATE2 through the default deployer `0x4e59b44847b379578588920cA78FbF26c0B4956C` |
| Salt | `keccak256("klimaprotocol.com/KlimaVeTokenConduitExecutor/v1")` |

Not deployed yet; the predicted address is in `verification/bytecode-hashes.json`. `script/Deploy.s.sol` reads
`KEEPER` from `test/upstream/keeper/keeper.json`, a byte-for-byte copy of the hydrex-keeper-key record, and
`test/Deploy.t.sol` and `script/check-verification.sh` re-derive it from the public key vendored next to it.

```
forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --broadcast --ledger   # or --private-key
ARGS=$(jq -r .deployment.constructorArgs verification/bytecode-hashes.json)
forge verify-contract <address> src/KlimaVeTokenConduitExecutor.sol:KlimaVeTokenConduitExecutor --chain base \
  --constructor-args $ARGS --license-type MIT --watch
forge verify-contract <address> src/KlimaVeTokenConduitExecutor.sol:KlimaVeTokenConduitExecutor --chain base \
  --verifier sourcify
```

Etherscan records the license separately from the SPDX header, hence `--license-type`; Sourcify reads it from the
source.

The CREATE2 address depends on the constructor arguments, so a new key or conduit means a new address under a new
salt. After changing the source or `script/Deploy.s.sol`, run `script/refresh-verification.sh`.

## Wiring, outside this repo

1. **Hydrex** calls `conduit.grantRole(EXECUTOR_ROLE, SAFE)` from the admin EOA
   `0x74266f2b206d1359b83fc74949ef07176fb3ae03`. Done on 2026-09-23
   ([tx](https://basescan.org/tx/0xf134ecbf1b704707d7a26465694cd0e5a8d1f37bbd8a59a095bc03bbbc0ab544)). Hydrex may
   revoke its outgoing keeper `0x1681b1d40ab2fb81f8a1dd28b56baffbb869a214` once the module has voted.
2. **The Safe owners** call `enableModule(<module address>)` on the Safe.
3. **hydrex-keeper-key** grants the keeper service's service account signing rights (`sh/grant.sh`).
4. **hydrex-keeper** casts the first vote with a human watching `Voter.poolVote(CONDUIT, i)` and
   `Voter.votes(CONDUIT, pool)`. Votes are per epoch (Thursday 00:00 UTC) and do not carry over.

To undo: Hydrex revokes the role, or the Safe owners call `disableModule(prevModule, module)`.

## Upstream pins

`test/upstream/` vendors the conduit source (Sourcify), Safe 1.4.1's `ModuleManager` and dependencies, and the
keeper record; see [`UPSTREAM.md`](test/upstream/UPSTREAM.md). `src/interfaces/` re-declares the members used and
imports nothing. `test/Selectors.t.sol` pins the selectors, and `test/Fork.t.sol` pins the conduit's code hash and
the Safe's singleton on Base. A new conduit, Safe singleton or keeper key fails CI and needs a new salt.

## Reviewing

- `src/` is the whole on-chain surface.
- `forge test` runs the unit suite against `test/mocks/`, which mirror the Safe's `GS104` gate and return-data path
  and the conduit's role gate.
- `BASE_RPC_URL=<archive rpc> forge test --match-path test/Fork.t.sol` runs against Base at pinned blocks: it wires
  the live Safe and conduit, votes and claims through the module, and replays the Safe owners' 2026-09-23 vote
  ([tx](https://basescan.org/tx/0x57a86aa659a3685446b471e59c351d41f3f52c33f7e5df1cf77cfa4457b6c7a3)) with an
  identical `Voted` weight. CI runs it only when the `BASE_RPC_URL` secret is set.
- Builds are reproducible; `verification/` holds the standard JSON input and bytecode hashes, checked in CI.
- Compiler: solc 0.8.37, `prague`, optimizer 1,000,000 runs, via-IR, ipfs metadata.

## Known limitations

- One keeper, fixed at deployment. Rotating it means a new module under a new salt and two Safe transactions.
- The module does not check epochs, pools or weights; the Voter does.
- The keeper can claim for any delegator's veNFT with any swap calldata the conduit's routers accept. The conduit's
  output-token check limits a bad route to a bad price, and rewards still go to the delegator.
- Only the `KlimaVeTokenConduit` claim signature is supported.

## License

MIT, REUSE compliant. The vendored conduit source and keeper record are MIT and the vendored Safe files are
LGPL-3.0-only, all unmodified, with their copyright holders recorded in `REUSE.toml`.
