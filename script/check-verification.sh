#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Léo de Souza
# SPDX-License-Identifier: MIT
# Compare a fresh build against the files under verification/.
set -euo pipefail
cd "$(dirname "$0")/.."

ARTIFACT=out/HydrexCarbonImpactExecutor.sol/HydrexCarbonImpactExecutor.json
HASHES=verification/bytecode-hashes.json
INPUT=verification/HydrexCarbonImpactExecutor.standard-input.json
[ -f "$ARTIFACT" ] || { echo "::error::$ARTIFACT missing; run forge build" >&2; exit 1; }
[ -f "$HASHES" ] || { echo "::error::$HASHES missing; run script/refresh-verification.sh" >&2; exit 1; }
[ -f "$INPUT" ] || { echo "::error::$INPUT missing; run script/refresh-verification.sh" >&2; exit 1; }
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

# The record must describe the constants in script/Deploy.s.sol and the vendored keeper record, not merely be
# self-consistent. The keeper address is re-derived from the vendored public key: DER, last 64 bytes, keccak256.
KEEPER_DIR=test/upstream/keeper-key
constant() { grep -oE "constant $1 = 0x[0-9a-fA-F]{40}" script/Deploy.s.sol | grep -oE '0x[0-9a-fA-F]{40}'; }
expect .deployment.safe "$(cast to-check-sum-address "$(constant SAFE)")"
expect .deployment.conduit "$(cast to-check-sum-address "$(constant CONDUIT)")"
expect .deployment.keeper "$(cast to-check-sum-address "$(jq -r .address "$KEEPER_DIR/keeper.json")")"
der=$(mktemp)
openssl pkey -pubin -in "$KEEPER_DIR/keeper.pem" -outform DER -out "$der"
xy=$(tail -c 64 "$der" | od -An -v -tx1 | tr -d ' \n')
rm -f "$der"
expect .deployment.keeper "$(cast to-check-sum-address "0x$(cast keccak "0x$xy" | tr -d '\n' | tail -c 40)")"
expect .saltPreimage "$(grep -oE 'SALT_PREIMAGE = "[^"]+"' script/Deploy.s.sol | cut -d'"' -f2)"
expect .salt "$(cast keccak "$(jq -r .saltPreimage "$HASHES")")"

args=$(cast abi-encode 'constructor(address,address,address)' \
  "$(jq -r .deployment.safe "$HASHES")" "$(jq -r .deployment.conduit "$HASHES")" "$(jq -r .deployment.keeper "$HASHES")")
expect .deployment.constructorArgs "$args"
expect .deployment.address "$(cast create2 --deployer "$(jq -r .create2Deployer "$HASHES")" --salt "$(jq -r .salt "$HASHES")" --init-code "${creation}${args#0x}" | grep -oE '0x[0-9a-fA-F]{40}' | head -n1)"
# .deployment.runtimeKeccak needs a deployment to recompute; test/Deploy.t.sol checks it.

# Everything solc reads, so a settings change in foundry.toml that verifiers must know about fails here.
projection='del(.settings.outputSelection)'
current=$(forge verify-contract --show-standard-json-input 0x0000000000000000000000000000000000000001 src/HydrexCarbonImpactExecutor.sol:HydrexCarbonImpactExecutor | jq -S "$projection")
if [ "$current" != "$(jq -S "$projection" "$INPUT")" ]; then
  echo "::error::$INPUT is stale" >&2
  status=1
else
  echo "$INPUT ok"
fi

exit $status
