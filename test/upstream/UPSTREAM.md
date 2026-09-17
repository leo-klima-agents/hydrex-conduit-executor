<!--
SPDX-FileCopyrightText: 2026 Léo de Souza
SPDX-License-Identifier: MIT
-->

# Vendored upstream fixtures

Byte-identical copies of the upstream files KlimaConduitExecutor is built against; `src/` never imports them.
The Safe files are self-contained and `test/Selectors.t.sol` compiles `ModuleManager.sol` to compare selectors.
The conduit imports OpenZeppelin and Hydrex interfaces that are not vendored, so `foundry.toml` skips it and the
test checks its `EXECUTOR_ROLE` members as text.

| Local file | Upstream | License |
|---|---|---|
| `hydrex/KlimaVeTokenConduit.sol` | Sourcify exact match of Base `0xde91885cf35ac57df0c4a75c16862127dbe8317c`, `contracts/conduits/KlimaVeTokenConduit.sol` | MIT |
| `safe/base/ModuleManager.sol` | safe-global/safe-smart-account `v1.3.0`, `contracts/base/ModuleManager.sol` | LGPL-3.0-only |
| `safe/base/Executor.sol` | safe-global/safe-smart-account `v1.3.0`, `contracts/base/Executor.sol` | LGPL-3.0-only |
| `safe/common/Enum.sol` | safe-global/safe-smart-account `v1.3.0`, `contracts/common/Enum.sol` | LGPL-3.0-only |
| `safe/common/SelfAuthorized.sol` | safe-global/safe-smart-account `v1.3.0`, `contracts/common/SelfAuthorized.sol` | LGPL-3.0-only |
| `keeper-key/keeper.json` | ldeso/hydrex-keeper-key `cdb829a`, `record/keeper.json` | MIT |
| `keeper-key/keeper.pem` | ldeso/hydrex-keeper-key `cdb829a`, `record/keeper.pem` | MIT |

- Conduit: verified on Sourcify (creation and runtime exact match, 2026-04-29) with solc `0.8.26+commit.8a97fa7a`,
  `cancun`, optimizer 200 runs, via-IR. Runtime `keccak256` on Base:
  `0x0d67cd335e3ae9cde256cf399f819a3ea2b9c248b0336840a3b20a2ee82c192e`, pinned by `test/Fork.t.sol`.
- Safe: https://github.com/safe-global/safe-smart-account at tag `v1.3.0`. The Klima Safe's singleton is
  `GnosisSafeL2` 1.3.0 at `0xfb1bffC9d739B8D520DaF37dF666da4C687191EA`, pinned by `test/Fork.t.sol`.
- Keeper: https://github.com/ldeso/hydrex-keeper-key writes `record/` from Cloud KMS key
  `projects/hydrex-keeper-key-bpzw/locations/us/keyRings/hydrex-keeper/cryptoKeys/hydrex-keeper-v1`, version 1,
  HSM, secp256k1. `script/Deploy.s.sol` reads `KEEPER` from the vendored `keeper.json`; `test/Deploy.t.sol` and
  `script/check-verification.sh` each re-derive the address from the vendored `keeper.pem`.
- Hashes: see `SHA256SUMS` (verified in CI with `sha256sum -c`)

```
948c9539e83442a3386e39beb4c0ecccb8b4e7b020c3f493a8ef860106506990  hydrex/KlimaVeTokenConduit.sol
63ac8b6e0556ab32dee207b168916751982f4dc20efb9544740f5e35ff3ce6a5  safe/base/ModuleManager.sol
87c8c6cb45069e68dfb58c2347e69b43ab8b5a31f34adcf5c0705b9f595a7815  safe/base/Executor.sol
9beffe49e2ddcc6548f16883c9333daa607a7d21eda1cc5b7af8cefef034f64c  safe/common/Enum.sol
24764612bf5539179a07a7655ec6ccb22eab6ffdd0b7c77730c79e1995b64326  safe/common/SelfAuthorized.sol
0924a6fe71c7e259ad3e8a0398bc7277d63af85ad47520cc3a6f509134cda2de  keeper-key/keeper.json
37051d3995a3525ed2033b37bf39a91e2d2d826caca177bba63d67a517baab9d  keeper-key/keeper.pem
```

## Selectors pinned from these files

| Member | Selector | Source |
|---|---|---|
| `vote(address[],uint256[])` | `0x6f816a20` | `KlimaVeTokenConduit` |
| `claimSwapAndDistribute(uint256,address[],bytes[],address[],address[],address[],uint256,uint256)` | `0x786fb402` | `KlimaVeTokenConduit` |
| `execTransactionFromModuleReturnData(address,uint256,bytes,uint8)` | `0x5229073f` | `ModuleManager` + `Enum.Operation` |

`EXECUTOR_ROLE` is `keccak256("EXECUTOR_ROLE")` =
`0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63`. These are the conduit's only two
members gated on it; the test counts the `onlyRole(EXECUTOR_ROLE)` occurrences.

## Refreshing the pin

```
# conduit, from Sourcify
curl -sS "https://sourcify.dev/server/v2/contract/8453/0xde91885cf35ac57df0c4a75c16862127dbe8317c?fields=sources" \
  | jq -r '.sources["contracts/conduits/KlimaVeTokenConduit.sol"].content' > test/upstream/hydrex/KlimaVeTokenConduit.sol
# Safe 1.3.0
T=v1.3.0
for f in base/ModuleManager base/Executor common/Enum common/SelfAuthorized; do
  curl -sSL -o test/upstream/safe/$f.sol https://raw.githubusercontent.com/safe-global/safe-smart-account/$T/contracts/$f.sol
done
# keeper record
C=cdb829a
for f in keeper.json keeper.pem; do
  curl -sSL -o test/upstream/keeper-key/$f https://raw.githubusercontent.com/ldeso/hydrex-keeper-key/$C/record/$f
done
(cd test/upstream && sha256sum hydrex/KlimaVeTokenConduit.sol safe/base/ModuleManager.sol safe/base/Executor.sol \
  safe/common/Enum.sol safe/common/SelfAuthorized.sol keeper-key/keeper.json keeper-key/keeper.pem > SHA256SUMS)
forge test --match-path 'test/{Selectors,Deploy}.t.sol'
```

The conduit is not upgradeable, so its file changes only if Hydrex deploys a new conduit; that is a new
`CONDUIT` immutable and a new salt. The keeper record changes only if a new key is created; that is a new
`KEEPER` immutable and a new salt. If a selector or record test fails after a refresh, fix `src/interfaces/` or
bump the salt, regenerate both files under `verification/` with `script/refresh-verification.sh`, and redeploy.
