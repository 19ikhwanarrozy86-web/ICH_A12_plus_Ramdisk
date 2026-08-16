#!/usr/bin/env bash
# Quick SSH connection helper for ICH_A12+ Ramdisk.
# Automatically starts iproxy if needed and opens an interactive SSH session.
set -euo pipefail

PORT="${ICH_SSH_PORT:-2222}"
DEVPORT="${ICH_DEV_PORT:-22}"
PASS="${ICH_SSH_PASS:-alpine}"

printf '============================================================\n'
printf '  ICH_A12+ Ramdisk SSH Connector\n'
printf '============================================================\n'

# 1. Check if iproxy is running
if ! pgrep -f "iproxy.*${PORT}.*${DEVPORT}" >/dev/null 2>&1; then
    if command -v iproxy >/dev/null 2>&1; then
        printf '[*] Starting iproxy %s %s in background...\n' "$PORT" "$DEVPORT"
        iproxy "$PORT" "$DEVPORT" >/dev/null 2>&1 &
        IPROXY_PID=$!
        sleep 1
    else
        printf '[!] iproxy command not found. Install libusbmuxd-tools / libimobiledevice.\n' >&2
    fi
else
    printf '[*] iproxy is already running on port %s\n' "$PORT"
fi

printf '[*] Connecting to root@127.0.0.1 -p %s (Password: %s)...\n' "$PORT" "$PASS"

# 2. Connect via sshpass if available, or fall back to standard ssh
if command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$PORT" "root@127.0.0.1" "$@"
else
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$PORT" "root@127.0.0.1" "$@"
fi
