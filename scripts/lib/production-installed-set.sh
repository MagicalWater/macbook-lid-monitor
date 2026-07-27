#!/usr/bin/env bash

installed_set_error() {
    local reason=$1 path=${2:-unavailable}
    printf 'error=installed-set-invalid reason=%s path=%s\n' "$reason" "$path" >&2
    return 65
}

managed_expected_owner() {
    if [[ -n "$SYSTEM_ROOT" ]]; then id -u; else printf '0\n'; fi
}

managed_expected_group() {
    if [[ -n "$SYSTEM_ROOT" ]]; then id -g; else printf '0\n'; fi
}

verify_safe_ancestors() {
    local path=$1 parent current mode
    parent="$(dirname -- "$path")"
    current="$parent"
    while [[ "$current" != / && -n "$current" ]]; do
        [[ ! -L "$current" ]] || { installed_set_error unsafe-ancestor "$current"; return $?; }
        if [[ -e "$current" ]]; then
            mode="$(stat -f '%Lp' "$current")" || { installed_set_error ancestor-stat "$current"; return $?; }
            (( (8#$mode & 8#022) == 0 )) || { installed_set_error unsafe-ancestor "$current"; return $?; }
            [[ "$(stat -f '%u' "$current")" == "$(managed_expected_owner)" ]] || {
                installed_set_error unsafe-ancestor-owner "$current"
                return $?
            }
        fi
        if [[ -n "$SYSTEM_ROOT" && "$current" == "$SYSTEM_ROOT" ]]; then break; fi
        current="$(dirname -- "$current")"
    done
}

verify_managed_metadata() {
    local path=$1 expected_type=$2 expected_owner=$3 expected_group=$4 expected_mode=$5 expected_links=$6
    local actual_owner actual_group actual_mode actual_links
    [[ -e "$path" || -L "$path" ]] || { installed_set_error missing "$path"; return $?; }
    [[ ! -L "$path" ]] || { installed_set_error symlink "$path"; return $?; }
    case "$expected_type" in
        regular) [[ -f "$path" ]] || { installed_set_error type "$path"; return $?; } ;;
        directory) [[ -d "$path" ]] || { installed_set_error type "$path"; return $?; } ;;
        *) installed_set_error expected-type "$path"; return $? ;;
    esac
    verify_safe_ancestors "$path" || return $?
    actual_owner="$(stat -f '%u' "$path")" || { installed_set_error owner-stat "$path"; return $?; }
    actual_group="$(stat -f '%g' "$path")" || { installed_set_error group-stat "$path"; return $?; }
    actual_mode="$(stat -f '%Lp' "$path")" || { installed_set_error mode-stat "$path"; return $?; }
    actual_links="$(stat -f '%l' "$path")" || { installed_set_error links-stat "$path"; return $?; }
    [[ "$actual_owner" == "$expected_owner" ]] || { installed_set_error owner "$path"; return $?; }
    [[ "$actual_group" == "$expected_group" ]] || { installed_set_error group "$path"; return $?; }
    [[ "$actual_mode" == "$expected_mode" ]] || { installed_set_error mode "$path"; return $?; }
    [[ "$actual_links" == "$expected_links" ]] || { installed_set_error link-count "$path"; return $?; }
}

normalized_config_sha256() {
    local config_path=$1 temporary
    temporary="$(mktemp "${TMPDIR:-/tmp}/mlm-config.XXXXXX.plist")"
    cleanup_normalized_config() { rm -f -- "$temporary"; }
    trap cleanup_normalized_config RETURN
    cp -- "$config_path" "$temporary"
    /usr/libexec/PlistBuddy -c 'Set :Mode disabled' "$temporary" >/dev/null
    plutil -convert json -o - "$temporary" | /usr/bin/python3 -c \
        'import json,sys; sys.stdout.write(json.dumps(json.load(sys.stdin), sort_keys=True, separators=(",", ":")))' | \
        shasum -a 256 | awk '{print $1}'
    cleanup_normalized_config
    trap - RETURN
}

manifest_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$MANAGED_MANIFEST" 2>/dev/null
}

staged_manifest_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$STAGING_DIR/manifest.plist" 2>/dev/null
}

verify_staged_payload() {
    local binary plist config manifest expected actual
    binary="$STAGING_DIR/macbook-lid-monitor-daemon"
    plist="$STAGING_DIR/com.crazydennies.macbook-lid-monitor.plist"
    config="$STAGING_DIR/config.plist"
    manifest="$STAGING_DIR/manifest.plist"
    assert_regular_source "$binary" || return $?
    assert_regular_source "$plist" || return $?
    assert_regular_source "$config" || return $?
    assert_regular_source "$manifest" || return $?
    [[ -x "$binary" ]] || { installed_set_error staged-binary-mode "$binary"; return $?; }
    plutil -lint "$plist" "$config" "$manifest" >/dev/null 2>&1 || {
        installed_set_error staged-plist-lint "$manifest"; return $?
    }
    [[ "$(staged_manifest_value SchemaVersion)" == 1 ]] || { installed_set_error staged-schema "$manifest"; return $?; }
    [[ "$(staged_manifest_value Product)" == macbook-lid-monitor-daemon ]] || { installed_set_error staged-product "$manifest"; return $?; }
    [[ "$(staged_manifest_value BinaryPath)" == /Library/PrivilegedHelperTools/macbook-lid-monitor-daemon ]] || { installed_set_error staged-binary-path "$manifest"; return $?; }
    [[ "$(staged_manifest_value PlistPath)" == /Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist ]] || { installed_set_error staged-plist-path "$manifest"; return $?; }
    [[ "$(staged_manifest_value ConfigPath)" == '/Library/Application Support/MacBookLidMonitor/config.plist' ]] || { installed_set_error staged-config-path "$manifest"; return $?; }
    [[ "$(staged_manifest_value SleepAuthorityPath)" == '/Library/Application Support/MacBookLidMonitor/sleep-authority.lock' ]] || { installed_set_error staged-sleep-authority-path "$manifest"; return $?; }
    [[ "$(staged_manifest_value AcceptanceStatePath)" == '/Library/Application Support/MacBookLidMonitor/deployment-acceptance.plist' ]] || { installed_set_error staged-acceptance-path "$manifest"; return $?; }
    [[ "$(staged_manifest_value HealthStatePath)" == '/Library/Application Support/MacBookLidMonitor/health.plist' ]] || { installed_set_error staged-health-path "$manifest"; return $?; }
    [[ "$(staged_manifest_value HardwareProfileID)" == m1-pro-0x8104-report-id-1-v1 ]] || { installed_set_error staged-hardware-profile "$manifest"; return $?; }
    [[ "$(staged_manifest_value SourceCommit)" =~ ^[0-9a-f]{40}$ ]] || { installed_set_error staged-source-commit "$manifest"; return $?; }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$config" 2>/dev/null || true)" == disabled ]] || {
        installed_set_error staged-mode "$config"; return $?
    }
    expected="$(staged_manifest_value BinarySHA256)"; actual="$(sha256_file "$binary")"
    [[ "$expected" == "$actual" ]] || { installed_set_error staged-binary-checksum "$binary"; return $?; }
    expected="$(staged_manifest_value PlistSHA256)"; actual="$(sha256_file "$plist")"
    [[ "$expected" == "$actual" ]] || { installed_set_error staged-plist-checksum "$plist"; return $?; }
    expected="$(staged_manifest_value DisabledConfigSHA256)"; actual="$(normalized_config_sha256 "$config")"
    [[ "$expected" == "$actual" ]] || { installed_set_error staged-config-checksum "$config"; return $?; }
    if /usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables' "$plist" >/dev/null 2>&1; then
        installed_set_error staged-prohibited-environment "$plist"
        return $?
    fi
}

staged_payload_matches_installed_identity() {
    local key
    verify_installed_set || return $?
    verify_staged_payload || return $?
    while IFS= read -r key; do
        [[ "$(manifest_value "$key")" == "$(staged_manifest_value "$key")" ]] || return 1
    done < <(deployment_payload_identity_keys)
}

rollback_set_error() {
    local reason=$1 path=${2:-unavailable}
    printf 'error=rollback-set-invalid reason=%s path=%s\n' "$reason" "$path" >&2
    return 65
}

verify_rollback_set() {
    local binary plist config manifest expected actual
    [[ -d "$MANAGED_ROLLBACK" && ! -L "$MANAGED_ROLLBACK" ]] || {
        rollback_set_error directory "$MANAGED_ROLLBACK"; return $?
    }
    assert_managed_path_safe "$MANAGED_ROLLBACK" || return $?
    binary="$MANAGED_ROLLBACK/macbook-lid-monitor-daemon"
    plist="$MANAGED_ROLLBACK/com.crazydennies.macbook-lid-monitor.plist"
    config="$MANAGED_ROLLBACK/config.plist"
    manifest="$MANAGED_ROLLBACK/manifest.plist"
    verify_managed_metadata "$binary" regular "$(managed_expected_owner)" "$(managed_expected_group)" 755 1 >/dev/null 2>&1 || {
        rollback_set_error metadata "$binary"; return $?
    }
    for path in "$plist" "$config" "$manifest"; do
        verify_managed_metadata "$path" regular "$(managed_expected_owner)" "$(managed_expected_group)" 644 1 >/dev/null 2>&1 || {
            rollback_set_error metadata "$path"; return $?
        }
    done
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :SchemaVersion' "$manifest" 2>/dev/null || true)" == 1 ]] || {
        rollback_set_error schema "$manifest"; return $?
    }
    expected="$(/usr/libexec/PlistBuddy -c 'Print :BinarySHA256' "$manifest" 2>/dev/null || true)"
    actual="$(sha256_file "$binary")"
    [[ "$expected" == "$actual" ]] || { rollback_set_error binary-checksum "$binary"; return $?; }
    expected="$(/usr/libexec/PlistBuddy -c 'Print :PlistSHA256' "$manifest" 2>/dev/null || true)"
    actual="$(sha256_file "$plist")"
    [[ "$expected" == "$actual" ]] || { rollback_set_error plist-checksum "$plist"; return $?; }
    expected="$(/usr/libexec/PlistBuddy -c 'Print :DisabledConfigSHA256' "$manifest" 2>/dev/null || true)"
    actual="$(normalized_config_sha256 "$config")"
    [[ "$expected" == "$actual" ]] || { rollback_set_error config-checksum "$config"; return $?; }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$config" 2>/dev/null || true)" == disabled ]] || {
        rollback_set_error mode "$config"; return $?
    }
    if /usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables' "$plist" >/dev/null 2>&1; then
        rollback_set_error prohibited-environment "$plist"
        return $?
    fi
}

verify_installed_set() {
    local owner group expected actual
    owner="$(managed_expected_owner)"
    group="$(managed_expected_group)"
    verify_managed_metadata "$MANAGED_BINARY" regular "$owner" "$group" 755 1 || return $?
    verify_managed_metadata "$MANAGED_PLIST" regular "$owner" "$group" 644 1 || return $?
    verify_managed_metadata "$MANAGED_CONFIG" regular "$owner" "$group" 644 1 || return $?
    verify_managed_metadata "$MANAGED_MANIFEST" regular "$owner" "$group" 644 1 || return $?
    plutil -lint "$MANAGED_PLIST" "$MANAGED_CONFIG" "$MANAGED_MANIFEST" >/dev/null 2>&1 || {
        installed_set_error plist-lint "$MANAGED_MANIFEST"; return $?
    }
    [[ "$(manifest_value SchemaVersion)" == 1 ]] || { installed_set_error schema "$MANAGED_MANIFEST"; return $?; }
    [[ "$(manifest_value Product)" == macbook-lid-monitor-daemon ]] || { installed_set_error product "$MANAGED_MANIFEST"; return $?; }
    [[ "$(manifest_value BinaryPath)" == /Library/PrivilegedHelperTools/macbook-lid-monitor-daemon ]] || { installed_set_error binary-path "$MANAGED_MANIFEST"; return $?; }
    [[ "$(manifest_value PlistPath)" == /Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.plist ]] || { installed_set_error plist-path "$MANAGED_MANIFEST"; return $?; }
    [[ "$(manifest_value ConfigPath)" == '/Library/Application Support/MacBookLidMonitor/config.plist' ]] || { installed_set_error config-path "$MANAGED_MANIFEST"; return $?; }
    [[ "$(manifest_value SleepAuthorityPath)" == '/Library/Application Support/MacBookLidMonitor/sleep-authority.lock' ]] || { installed_set_error sleep-authority-path "$MANAGED_MANIFEST"; return $?; }
    [[ "$(manifest_value AcceptanceStatePath)" == '/Library/Application Support/MacBookLidMonitor/deployment-acceptance.plist' ]] || { installed_set_error acceptance-path "$MANAGED_MANIFEST"; return $?; }
    [[ "$(manifest_value HealthStatePath)" == '/Library/Application Support/MacBookLidMonitor/health.plist' ]] || { installed_set_error health-path "$MANAGED_MANIFEST"; return $?; }
    [[ "$(manifest_value HardwareProfileID)" == m1-pro-0x8104-report-id-1-v1 ]] || { installed_set_error hardware-profile "$MANAGED_MANIFEST"; return $?; }
    [[ "$(manifest_value SourceCommit)" =~ ^[0-9a-f]{40}$ ]] || { installed_set_error source-commit "$MANAGED_MANIFEST"; return $?; }
    expected="$(manifest_value BinarySHA256)"; actual="$(sha256_file "$MANAGED_BINARY")"
    [[ "$expected" == "$actual" ]] || { installed_set_error binary-checksum "$MANAGED_BINARY"; return $?; }
    expected="$(manifest_value PlistSHA256)"; actual="$(sha256_file "$MANAGED_PLIST")"
    [[ "$expected" == "$actual" ]] || { installed_set_error plist-checksum "$MANAGED_PLIST"; return $?; }
    expected="$(manifest_value DisabledConfigSHA256)"; actual="$(normalized_config_sha256 "$MANAGED_CONFIG")"
    [[ "$expected" == "$actual" ]] || { installed_set_error config-checksum "$MANAGED_CONFIG"; return $?; }
    if /usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables' "$MANAGED_PLIST" >/dev/null 2>&1; then
        installed_set_error prohibited-environment "$MANAGED_PLIST"
        return $?
    fi
}

installed_identity_lines() {
    verify_installed_set
    printf 'product=%s\n' "$(manifest_value Product)"
    printf 'version=%s\n' "$(manifest_value Version)"
    printf 'source_commit=%s\n' "$(manifest_value SourceCommit)"
    printf 'binary_sha256=%s\n' "$(manifest_value BinarySHA256)"
    printf 'plist_sha256=%s\n' "$(manifest_value PlistSHA256)"
    printf 'disabled_config_sha256=%s\n' "$(manifest_value DisabledConfigSHA256)"
    printf 'hardware_profile=%s\n' "$(manifest_value HardwareProfileID)"
    printf 'binary_path=%s\n' "$(manifest_value BinaryPath)"
    printf 'plist_path=%s\n' "$(manifest_value PlistPath)"
    printf 'config_path=%s\n' "$(manifest_value ConfigPath)"
    printf 'manifest_path=%s\n' '/Library/Application Support/MacBookLidMonitor/manifest.plist'
    printf 'sleep_authority_path=%s\n' "$(manifest_value SleepAuthorityPath)"
    printf 'acceptance_state_path=%s\n' "$(manifest_value AcceptanceStatePath)"
    printf 'health_state_path=%s\n' "$(manifest_value HealthStatePath)"
}

with_lifecycle_guard() {
    local command=$1 status
    shift
    assert_managed_path_safe "$MANAGED_SUPPORT"
    mkdir -p -- "$MANAGED_SUPPORT"
    chmod 0755 "$MANAGED_SUPPORT"
    if [[ -z "$SYSTEM_ROOT" ]]; then chown root:wheel "$MANAGED_SUPPORT"; fi
    [[ ! -L "$MANAGED_LIFECYCLE_GUARD" ]] || { printf 'error=lifecycle-guard-unsafe\n' >&2; return 74; }
    if ! mkdir -- "$MANAGED_LIFECYCLE_GUARD" 2>/dev/null; then
        printf 'error=lifecycle-busy\n' >&2
        return 75
    fi
    cleanup_lifecycle_guard() {
        rmdir -- "$MANAGED_LIFECYCLE_GUARD" 2>/dev/null || true
        rmdir -- "$MANAGED_SUPPORT" 2>/dev/null || true
    }
    # shellcheck disable=SC2329 # invoked through signal traps below
    lifecycle_guard_signal() {
        local signal_status=$1
        cleanup_lifecycle_guard
        trap - EXIT HUP INT TERM
        exit "$signal_status"
    }
    trap cleanup_lifecycle_guard EXIT
    trap 'lifecycle_guard_signal 129' HUP
    trap 'lifecycle_guard_signal 130' INT
    trap 'lifecycle_guard_signal 143' TERM
    if [[ -n "${MLM_TEST_HOLD_LIFECYCLE_GUARD_SECONDS:-}" ]]; then
        [[ -n "$SYSTEM_ROOT" ]] || { printf 'error=test-hook-production-disabled\n' >&2; return 64; }
        sleep "$MLM_TEST_HOLD_LIFECYCLE_GUARD_SECONDS"
    fi
    "$command" "$@"
    status=$?
    cleanup_lifecycle_guard
    trap - EXIT HUP INT TERM
    return "$status"
}
