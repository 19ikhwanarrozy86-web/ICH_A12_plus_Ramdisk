#!/usr/bin/env bash
# Linux: libirecovery owns Recovery transport; usbliter8ctl owns pwned DFU boot.

backend_init_linux() {
    BACKEND_NAME="linux"
    IRECOVERY="${IRECOVERY:-$(command -v irecovery 2>/dev/null || true)}"
    USBLITER8CTL="${USBLITER8CTL:-}"
    if [[ -z "$USBLITER8CTL" ]]; then
        for candidate in "$ROOT/../usbliter8ra1n/tools/usbliter8ctl" "$ROOT/tools/linux/usbliter8ctl"; do
            [[ -f "$candidate" ]] && USBLITER8CTL="$candidate" && break
        done
    fi
}

backend_require_runtime_tools() {
    backend_require_executable IRECOVERY "$IRECOVERY"
    backend_require_executable USBLITER8CTL "$USBLITER8CTL"
    command -v python3 >/dev/null 2>&1 || {
        backend_error "Python unavailable" "python3 is required to run usbliter8ctl." \
            "Python 3 with PyUSB." "Install python and pyusb, then retry."
        return 1
    }
    python3 -c 'import usb' >/dev/null 2>&1 || {
        backend_error "PyUSB unavailable" "usbliter8ctl cannot import its usb module." \
            "The Python package pyusb and a usable libusb backend." \
            "Install pyusb and libusb through setup-linux.sh (to be added next), then retry."
        return 1
    }
}

backend_query() { backend_with_timeout 8 "$IRECOVERY" -q; }
backend_send_file() { backend_with_timeout "${IRECV_UPLOAD_TIMEOUT_SECS:-300}" "$IRECOVERY" -f "$1"; }
backend_send_command() { backend_with_timeout "${IRECV_CMD_TIMEOUT_SECS:-30}" "$IRECOVERY" -c "$1"; }
backend_boot_raw() { python3 "$USBLITER8CTL" boot "$1"; }
backend_supports_local_logo_build() { return 1; }

# Linux-native USB presence check.  Works at the kernel/sysfs level so it is
# independent of libirecovery handle state.  Returns 0 when at least one USB
# device with the given Vendor:Product is visible to the host.
#   backend_usb_apple_present <idProduct>   e.g. 1281 for Recovery
backend_usb_apple_present() {
    local product_id="${1:?product_id required}"
    # Fast path: sysfs (no external tool needed)
    local d
    for d in /sys/bus/usb/devices/*/idVendor; do
        [[ -f "$d" ]] || continue
        [[ "$(< "$d")" == "05ac" ]] || continue
        local pid_file="${d%idVendor}idProduct"
        [[ -f "$pid_file" && "$(< "$pid_file")" == "$product_id" ]] && return 0
    done
    # Fallback: lsusb (heavier, but works on unusual sysfs layouts)
    if command -v lsusb >/dev/null 2>&1; then
        lsusb -d "05ac:${product_id}" >/dev/null 2>&1 && return 0
    fi
    return 1
}

# Ask the kernel to finish processing any pending USB uevent before continuing.
backend_usb_settle() {
    if command -v udevadm >/dev/null 2>&1; then
        udevadm settle --timeout="${1:-5}" 2>/dev/null || true
    fi
}

# Record the USB bus/port path of the Apple DFU device (05ac:1227).
# Must be called BEFORE boot_raw_and_poll so the device still exists in sysfs.
# Sets _ICH_USB_PORT (e.g. "1-2") and _ICH_USB_BUS (e.g. "1").
backend_usb_record_apple_port() {
    _ICH_USB_PORT=""
    _ICH_USB_BUS=""
    local d base pid
    for d in /sys/bus/usb/devices/*/idVendor; do
        [[ -f "$d" && "$(< "$d")" == "05ac" ]] || continue
        base="${d%/idVendor}"
        pid="$(< "${base}/idProduct" 2>/dev/null || true)"
        if [[ "$pid" == "1227" ]]; then
            _ICH_USB_PORT="${base##*/}"          # e.g. "1-2" or "3-1.4"
            _ICH_USB_BUS="${_ICH_USB_PORT%%-*}"  # e.g. "1" or "3"
            printf '  [usb] DFU device on bus %s port %s\n' "$_ICH_USB_BUS" "$_ICH_USB_PORT"
            return 0
        fi
    done
    return 1
}

# Force the Linux USB subsystem to re-detect whatever device is now on the port
# that previously held the DFU device.  Three steps in sequence:
#
#   (a) Remove any stale DFU device (05ac:1227) still lingering in sysfs.
#       After usbliter8ctl exits, the kernel may still show the old DFU entry
#       on the port even though the device has already rebooted to iBoot.
#
#   (b) Cycle the root hub authorization on the recorded USB bus.
#       This forces the xHCI/EHCI hub driver to re-scan all downstream ports
#       and detect the Recovery device (05ac:1281).  Only the bus that had the
#       Apple device is affected; other buses are left alone.
#
#   (c) Settle udev so permissions (uaccess tag) are applied before irecovery
#       tries to claim the interface.
#
# Returns 0 if at least one action was taken, 1 otherwise.
backend_usb_kickstart_reenumerate() {
    local kicked=0

    # (a) remove stale DFU entries
    local d base pid
    for d in /sys/bus/usb/devices/*/idVendor; do
        [[ -f "$d" && "$(< "$d")" == "05ac" ]] || continue
        base="${d%/idVendor}"
        pid="$(< "${base}/idProduct" 2>/dev/null || true)"
        if [[ "$pid" == "1227" && -w "${base}/remove" ]]; then
            printf '  [usb] removing stale DFU entry %s\n' "${base##*/}"
            echo 1 > "${base}/remove" 2>/dev/null || true
            kicked=1
        fi
    done

    # (b) cycle the root hub on the recorded bus
    if [[ -n "${_ICH_USB_BUS:-}" ]]; then
        local bus_path="/sys/bus/usb/devices/usb${_ICH_USB_BUS}"
        if [[ -w "$bus_path/authorized" ]]; then
            printf '  [usb] cycling bus %s to trigger port re-scan\n' "$_ICH_USB_BUS"
            echo 0 > "$bus_path/authorized" 2>/dev/null || true
            sleep 0.5
            echo 1 > "$bus_path/authorized" 2>/dev/null || true
            kicked=1
        fi
    fi

    # (c) settle udev
    backend_usb_settle 5

    return $(( ! kicked ))
}

