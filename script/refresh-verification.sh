#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Klima Protocol
# SPDX-License-Identifier: MIT
# Regenerate both files under verification/ from the current source and script/Deploy.s.sol constants.
set -euo pipefail
cd "$(dirname "$0")/.."

forge build
forge script script/Hashes.s.sol
forge verify-contract --show-standard-json-input 0x0000000000000000000000000000000000000001 \
  src/KlimaConduitExecutor.sol:KlimaConduitExecutor > verification/KlimaConduitExecutor.standard-input.json
./script/check-verification.sh
