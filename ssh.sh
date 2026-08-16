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

# 1. Kill stale iproxy instances to ensure a fresh connection
killall iproxy 2>/dev/null || true

# 2. Check if usbmuxd sees any device
if command -v idevice_id >/dev/null 2>&1; then
    DEV_COUNT="$(idevice_id -l 2>/dev/null | wc -l || echo 0)"
    if [[ "$DEV_COUNT" -eq 0 ]]; then
        printf '[*] Note: If usbmuxd does not detect the ramdisk, restart usbmuxd with --no-preflight:\n'
        printf '    sudo systemctl stop usbmuxd\n'
        printf '    sudo usbmuxd -p -U usbmux\n\n'
    fi
fi

# 3. Start fresh iproxy in background
if command -v iproxy >/dev/null 2>&1; then
    printf '[*] Starting iproxy %s %s...\n' "$PORT" "$DEVPORT"
    iproxy "$PORT" "$DEVPORT" >/dev/null 2>&1 &
    sleep 1
else
    printf '[!] iproxy command not found. Install libusbmuxd-tools / libimobiledevice.\n' >&2
fi

printf '[*] Connecting to root@127.0.0.1 -p %s (Password: %s)...\n' "$PORT" "$PASS"

# 4. Connect via sshpass if available, or fall back to standard ssh
if command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$PORT" "root@127.0.0.1" "$@"
else
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p "$PORT" "root@127.0.0.1" "$@"
fi
