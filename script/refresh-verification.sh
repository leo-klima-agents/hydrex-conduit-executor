#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Léo de Souza
# SPDX-License-Identifier: MIT
set -euo pipefail
cd "$(dirname "$0")/.."

forge build
forge script script/Hashes.s.sol
forge verify-contract --show-standard-json-input 0x0000000000000000000000000000000000000001 \
  src/KlimaVeTokenConduitExecutor.sol:KlimaVeTokenConduitExecutor > verification/KlimaVeTokenConduitExecutor.standard-input.json
./script/check-verification.sh
