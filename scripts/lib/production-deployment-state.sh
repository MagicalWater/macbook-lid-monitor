#!/usr/bin/env bash

deployment_state_error() {
    local error=$1 reason=${2:-unavailable}
    printf 'error=%s reason=%s\n' "$error" "$reason" >&2
    return 65
}

deployment_target_model() {
    if [[ -n "$SYSTEM_ROOT" ]]; then
        printf '%s\n' "${MLM_TEST_TARGET_MODEL:-MacBookPro18,1}"
        return
    fi
    [[ -z "${MLM_TEST_TARGET_MODEL:-}" ]] || {
        deployment_state_error test-hook-production-disabled target-model
        return $?
    }
    /usr/sbin/sysctl -n hw.model
}

deployment_target_chip() {
    if [[ -n "$SYSTEM_ROOT" ]]; then
        printf '%s\n' "${MLM_TEST_TARGET_CHIP:-Apple M1 Pro}"
        return
    fi
    [[ -z "${MLM_TEST_TARGET_CHIP:-}" ]] || {
        deployment_state_error test-hook-production-disabled target-chip
        return $?
    }
    /usr/sbin/system_profiler SPHardwareDataType | awk -F': ' '$1 ~ /^[[:space:]]*Chip$/ {print $2; exit}'
}

verify_target_hardware() {
    local model chip
    model="$(deployment_target_model)" || return $?
    chip="$(deployment_target_chip)" || return $?
    [[ "$model" == MacBookPro18,1 ]] || {
        deployment_state_error target-hardware-invalid model
        return $?
    }
    [[ "$chip" == 'Apple M1 Pro' ]] || {
        deployment_state_error target-hardware-invalid chip
        return $?
    }
}

target_hardware_identity_lines() {
    verify_target_hardware || return $?
    printf 'target_model=%s\n' "$(deployment_target_model)"
    printf 'target_chip=%s\n' "$(deployment_target_chip)"
}

deployment_identity_lines() {
    verify_target_hardware || return $?
    installed_identity_lines || return $?
    target_hardware_identity_lines
}

deployment_identity_value() {
    case "$1" in
        Product) manifest_value Product ;;
        SourceCommit) manifest_value SourceCommit ;;
        BinarySHA256) manifest_value BinarySHA256 ;;
        PlistSHA256) manifest_value PlistSHA256 ;;
        DisabledConfigSHA256) manifest_value DisabledConfigSHA256 ;;
        HardwareProfileID) manifest_value HardwareProfileID ;;
        TargetModel) deployment_target_model ;;
        TargetChip) deployment_target_chip ;;
        *) return 64 ;;
    esac
}

deployment_payload_identity_keys() {
    printf '%s\n' \
        Product BinarySHA256 PlistSHA256 DisabledConfigSHA256 HardwareProfileID \
        BinaryPath PlistPath ConfigPath SleepAuthorityPath AcceptanceStatePath HealthStatePath
}

verify_state_identity() {
    local path=$1 error_key=$2 key expected actual
    for key in Product SourceCommit BinarySHA256 PlistSHA256 DisabledConfigSHA256 HardwareProfileID TargetModel TargetChip; do
        expected="$(deployment_identity_value "$key")" || return $?
        actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$path" 2>/dev/null || true)"
        [[ "$actual" == "$expected" ]] || {
            deployment_state_error "$error_key" "identity-$key"
            return $?
        }
    done
}

atomic_write_deployment_plist() {
    local destination=$1 python_program=$2
    shift 2
    local temporary
    assert_managed_path_safe "$destination"
    temporary="$(mktemp "$MANAGED_SUPPORT/.deployment-state.XXXXXX")"
    # shellcheck disable=SC2329 # invoked through RETURN trap below
    cleanup_deployment_temporary() { rm -f -- "$temporary"; }
    trap cleanup_deployment_temporary RETURN
    /usr/bin/python3 -c "$python_program" "$temporary" "$@"
    chmod 0600 "$temporary"
    if [[ -z "$SYSTEM_ROOT" ]]; then chown root:wheel "$temporary"; fi
    mv -f -- "$temporary" "$destination"
    trap - RETURN
}

record_deployment_acceptance() {
    local stage=$1 result=$2
    [[ "$stage" =~ ^[a-z0-9-]+$ ]] || { deployment_state_error deployment-acceptance-invalid stage; return $?; }
    [[ "$result" == pass || "$result" == fail ]] || { deployment_state_error deployment-acceptance-invalid result; return $?; }
    verify_installed_set || return $?
    verify_target_hardware || return $?
    if [[ -e "$MANAGED_ACCEPTANCE_STATE" || -L "$MANAGED_ACCEPTANCE_STATE" ]]; then
        verify_managed_metadata "$MANAGED_ACCEPTANCE_STATE" regular "$(managed_expected_owner)" "$(managed_expected_group)" 600 1 || return $?
        verify_state_identity "$MANAGED_ACCEPTANCE_STATE" deployment-acceptance-invalid || return $?
    fi
    local timestamp
    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    atomic_write_deployment_plist "$MANAGED_ACCEPTANCE_STATE" '
import os, plistlib, sys
path, existing, stage, result, timestamp = sys.argv[1:6]
keys = ["Product", "SourceCommit", "BinarySHA256", "PlistSHA256", "DisabledConfigSHA256", "HardwareProfileID", "TargetModel", "TargetChip"]
values = sys.argv[6:14]
state = {}
if existing and os.path.exists(existing):
    with open(existing, "rb") as handle:
        state = plistlib.load(handle)
state.update({"SchemaVersion": 1, **dict(zip(keys, values))})
stages = state.setdefault("Stages", {})
stages[stage] = {"Result": result, "RecordedAt": timestamp}
with open(path, "wb") as handle:
    plistlib.dump(state, handle, sort_keys=True)
' "$MANAGED_ACCEPTANCE_STATE" "$stage" "$result" "$timestamp" \
        "$(deployment_identity_value Product)" \
        "$(deployment_identity_value SourceCommit)" \
        "$(deployment_identity_value BinarySHA256)" \
        "$(deployment_identity_value PlistSHA256)" \
        "$(deployment_identity_value DisabledConfigSHA256)" \
        "$(deployment_identity_value HardwareProfileID)" \
        "$(deployment_identity_value TargetModel)" \
        "$(deployment_identity_value TargetChip)"
    printf 'recorded deployment-acceptance stage=%s result=%s\n' "$stage" "$result"
}

verify_deployment_acceptance() {
    local stage result
    verify_installed_set >/dev/null 2>&1 || {
        deployment_state_error deployment-acceptance-invalid installed-set
        return $?
    }
    verify_target_hardware >/dev/null 2>&1 || {
        deployment_state_error deployment-acceptance-invalid target-hardware
        return $?
    }
    verify_managed_metadata "$MANAGED_ACCEPTANCE_STATE" regular "$(managed_expected_owner)" "$(managed_expected_group)" 600 1 >/dev/null 2>&1 || {
        deployment_state_error deployment-acceptance-invalid metadata
        return $?
    }
    [[ "$(/usr/libexec/PlistBuddy -c 'Print :SchemaVersion' "$MANAGED_ACCEPTANCE_STATE" 2>/dev/null || true)" == 1 ]] || {
        deployment_state_error deployment-acceptance-invalid schema
        return $?
    }
    verify_state_identity "$MANAGED_ACCEPTANCE_STATE" deployment-acceptance-invalid || return $?
    for stage in "$@"; do
        result="$(/usr/libexec/PlistBuddy -c "Print :Stages:$stage:Result" "$MANAGED_ACCEPTANCE_STATE" 2>/dev/null || true)"
        [[ "$result" == pass ]] || {
            deployment_state_error deployment-acceptance-invalid "stage-$stage"
            return $?
        }
    done
    printf 'verified deployment-acceptance stages=%s\n' "$*"
}

invalidate_deployment_acceptance() {
    local reason=$1
    assert_managed_path_safe "$MANAGED_ACCEPTANCE_STATE"
    [[ ! -L "$MANAGED_ACCEPTANCE_STATE" ]] || {
        deployment_state_error deployment-acceptance-invalid symlink
        return $?
    }
    rm -f -- "$MANAGED_ACCEPTANCE_STATE" "$MANAGED_REBOOT_STATE"
    printf 'invalidated deployment-acceptance reason=%s\n' "$reason"
}

deployment_boot_epoch() {
    if [[ -n "${MLM_TEST_BOOT_EPOCH:-}" ]]; then
        [[ -n "$SYSTEM_ROOT" ]] || { deployment_state_error test-hook-production-disabled boot-epoch; return $?; }
        printf '%s\n' "$MLM_TEST_BOOT_EPOCH"
        return
    fi
    /usr/sbin/sysctl -n kern.boottime | sed -E 's/^\{ sec = ([0-9]+), usec = [0-9]+ \}.*$/\1/'
}

write_deployment_reboot_state() {
    local boot_epoch=$1
    [[ "$boot_epoch" =~ ^[0-9]+$ ]] || { deployment_state_error deployment-reboot-invalid boot-epoch; return $?; }
    verify_installed_set || return $?
    verify_target_hardware || return $?
    atomic_write_deployment_plist "$MANAGED_REBOOT_STATE" '
import plistlib, sys
path, boot = sys.argv[1:3]
keys = ["Product", "SourceCommit", "BinarySHA256", "PlistSHA256", "DisabledConfigSHA256", "HardwareProfileID", "TargetModel", "TargetChip"]
values = sys.argv[3:11]
state = {"SchemaVersion": 1, "BootEpoch": int(boot), **dict(zip(keys, values))}
with open(path, "wb") as handle:
    plistlib.dump(state, handle, sort_keys=True)
' "$boot_epoch" \
        "$(deployment_identity_value Product)" \
        "$(deployment_identity_value SourceCommit)" \
        "$(deployment_identity_value BinarySHA256)" \
        "$(deployment_identity_value PlistSHA256)" \
        "$(deployment_identity_value DisabledConfigSHA256)" \
        "$(deployment_identity_value HardwareProfileID)" \
        "$(deployment_identity_value TargetModel)" \
        "$(deployment_identity_value TargetChip)"
    printf 'wrote deployment-reboot-state boot-epoch=%s\n' "$boot_epoch"
}

verify_deployment_reboot_state() {
    local start_boot current_boot
    verify_installed_set >/dev/null 2>&1 || { deployment_state_error deployment-reboot-invalid installed-set; return $?; }
    verify_target_hardware >/dev/null 2>&1 || { deployment_state_error deployment-reboot-invalid target-hardware; return $?; }
    verify_managed_metadata "$MANAGED_REBOOT_STATE" regular "$(managed_expected_owner)" "$(managed_expected_group)" 600 1 >/dev/null 2>&1 || {
        deployment_state_error deployment-reboot-invalid metadata
        return $?
    }
    verify_state_identity "$MANAGED_REBOOT_STATE" deployment-reboot-invalid || return $?
    start_boot="$(/usr/libexec/PlistBuddy -c 'Print :BootEpoch' "$MANAGED_REBOOT_STATE" 2>/dev/null || true)"
    current_boot="$(deployment_boot_epoch)" || return $?
    [[ "$start_boot" =~ ^[0-9]+$ && "$current_boot" =~ ^[0-9]+$ && "$current_boot" -gt "$start_boot" ]] || {
        deployment_state_error deployment-reboot-invalid reboot-not-detected
        return $?
    }
    printf 'verified deployment-reboot-state boot-changed=true start=%s current=%s\n' "$start_boot" "$current_boot"
}
