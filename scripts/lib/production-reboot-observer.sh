#!/usr/bin/env bash
set -euo pipefail

support='/Library/Application Support/MacBookLidMonitor'
config="$support/config.plist"
manifest="$support/manifest.plist"
health="$support/health.plist"
evidence="$support/reboot-observer-evidence.plist"
label='com.crazydennies.macbook-lid-monitor'

boot_epoch="$(/usr/sbin/sysctl -n kern.boottime | sed -E 's/^\{ sec = ([0-9]+), usec = [0-9]+ \}.*$/\1/')"
console_user="$(/usr/bin/stat -f '%Su' /dev/console 2>/dev/null || printf unknown)"
job_state=absent
pid=''
process_count=0
health_state=unavailable
health_pid=unavailable
for _ in {1..120}; do
    if /bin/launchctl print "system/$label" >/dev/null 2>&1; then job_state=loaded; fi
    pid="$({ /usr/bin/pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | head -n 1)"
    process_count="$({ /usr/bin/pgrep -f '^/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon$' || true; } | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
    if [[ -f "$health" && ! -L "$health" ]]; then
        read -r health_state health_pid < <(/usr/bin/python3 - "$health" <<'PY'
import json, sys
try:
    with open(sys.argv[1], 'rb') as f: value=json.load(f)
    print(value.get('state','unavailable'), value.get('pid','unavailable'))
except Exception:
    print('corrupt', 'corrupt')
PY
)
    fi
    [[ "$job_state" == loaded && "$process_count" == 1 && "$health_state" == monitoring-armed && "$health_pid" == "$pid" ]] && break
    /bin/sleep 1
done
mode="$(/usr/libexec/PlistBuddy -c 'Print :Mode' "$config" 2>/dev/null || printf unavailable)"
source_commit="$(/usr/libexec/PlistBuddy -c 'Print :SourceCommit' "$manifest" 2>/dev/null || printf unavailable)"
version="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$manifest" 2>/dev/null || printf unavailable)"
profile="$(/usr/libexec/PlistBuddy -c 'Print :HardwareProfileID' "$manifest" 2>/dev/null || printf unavailable)"
temporary="$(/usr/bin/mktemp "$support/.reboot-observer.XXXXXX")"
trap 'rm -f -- "$temporary"' EXIT
/usr/bin/python3 - "$temporary" "$boot_epoch" "$console_user" "$job_state" "$process_count" "$pid" "$mode" "$source_commit" "$version" "$profile" "$health_state" "$health_pid" <<'PY'
import datetime, plistlib, sys
(path, boot, console, job, count, pid, mode, commit, version, profile, health, health_pid)=sys.argv[1:13]
value={
 'SchemaVersion':1,'BootEpoch':int(boot),'ObservedAt':datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
 'ConsoleUser':console,'JobState':job,'ProcessCount':int(count),'PID':pid,'Mode':mode,
 'SourceCommit':commit,'Version':version,'HardwareProfileID':profile,'HealthState':health,'HealthPID':health_pid,
}
with open(path,'wb') as f: plistlib.dump(value,f,sort_keys=True)
PY
/bin/chmod 0600 "$temporary"
/usr/sbin/chown root:wheel "$temporary"
/bin/mv -f -- "$temporary" "$evidence"
trap - EXIT
