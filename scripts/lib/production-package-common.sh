#!/usr/bin/env bash

SCRIPT_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_LIB_DIR/../.." && pwd -P)"
export STAGING_DIR="$REPO_ROOT/.build/production-package"
export SOURCE_BINARY="$REPO_ROOT/.build/release/macbook-lid-monitor-daemon"
export SOURCE_PLIST="$REPO_ROOT/packaging/launchd/com.crazydennies.macbook-lid-monitor.plist"
export SOURCE_CONFIG="$REPO_ROOT/packaging/config/config.plist.example"
export SOURCE_MANIFEST="$REPO_ROOT/packaging/manifest/manifest.plist.example"

SYSTEM_ROOT="${MLM_TEST_ROOT:-}"
if [[ -n "$SYSTEM_ROOT" ]]; then
    [[ "$SYSTEM_ROOT" = /* ]] || { printf 'error: MLM_TEST_ROOT must be absolute\n' >&2; return 64; }
    case "$SYSTEM_ROOT" in
        "$REPO_ROOT"/.build/*) ;;
        *) printf 'error: MLM_TEST_ROOT must stay under repository .build\n' >&2; return 64 ;;
    esac
fi
export MANAGED_BINARY="$SYSTEM_ROOT/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon"
export MANAGED_PLIST="$SYSTEM_ROOT/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist"
export MANAGED_SUPPORT="$SYSTEM_ROOT/Library/Application Support/MacBookLidMonitor"
export MANAGED_CONFIG="$MANAGED_SUPPORT/config.plist"
export MANAGED_MANIFEST="$MANAGED_SUPPORT/manifest.plist"
export MANAGED_LOG_DIR="$SYSTEM_ROOT/Library/Logs/MacBookLidMonitor"
export MANAGED_STDOUT_LOG="$MANAGED_LOG_DIR/production.log"
export MANAGED_STDERR_LOG="$MANAGED_LOG_DIR/production-error.log"
export MANAGED_ROLLBACK="$MANAGED_SUPPORT/rollback"
export MANAGED_TASK14_STATE="$MANAGED_SUPPORT/task14-reboot-state"
export MANAGED_SLEEP_AUTHORITY="$MANAGED_SUPPORT/sleep-authority.lock"
export MANAGED_ACCEPTANCE_STATE="$MANAGED_SUPPORT/deployment-acceptance.plist"
export MANAGED_HEALTH_STATE="$MANAGED_SUPPORT/health.plist"
export MANAGED_REBOOT_STATE="$MANAGED_SUPPORT/deployment-reboot.plist"
export MANAGED_LIFECYCLE_GUARD="$MANAGED_SUPPORT/.lifecycle-guard"
export LAUNCHD_LABEL="com.crazydennies.macbook-lid-monitor"

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

require_root_for_system() {
    if [[ -z "$SYSTEM_ROOT" && "$(id -u)" -ne 0 ]]; then
        printf 'error: root required\n' >&2
        return 77
    fi
}

assert_managed_path_safe() {
    local path=$1 current=""
    IFS='/' read -r -a parts <<< "${path#/}"
    for part in "${parts[@]}"; do
        current="$current/$part"
        if [[ -L "$current" ]]; then
            printf 'error: refusing symlink managed path: %s\n' "$current" >&2
            return 74
        fi
    done
}

launchctl_system() {
    if [[ -n "$SYSTEM_ROOT" ]]; then
        return 0
    fi
    launchctl "$@"
}
