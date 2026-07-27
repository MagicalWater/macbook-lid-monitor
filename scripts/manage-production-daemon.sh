#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/lib/production-package-common.sh
source "$SCRIPT_DIR/lib/production-package-common.sh"
# shellcheck source=scripts/lib/production-installed-set.sh
source "$SCRIPT_DIR/lib/production-installed-set.sh"
# shellcheck source=scripts/lib/production-deployment-state.sh
source "$SCRIPT_DIR/lib/production-deployment-state.sh"
# shellcheck source=scripts/lib/production-observability.sh
source "$SCRIPT_DIR/lib/production-observability.sh"

usage() {
    printf '%s\n' 'usage: manage-production-daemon.sh prepare|verify|install|bootstrap|status|stop|bootout|disable|dry-run|deployment-dry-run|deployment-dry-run-reopen|deployment-dry-run-sleep-wake|deployment-enabled-once|deployment-recovery-resleep|activate|upgrade|rollback|reset-crash-budget|rotate-logs|diagnostics|operational-baseline|uninstall|accept-task9|accept-task10|accept-task11|accept-task12-logged-in|accept-task12-loginwindow-start|accept-task12-loginwindow-finish|accept-task12-sleep-wake|accept-task13-dry-run-path|accept-task13-enabled-once|accept-task13-recovery-resleep|accept-task14-reboot-start|accept-task14-reboot-finish' >&2
    exit 64
}

verify_managed_sleep_authority() {
    verify_managed_metadata \
        "$MANAGED_SLEEP_AUTHORITY" regular \
        "$(managed_expected_owner)" "$(managed_expected_group)" 600 1
}

ensure_managed_sleep_authority() {
    require_root_for_system
    assert_managed_path_safe "$MANAGED_SLEEP_AUTHORITY"
    if [[ -e "$MANAGED_SLEEP_AUTHORITY" || -L "$MANAGED_SLEEP_AUTHORITY" ]]; then
        verify_managed_sleep_authority
        return
    fi

    local temporary="$MANAGED_SLEEP_AUTHORITY.tmp"
    assert_managed_path_safe "$temporary"
    [[ ! -e "$temporary" && ! -L "$temporary" ]] || {
        printf 'error: refusing existing sleep-authority temporary path: %s\n' "$temporary" >&2
        return 74
    }
    (umask 077; : > "$temporary")
    chmod 0600 "$temporary"
    if [[ -z "$SYSTEM_ROOT" ]]; then chown root:wheel "$temporary"; fi
    mv -- "$temporary" "$MANAGED_SLEEP_AUTHORITY"
    verify_managed_sleep_authority
}

install_package_unlocked() {
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
    ensure_managed_sleep_authority
    invalidate_deployment_acceptance install >/dev/null
    printf 'installed mode=disabled\n'
}

install_package() { with_lifecycle_guard install_package_unlocked; }

bootstrap_job() {
    require_root_for_system
    verify_installed_set
    assert_regular_source "$MANAGED_PLIST"
    launchctl_system bootstrap system "$MANAGED_PLIST"
    printf 'bootstrapped label=%s\n' "$LAUNCHD_LABEL"
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

set_managed_mode() {
    local requested_mode=$1 temporary
    case "$requested_mode" in
        disabled|dry-run|enabled) ;;
        *) printf 'error=managed-mode-invalid mode=%s\n' "$requested_mode" >&2; return 64 ;;
    esac
    require_root_for_system
    verify_installed_set
    assert_regular_source "$MANAGED_CONFIG"
    temporary="$(mktemp "$MANAGED_SUPPORT/.config-mode.XXXXXX")"
    cleanup_managed_mode_temporary() { rm -f -- "$temporary"; }
    trap cleanup_managed_mode_temporary RETURN
    cp -- "$MANAGED_CONFIG" "$temporary"
    /usr/libexec/PlistBuddy -c "Set :Mode $requested_mode" "$temporary"
    chmod 0644 "$temporary"
    if [[ -z "$SYSTEM_ROOT" ]]; then chown root:wheel "$temporary"; fi
    mv -f -- "$temporary" "$MANAGED_CONFIG"
    trap - RETURN
    verify_installed_set
}

disable_job() {
    set_managed_mode disabled
    stop_job
    printf 'disabled label=%s\n' "$LAUNCHD_LABEL"
}

reset_crash_budget() {
    require_root_for_system
    verify_installed_set
    assert_regular_source "$MANAGED_CONFIG"
    assert_managed_path_safe "$MANAGED_SUPPORT/crash-budget.json"
    [[ ! -L "$MANAGED_SUPPORT/crash-budget.json" ]] || {
        printf 'error: refusing symlink crash budget path\n' >&2
        return 74
    }
    local mode process_count
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG")"
    [[ "$mode" == disabled ]] || {
        printf 'error: crash budget reset requires disabled mode\n' >&2
        return 70
    }
    if [[ -z "$SYSTEM_ROOT" ]]; then
        process_count="$({ pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | wc -l | tr -d ' ')"
        [[ "$process_count" == 0 ]] || {
            printf 'error: crash budget reset requires no resident daemon\n' >&2
            return 70
        }
    fi
    rm -f -- "$MANAGED_SUPPORT/crash-budget.json"
    printf 'reset crash-budget label=%s mode=disabled\n' "$LAUNCHD_LABEL"
}


set_enabled_mode() {
    set_managed_mode enabled
    bootout_job
    bootstrap_job
    printf 'mode=enabled label=%s\n' "$LAUNCHD_LABEL"
}

set_dry_run_mode() {
    set_managed_mode dry-run
    bootout_job
    bootstrap_job
    printf 'mode=dry-run label=%s\n' "$LAUNCHD_LABEL"
}

deployment_test_checkpoint() {
    local stage=$1
    if [[ -n "${MLM_TEST_DEPLOYMENT_FAIL_STAGE:-}" || -n "${MLM_TEST_DEPLOYMENT_HOLD_SECONDS:-}" ]]; then
        [[ -n "$SYSTEM_ROOT" ]] || {
            printf 'error=test-hook-production-disabled reason=deployment\n' >&2
            return 64
        }
    fi
    if [[ "${MLM_TEST_DEPLOYMENT_FAIL_STAGE:-}" == "$stage" ]]; then
        printf 'error=deployment-test-failure stage=%s\n' "$stage" >&2
        return 70
    fi
    if [[ -n "${MLM_TEST_DEPLOYMENT_HOLD_SECONDS:-}" ]]; then
        sleep "$MLM_TEST_DEPLOYMENT_HOLD_SECONDS"
    fi
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

accept_task12_sleep_wake() {
    require_root_for_system
    local mode before_pid process_count log_offset evidence_found=0
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG")"
    [[ "$mode" == "disabled" ]] || { printf 'error: expected disabled starting mode\n' >&2; return 65; }
    cleanup_task12_sleep_wake_to_disabled() {
        if [[ -f "$MANAGED_CONFIG" && ! -L "$MANAGED_CONFIG" ]]; then
            disable_job >/dev/null 2>&1 || true
            bootout_job >/dev/null 2>&1 || true
            bootstrap_job >/dev/null 2>&1 || true
        fi
    }
    trap cleanup_task12_sleep_wake_to_disabled EXIT
    if [[ "${1:-legacy}" != stable ]]; then
        prepare_as_invoking_user
        verify_package
        upgrade_package
    else
        verify_installed_set
    fi
    set_dry_run_mode
    verify_logged_in_dry_run
    if [[ -n "$SYSTEM_ROOT" ]]; then
        printf 'timestamp=test event=state-changed pid=1 state=monitoring-disarmed\n' >> "$MANAGED_STDOUT_LOG"
        evidence_found=1
        before_pid=1
    else
        before_pid="$(pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$')"
        log_offset="$(stat -f '%z' "$MANAGED_STDOUT_LOG")"
        printf 'sleep-imminent task=12 scope=sleep-wake pid=%s\n' "$before_pid"
        /usr/bin/pmset sleepnow
        for _ in {1..30}; do
            if dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -q 'event=state-changed.*state=monitoring-disarmed'; then
                evidence_found=1
                break
            fi
            sleep 1
        done
    fi
    [[ "$evidence_found" -eq 1 ]] || { printf 'error: wake-recovery production evidence missing\n' >&2; return 70; }
    process_count="$({ pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | wc -l | tr -d ' ')"
    if [[ -z "$SYSTEM_ROOT" ]]; then
        [[ "$process_count" == 1 ]] || { printf 'error: expected one daemon after wake, got %s\n' "$process_count" >&2; return 70; }
        [[ "$(pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$')" == "$before_pid" ]] || {
            printf 'error: daemon PID changed across sleep/wake\n' >&2
            return 70
        }
    fi
    printf 'verified task=12 scope=sleep-wake wake-evidence=true pid-stable=true\n'
    disable_job
    bootout_job
    bootstrap_job
    diagnostics
    trap - EXIT
    printf 'accepted task=12 scope=sleep-wake final-mode=disabled label=%s\n' "$LAUNCHD_LABEL"
}

deployment_dry_run_sleep_wake() {
    require_root_for_system
    verify_deployment_acceptance deployment-dry-run
    accept_task12_sleep_wake stable
}

deployment_dry_run_reopen() {
    require_root_for_system
    local mode before_pid after_pid log_offset would_sleep_count rearmed_count process_count
    verify_deployment_acceptance deployment-dry-run
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG")"
    [[ "$mode" == disabled ]] || { printf 'error: expected disabled starting mode\n' >&2; return 65; }
    cleanup_task17_dry_run_reopen_to_disabled() {
        if [[ -f "$MANAGED_CONFIG" && ! -L "$MANAGED_CONFIG" ]]; then
            disable_job >/dev/null 2>&1 || true
            bootout_job >/dev/null 2>&1 || true
            bootstrap_job >/dev/null 2>&1 || true
        fi
    }
    trap cleanup_task17_dry_run_reopen_to_disabled EXIT
    set_dry_run_mode
    verify_logged_in_dry_run
    if [[ -n "$SYSTEM_ROOT" ]]; then
        before_pid=1
        mkdir -p -- "$MANAGED_LOG_DIR"
        touch "$MANAGED_STDOUT_LOG"
        log_offset="$(stat -f '%z' "$MANAGED_STDOUT_LOG")"
        {
            printf 'timestamp=test event=transition pid=1 name=candidate-started\n'
            printf 'timestamp=test event=transition pid=1 name=debounce-elapsed\n'
            printf 'timestamp=test event=transition pid=1 name=sleep-request-attempted\n'
            printf 'timestamp=test event=transition pid=1 name=would-sleep\n'
            printf 'timestamp=test event=transition pid=1 name=monitoring-armed\n'
        } >> "$MANAGED_STDOUT_LOG"
    else
        before_pid="$(pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$')"
        log_offset="$(stat -f '%z' "$MANAGED_STDOUT_LOG")"
        printf 'armed task=17 scope=dry-run-reopen pid=%s action=move-lid-below-68-degrees-and-hold-2-seconds-within-180-seconds\n' "$before_pid"
        for _ in {1..180}; do
            would_sleep_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=would-sleep' || true)"
            [[ "$would_sleep_count" -ge 1 ]] && break
            sleep 1
        done
        [[ "${would_sleep_count:-0}" -ge 1 ]] || { printf 'error: would-sleep evidence missing\n' >&2; return 70; }
        printf 'reopen task=17 scope=dry-run-reopen action=move-lid-above-78-degrees-within-180-seconds\n'
        for _ in {1..180}; do
            rearmed_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=monitoring-armed' || true)"
            [[ "$rearmed_count" -ge 1 ]] && break
            sleep 1
        done
    fi
    would_sleep_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=would-sleep' || true)"
    rearmed_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=monitoring-armed' || true)"
    [[ "$would_sleep_count" == 1 ]] || { printf 'error: expected exactly one would-sleep event, got %s\n' "$would_sleep_count" >&2; return 70; }
    [[ "$rearmed_count" -ge 1 ]] || { printf 'error: reopen rearm evidence missing\n' >&2; return 70; }
    if [[ -z "$SYSTEM_ROOT" ]]; then
        process_count="$({ pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | wc -l | tr -d ' ')"
        [[ "$process_count" == 1 ]] || { printf 'error: expected one dry-run daemon after reopen, got %s\n' "$process_count" >&2; return 70; }
        after_pid="$(pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$')"
        [[ "$after_pid" == "$before_pid" ]] || { printf 'error: daemon PID changed across reopen\n' >&2; return 70; }
    fi
    printf 'verified task=17 scope=dry-run-reopen would-sleep=true rearmed=true pid-stable=true\n'
    disable_job
    bootout_job
    bootstrap_job
    diagnostics
    trap - EXIT
    printf 'accepted task=17 scope=dry-run-reopen final-mode=disabled label=%s\n' "$LAUNCHD_LABEL"
}

accept_task13_enabled_once() {
    require_root_for_system
    local mode before_pid process_count log_offset attempt_count=0 returned_count=0 wake_found=0
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG")"
    [[ "$mode" == "disabled" ]] || { printf 'error: expected disabled starting mode\n' >&2; return 65; }
    cleanup_task13_enabled_once_to_disabled() {
        if [[ -f "$MANAGED_CONFIG" && ! -L "$MANAGED_CONFIG" ]]; then
            disable_job >/dev/null 2>&1 || true
            bootout_job >/dev/null 2>&1 || true
            bootstrap_job >/dev/null 2>&1 || true
        fi
    }
    trap cleanup_task13_enabled_once_to_disabled EXIT
    if [[ "${1:-legacy}" != stable ]]; then
        prepare_as_invoking_user
        verify_package
        upgrade_package
    fi
    set_enabled_mode
    deployment_test_checkpoint enabled-once
    if [[ -n "$SYSTEM_ROOT" ]]; then
        mkdir -p -- "$MANAGED_LOG_DIR"
        touch "$MANAGED_STDOUT_LOG"
        log_offset="$(stat -f '%z' "$MANAGED_STDOUT_LOG")"
        {
            printf 'timestamp=test event=transition pid=1 name=sleep-request-attempted\n'
            printf 'timestamp=test event=state-changed pid=1 state=monitoring-disarmed\n'
        } >> "$MANAGED_STDOUT_LOG"
        before_pid=1
        attempt_count=1
        wake_found=1
    else
        sleep 2
        launchctl print "system/$LAUNCHD_LABEL" >/dev/null
        process_count="$({ pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | wc -l | tr -d ' ')"
        [[ "$process_count" == 1 ]] || { printf 'error: expected one enabled daemon before close, got %s\n' "$process_count" >&2; return 70; }
        before_pid="$(pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$')"
        log_offset="$(stat -f '%z' "$MANAGED_STDOUT_LOG")"
        printf 'armed task=13 scope=enabled-once pid=%s action=close-lid-within-180-seconds\n' "$before_pid"
        for _ in {1..180}; do
            attempt_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=sleep-request-attempted' || true)"
            if [[ "$attempt_count" -ge 1 ]] && dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -q 'event=state-changed.*state=monitoring-disarmed'; then
                wake_found=1
                break
            fi
            sleep 1
        done
    fi
    attempt_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=sleep-request-attempted' || true)"
    returned_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=sleep-requested' || true)"
    [[ "$attempt_count" == 1 ]] || { printf 'error: expected exactly one sleep-request-attempted event, got %s\n' "$attempt_count" >&2; return 70; }
    [[ "$returned_count" -le 1 ]] || { printf 'error: expected at most one sleep-requested return event, got %s\n' "$returned_count" >&2; return 70; }
    [[ "$wake_found" -eq 1 ]] || { printf 'error: wake-recovery production evidence missing\n' >&2; return 70; }
    if [[ -z "$SYSTEM_ROOT" ]]; then
        process_count="$({ pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | wc -l | tr -d ' ')"
        [[ "$process_count" == 1 ]] || { printf 'error: expected one daemon after wake, got %s\n' "$process_count" >&2; return 70; }
        [[ "$(pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$')" == "$before_pid" ]] || { printf 'error: daemon PID changed across enabled sleep/wake\n' >&2; return 70; }
    fi
    printf 'verified task=13 scope=enabled-once attempt-count=1 return-count=%s wake-evidence=true pid-stable=true\n' "$returned_count"
    disable_job
    bootout_job
    bootstrap_job
    diagnostics
    trap - EXIT
    printf 'accepted task=13 scope=enabled-once final-mode=disabled label=%s\n' "$LAUNCHD_LABEL"
}

accept_task13_recovery_resleep() {
    require_root_for_system
    local mode before_pid process_count log_offset attempt_count=0 return_count=0 recovery_count=0 wake_count=0
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG")"
    [[ "$mode" == "disabled" ]] || { printf 'error: expected disabled starting mode\n' >&2; return 65; }
    cleanup_task13_recovery_resleep_to_disabled() {
        if [[ -f "$MANAGED_CONFIG" && ! -L "$MANAGED_CONFIG" ]]; then
            disable_job >/dev/null 2>&1 || true
            bootout_job >/dev/null 2>&1 || true
            bootstrap_job >/dev/null 2>&1 || true
        fi
    }
    trap cleanup_task13_recovery_resleep_to_disabled EXIT
    if [[ "${1:-legacy}" != stable ]]; then
        prepare_as_invoking_user
        verify_package
        upgrade_package
    fi
    set_enabled_mode
    deployment_test_checkpoint recovery-resleep
    if [[ -n "$SYSTEM_ROOT" ]]; then
        mkdir -p -- "$MANAGED_LOG_DIR"
        touch "$MANAGED_STDOUT_LOG"
        log_offset="$(stat -f '%z' "$MANAGED_STDOUT_LOG")"
        {
            printf 'timestamp=test event=transition pid=1 name=sleep-request-attempted\n'
            printf 'timestamp=test event=sleep-requested pid=1\n'
            printf 'timestamp=test event=state-changed pid=1 state=monitoring-disarmed\n'
            printf 'timestamp=test event=transition pid=1 name=recovery-resleep\n'
            printf 'timestamp=test event=transition pid=1 name=sleep-request-attempted\n'
            printf 'timestamp=test event=sleep-requested pid=1\n'
            printf 'timestamp=test event=state-changed pid=1 state=monitoring-disarmed\n'
        } >> "$MANAGED_STDOUT_LOG"
        before_pid=1
    else
        sleep 2
        launchctl print "system/$LAUNCHD_LABEL" >/dev/null
        process_count="$({ pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | wc -l | tr -d ' ')"
        [[ "$process_count" == 1 ]] || { printf 'error: expected one enabled daemon before recovery acceptance, got %s\n' "$process_count" >&2; return 70; }
        before_pid="$(pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$')"
        log_offset="$(stat -f '%z' "$MANAGED_STDOUT_LOG")"
        printf 'armed task=13 scope=recovery-resleep pid=%s first-action=move-lid-below-68-degrees-and-hold-2-seconds second-action=after-first-wake-keep-lid-below-68-degrees-for-15-seconds third-action=after-second-sleep-open-lid-and-wake-with-keyboard\n' "$before_pid"
        for _ in {1..300}; do
            attempt_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=sleep-request-attempted' || true)"
            recovery_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=recovery-resleep' || true)"
            wake_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=state-changed.*state=monitoring-disarmed' || true)"
            [[ "$attempt_count" -ge 2 && "$recovery_count" -ge 1 && "$wake_count" -ge 2 ]] && break
            sleep 1
        done
    fi
    attempt_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=sleep-request-attempted' || true)"
    return_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=sleep-requested' || true)"
    recovery_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=recovery-resleep' || true)"
    wake_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=state-changed.*state=monitoring-disarmed' || true)"
    [[ "$attempt_count" == 2 ]] || { printf 'error: expected exactly two sleep-request-attempted events, got %s\n' "$attempt_count" >&2; return 70; }
    [[ "$return_count" -le 2 ]] || { printf 'error: expected at most two sleep-requested return events, got %s\n' "$return_count" >&2; return 70; }
    [[ "$recovery_count" == 1 ]] || { printf 'error: expected exactly one recovery-resleep event, got %s\n' "$recovery_count" >&2; return 70; }
    [[ "$wake_count" -ge 2 ]] || { printf 'error: expected two wake-recovery events, got %s\n' "$wake_count" >&2; return 70; }
    if [[ -z "$SYSTEM_ROOT" ]]; then
        process_count="$({ pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | wc -l | tr -d ' ')"
        [[ "$process_count" == 1 ]] || { printf 'error: expected one daemon after recovery resleep, got %s\n' "$process_count" >&2; return 70; }
        [[ "$(pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$')" == "$before_pid" ]] || { printf 'error: daemon PID changed across recovery resleep\n' >&2; return 70; }
    fi
    printf 'verified task=13 scope=recovery-resleep attempt-count=2 return-count=%s recovery-count=1 wake-count=%s pid-stable=true\n' "$return_count" "$wake_count"
    disable_job
    bootout_job
    bootstrap_job
    diagnostics
    trap - EXIT
    printf 'accepted task=13 scope=recovery-resleep final-mode=disabled label=%s\n' "$LAUNCHD_LABEL"
}

accept_task13_dry_run_path() {
    require_root_for_system
    local mode log_offset candidate_count debounce_count attempt_count would_sleep_count process_count
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG")"
    [[ "$mode" == "disabled" ]] || { printf 'error: expected disabled starting mode\n' >&2; return 65; }
    cleanup_task13_dry_run_path_to_disabled() {
        if [[ -f "$MANAGED_CONFIG" && ! -L "$MANAGED_CONFIG" ]]; then
            disable_job >/dev/null 2>&1 || true
            bootout_job >/dev/null 2>&1 || true
            bootstrap_job >/dev/null 2>&1 || true
        fi
    }
    trap cleanup_task13_dry_run_path_to_disabled EXIT
    if [[ "${1:-legacy}" != stable ]]; then
        prepare_as_invoking_user
        verify_package
        upgrade_package
    fi
    set_dry_run_mode
    deployment_test_checkpoint dry-run
    verify_logged_in_dry_run
    if [[ -n "$SYSTEM_ROOT" ]]; then
        mkdir -p -- "$MANAGED_LOG_DIR"
        touch "$MANAGED_STDOUT_LOG"
        log_offset="$(stat -f '%z' "$MANAGED_STDOUT_LOG")"
        {
            printf 'timestamp=test event=transition pid=1 name=candidate-started\n'
            printf 'timestamp=test event=transition pid=1 name=debounce-elapsed\n'
            printf 'timestamp=test event=transition pid=1 name=sleep-request-attempted\n'
            printf 'timestamp=test event=transition pid=1 name=would-sleep\n'
        } >> "$MANAGED_STDOUT_LOG"
    else
        log_offset="$(stat -f '%z' "$MANAGED_STDOUT_LOG")"
        printf 'armed task=13 scope=dry-run-path action=move-lid-below-68-degrees-and-hold-2-seconds-within-180-seconds\n'
        for _ in {1..180}; do
            would_sleep_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=would-sleep' || true)"
            [[ "$would_sleep_count" -ge 1 ]] && break
            sleep 1
        done
    fi
    candidate_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=candidate-started' || true)"
    debounce_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=debounce-elapsed' || true)"
    attempt_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=sleep-request-attempted' || true)"
    would_sleep_count="$(dd if="$MANAGED_STDOUT_LOG" bs=1 skip="$log_offset" 2>/dev/null | grep -c 'event=transition.*name=would-sleep' || true)"
    [[ "$candidate_count" -ge 1 ]] || { printf 'error: candidate-started evidence missing\n' >&2; return 70; }
    [[ "$debounce_count" -ge 1 ]] || { printf 'error: debounce-elapsed evidence missing\n' >&2; return 70; }
    [[ "$attempt_count" == 1 ]] || { printf 'error: expected exactly one sleep-request-attempted event, got %s\n' "$attempt_count" >&2; return 70; }
    [[ "$would_sleep_count" == 1 ]] || { printf 'error: expected exactly one would-sleep event, got %s\n' "$would_sleep_count" >&2; return 70; }
    if [[ -z "$SYSTEM_ROOT" ]]; then
        process_count="$({ pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | wc -l | tr -d ' ')"
        [[ "$process_count" == 1 ]] || { printf 'error: expected one dry-run daemon, got %s\n' "$process_count" >&2; return 70; }
    fi
    printf 'verified task=13 scope=dry-run-path candidate=true debounce=true attempt-count=1 would-sleep-count=1\n'
    disable_job
    bootout_job
    bootstrap_job
    diagnostics
    trap - EXIT
    printf 'accepted task=13 scope=dry-run-path final-mode=disabled label=%s\n' "$LAUNCHD_LABEL"
}

deployment_dry_run() {
    require_root_for_system
    verify_installed_set
    verify_target_hardware
    accept_task13_dry_run_path stable
    record_deployment_acceptance deployment-dry-run pass
}

deployment_enabled_once() {
    require_root_for_system
    verify_deployment_acceptance deployment-dry-run
    accept_task13_enabled_once stable
    record_deployment_acceptance deployment-enabled-once pass
}

deployment_recovery_resleep() {
    require_root_for_system
    verify_deployment_acceptance deployment-dry-run deployment-enabled-once
    accept_task13_recovery_resleep stable
    record_deployment_acceptance deployment-recovery-resleep pass
}

activate_deployment() {
    require_root_for_system
    if [[ -n "${MLM_TEST_ACTIVATION_BOOTSTRAP_FAIL:-}" && -z "$SYSTEM_ROOT" ]]; then
        printf 'error=test-hook-production-disabled reason=activation-bootstrap\n' >&2
        return 65
    fi
    verify_deployment_acceptance deployment-dry-run deployment-enabled-once deployment-recovery-resleep
    set_managed_mode enabled
    bootout_job
    if [[ -n "${MLM_TEST_ACTIVATION_BOOTSTRAP_FAIL:-}" ]] || ! bootstrap_job; then
        set_managed_mode disabled
        bootout_job
        bootstrap_job >/dev/null 2>&1 || true
        printf 'error: activation bootstrap failed; restored disabled mode\n' >&2
        return 70
    fi
    printf 'activated deployment mode=enabled label=%s\n' "$LAUNCHD_LABEL"
}

uninstall_package_unlocked() {
    require_root_for_system
    verify_installed_set
    for path in "$MANAGED_BINARY" "$MANAGED_PLIST" "$MANAGED_CONFIG" "$MANAGED_MANIFEST" \
        "$MANAGED_SLEEP_AUTHORITY" "$MANAGED_ACCEPTANCE_STATE" "$MANAGED_REBOOT_STATE" \
        "$MANAGED_HEALTH_STATE" "$MANAGED_SUPPORT/crash-budget.json" "$MANAGED_TASK14_STATE" \
        "$MANAGED_STDOUT_LOG" "$MANAGED_STDERR_LOG" "$MANAGED_ROLLBACK"; do
        assert_managed_path_safe "$path"
        [[ -L "$path" ]] && { printf 'error: refusing symlink uninstall path: %s\n' "$path" >&2; return 74; }
    done
    prepare_maintenance_disabled_state
    for path in "$MANAGED_BINARY" "$MANAGED_PLIST" "$MANAGED_CONFIG" "$MANAGED_MANIFEST" \
        "$MANAGED_SLEEP_AUTHORITY" "$MANAGED_ACCEPTANCE_STATE" "$MANAGED_REBOOT_STATE" \
        "$MANAGED_HEALTH_STATE" "$MANAGED_SUPPORT/crash-budget.json" "$MANAGED_TASK14_STATE" \
        "$MANAGED_STDOUT_LOG" "$MANAGED_STDERR_LOG"; do
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


uninstall_package() { with_lifecycle_guard uninstall_package_unlocked; }

verify_uninstalled_state() {
    local found=0
    for path in "$MANAGED_BINARY" "$MANAGED_PLIST" "$MANAGED_CONFIG" "$MANAGED_MANIFEST" \
        "$MANAGED_SLEEP_AUTHORITY" "$MANAGED_ACCEPTANCE_STATE" "$MANAGED_REBOOT_STATE" \
        "$MANAGED_HEALTH_STATE" "$MANAGED_SUPPORT/crash-budget.json" "$MANAGED_TASK14_STATE" "$MANAGED_ROLLBACK" \
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

current_boot_epoch() {
    if [[ -n "${MLM_TEST_BOOT_EPOCH:-}" ]]; then
        [[ -n "$SYSTEM_ROOT" ]] || {
            printf 'error=test-hook-production-disabled reason=boot-epoch\n' >&2
            return 64
        }
        printf '%s\n' "$MLM_TEST_BOOT_EPOCH"
        return
    fi
    sysctl -n kern.boottime | sed -E 's/^\{ sec = ([0-9]+), usec = [0-9]+ \}.*$/\1/'
}

accept_task14_reboot_start() {
    require_root_for_system
    local mode current_version rollback_version boot_epoch
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG")"
    [[ "$mode" == "disabled" ]] || { printf 'error: expected disabled starting mode\n' >&2; return 65; }
    prepare_as_invoking_user
    verify_package
    upgrade_package
    disable_job
    bootout_job
    bootstrap_job
    current_version="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$MANAGED_MANIFEST")"
    rollback_version="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$MANAGED_ROLLBACK/manifest.plist")"
    [[ "$current_version" != "$rollback_version" ]] || { printf 'error: task14 requires distinct current and rollback versions\n' >&2; return 70; }
    boot_epoch="$(current_boot_epoch)"
    {
        printf 'schema=1\n'
        printf 'boot_epoch=%s\n' "$boot_epoch"
        printf 'current_version=%s\n' "$current_version"
        printf 'rollback_version=%s\n' "$rollback_version"
    } > "$MANAGED_TASK14_STATE"
    chmod 0600 "$MANAGED_TASK14_STATE"
    if [[ -z "$SYSTEM_ROOT" ]]; then chown root:wheel "$MANAGED_TASK14_STATE"; fi
    diagnostics
    printf 'armed task=14 scope=reboot current-version=%s rollback-version=%s boot-epoch=%s action=restart-mac-then-run-accept-task14-reboot-finish\n' \
        "$current_version" "$rollback_version" "$boot_epoch"
}

accept_task14_reboot_finish() {
    require_root_for_system
    verify_installed_set
    assert_regular_source "$MANAGED_TASK14_STATE"
    local schema start_boot current_boot expected_current expected_rollback actual_current mode process_count actual_rollback state_mtime
    schema="$(awk -F= '$1 == "schema" {print $2}' "$MANAGED_TASK14_STATE")"
    start_boot="$(awk -F= '$1 == "boot_epoch" {print $2}' "$MANAGED_TASK14_STATE")"
    expected_current="$(awk -F= '$1 == "current_version" {print $2}' "$MANAGED_TASK14_STATE")"
    expected_rollback="$(awk -F= '$1 == "rollback_version" {print $2}' "$MANAGED_TASK14_STATE")"
    [[ "$schema" == 1 && -n "$start_boot" && -n "$expected_current" && -n "$expected_rollback" ]] || {
        printf 'error: invalid task14 reboot state\n' >&2
        return 65
    }
    current_boot="$(current_boot_epoch)"
    if [[ "$start_boot" -ge 1000000000 ]]; then
        [[ "$current_boot" -gt "$start_boot" ]] || { printf 'error: reboot not detected
' >&2; return 70; }
    else
        if [[ -n "${MLM_TEST_STATE_MTIME:-}" ]]; then
            [[ -n "$SYSTEM_ROOT" ]] || {
                printf 'error=test-hook-production-disabled reason=state-mtime\n' >&2
                return 64
            }
            state_mtime="$MLM_TEST_STATE_MTIME"
        else
            state_mtime="$(stat -f '%m' "$MANAGED_TASK14_STATE")"
        fi
        [[ "$state_mtime" -lt "$current_boot" ]] || { printf 'error: legacy reboot state predates no detected boot
' >&2; return 70; }
        printf 'verified task=14 scope=reboot-proof migration=legacy-usec state-mtime=%s boot-epoch=%s
' "$state_mtime" "$current_boot"
    fi
    actual_current="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$MANAGED_MANIFEST")"
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG")"
    [[ "$actual_current" == "$expected_current" ]] || { printf 'error: post-reboot version mismatch\n' >&2; return 70; }
    [[ "$mode" == disabled ]] || { printf 'error: post-reboot mode is not disabled\n' >&2; return 70; }
    if [[ -z "$SYSTEM_ROOT" ]]; then
        launchctl print "system/$LAUNCHD_LABEL" >/dev/null || { printf 'error: system job missing after reboot\n' >&2; return 70; }
        process_count="$({ pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | wc -l | tr -d ' ')"
        [[ "$process_count" == 0 ]] || { printf 'error: disabled daemon unexpectedly running after reboot\n' >&2; return 70; }
    fi
    printf 'verified task=14 scope=reboot boot-changed=true job-loaded=true mode=disabled process-count=0 version=%s\n' "$actual_current"
    rollback_upgrade
    actual_rollback="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$MANAGED_MANIFEST")"
    [[ "$actual_rollback" == "$expected_rollback" ]] || { printf 'error: rollback version mismatch\n' >&2; return 70; }
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG")"
    [[ "$mode" == disabled ]] || { printf 'error: rollback did not restore disabled mode\n' >&2; return 70; }
    printf 'verified task=14 scope=rollback version=%s mode=disabled\n' "$actual_rollback"
    uninstall_package
    verify_uninstalled_state
    printf 'accepted task=14 reboot=true rollback=true uninstall=true residual-state=clean label=%s\n' "$LAUNCHD_LABEL"
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

prepare_maintenance_disabled_state() {
    require_root_for_system
    verify_installed_set
    set_managed_mode disabled
    bootout_job
    if [[ -z "$SYSTEM_ROOT" ]] && pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' >/dev/null 2>&1; then
        printf 'error: maintenance requires no resident daemon\n' >&2
        return 70
    fi
    printf 'maintenance-state mode=disabled job=booted-out process-count=0\n'
}

backup_current_set() {
    verify_managed_set
    assert_regular_source "$MANAGED_BINARY"
    assert_regular_source "$MANAGED_PLIST"
    assert_regular_source "$MANAGED_CONFIG"
    assert_regular_source "$MANAGED_MANIFEST"
    assert_managed_path_safe "$MANAGED_ROLLBACK"
    [[ ! -L "$MANAGED_ROLLBACK" ]] || { printf 'error=rollback-set-invalid reason=symlink path=%s\n' "$MANAGED_ROLLBACK" >&2; return 74; }
    rm -rf -- "$MANAGED_ROLLBACK"
    mkdir -p -- "$MANAGED_ROLLBACK"
    cp -p -- "$MANAGED_BINARY" "$MANAGED_ROLLBACK/macbook-lid-monitor-daemon"
    cp -p -- "$MANAGED_PLIST" "$MANAGED_ROLLBACK/com.crazydennies.macbook-lid-monitor.plist"
    cp -p -- "$MANAGED_CONFIG" "$MANAGED_ROLLBACK/config.plist"
    cp -p -- "$MANAGED_MANIFEST" "$MANAGED_ROLLBACK/manifest.plist"
}

verify_managed_set() {
    verify_installed_set
}

activate_staged_set_disabled() {
    verify_staged_payload
    install -m 0755 "$STAGING_DIR/macbook-lid-monitor-daemon" "$MANAGED_BINARY.tmp"
    install -m 0644 "$STAGING_DIR/com.crazydennies.macbook-lid-monitor.plist" "$MANAGED_PLIST.tmp"
    install -m 0644 "$STAGING_DIR/config.plist" "$MANAGED_CONFIG.tmp"
    install -m 0644 "$STAGING_DIR/manifest.plist" "$MANAGED_MANIFEST.tmp"
    mv -f -- "$MANAGED_BINARY.tmp" "$MANAGED_BINARY"
    mv -f -- "$MANAGED_PLIST.tmp" "$MANAGED_PLIST"
    mv -f -- "$MANAGED_CONFIG.tmp" "$MANAGED_CONFIG"
    mv -f -- "$MANAGED_MANIFEST.tmp" "$MANAGED_MANIFEST"
    if [[ -z "$SYSTEM_ROOT" ]]; then
        chown root:wheel "$MANAGED_BINARY" "$MANAGED_PLIST" "$MANAGED_CONFIG" "$MANAGED_MANIFEST"
    fi
    ensure_managed_sleep_authority
    verify_managed_set
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG")" == disabled ]]
}

restore_rollback_set_disabled() {
    verify_rollback_set
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
    /usr/libexec/PlistBuddy -c 'Set :Mode disabled' "$MANAGED_CONFIG.tmp"
    mv -f -- "$MANAGED_BINARY.tmp" "$MANAGED_BINARY"
    mv -f -- "$MANAGED_PLIST.tmp" "$MANAGED_PLIST"
    mv -f -- "$MANAGED_CONFIG.tmp" "$MANAGED_CONFIG"
    mv -f -- "$MANAGED_MANIFEST.tmp" "$MANAGED_MANIFEST"
    if [[ -z "$SYSTEM_ROOT" ]]; then
        chown root:wheel "$MANAGED_BINARY" "$MANAGED_PLIST" "$MANAGED_CONFIG" "$MANAGED_MANIFEST"
    fi
    ensure_managed_sleep_authority
    verify_managed_set
}

rollback_upgrade_unlocked() {
    require_root_for_system
    verify_installed_set
    ensure_managed_sleep_authority
    verify_rollback_set
    prepare_maintenance_disabled_state
    restore_rollback_set_disabled
    invalidate_deployment_acceptance rollback >/dev/null
    bootstrap_job
    printf 'rolled-back mode=disabled label=%s\n' "$LAUNCHD_LABEL"
}

rollback_upgrade() { with_lifecycle_guard rollback_upgrade_unlocked; }

upgrade_package_unlocked() {
    require_root_for_system
    local provenance_only=0
    verify_installed_set
    ensure_managed_sleep_authority
    verify_staged_payload
    if staged_payload_matches_installed_identity; then
        if [[ "$(manifest_value Version)" == "$(staged_manifest_value Version)" && \
              "$(manifest_value SourceCommit)" == "$(staged_manifest_value SourceCommit)" ]]; then
            printf 'upgrade=no-op identity=unchanged acceptance=preserved\n'
            return 0
        fi
        provenance_only=1
    fi
    verify_package
    prepare_maintenance_disabled_state
    backup_current_set
    invalidate_deployment_acceptance upgrade >/dev/null
    local failed=0
    activate_staged_set_disabled || failed=1
    if [[ "${MLM_FAIL_UPGRADE_STAGE:-}" == "after-activation" || "${MLM_FAIL_UPGRADE_STAGE:-}" == "rollback-restore" ]]; then failed=1; fi
    if [[ "$failed" -eq 0 ]]; then
        bootstrap_job || failed=1
    fi
    if [[ "$failed" -ne 0 ]]; then
        if ! restore_rollback_set_disabled; then
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
    if [[ "$provenance_only" -eq 1 ]]; then
        printf 'upgrade=provenance-updated acceptance=invalidated mode=disabled label=%s\n' "$LAUNCHD_LABEL"
    else
        printf 'upgraded mode=disabled label=%s\n' "$LAUNCHD_LABEL"
    fi
}

upgrade_package() { with_lifecycle_guard upgrade_package_unlocked; }

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

    local version source_commit checksum plist_checksum config_checksum
    version="$(package_version)"
    source_commit="$(git -c safe.directory="$REPO_ROOT" -C "$REPO_ROOT" rev-parse HEAD)"
    checksum="$(sha256_file "$STAGING_DIR/macbook-lid-monitor-daemon")"
    plist_checksum="$(sha256_file "$STAGING_DIR/com.crazydennies.macbook-lid-monitor.plist")"
    config_checksum="$(normalized_config_sha256 "$STAGING_DIR/config.plist")"
    /usr/libexec/PlistBuddy -c "Set :Version $version" "$STAGING_DIR/manifest.plist"
    /usr/libexec/PlistBuddy -c "Set :SourceCommit $source_commit" "$STAGING_DIR/manifest.plist"
    /usr/libexec/PlistBuddy -c "Set :BinarySHA256 $checksum" "$STAGING_DIR/manifest.plist"
    /usr/libexec/PlistBuddy -c "Set :PlistSHA256 $plist_checksum" "$STAGING_DIR/manifest.plist"
    /usr/libexec/PlistBuddy -c "Set :DisabledConfigSHA256 $config_checksum" "$STAGING_DIR/manifest.plist"
    printf 'prepared staging=%s version=%s source-commit=%s binary=%s plist=%s config=%s\n' \
        "$STAGING_DIR" "$version" "$source_commit" "$checksum" "$plist_checksum" "$config_checksum"
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

    local expected actual version source_commit expected_plist actual_plist expected_config actual_config
    expected="$(/usr/libexec/PlistBuddy -c 'Print :BinarySHA256' "$manifest")"
    actual="$(sha256_file "$binary")"
    version="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$manifest")"
    source_commit="$(/usr/libexec/PlistBuddy -c 'Print :SourceCommit' "$manifest")"
    expected_plist="$(/usr/libexec/PlistBuddy -c 'Print :PlistSHA256' "$manifest")"
    actual_plist="$(sha256_file "$plist")"
    expected_config="$(/usr/libexec/PlistBuddy -c 'Print :DisabledConfigSHA256' "$manifest")"
    actual_config="$(normalized_config_sha256 "$config")"
    test "$expected" = "$actual"
    test "$version" = "$(package_version)"
    test "$source_commit" = "$(git -c safe.directory="$REPO_ROOT" -C "$REPO_ROOT" rev-parse HEAD)"
    test "$expected_plist" = "$actual_plist"
    test "$expected_config" = "$actual_config"
    if /usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables' "$plist" >/dev/null 2>&1; then
        printf 'error: staged LaunchDaemon must not define EnvironmentVariables\n' >&2
        return 65
    fi
    printf 'verified staging=%s version=%s source-commit=%s binary=%s plist=%s config=%s\n' \
        "$STAGING_DIR" "$version" "$source_commit" "$actual" "$actual_plist" "$actual_config"
}

[[ $# -eq 1 ]] || usage
case "$1" in
    prepare) prepare_package ;;
    verify) verify_package ;;
    install) install_package ;;
    installed-identity) installed_identity_lines ;;
    bootstrap) bootstrap_job ;;
    status) status_job ;;
    stop) stop_job ;;
    bootout) bootout_job ;;
    disable) disable_job ;;
    dry-run) set_dry_run_mode ;;
    deployment-dry-run) deployment_dry_run ;;
    deployment-dry-run-reopen) deployment_dry_run_reopen ;;
    deployment-dry-run-sleep-wake) deployment_dry_run_sleep_wake ;;
    deployment-enabled-once) deployment_enabled_once ;;
    deployment-recovery-resleep) deployment_recovery_resleep ;;
    activate) activate_deployment ;;
    upgrade) upgrade_package ;;
    rollback) rollback_upgrade ;;
    reset-crash-budget) reset_crash_budget ;;
    rotate-logs) rotate_logs ;;
    diagnostics) diagnostics ;;
    operational-baseline) operational_baseline ;;
    uninstall) uninstall_package ;;
    accept-task9) accept_task9 ;;
    accept-task10) accept_task10 ;;
    accept-task11) accept_task11 ;;
    accept-task12-logged-in) accept_task12_logged_in ;;
    accept-task12-loginwindow-start) accept_task12_loginwindow_start ;;
    accept-task12-loginwindow-finish) accept_task12_loginwindow_finish ;;
    accept-task12-sleep-wake) accept_task12_sleep_wake ;;
    accept-task13-dry-run-path) accept_task13_dry_run_path ;;
    accept-task13-enabled-once) accept_task13_enabled_once ;;
    accept-task13-recovery-resleep) accept_task13_recovery_resleep ;;
    accept-task14-reboot-start) accept_task14_reboot_start ;;
    accept-task14-reboot-finish) accept_task14_reboot_finish ;;
    *) usage ;;
esac
