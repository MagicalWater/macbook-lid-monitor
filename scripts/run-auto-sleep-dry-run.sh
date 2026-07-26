#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}"

swift build -c release

exec .build/release/macbook-lid-monitor \
  --auto-sleep --dry-run \
  --sleep-threshold 60 \
  --reopen-threshold 70 \
  --debounce 2 \
  --wake-cooldown 5
