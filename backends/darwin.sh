#!/usr/bin/env bash
# Darwin implementation retains the original vendored tools.

backend_init_darwin() {
    BACKEND_NAME="darwin"
    IRECOVERY="${IRECOVERY:-$NR_TOOLS/irecovery}"
    USBLITER8_BOOT="${USBLITER8_BOOT:-$NR_TOOLS/usbliter8_boot}"
    USBLITER8CTL="${USBLITER8CTL:-}"
    if [[ -z "$USBLITER8CTL" ]]; then
        for candidate in "$ROOT/../usbliter8ra1n/tools/usbliter8ctl" "$ROOT/../usbliter8-xr-ramdisk/tools/usbliter8ctl" "$NR_TOOLS/usbliter8ctl"; do
            [[ -f "$candidate" ]] && USBLITER8CTL="$candidate" && break
        done
    fi
}

backend_require_runtime_tools() {
    backend_require_executable IRECOVERY "$IRECOVERY"
    if [[ -n "$USBLITER8CTL" ]]; then
        command -v python3 >/dev/null 2>&1 || return 1
    else
        backend_require_executable USBLITER8_BOOT "$USBLITER8_BOOT"
    fi
}

backend_query() { backend_with_timeout 8 "$IRECOVERY" -q; }
backend_send_file() { backend_with_timeout "${IRECV_UPLOAD_TIMEOUT_SECS:-300}" "$IRECOVERY" -f "$1"; }
backend_send_command() { backend_with_timeout "${IRECV_CMD_TIMEOUT_SECS:-30}" "$IRECOVERY" -c "$1"; }
backend_boot_raw() {
    if [[ -n "$USBLITER8CTL" ]]; then python3 "$USBLITER8CTL" boot "$1"; else "$USBLITER8_BOOT" "$1"; fi
}
backend_supports_local_logo_build() { return 0; }
