#!/usr/bin/env bash

SCRIPT_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_LIB_DIR/../.." && pwd -P)"
export STAGING_DIR="$REPO_ROOT/.build/production-package"
export SOURCE_BINARY="$REPO_ROOT/.build/release/macbook-lid-monitor-daemon"
export SOURCE_PLIST="$REPO_ROOT/packaging/launchd/com.crazydennies.macbook-lid-monitor.plist"
export SOURCE_CONFIG="$REPO_ROOT/packaging/config/config.plist.example"
export SOURCE_MANIFEST="$REPO_ROOT/packaging/manifest/manifest.plist.example"

assert_regular_source() {
    local path=$1
    if [[ -L "$path" ]]; then
        printf 'error: refusing symlink source: %s\n' "$path" >&2
        return 74
    fi
    if [[ ! -f "$path" ]]; then
        printf 'error: missing source: %s\n' "$path" >&2
        return 66
    fi
}

sha256_file() {
    shasum -a 256 "$1" | awk '{print $1}'
}

package_version() {
    git -C "$REPO_ROOT" rev-parse --short=12 HEAD
}
