#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=scripts/lib/production-package-common.sh
source "$SCRIPT_DIR/lib/production-package-common.sh"

usage() {
    printf '%s\n' 'usage: manage-production-daemon.sh prepare|verify' >&2
    exit 64
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
    *) usage ;;
esac
