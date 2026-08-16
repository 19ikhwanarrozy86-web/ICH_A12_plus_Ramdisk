#!/usr/bin/env bash
# Cross-platform boot runtime for an already-built A12/A13 SSH ramdisk.
# Build remains macOS/GitHub Actions work; this script never creates IMG4 files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=env.sh
source "$ROOT/env.sh"
# shellcheck source=backends/common.sh
source "$ROOT/backends/common.sh"
# shellcheck source=scripts/artifact_validate.sh
source "$ROOT/scripts/artifact_validate.sh"

LOGO_HOLD_SECS="${LOGO_HOLD_SECS:-3}"
RECOVERY_WAIT_SECS="${RECOVERY_WAIT_SECS:-120}"
IRECV_CMD_TIMEOUT_SECS="${IRECV_CMD_TIMEOUT_SECS:-30}"
IRECV_UPLOAD_TIMEOUT_SECS="${IRECV_UPLOAD_TIMEOUT_SECS:-300}"
BOOTARGS="${BOOTARGS:-rd=md0 -v debug=0x14e serial=3 wdt=-1 keepsyms=1}"

WITH_FW=-1
SEP=-1
USE_LOGO=1
VALIDATE_ONLY=0
DRY_RUN=0
DEBUG=0
REQUESTED_BACKEND="${ICH_RAMDISK_BACKEND:-auto}"

usage() {
    cat <<'EOF'
usage: ./boot.sh [options]

Boots an already-built artifact/bootchain. No build or IMG4 generation is done.

  --validate              validate artifact metadata and IMG4 markers only
  --dry-run               validate, inspect pwned DFU, print sequence; send nothing
  --debug                 also write an execution log (boot-debug.log by default)
  --backend linux|darwin  select backend (default: detected from uname)
  --no-fw | --with-fw     override firmware selection from artifact metadata
  --no-logo | --logo      disable or enable a prebuilt signed logo
  --sep | --no-sep        override RestoreSEP selection

Configuration:
  BOOTCHAIN_PATH           explicit bootchain directory
  ICH_RAMDISK_ARTIFACT     artifact root (default: ./artifact)
  IRECOVERY                Linux/Darwin irecovery executable
  USBLITER8CTL             Python usbliter8ctl path for pwned DFU raw boot
EOF
}

while (($#)); do
    case "$1" in
        --validate) VALIDATE_ONLY=1; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --debug) DEBUG=1; shift ;;
        --backend)
            (($# >= 2)) || { usage >&2; exit 64; }
            REQUESTED_BACKEND="$2"; shift 2 ;;
        --no-fw) WITH_FW=0; shift ;;
        --with-fw) WITH_FW=1; shift ;;
        --no-logo) USE_LOGO=0; shift ;;
        --logo) USE_LOGO=1; shift ;;
        --sep) SEP=1; shift ;;
        --no-sep) SEP=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
done

case "$REQUESTED_BACKEND" in
    auto)
        case "$(uname -s)" in
            Linux) REQUESTED_BACKEND=linux ;;
            Darwin) REQUESTED_BACKEND=darwin ;;
            *) backend_error "Unsupported host OS" "uname reports $(uname -s)." "Linux or Darwin." "Run the build on macOS or the runtime on a supported Linux host."; exit 1 ;;
        esac
        ;;
    linux|darwin) ;;
    *) backend_error "Invalid backend" "--backend is $REQUESTED_BACKEND." "linux, darwin, or auto." "Use ./boot.sh --help."; exit 64 ;;
esac
# shellcheck source=backends/linux.sh
source "$ROOT/backends/$REQUESTED_BACKEND.sh"
"backend_init_$REQUESTED_BACKEND"

if ((DEBUG)); then
    DEBUG_LOG="${BOOT_DEBUG_LOG:-$ROOT/boot-debug.log}"
    exec > >(tee -a "$DEBUG_LOG") 2>&1
    printf '[DEBUG] started=%s backend=%s bootchain=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BACKEND_NAME" "$BOOTCHAIN"
fi

bootchain_name="${BOOTCHAIN_NAME:-$(basename "${BOOTCHAIN:-bootchain}")}"
if ((WITH_FW < 0)); then
    [[ -f "${BOOTCHAIN:-}/with-fw.enabled" ]] && WITH_FW=1 || WITH_FW=0
fi

print_system() {
    printf 'System: %s\nBackend: %s\nBootchain: %s\n' "$(uname -s)" "$BACKEND_NAME" "$BOOTCHAIN"
}

require_pwned_matching_dfu() {
    local info mode pwnd product model cpid
    info="$(backend_query 2>/dev/null)" || {
        backend_error "Apple device not detected" "irecovery could not query a DFU or Recovery device." \
            "A USB-connected iPhone in pwned DFU." "Check the cable and udev permissions, then re-run ./boot.sh --dry-run."
        return 1
    }
    artifact_validate_device "$info"
    mode="$(backend_field MODE "$info")"; pwnd="$(backend_field PWND "$info")"
    product="$(backend_field PRODUCT "$info")"; model="$(backend_field MODEL "$info")"; cpid="$(backend_field CPID "$info")"
    printf '[+] USB device found\n[+] Product: %s\n[+] Board: %s\n[+] CPID: %s\n[+] Mode: %s\n[+] Pwned: %s\n' \
        "$product" "$model" "$cpid" "${mode:-unknown}" "${pwnd:-no}"
    [[ "$mode" == "DFU" && "${pwnd,,}" == "usbliter8" ]] || {
        backend_error "Device is not ready" "Current mode is ${mode:-unknown}; PWND is ${pwnd:-none}." \
            "MODE=DFU and PWND=usbliter8." "Run usbliter8 with RP2350, then reconnect the phone and retry."
        return 1
    }
}

recovery_mode() {
    local info
    info="$(backend_query 2>/dev/null || true)"
    backend_field MODE "$info"
}

wait_recovery() {
    local i mode last="" prompt_at=30
    local APPLE_DFU_PID="1227"   # 05ac:1227
    local APPLE_RECOV_PID="1281" # 05ac:1281
    printf 'Waiting for USB Recovery after iBoot (up to %ss)...\n' "$RECOVERY_WAIT_SECS"

    # ── Phase 1: wait for the DFU device to disappear ──
    # After usbliter8ctl boots the patched iBoot, the device drops off USB
    # (DFU 05ac:1227 goes away).  We wait up to 20s for that; if the device
    # is already absent we move on immediately.
    for i in $(seq 1 20); do
        mode="$(recovery_mode)"
        if [[ "$mode" == "Recovery" ]]; then
            printf '  iBoot Recovery already present\n'
            break 2 2>/dev/null || break
        fi
        # Device truly still in DFU → wait for it to leave
        if [[ "$mode" == "DFU" ]]; then
            ((i == 1 || i % 5 == 0)) && printf '  still DFU — waiting for re-enumeration (%ss)\n' "$i"
            sleep 1
            continue
        fi
        # Empty mode = device absent from USB.  On Linux, double-check with
        # sysfs to distinguish "gone" from "irecovery can't claim handle".
        if type -t backend_usb_apple_present &>/dev/null; then
            if backend_usb_apple_present "$APPLE_DFU_PID"; then
                # sysfs still shows DFU — kernel hasn't dropped it yet
                ((i == 1 || i % 5 == 0)) && printf '  DFU USB still present in kernel — waiting (%ss)\n' "$i"
                sleep 1
                continue
            fi
        fi
        # Device has left DFU (USB bus clear)
        printf '  DFU device absent from USB\n'
        break
    done

    # ── Phase 2: wait for Recovery USB to appear at kernel level ──
    # This is the critical gap the old code missed.  The device needs time to
    # re-enumerate as 05ac:1281.  On Linux we check sysfs directly; this avoids
    # the race where irecovery can't yet claim the interface.
    #
    # If the device doesn't appear naturally within a few seconds, we actively
    # kick the USB bus: remove stale sysfs entries and cycle the root hub
    # authorization so the xHCI hub driver re-probes all ports.
    if type -t backend_usb_apple_present &>/dev/null; then
        local appeared=0 kickstart_at=8
        for i in $(seq 1 "$RECOVERY_WAIT_SECS"); do
            if backend_usb_apple_present "$APPLE_RECOV_PID"; then
                printf '  Recovery USB appeared in kernel (after %ss)\n' "$i"
                appeared=1
                # Let udev finish applying permissions before irecovery tries to claim
                backend_usb_settle 3
                break
            fi
            # Actively kick the USB subsystem if the device hasn't appeared
            if ((i == kickstart_at)) && type -t backend_usb_kickstart_reenumerate &>/dev/null; then
                printf '  Recovery not detected after %ss — forcing USB re-enumeration\n' "$i"
                backend_usb_kickstart_reenumerate || true
                kickstart_at=$((kickstart_at + 20))
            fi
            if ((i == prompt_at)); then
                printf '  USB Recovery not ready: unplug/replug the Lightning cable once; waiting continues.\n' >&2
                prompt_at=$((prompt_at + 30))
            fi
            sleep 1
        done
        if ((! appeared)); then
            backend_error "Timed out waiting for Recovery" "Recovery USB (05ac:1281) never appeared on the bus." \
                "The device re-enumerating as USB Recovery after iBoot." "Use a direct USB-A cable, re-pwn DFU, and retry."
            return 1
        fi
    fi

    # ── Phase 3: wait for irecovery to successfully query Recovery ──
    # The device is on the bus; now wait for libirecovery to claim the interface
    # and for iBoot to respond to commands.
    local ready_tries="${RECOVERY_READY_TRIES:-15}"
    for i in $(seq 1 "$ready_tries"); do
        mode="$(recovery_mode)"
        if [[ "$mode" != "$last" ]]; then printf '  USB MODE: %s\n' "${mode:-none}"; last="$mode"; fi
        if [[ "$mode" == "Recovery" ]]; then
            if backend_send_command 'getenv build-version' >/dev/null 2>&1 || backend_query >/dev/null 2>&1; then
                printf '  iBoot Recovery ready (USB)\n'; return 0
            fi
            # irecovery sees Recovery but command failed — interface not settled
            ((i % 3 == 0)) && printf '  Recovery visible but interface not ready (%s/%s)\n' "$i" "$ready_tries"
        fi
        sleep 1
    done

    # If we reached here without success but the kernel shows Recovery, give a
    # specific message rather than a generic timeout.
    if type -t backend_usb_apple_present &>/dev/null && backend_usb_apple_present "$APPLE_RECOV_PID"; then
        backend_error "Recovery USB present but irecovery cannot claim it" \
            "The device is in Recovery on the USB bus, but libirecovery failed to communicate." \
            "Proper udev rules granting user access to 05ac:1281." \
            "Verify udev rules: sudo install -Dm0644 udev/39-ich-apple-recovery.rules /etc/udev/rules.d/39-ich-apple-recovery.rules && sudo udevadm control --reload-rules && sudo udevadm trigger"
        return 1
    fi
    backend_error "Timed out waiting for Recovery" "iBoot did not re-enumerate as USB Recovery." \
        "MODE=Recovery and a responding iBoot interface." "Use a direct USB-A cable, re-pwn DFU, and ensure the artifact includes firmware."
    return 1
}

boot_raw_and_poll() {
    local image="$1" log pid iteration
    log="$(mktemp -t ich-usbliter8ctl.XXXXXX)"
    printf 'Loading raw iBoot through %s: %s\n' "$BACKEND_NAME" "$(basename "$image")"
    backend_boot_raw "$image" >"$log" 2>&1 & pid=$!
    for iteration in $(seq 1 25); do
        if ! kill -0 "$pid" 2>/dev/null; then wait "$pid" || { cat "$log"; rm -f "$log"; return 1; }; cat "$log"; rm -f "$log"; return 0; fi
        [[ "$(recovery_mode)" == "Recovery" ]] && { kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; cat "$log"; rm -f "$log"; return 0; }
        sleep 1
    done
    kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
    cat "$log"; rm -f "$log"
    printf 'warning: raw boot command did not exit; continuing because Recovery polling is authoritative\n' >&2
}

send_firmware_set() {
    local fw
    for fw in PMP AOP ANE AVE ISP GFX SIO; do
        [[ -f "$BOOTCHAIN/$fw.img4" ]] || continue
        printf 'Loading %s...\n' "$fw"
        backend_send_file "$BOOTCHAIN/$fw.img4"
        backend_send_command firmware
    done
}

show_logo_if_available() {
    local logo=""
    [[ -s "$BOOTCHAIN/logo.img4" ]] && logo="$BOOTCHAIN/logo.img4"
    [[ -z "$logo" && -s "$NR_RESOURCES/logo.img4" ]] && logo="$NR_RESOURCES/logo.img4"
    if [[ -z "$logo" ]]; then
        printf 'warning: no prebuilt logo.img4; skipping logo on %s runtime\n' "$BACKEND_NAME" >&2
        return 0
    fi
    printf 'Setting signed logo: %s\n' "$logo"
    backend_send_file "$logo" && { backend_send_command 'setpicture 1' || backend_send_command setpicture || backend_send_command 'setpicture 0'; sleep "$LOGO_HOLD_SECS"; }
}

print_dry_run() {
    cat <<'EOF'
[DRY-RUN]

[1] Detect device
[2] Verify Product / board / CPID
[3] Verify artifact
[4] Verify pwned DFU
[5] Send patched iBoot
[6] Wait for Recovery
[7] Send SPTM/TXM and RestoreSEP when staged
[8] Send required firmware
[9] Send DeviceTree
[10] Send trustcache
[11] Send ramdisk
[12] Send kernelcache, boot arguments, and bootx
EOF
}

print_system
artifact_validate
if ((VALIDATE_ONLY)); then exit 0; fi
backend_require_runtime_tools
require_pwned_matching_dfu
if ((DRY_RUN)); then print_dry_run; exit 0; fi

printf 'Booting: %s\n' "$bootchain_name"
printf 'Boot arguments: %s\nUSB firmware: %s\n' "$BOOTARGS" "$([[ "$WITH_FW" -eq 1 ]] && echo enabled || echo disabled)"

# Record USB port while DFU device is still visible in sysfs.
if type -t backend_usb_record_apple_port &>/dev/null; then
    backend_usb_record_apple_port || true
fi

if [[ -f "$BOOTCHAIN/iBSS.patched.bin" && -f "$BOOTCHAIN/use-ibss" ]]; then
    printf 'Loading iBSS → iBEC path...\n'
    boot_raw_and_poll "$BOOTCHAIN/iBSS.patched.bin"
    sleep 4
    if [[ -f "$BOOTCHAIN/iBEC.patched.img4" ]]; then
        backend_send_file "$BOOTCHAIN/iBEC.patched.img4"
    else
        backend_send_file "$BOOTCHAIN/iBoot.patched.bin"
    fi
    backend_send_command go || true
    sleep 3
    wait_recovery
else
    boot_raw_and_poll "$BOOTCHAIN/iBoot.patched.bin"
    wait_recovery
fi

backend_send_command 'bgcolor 0 0 0' || printf 'warning: bgcolor failed\n' >&2
((USE_LOGO)) && show_logo_if_available || true
if [[ -f "$BOOTCHAIN/sptm.img4" ]]; then backend_send_file "$BOOTCHAIN/sptm.img4"; backend_send_command firmware; fi
if [[ -f "$BOOTCHAIN/txm.img4" ]]; then backend_send_file "$BOOTCHAIN/txm.img4"; backend_send_command firmware; fi
if ((SEP < 0)); then [[ -f "$BOOTCHAIN/sep-firmware.img4" ]] && SEP=1 || SEP=0; fi
if ((SEP)); then
    [[ -f "$BOOTCHAIN/sep-firmware.img4" ]] || { backend_error "Missing RestoreSEP" "--sep was requested but sep-firmware.img4 is absent." "A staged RestoreSEP image." "Rebuild the artifact or use --no-sep."; exit 1; }
    backend_send_file "$BOOTCHAIN/sep-firmware.img4"; backend_send_command rsepfirmware
fi
if ((WITH_FW)) && [[ ! -f "$BOOTCHAIN/use-ibss" ]]; then send_firmware_set; fi
backend_send_file "$BOOTCHAIN/devicetree.img4"; backend_send_command devicetree
backend_send_file "$BOOTCHAIN/trustcache.img4"; backend_send_command firmware
backend_send_file "$BOOTCHAIN/ramdisk.img4"; sleep 2; backend_send_command ramdisk
if ((WITH_FW)) && [[ -f "$BOOTCHAIN/use-ibss" ]]; then send_firmware_set; fi
backend_send_file "$BOOTCHAIN/kernelcache.img4"
backend_send_command "setenvnp boot-args $BOOTARGS" || backend_send_command "setenv boot-args $BOOTARGS" || printf 'warning: boot-args command failed\n' >&2
backend_send_command bootx

wait_for_ramdisk_ssh() {
    local max_wait="${RAMDISK_BOOT_WAIT_SECS:-45}"
    printf '\n[*] Boot command sent (bootx). Waiting for ramdisk kernel & USB Mux to start (up to %ss)...\n' "$max_wait"
    
    # 1. Wait for Recovery device (05ac:1281) to disconnect as kernel takes over
    local i
    for i in $(seq 1 15); do
        if type -t backend_usb_apple_present &>/dev/null; then
            if ! backend_usb_apple_present "1281"; then
                printf '  Recovery device disconnected (kernel booting)...\n'
                break
            fi
        fi
        sleep 1
    done
    
    # 2. Wait for Ramdisk USB Mux device (05ac:12a8 / Apple USB) to appear
    local detected=0
    for i in $(seq 1 "$max_wait"); do
        if type -t backend_usb_apple_present &>/dev/null; then
            if backend_usb_apple_present "12a8" || backend_usb_apple_present "12aa" || backend_usb_apple_present "12ab"; then
                printf '  Ramdisk USB interface detected in kernel (after %ss)\n' "$i"
                detected=1
                break
            fi
        fi
        ((i % 5 == 0)) && printf '  Waiting for ramdisk USB interface... (%ss/%ss)\n' "$i" "$max_wait"
        sleep 1
    done
    
    if type -t backend_usb_settle &>/dev/null; then
        backend_usb_settle 3
    fi
    
    printf '\n============================================================\n'
    printf '  ICH_A12+ Ramdisk is booted!\n'
    printf '============================================================\n'
    printf 'To connect to SSH:\n'
    printf '  Option A: Use the helper script:\n'
    printf '     ./ssh.sh\n\n'
    printf '  Option B: Manual commands:\n'
    printf '     1. iproxy 2222 22\n'
    printf '     2. ssh root@127.0.0.1 -p 2222  (Password: alpine)\n\n'
    printf 'After login, mount all partitions with:\n'
    printf '     mount_ich\n'
    printf '============================================================\n\n'
}

wait_for_ramdisk_ssh

