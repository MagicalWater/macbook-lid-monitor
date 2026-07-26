#!/usr/bin/env bash
set -euo pipefail

LABEL='com.crazydennies.macbook-lid-monitor.feasibility'
BINARY_PATH='/Library/PrivilegedHelperTools/macbook-lid-monitor-daemon-spike'
PLIST_PATH='/Library/LaunchDaemons/com.crazydennies.macbook-lid-monitor.feasibility.plist'
LOG_DIR='/Library/Logs/MacBookLidMonitor/Feasibility'
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
SOURCE_BINARY="$REPO_ROOT/.build/release/macbook-lid-monitor-daemon-spike"
SOURCE_PLIST="$REPO_ROOT/packaging/launchd/com.crazydennies.macbook-lid-monitor.feasibility.plist"
DOMAIN_TARGET="system/$LABEL"

usage() {
    printf '%s\n' 'usage: manage-feasibility-daemon.sh prepare|install|bootstrap|status|logs|stop|bootout|uninstall' >&2
    exit 64
}

require_root() {
    if [[ ${EUID} -ne 0 ]]; then
        printf '%s\n' 'error: this subcommand requires root' >&2
        exit 77
    fi
}

assert_not_symlink() {
    local path=$1
    if [[ -L "$path" ]]; then
        printf 'error: refusing symlink path: %s\n' "$path" >&2
        exit 74
    fi
}

job_loaded() {
    launchctl print "$DOMAIN_TARGET" >/dev/null 2>&1
}

prepare() {
    cd -- "$REPO_ROOT"
    swift build -c release --product macbook-lid-monitor-daemon-spike
    plutil -lint "$SOURCE_PLIST"
    test -x "$SOURCE_BINARY"
    printf 'prepared binary=%s plist=%s\n' "$SOURCE_BINARY" "$SOURCE_PLIST"
}

install_files() {
    require_root
    if job_loaded; then
        printf 'error: %s is already loaded; bootout it before install\n' "$LABEL" >&2
        exit 69
    fi
    test -f "$SOURCE_BINARY"
    test -x "$SOURCE_BINARY"
    test ! -L "$SOURCE_BINARY"
    test -f "$SOURCE_PLIST"
    test ! -L "$SOURCE_PLIST"
    plutil -lint "$SOURCE_PLIST" >/dev/null

    assert_not_symlink '/Library/PrivilegedHelperTools'
    assert_not_symlink '/Library/LaunchDaemons'
    assert_not_symlink '/Library/Logs'
    assert_not_symlink '/Library/Logs/MacBookLidMonitor'
    assert_not_symlink "$LOG_DIR"
    assert_not_symlink "$BINARY_PATH"
    assert_not_symlink "$PLIST_PATH"
    if [[ -e "$BINARY_PATH" || -e "$PLIST_PATH" ]]; then
        printf '%s\n' 'error: feasibility artifacts already exist; uninstall them before install' >&2
        exit 73
    fi
    mkdir -p -- "$LOG_DIR"
    chown root:wheel "$LOG_DIR"
    chmod 0755 "$LOG_DIR"

    local binary_tmp plist_tmp
    binary_tmp="$(mktemp '/Library/PrivilegedHelperTools/.macbook-lid-monitor-daemon-spike.XXXXXX')"
    plist_tmp="$(mktemp '/Library/LaunchDaemons/.com.crazydennies.macbook-lid-monitor.feasibility.XXXXXX')"
    trap 'rm -f -- "$binary_tmp" "$plist_tmp"' EXIT

    cp -- "$SOURCE_BINARY" "$binary_tmp"
    chown root:wheel "$binary_tmp"
    chmod 0755 "$binary_tmp"
    mv -f -- "$binary_tmp" "$BINARY_PATH"

    cp -- "$SOURCE_PLIST" "$plist_tmp"
    chown root:wheel "$plist_tmp"
    chmod 0644 "$plist_tmp"
    plutil -lint "$plist_tmp" >/dev/null
    mv -f -- "$plist_tmp" "$PLIST_PATH"
    trap - EXIT
    printf 'installed binary=%s plist=%s\n' "$BINARY_PATH" "$PLIST_PATH"
}

bootstrap_job() {
    require_root
    test -x "$BINARY_PATH"
    test -f "$PLIST_PATH"
    plutil -lint "$PLIST_PATH" >/dev/null
    if job_loaded; then
        printf 'error: %s is already loaded\n' "$LABEL" >&2
        exit 69
    fi
    launchctl bootstrap system "$PLIST_PATH"
    launchctl print "$DOMAIN_TARGET"
}

status_job() {
    launchctl print "$DOMAIN_TARGET"
}

show_logs() {
    if [[ -f "$LOG_DIR/stdout.log" ]]; then
        tail -n 200 -- "$LOG_DIR/stdout.log"
    fi
    if [[ -f "$LOG_DIR/stderr.log" ]]; then
        tail -n 200 -- "$LOG_DIR/stderr.log" >&2
    fi
}

stop_job() {
    require_root
    launchctl kill SIGTERM "$DOMAIN_TARGET"
}

bootout_job() {
    require_root
    if job_loaded; then
        launchctl bootout "$DOMAIN_TARGET"
    fi
}

uninstall_job() {
    require_root
    bootout_job
    if pgrep -x 'macbook-lid-monitor-daemon-spike' >/dev/null 2>&1; then
        printf '%s\n' 'error: daemon process remains after bootout' >&2
        exit 70
    fi
    assert_not_symlink "$BINARY_PATH"
    assert_not_symlink "$PLIST_PATH"
    assert_not_symlink "$LOG_DIR"
    rm -f -- "$BINARY_PATH"
    rm -f -- "$PLIST_PATH"
    rm -f -- "$LOG_DIR/stdout.log"
    rm -f -- "$LOG_DIR/stderr.log"
    rmdir -- "$LOG_DIR" 2>/dev/null || true
    printf '%s\n' 'uninstalled feasibility daemon artifacts'
}

[[ $# -eq 1 ]] || usage
case "$1" in
    prepare) prepare ;;
    install) install_files ;;
    bootstrap) bootstrap_job ;;
    status) status_job ;;
    logs) show_logs ;;
    stop) stop_job ;;
    bootout) bootout_job ;;
    uninstall) uninstall_job ;;
    *) usage ;;
esac
