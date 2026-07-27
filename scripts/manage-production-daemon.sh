#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/lib/production-package-common.sh
source "$SCRIPT_DIR/lib/production-package-common.sh"

usage() {
    printf '%s\n' 'usage: manage-production-daemon.sh prepare|verify|install|bootstrap|status|stop|bootout|disable|dry-run|upgrade|rollback|rotate-logs|diagnostics|uninstall|accept-task9|accept-task10|accept-task11|accept-task12-logged-in|accept-task12-loginwindow-start|accept-task12-loginwindow-finish' >&2
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

set_dry_run_mode() {
    require_root_for_system
    assert_regular_source "$MANAGED_CONFIG"
    /usr/libexec/PlistBuddy -c 'Set :Mode dry-run' "$MANAGED_CONFIG"
    chmod 0644 "$MANAGED_CONFIG"
    if [[ -z "$SYSTEM_ROOT" ]]; then chown root:wheel "$MANAGED_CONFIG"; fi
    bootout_job
    bootstrap_job
    printf 'mode=dry-run label=%s\n' "$LAUNCHD_LABEL"
}

verify_logged_in_dry_run() {
    local mode process_count
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG")"
    [[ "$mode" == "dry-run" ]] || {
        printf 'error: expected dry-run mode, got %s\n' "$mode" >&2
        return 65
    }
    if [[ -n "$SYSTEM_ROOT" ]]; then
        printf 'verified logged-in dry-run test-root=%s\n' "$SYSTEM_ROOT"
        return 0
    fi
    sleep 2
    launchctl print "system/$LAUNCHD_LABEL" >/dev/null
    process_count="$({ pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | wc -l | tr -d ' ')"
    [[ "$process_count" == "1" ]] || {
        printf 'error: expected one production daemon process, got %s\n' "$process_count" >&2
        return 70
    }
    [[ -f "$MANAGED_STDOUT_LOG" && ! -L "$MANAGED_STDOUT_LOG" ]] || {
        printf 'error: production stdout log missing\n' >&2
        return 70
    }
    grep -q 'mode=dry-run' "$MANAGED_STDOUT_LOG" || {
        printf 'error: dry-run startup evidence missing\n' >&2
        return 70
    }
    printf 'verified logged-in dry-run process-count=1 label=%s\n' "$LAUNCHD_LABEL"
}

accept_task12_logged_in() {
    require_root_for_system
    verify_uninstalled_state
    cleanup_task12_to_disabled() {
        if [[ -f "$MANAGED_CONFIG" && ! -L "$MANAGED_CONFIG" ]]; then
            disable_job >/dev/null 2>&1 || true
            bootout_job >/dev/null 2>&1 || true
            bootstrap_job >/dev/null 2>&1 || true
        fi
    }
    trap cleanup_task12_to_disabled EXIT
    prepare_as_invoking_user
    verify_package
    install_package
    bootstrap_job
    set_dry_run_mode
    verify_logged_in_dry_run
    diagnostics
    rotate_logs
    disable_job
    bootout_job
    bootstrap_job
    diagnostics
    trap - EXIT
    printf 'accepted task=12 scope=logged-in final-mode=disabled label=%s\n' "$LAUNCHD_LABEL"
}

loginwindow_evidence_path() {
    printf '%s\n' "$MANAGED_SUPPORT/task12-loginwindow-evidence.txt"
}

loginwindow_observer_script_path() {
    printf '%s\n' "$SYSTEM_ROOT/Library/PrivilegedHelperTools/macbook-lid-monitor-task12-loginwindow-observer"
}

loginwindow_observer_plist_path() {
    printf '%s\n' "$SYSTEM_ROOT/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.task12-loginwindow-observer.plist"
}

cleanup_loginwindow_observer() {
    local observer_script observer_plist
    observer_script="$(loginwindow_observer_script_path)"
    observer_plist="$(loginwindow_observer_plist_path)"
    if [[ -z "$SYSTEM_ROOT" ]]; then
        /bin/launchctl bootout system/com.crazydennies.macbook-lid-monitor.task12-loginwindow-observer >/dev/null 2>&1 || true
    fi
    rm -f -- "$observer_script" "$observer_plist"
}

accept_task12_loginwindow_start() {
    require_root_for_system
    local mode invoking_user invoking_uid evidence observer_script observer_plist
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG")"
    [[ "$mode" == "disabled" ]] || { printf 'error: expected disabled starting mode\n' >&2; return 65; }
    invoking_user=${SUDO_USER:-}
    [[ -n "$invoking_user" && "$invoking_user" != root ]] || { printf 'error: SUDO_USER is required\n' >&2; return 77; }
    invoking_uid="$(id -u "$invoking_user")"
    evidence="$(loginwindow_evidence_path)"
    observer_script="$(loginwindow_observer_script_path)"
    observer_plist="$(loginwindow_observer_plist_path)"
    cleanup_loginwindow_observer
    rm -f -- "$evidence"
    set_dry_run_mode
    verify_logged_in_dry_run
    if [[ -n "$SYSTEM_ROOT" ]]; then
        printf 'console-user=loginwindow\nprocess-count=1\nsystem-job=loaded\n' > "$evidence"
        printf 'started task=12 scope=loginwindow test-root=%s\n' "$SYSTEM_ROOT"
        return 0
    fi
    cat > "$observer_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
stable=0
for _ in {1..180}; do
  owner="\$(stat -f %Su /dev/console 2>/dev/null || true)"
  count="\$({ pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | wc -l | tr -d ' ')"
  job=absent
  /bin/launchctl print system/$LAUNCHD_LABEL >/dev/null 2>&1 && job=loaded
  if [[ "\$owner" != "$invoking_user" && -n "\$owner" && "\$count" == 1 && "\$job" == loaded ]]; then
    stable=\$((stable + 1))
    if [[ "\$stable" -ge 2 ]]; then
      printf 'console-user=%s\nprocess-count=%s\nsystem-job=%s\n' "\$owner" "\$count" "\$job" > "$evidence.tmp"
      chmod 0600 "$evidence.tmp"
      chown root:wheel "$evidence.tmp"
      mv -f "$evidence.tmp" "$evidence"
      exit 0
    fi
  else
    stable=0
  fi
  sleep 1
done
printf 'console-user=timeout\nprocess-count=0\nsystem-job=absent\n' > "$evidence.tmp"
chmod 0600 "$evidence.tmp"
chown root:wheel "$evidence.tmp"
mv -f "$evidence.tmp" "$evidence"
exit 70
EOF
    chmod 0700 "$observer_script"
    chown root:wheel "$observer_script"
    cat > "$observer_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.crazydennies.macbook-lid-monitor.task12-loginwindow-observer</string>
  <key>ProgramArguments</key>
  <array>
    <string>$observer_script</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
EOF
    chmod 0644 "$observer_plist"
    chown root:wheel "$observer_plist"
    plutil -lint "$observer_plist" >/dev/null
    /bin/launchctl bootstrap system "$observer_plist"
    printf 'logout-imminent task=12 scope=loginwindow user=%s\n' "$invoking_user"
    launchctl bootout "gui/$invoking_uid"
}

accept_task12_loginwindow_finish() {
    require_root_for_system
    local evidence owner count job
    evidence="$(loginwindow_evidence_path)"
    cleanup_task12_loginwindow_to_disabled() {
        cleanup_loginwindow_observer
        if [[ -f "$MANAGED_CONFIG" && ! -L "$MANAGED_CONFIG" ]]; then
            disable_job >/dev/null 2>&1 || true
            bootout_job >/dev/null 2>&1 || true
            bootstrap_job >/dev/null 2>&1 || true
        fi
    }
    trap cleanup_task12_loginwindow_to_disabled EXIT
    [[ -f "$evidence" && ! -L "$evidence" ]] || { printf 'error: loginwindow evidence missing\n' >&2; return 70; }
    owner="$(awk -F= '$1=="console-user" {print $2}' "$evidence")"
    count="$(awk -F= '$1=="process-count" {print $2}' "$evidence")"
    job="$(awk -F= '$1=="system-job" {print $2}' "$evidence")"
    [[ "$owner" != "${SUDO_USER:-root}" && "$count" == 1 && "$job" == loaded ]] || {
        printf 'error: invalid loginwindow evidence owner=%s process-count=%s job=%s\n' "$owner" "$count" "$job" >&2
        return 70
    }
    disable_job
    bootout_job
    bootstrap_job
    diagnostics
    rm -f -- "$evidence"
    cleanup_loginwindow_observer
    trap - EXIT
    printf 'accepted task=12 scope=loginwindow final-mode=disabled observed-console-user=%s label=%s\n' "$owner" "$LAUNCHD_LABEL"
}

rotate_one_log() {
    local path=$1 max_bytes=1048576 generations=3 size=0 index
    [[ -e "$path" ]] || return 0
    assert_regular_source "$path"
    size="$(stat -f '%z' "$path")"
    [[ "$size" -gt "$max_bytes" ]] || return 0
    rm -f -- "$path.$generations"
    for ((index=generations-1; index>=1; index--)); do
        [[ -f "$path.$index" && ! -L "$path.$index" ]] && mv -f -- "$path.$index" "$path.$((index+1))"
    done
    mv -f -- "$path" "$path.1"
    : > "$path"
    chmod 0600 "$path"
    if [[ -z "$SYSTEM_ROOT" ]]; then chown root:wheel "$path"; fi
}

rotate_logs() {
    require_root_for_system
    assert_managed_path_safe "$MANAGED_LOG_DIR"
    mkdir -p -- "$MANAGED_LOG_DIR"
    chmod 0700 "$MANAGED_LOG_DIR"
    if [[ -z "$SYSTEM_ROOT" ]]; then chown root:wheel "$MANAGED_LOG_DIR"; fi
    for path in "$MANAGED_STDOUT_LOG" "$MANAGED_STDERR_LOG"; do
        if [[ -f "$path" && ! -L "$path" ]]; then
            chmod 0600 "$path"
            if [[ -z "$SYSTEM_ROOT" ]]; then chown root:wheel "$path"; fi
        fi
    done
    rotate_one_log "$MANAGED_STDOUT_LOG"
    rotate_one_log "$MANAGED_STDERR_LOG"
    printf 'rotated logs max-bytes=1048576 generations=3\n'
}

diagnostics() {
    local mode version checksum job_state process_count
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG" 2>/dev/null || printf unavailable)"
    version="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$MANAGED_MANIFEST" 2>/dev/null || printf unavailable)"
    checksum="$(sha256_file "$MANAGED_BINARY" 2>/dev/null || printf unavailable)"
    if [[ -n "$SYSTEM_ROOT" ]]; then
        job_state=test-double
        process_count=0
    else
        if launchctl print "system/$LAUNCHD_LABEL" >/dev/null 2>&1; then job_state=loaded; else job_state=absent; fi
        process_count="$({ pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | wc -l | tr -d ' ')"
    fi
    printf 'diagnostics label=%s job=%s mode=%s version=%s checksum=%s process-count=%s\n' \
        "$LAUNCHD_LABEL" "$job_state" "$mode" "$version" "$checksum" "$process_count"
    for path in "$MANAGED_STDOUT_LOG" "$MANAGED_STDERR_LOG"; do
        if [[ -f "$path" && ! -L "$path" ]]; then
            printf 'log path=%s bytes=%s mode=%s\n' "$path" "$(stat -f '%z' "$path")" "$(stat -f '%Lp' "$path")"
        else
            printf 'log path=%s absent\n' "$path"
        fi
    done
}

uninstall_package() {
    require_root_for_system
    for path in "$MANAGED_BINARY" "$MANAGED_PLIST" "$MANAGED_CONFIG" "$MANAGED_MANIFEST" \
        "$MANAGED_SUPPORT/crash-budget.json" "$MANAGED_STDOUT_LOG" "$MANAGED_STDERR_LOG" "$MANAGED_ROLLBACK"; do
        assert_managed_path_safe "$path"
        [[ -L "$path" ]] && { printf 'error: refusing symlink uninstall path: %s\n' "$path" >&2; return 74; }
    done
    disable_job 2>/dev/null || true
    bootout_job
    for path in "$MANAGED_BINARY" "$MANAGED_PLIST" "$MANAGED_CONFIG" "$MANAGED_MANIFEST" \
        "$MANAGED_SUPPORT/crash-budget.json" "$MANAGED_STDOUT_LOG" "$MANAGED_STDERR_LOG"; do
        rm -f -- "$path"
    done
    for path in "$MANAGED_STDOUT_LOG" "$MANAGED_STDERR_LOG"; do
        rm -f -- "$path.1" "$path.2" "$path.3"
    done
    rm -rf -- "$MANAGED_ROLLBACK"
    rmdir "$MANAGED_SUPPORT" 2>/dev/null || true
    rmdir "$MANAGED_LOG_DIR" 2>/dev/null || true
    printf 'uninstalled label=%s\n' "$LAUNCHD_LABEL"
}

verify_uninstalled_state() {
    local found=0
    for path in "$MANAGED_BINARY" "$MANAGED_PLIST" "$MANAGED_CONFIG" "$MANAGED_MANIFEST" \
        "$MANAGED_SUPPORT/crash-budget.json" "$MANAGED_ROLLBACK" \
        "$MANAGED_STDOUT_LOG" "$MANAGED_STDERR_LOG"; do
        if [[ -e "$path" || -L "$path" ]]; then
            printf 'error: managed residual remains: %s\n' "$path" >&2
            found=1
        fi
    done
    for path in "$MANAGED_STDOUT_LOG" "$MANAGED_STDERR_LOG"; do
        for generation in 1 2 3; do
            if [[ -e "$path.$generation" || -L "$path.$generation" ]]; then
                printf 'error: managed residual remains: %s\n' "$path.$generation" >&2
                found=1
            fi
        done
    done
    if [[ -z "$SYSTEM_ROOT" ]]; then
        if launchctl print "system/$LAUNCHD_LABEL" >/dev/null 2>&1; then
            printf 'error: system job remains loaded\n' >&2
            found=1
        fi
        if pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' >/dev/null 2>&1; then
            printf 'error: daemon process remains active\n' >&2
            found=1
        fi
    fi
    [[ "$found" -eq 0 ]]
    printf 'verified uninstall residual-state=clean label=%s\n' "$LAUNCHD_LABEL"
}

accept_task11() {
    require_root_for_system
    printf '%s\n' '--- pre-task11 diagnostics ---'
    diagnostics
    rotate_logs
    printf '%s\n' '--- post-rotation diagnostics ---'
    diagnostics
    uninstall_package
    verify_uninstalled_state
    printf 'accepted task=11 state=uninstalled label=%s\n' "$LAUNCHD_LABEL"
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
    dry-run) set_dry_run_mode ;;
    upgrade) upgrade_package ;;
    rollback) rollback_upgrade ;;
    rotate-logs) rotate_logs ;;
    diagnostics) diagnostics ;;
    uninstall) uninstall_package ;;
    accept-task9) accept_task9 ;;
    accept-task10) accept_task10 ;;
    accept-task11) accept_task11 ;;
    accept-task12-logged-in) accept_task12_logged_in ;;
    accept-task12-loginwindow-start) accept_task12_loginwindow_start ;;
    accept-task12-loginwindow-finish) accept_task12_loginwindow_finish ;;
    *) usage ;;
esac
