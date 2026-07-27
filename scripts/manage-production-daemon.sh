#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/lib/production-package-common.sh
source "$SCRIPT_DIR/lib/production-package-common.sh"

usage() {
    printf '%s\n' 'usage: manage-production-daemon.sh prepare|verify|install|bootstrap|status|stop|bootout|disable|upgrade|rollback|accept-task9|accept-task10' >&2
    exit 64
}

install_package() {
    require_root_for_system
    verify_package
    local initial_mode
    initial_mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$STAGING_DIR/config.plist")"
    [[ "$initial_mode" == "disabled" ]] || {
        printf 'error: initial install configuration must be disabled\n' >&2
        return 78
    }
    for path in "$MANAGED_BINARY" "$MANAGED_PLIST" "$MANAGED_SUPPORT" "$MANAGED_LOG_DIR"; do
        assert_managed_path_safe "$path"
    done
    if [[ -z "$SYSTEM_ROOT" ]]; then
        if launchctl print "system/$LAUNCHD_LABEL" >/dev/null 2>&1; then
            printf 'error: production job already loaded; bootout first\n' >&2
            return 69
        fi
        if launchctl print "gui/$(stat -f %u /dev/console)/$LAUNCHD_LABEL" >/dev/null 2>&1; then
            printf 'error: duplicate user authority detected\n' >&2
            return 69
        fi
    fi
    mkdir -p -- "$(dirname -- "$MANAGED_BINARY")" "$(dirname -- "$MANAGED_PLIST")" "$MANAGED_SUPPORT" "$MANAGED_LOG_DIR"
    install -m 0755 "$STAGING_DIR/macbook-lid-monitor-daemon" "$MANAGED_BINARY.tmp"
    install -m 0644 "$STAGING_DIR/com.crazydennies.macbook-lid-monitor.plist" "$MANAGED_PLIST.tmp"
    install -m 0644 "$STAGING_DIR/config.plist" "$MANAGED_CONFIG.tmp"
    install -m 0644 "$STAGING_DIR/manifest.plist" "$MANAGED_MANIFEST.tmp"
    mv -f -- "$MANAGED_BINARY.tmp" "$MANAGED_BINARY"
    mv -f -- "$MANAGED_PLIST.tmp" "$MANAGED_PLIST"
    mv -f -- "$MANAGED_CONFIG.tmp" "$MANAGED_CONFIG"
    mv -f -- "$MANAGED_MANIFEST.tmp" "$MANAGED_MANIFEST"
    if [[ -z "$SYSTEM_ROOT" ]]; then
        chown root:wheel "$MANAGED_BINARY" "$MANAGED_PLIST" "$MANAGED_CONFIG" "$MANAGED_MANIFEST" "$MANAGED_SUPPORT" "$MANAGED_LOG_DIR"
    fi
    printf 'installed mode=disabled\n'
}

bootstrap_job() {
    require_root_for_system
    assert_regular_source "$MANAGED_PLIST"
    launchctl_system bootstrap system "$MANAGED_PLIST"
    printf 'bootstrapped label=%s\n' "$LAUNCHD_LABEL"
}

status_job() {
    if [[ -n "$SYSTEM_ROOT" ]]; then
        [[ -f "$MANAGED_BINARY" && -f "$MANAGED_PLIST" && -f "$MANAGED_CONFIG" ]] || return 69
        printf 'status installed=true test-root=%s\n' "$SYSTEM_ROOT"
    else
        launchctl print "system/$LAUNCHD_LABEL"
    fi
}

stop_job() {
    require_root_for_system
    launchctl_system kill SIGTERM "system/$LAUNCHD_LABEL" 2>/dev/null || true
    printf 'stopped label=%s\n' "$LAUNCHD_LABEL"
}

bootout_job() {
    require_root_for_system
    launchctl_system bootout "system/$LAUNCHD_LABEL" 2>/dev/null || true
    printf 'booted-out label=%s\n' "$LAUNCHD_LABEL"
}

disable_job() {
    require_root_for_system
    assert_regular_source "$MANAGED_CONFIG"
    /usr/libexec/PlistBuddy -c 'Set :Mode disabled' "$MANAGED_CONFIG"
    chmod 0644 "$MANAGED_CONFIG"
    if [[ -z "$SYSTEM_ROOT" ]]; then chown root:wheel "$MANAGED_CONFIG"; fi
    stop_job
    printf 'disabled label=%s\n' "$LAUNCHD_LABEL"
}

backup_current_set() {
    verify_managed_set
    assert_regular_source "$MANAGED_BINARY"
    assert_regular_source "$MANAGED_PLIST"
    assert_regular_source "$MANAGED_CONFIG"
    assert_regular_source "$MANAGED_MANIFEST"
    rm -rf -- "$MANAGED_ROLLBACK"
    mkdir -p -- "$MANAGED_ROLLBACK"
    cp -p -- "$MANAGED_BINARY" "$MANAGED_ROLLBACK/macbook-lid-monitor-daemon"
    cp -p -- "$MANAGED_PLIST" "$MANAGED_ROLLBACK/com.crazydennies.macbook-lid-monitor.plist"
    cp -p -- "$MANAGED_CONFIG" "$MANAGED_ROLLBACK/config.plist"
    cp -p -- "$MANAGED_MANIFEST" "$MANAGED_ROLLBACK/manifest.plist"
}

verify_managed_set() {
    assert_regular_source "$MANAGED_BINARY"
    assert_regular_source "$MANAGED_MANIFEST"
    local expected actual
    expected="$(/usr/libexec/PlistBuddy -c 'Print :BinarySHA256' "$MANAGED_MANIFEST")"
    actual="$(sha256_file "$MANAGED_BINARY")"
    [[ "$expected" == "$actual" ]] || {
        printf 'error: installed checksum mismatch\n' >&2
        return 65
    }
}

restore_rollback_set() {
    if [[ "${MLM_FAIL_UPGRADE_STAGE:-}" == "rollback-restore" ]]; then
        printf 'error: injected rollback restore failure\n' >&2
        return 70
    fi
    assert_regular_source "$MANAGED_ROLLBACK/macbook-lid-monitor-daemon"
    assert_regular_source "$MANAGED_ROLLBACK/com.crazydennies.macbook-lid-monitor.plist"
    assert_regular_source "$MANAGED_ROLLBACK/config.plist"
    assert_regular_source "$MANAGED_ROLLBACK/manifest.plist"
    install -m 0755 "$MANAGED_ROLLBACK/macbook-lid-monitor-daemon" "$MANAGED_BINARY.tmp"
    install -m 0644 "$MANAGED_ROLLBACK/com.crazydennies.macbook-lid-monitor.plist" "$MANAGED_PLIST.tmp"
    install -m 0644 "$MANAGED_ROLLBACK/config.plist" "$MANAGED_CONFIG.tmp"
    install -m 0644 "$MANAGED_ROLLBACK/manifest.plist" "$MANAGED_MANIFEST.tmp"
    mv -f -- "$MANAGED_BINARY.tmp" "$MANAGED_BINARY"
    mv -f -- "$MANAGED_PLIST.tmp" "$MANAGED_PLIST"
    mv -f -- "$MANAGED_CONFIG.tmp" "$MANAGED_CONFIG"
    mv -f -- "$MANAGED_MANIFEST.tmp" "$MANAGED_MANIFEST"
    if [[ -z "$SYSTEM_ROOT" ]]; then
        chown root:wheel "$MANAGED_BINARY" "$MANAGED_PLIST" "$MANAGED_CONFIG" "$MANAGED_MANIFEST"
    fi
    verify_managed_set
}

rollback_upgrade() {
    require_root_for_system
    bootout_job
    restore_rollback_set
    bootstrap_job
    printf 'rolled-back label=%s\n' "$LAUNCHD_LABEL"
}

upgrade_package() {
    require_root_for_system
    verify_package
    backup_current_set
    bootout_job
    local failed=0
    install -m 0755 "$STAGING_DIR/macbook-lid-monitor-daemon" "$MANAGED_BINARY.tmp"
    install -m 0644 "$STAGING_DIR/com.crazydennies.macbook-lid-monitor.plist" "$MANAGED_PLIST.tmp"
    install -m 0644 "$STAGING_DIR/config.plist" "$MANAGED_CONFIG.tmp"
    install -m 0644 "$STAGING_DIR/manifest.plist" "$MANAGED_MANIFEST.tmp"
    mv -f -- "$MANAGED_BINARY.tmp" "$MANAGED_BINARY"
    mv -f -- "$MANAGED_PLIST.tmp" "$MANAGED_PLIST"
    mv -f -- "$MANAGED_CONFIG.tmp" "$MANAGED_CONFIG"
    mv -f -- "$MANAGED_MANIFEST.tmp" "$MANAGED_MANIFEST"
    if [[ "${MLM_FAIL_UPGRADE_STAGE:-}" == "after-activation" || "${MLM_FAIL_UPGRADE_STAGE:-}" == "rollback-restore" ]]; then failed=1; fi
    if [[ "$failed" -eq 0 ]]; then
        bootstrap_job || failed=1
    fi
    if [[ "$failed" -ne 0 ]]; then
        if ! restore_rollback_set; then
            printf 'error: rollback failed; job remains booted out\n' >&2
            return 71
        fi
        bootstrap_job || {
            printf 'error: rollback bootstrap failed; job remains fail-open\n' >&2
            return 71
        }
        printf 'error: upgrade failed and rollback restored previous set\n' >&2
        return 70
    fi
    printf 'upgraded label=%s\n' "$LAUNCHD_LABEL"
}

print_residual_state() {
    local phase=$1
    printf '%s\n' "--- $phase ---"
    for path in "$MANAGED_BINARY" "$MANAGED_PLIST" "$MANAGED_CONFIG" "$MANAGED_MANIFEST"; do
        if [[ -e "$path" ]]; then
            printf 'present path=%s owner=%s mode=%s\n' \
                "$path" "$(stat -f '%Su:%Sg' "$path")" "$(stat -f '%Lp' "$path")"
        else
            printf 'absent path=%s\n' "$path"
        fi
    done
    if [[ -z "$SYSTEM_ROOT" ]]; then
        if launchctl print "system/$LAUNCHD_LABEL" >/dev/null 2>&1; then
            printf 'job=loaded label=%s\n' "$LAUNCHD_LABEL"
        else
            printf 'job=absent label=%s\n' "$LAUNCHD_LABEL"
        fi
    else
        printf 'job=test-double label=%s\n' "$LAUNCHD_LABEL"
    fi
}

prepare_as_invoking_user() {
    if [[ -n "$SYSTEM_ROOT" ]]; then
        verify_package
        return
    fi
    if [[ "$(id -u)" -ne 0 ]]; then
        prepare_package
        return
    fi
    local invoking_user=${SUDO_USER:-}
    [[ -n "$invoking_user" && "$invoking_user" != "root" ]] || {
        printf 'error: accept-task9 must be invoked through sudo by a non-root user\n' >&2
        return 77
    }
    sudo -u "$invoking_user" -H "$0" prepare
}

accept_task9() {
    require_root_for_system
    print_residual_state pre-task9
    prepare_as_invoking_user
    verify_package
    install_package
    bootstrap_job
    status_job
    disable_job
    bootout_job
    bootstrap_job
    status_job
    print_residual_state post-task9
    printf 'accepted task=9 mode=disabled label=%s\n' "$LAUNCHD_LABEL"
}

managed_version() {
    assert_regular_source "$MANAGED_MANIFEST"
    /usr/libexec/PlistBuddy -c 'Print :Version' "$MANAGED_MANIFEST"
}

managed_checksum() {
    verify_managed_set
    sha256_file "$MANAGED_BINARY"
}

accept_task10() {
    require_root_for_system
    print_residual_state pre-task10
    verify_managed_set
    local original_version original_checksum candidate_version candidate_checksum
    original_version="$(managed_version)"
    original_checksum="$(managed_checksum)"

    prepare_as_invoking_user
    verify_package
    candidate_version="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$STAGING_DIR/manifest.plist")"
    candidate_checksum="$(/usr/libexec/PlistBuddy -c 'Print :BinarySHA256' "$STAGING_DIR/manifest.plist")"

    if MLM_FAIL_UPGRADE_STAGE=after-activation upgrade_package; then
        printf 'error: injected upgrade unexpectedly succeeded\n' >&2
        return 70
    fi
    [[ "$(managed_version)" == "$original_version" ]]
    [[ "$(managed_checksum)" == "$original_checksum" ]]
    printf 'injected-failure-rollback=verified version=%s checksum=%s\n' "$original_version" "$original_checksum"

    upgrade_package
    [[ "$(managed_version)" == "$candidate_version" ]]
    [[ "$(managed_checksum)" == "$candidate_checksum" ]]
    printf 'upgrade=verified version=%s checksum=%s\n' "$candidate_version" "$candidate_checksum"

    rollback_upgrade
    [[ "$(managed_version)" == "$original_version" ]]
    [[ "$(managed_checksum)" == "$original_checksum" ]]
    disable_job
    bootout_job
    bootstrap_job
    status_job
    print_residual_state post-task10
    printf 'accepted task=10 final-version=%s mode=disabled label=%s\n' "$original_version" "$LAUNCHD_LABEL"
}

prepare_package() {
    assert_regular_source "$SOURCE_PLIST"
    assert_regular_source "$SOURCE_CONFIG"
    assert_regular_source "$SOURCE_MANIFEST"

    swift build --package-path "$REPO_ROOT" -c release --product macbook-lid-monitor-daemon
    assert_regular_source "$SOURCE_BINARY"

    rm -rf -- "$STAGING_DIR"
    mkdir -p -- "$STAGING_DIR"
    cp -- "$SOURCE_BINARY" "$STAGING_DIR/macbook-lid-monitor-daemon"
    cp -- "$SOURCE_PLIST" "$STAGING_DIR/com.crazydennies.macbook-lid-monitor.plist"
    cp -- "$SOURCE_CONFIG" "$STAGING_DIR/config.plist"
    cp -- "$SOURCE_MANIFEST" "$STAGING_DIR/manifest.plist"
    chmod 0755 "$STAGING_DIR/macbook-lid-monitor-daemon"
    chmod 0644 "$STAGING_DIR"/*.plist

    local version checksum
    version="$(package_version)"
    checksum="$(sha256_file "$STAGING_DIR/macbook-lid-monitor-daemon")"
    /usr/libexec/PlistBuddy -c "Set :Version $version" "$STAGING_DIR/manifest.plist"
    /usr/libexec/PlistBuddy -c "Set :BinarySHA256 $checksum" "$STAGING_DIR/manifest.plist"
    printf 'prepared staging=%s version=%s checksum=%s\n' "$STAGING_DIR" "$version" "$checksum"
}

verify_package() {
    local binary plist config manifest
    binary="$STAGING_DIR/macbook-lid-monitor-daemon"
    plist="$STAGING_DIR/com.crazydennies.macbook-lid-monitor.plist"
    config="$STAGING_DIR/config.plist"
    manifest="$STAGING_DIR/manifest.plist"
    assert_regular_source "$binary"
    assert_regular_source "$plist"
    assert_regular_source "$config"
    assert_regular_source "$manifest"
    test -x "$binary"
    plutil -lint "$plist" "$config" "$manifest" >/dev/null

    local expected actual version
    expected="$(/usr/libexec/PlistBuddy -c 'Print :BinarySHA256' "$manifest")"
    actual="$(sha256_file "$binary")"
    version="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$manifest")"
    test "$expected" = "$actual"
    test "$version" = "$(package_version)"
    printf 'verified staging=%s version=%s checksum=%s\n' "$STAGING_DIR" "$version" "$actual"
}

[[ $# -eq 1 ]] || usage
case "$1" in
    prepare) prepare_package ;;
    verify) verify_package ;;
    install) install_package ;;
    bootstrap) bootstrap_job ;;
    status) status_job ;;
    stop) stop_job ;;
    bootout) bootout_job ;;
    disable) disable_job ;;
    upgrade) upgrade_package ;;
    rollback) rollback_upgrade ;;
    accept-task9) accept_task9 ;;
    accept-task10) accept_task10 ;;
    *) usage ;;
esac
