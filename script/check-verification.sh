#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Klima Protocol
# SPDX-License-Identifier: MIT
# Compare a fresh build against the files under verification/.
set -euo pipefail
cd "$(dirname "$0")/.."

ARTIFACT=out/KlimaConduitExecutor.sol/KlimaConduitExecutor.json
HASHES=verification/bytecode-hashes.json
INPUT=verification/KlimaConduitExecutor.standard-input.json
[ -f "$ARTIFACT" ] || { echo "::error::$ARTIFACT missing; run forge build" >&2; exit 1; }
[ -f "$HASHES" ] || { echo "::error::$HASHES missing; run forge script script/Hashes.s.sol" >&2; exit 1; }
status=0

expect() {
  local recorded
  recorded=$(jq -r "$1 // \"\"" "$HASHES")
  if [ "$recorded" != "$2" ]; then
    echo "::error::$1: recorded '$recorded', built '$2'" >&2
    status=1
  else
    echo "$1 ok"
  fi
}

creation=$(jq -r '.bytecode.object' "$ARTIFACT")
expect .runtimeTemplateKeccak "$(cast keccak "$(jq -r '.deployedBytecode.object' "$ARTIFACT")")"
expect .creationCodeKeccak "$(cast keccak "$creation")"
expect .solc "$(jq -r '.metadata.compiler.version' "$ARTIFACT")"

args=$(cast abi-encode 'constructor(address,address,address)' \
  "$(jq -r .deployment.safe "$HASHES")" "$(jq -r .deployment.conduit "$HASHES")" "$(jq -r .deployment.keeper "$HASHES")")
expect .deployment.constructorArgs "$args"
expect .deployment.address "$(cast create2 --deployer "$(jq -r .create2Deployer "$HASHES")" --salt "$(jq -r .salt "$HASHES")" --init-code "${creation}${args#0x}" | cut -f1)"

projection='{language, sources, settings: (.settings | {optimizer, evmVersion, viaIR: (.viaIR // false), metadata, remappings: (.remappings // [])})}'
current=$(forge verify-contract --show-standard-json-input 0x0000000000000000000000000000000000000001 src/KlimaConduitExecutor.sol:KlimaConduitExecutor | jq -S "$projection")
if [ "$current" != "$(jq -S "$projection" "$INPUT")" ]; then
  echo "::error::$INPUT is stale" >&2
  status=1
else
  echo "$INPUT ok"
fi

exit $status
