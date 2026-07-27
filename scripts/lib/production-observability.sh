#!/usr/bin/env bash

observability_unavailable() { printf '%s\n' unavailable; }

observability_test_hook() {
    local name=$1 value=${2:-}
    if [[ -n "$value" && -z "$SYSTEM_ROOT" ]]; then
        printf 'error=test-hook-production-disabled reason=%s\n' "$name" >&2
        return 65
    fi
}

job_state_value() {
    observability_test_hook job-state "${MLM_TEST_JOB_STATE:-}" || return $?
    if [[ -n "$SYSTEM_ROOT" ]]; then
        printf '%s\n' "${MLM_TEST_JOB_STATE:-absent}"
    elif launchctl print "system/$LAUNCHD_LABEL" >/dev/null 2>&1; then
        printf '%s\n' loaded
    else
        printf '%s\n' absent
    fi
}

process_id_lines() {
    observability_test_hook process-ids "${MLM_TEST_PROCESS_IDS:-}" || return $?
    if [[ -n "$SYSTEM_ROOT" ]]; then
        for pid in ${MLM_TEST_PROCESS_IDS:-}; do printf '%s\n' "$pid"; done
    else
        pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true
    fi
}

process_metric_lines() {
    local pid=$1 metrics
    observability_test_hook process-metrics "${MLM_TEST_PROCESS_METRICS:-}" || return $?
    if [[ -n "$SYSTEM_ROOT" && -n "${MLM_TEST_PROCESS_METRICS:-}" ]]; then
        metrics=$MLM_TEST_PROCESS_METRICS
    else
        metrics="$(ps -p "$pid" -o etimes=,%cpu=,rss=,vsz= 2>/dev/null | awk 'NF {printf "elapsed=%s cpu=%s rss=%s vsz=%s", $1, $2, $3, $4}')"
    fi
    [[ -n "$metrics" ]] || metrics='elapsed=unavailable cpu=unavailable rss=unavailable vsz=unavailable'
    printf 'pid=%s %s\n' "$pid" "$metrics"
}

health_status_lines() {
    if [[ ! -e "$MANAGED_HEALTH_STATE" ]]; then
        printf 'health_state=unavailable health_mode=unavailable health_pid=unavailable health_updated_at=unavailable\n'
        return
    fi
    verify_managed_metadata "$MANAGED_HEALTH_STATE" regular "$(managed_expected_owner)" "$(managed_expected_group)" 600 1 >/dev/null 2>&1 || {
        printf 'health_state=corrupt health_mode=corrupt health_pid=corrupt health_updated_at=corrupt\n'
        return
    }
    /usr/bin/python3 - "$MANAGED_HEALTH_STATE" <<'PY' || {
import datetime, json, sys
with open(sys.argv[1], 'rb') as handle:
    value = json.load(handle)
required = ('state', 'mode', 'pid', 'updatedAt')
if value.get('schemaVersion') != 1 or any(key not in value for key in required):
    raise ValueError('invalid health schema')
updated = datetime.datetime.fromisoformat(value['updatedAt'].replace('Z', '+00:00'))
now = datetime.datetime.now(datetime.timezone.utc)
state = 'stale' if (now - updated).total_seconds() > 180 else value['state']
print('health_state={} health_mode={} health_pid={} health_updated_at={}'.format(state, value['mode'], value['pid'], value['updatedAt']))
PY
        printf 'health_state=corrupt health_mode=corrupt health_pid=corrupt health_updated_at=corrupt\n'
    }
}

crash_budget_status_lines() {
    local path="$MANAGED_SUPPORT/crash-budget.json"
    if [[ ! -e "$path" ]]; then
        printf 'crash_state=unavailable crash_count=unavailable crash_run_active=unavailable\n'
        return
    fi
    [[ -f "$path" && ! -L "$path" ]] || {
        printf 'crash_state=corrupt crash_count=corrupt crash_run_active=corrupt\n'
        return
    }
    /usr/bin/python3 - "$path" <<'PY' || {
import json, sys
with open(sys.argv[1], 'rb') as handle:
    value = json.load(handle)
times = value['unexpectedExitTimes']
open_state = value['circuitOpen']
run_active = value.get('runActive', False)
if not isinstance(times, list) or not isinstance(open_state, bool) or not isinstance(run_active, bool):
    raise ValueError('invalid crash state')
print('crash_state={} crash_count={} crash_run_active={}'.format('open' if open_state else 'closed', len(times), str(run_active).lower()))
PY
        printf 'crash_state=corrupt crash_count=corrupt crash_run_active=corrupt\n'
    }
}

acceptance_status_value() {
    if [[ ! -e "$MANAGED_ACCEPTANCE_STATE" ]]; then printf '%s\n' missing; return; fi
    if verify_deployment_acceptance deployment-dry-run deployment-enabled-once deployment-recovery-resleep >/dev/null 2>&1; then
        printf '%s\n' complete
    else
        printf '%s\n' corrupt
    fi
}

lease_status_value() {
    if [[ ! -e "$MANAGED_SLEEP_AUTHORITY" ]]; then printf '%s\n' missing; return; fi
    [[ -f "$MANAGED_SLEEP_AUTHORITY" && ! -L "$MANAGED_SLEEP_AUTHORITY" ]] || { printf '%s\n' corrupt; return; }
    printf '%s\n' present
}

log_status_lines() {
    local path generation
    for path in "$MANAGED_STDOUT_LOG" "$MANAGED_STDERR_LOG"; do
        if [[ -f "$path" && ! -L "$path" ]]; then
            printf 'log_path=%s log_bytes=%s log_mode=%s\n' "$path" "$(stat -f '%z' "$path")" "$(stat -f '%Lp' "$path")"
        else
            printf 'log_path=%s log_state=unavailable\n' "$path"
        fi
        for generation in 1 2 3; do
            if [[ -f "$path.$generation" && ! -L "$path.$generation" ]]; then
                printf 'log_generation=%s log_path=%s log_bytes=%s\n' "$generation" "$path.$generation" "$(stat -f '%z' "$path.$generation")"
            fi
        done
    done
}

status_job() {
    local installed=false version=unavailable source_commit=unavailable mode=unavailable integrity=invalid
    local job process_count health hardware_model hardware_chip crash acceptance lease
    if [[ -f "$MANAGED_BINARY" && -f "$MANAGED_PLIST" && -f "$MANAGED_CONFIG" && -f "$MANAGED_MANIFEST" ]]; then
        installed=true
        version="$(manifest_value Version 2>/dev/null || observability_unavailable)"
        source_commit="$(manifest_value SourceCommit 2>/dev/null || observability_unavailable)"
        mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG" 2>/dev/null || observability_unavailable)"
        if verify_installed_set >/dev/null 2>&1; then integrity=valid; fi
    fi
    job="$(job_state_value)"
    process_count="$(process_id_lines | awk 'NF {count += 1} END {print count + 0}')"
    health="$(health_status_lines)"
    hardware_model="$(deployment_target_model 2>/dev/null || observability_unavailable)"
    hardware_chip="$(deployment_target_chip 2>/dev/null || observability_unavailable)"
    crash="$(crash_budget_status_lines)"
    acceptance="$(acceptance_status_value)"
    lease="$(lease_status_value)"
    printf 'installed=%s version=%s source_commit=%s mode=%s job=%s process_count=%s integrity=%s hardware_model=%s hardware_chip=%s acceptance_state=%s lease_state=%s %s %s\n' \
        "$installed" "$version" "$source_commit" "$mode" "$job" "$process_count" "$integrity" \
        "$hardware_model" "$hardware_chip" "$acceptance" "$lease" "$health" "$crash"
    [[ "$installed" == true ]] || return 69
}

diagnostics() {
    local pid
    status_job || true
    while IFS= read -r pid; do
        [[ -n "$pid" ]] && process_metric_lines "$pid"
    done < <(process_id_lines)
    log_status_lines
}

operational_baseline() {
    local mode job pids health_pid health_state
    verify_installed_set >/dev/null 2>&1 || { printf 'error=operational-baseline-invalid reason=installed-set\n' >&2; return 65; }
    mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$MANAGED_CONFIG" 2>/dev/null || true)"
    [[ "$mode" == enabled ]] || { printf 'error=operational-baseline-invalid reason=mode\n' >&2; return 65; }
    job="$(job_state_value)"
    [[ "$job" == loaded ]] || { printf 'error=operational-baseline-invalid reason=job\n' >&2; return 65; }
    pids="$(process_id_lines)"
    [[ "$(printf '%s\n' "$pids" | awk 'NF {count += 1} END {print count + 0}')" == 1 ]] || {
        printf 'error=operational-baseline-invalid reason=process-count\n' >&2; return 65;
    }
    health_state="$(health_status_lines)"
    [[ "$health_state" == *'health_state=monitoring-armed'* && "$health_state" == *'health_mode=enabled'* ]] || {
        printf 'error=operational-baseline-invalid reason=health\n' >&2; return 65;
    }
    health_pid="$(printf '%s\n' "$health_state" | sed -E 's/.*health_pid=([^ ]+).*/\1/')"
    [[ "$health_pid" == "$pids" ]] || { printf 'error=operational-baseline-invalid reason=health-pid\n' >&2; return 65; }
    verify_deployment_acceptance deployment-dry-run deployment-enabled-once deployment-recovery-resleep >/dev/null 2>&1 || {
        printf 'error=operational-baseline-invalid reason=acceptance\n' >&2; return 65;
    }
    printf 'operational_baseline=pass pid=%s\n' "$pids"
}
