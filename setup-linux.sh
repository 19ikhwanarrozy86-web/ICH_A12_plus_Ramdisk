#!/usr/bin/env bash
# Inspect or explicitly install Linux runtime prerequisites. It never builds IMG4.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
INSTALL=0
INSTALL_UDEV=0

usage() {
    cat <<'EOF'
usage: ./setup-linux.sh [--install] [--install-udev]

Without options this is read-only: it detects Linux, tools, Python/PyUSB,
libusb, libirecovery/irecovery, usbliter8ctl, and USB permission setup.

  --install       explicitly install available runtime packages through pacman/apt
  --install-udev  explicitly install the supplied least-privilege udev rules

Neither option rebuilds an artifact or changes the iPhone.
EOF
}

while (($#)); do
    case "$1" in
        --install) INSTALL=1 ;;
        --install-udev) INSTALL_UDEV=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
    shift
done

ok() { printf '  OK   %s\n' "$*"; }
warn() { printf '  WARN %s\n' "$*"; }
miss() { printf '  MISS %s\n' "$*"; MISSING=1; }
MISSING=0

[[ "$(uname -s)" == Linux ]] || { printf 'This setup script is for Linux only.\n' >&2; exit 1; }
if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
fi
DISTRO_ID="${ID:-unknown}"
ARCH="$(uname -m)"
printf '=== platform ===\n  distro: %s\n  architecture: %s\n' "$DISTRO_ID" "$ARCH"

case "$DISTRO_ID" in
    arch|cachyos|endeavouros|manjaro)
        MANAGER=pacman
        # libirecovery is not consistently packaged in Arch's official repos.
        # Install only known repository packages; report the official source path below.
        PACKAGES=(libusb python-pyusb usbmuxd libusbmuxd libimobiledevice sshpass)
        IRECOVERY_NOTE='Install libirecovery from its official source (or a trusted package) so irecovery is on PATH.'
        ;;
    debian|ubuntu|linuxmint|pop) MANAGER=apt; PACKAGES=(irecovery libusb-1.0-0 python3-usb usbmuxd libusbmuxd-tools libimobiledevice-utils sshpass) ;;
    *) MANAGER=none; PACKAGES=() ;;
esac

printf '\n=== runtime tools ===\n'
command -v bash >/dev/null && ok "bash $(bash --version | head -1)" || miss 'bash'
command -v python3 >/dev/null && ok "$(python3 --version)" || miss 'python3'
if command -v python3 >/dev/null && python3 -c 'import usb' >/dev/null 2>&1; then
    ok 'PyUSB module'
else
    miss 'PyUSB module (python3 -m pip install -r requirements.txt, or use distro package)'
fi
if command -v irecovery >/dev/null; then
    ok "irecovery: $(command -v irecovery)"
else
    miss 'irecovery (libirecovery CLI)'
    [[ -z "${IRECOVERY_NOTE:-}" ]] || printf '  note: %s\n' "$IRECOVERY_NOTE"
fi
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libusb-1.0; then
    ok "libusb: $(pkg-config --modversion libusb-1.0)"
else
    warn 'libusb pkg-config metadata unavailable (runtime may still be installed)'
fi
if command -v usbmuxd >/dev/null; then
    ok "usbmuxd: $(command -v usbmuxd)"
else
    warn 'usbmuxd not found (required for SSH/USB multiplexing; run with --install)'
fi
if command -v iproxy >/dev/null; then
    ok "iproxy: $(command -v iproxy)"
else
    warn 'iproxy not found (required for ./ssh.sh; install libusbmuxd)'
fi

USBLITER8CTL="${USBLITER8CTL:-}"
if [[ -z "$USBLITER8CTL" ]]; then
    for candidate in "$ROOT/../usbliter8ra1n/tools/usbliter8ctl" "$ROOT/tools/linux/usbliter8ctl"; do
        [[ -f "$candidate" ]] && USBLITER8CTL="$candidate" && break
    done
fi
if [[ -n "$USBLITER8CTL" && -x "$USBLITER8CTL" ]]; then
    ok "usbliter8ctl: $USBLITER8CTL"
else
    miss 'usbliter8ctl (set USBLITER8CTL=/path/to/usbliter8ctl)'
fi

printf '\n=== USB permissions ===\n'
if [[ -f /etc/udev/rules.d/39-ich-apple-recovery.rules ]]; then
    ok 'ICH Apple DFU/Recovery udev rules installed'
else
    warn 'udev rules not installed; non-root USB access may fail'
    printf '  fix: sudo install -Dm0644 %s /etc/udev/rules.d/39-ich-apple-recovery.rules\n' "$ROOT/udev/39-ich-apple-recovery.rules"
    printf '       sudo udevadm control --reload-rules && sudo udevadm trigger\n'
fi

if ((INSTALL)); then
    printf '\n=== explicit package installation ===\n'
    case "$MANAGER" in
        pacman)
            sudo pacman -S --needed "${PACKAGES[@]}"
            ;;
        apt)
            sudo apt-get update
            sudo apt-get install -y "${PACKAGES[@]}"
            ;;
        *)
            printf 'Unsupported package manager for %s. Install irecovery, libusb, and PyUSB manually.\n' "$DISTRO_ID" >&2
            exit 1
            ;;
    esac
    if [[ -f "$ROOT/requirements.txt" ]] && command -v python3 >/dev/null 2>&1; then
        python3 -m pip install -r "$ROOT/requirements.txt" 2>/dev/null || true
    fi
fi
if ((INSTALL_UDEV)); then
    [[ -d /run/udev || -d /etc/udev ]] || { printf 'udev is not available on this system.\n' >&2; exit 1; }
    sudo install -Dm0644 "$ROOT/udev/39-ich-apple-recovery.rules" /etc/udev/rules.d/39-ich-apple-recovery.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger
fi

printf '\n=== result ===\n'
if ((MISSING)); then
    printf 'Runtime setup is incomplete. Re-run with --install for supported distro packages, then resolve any remaining MISS items.\n'
    exit 1
fi
printf 'Runtime prerequisites are available. Next: ./boot.sh --validate && ./boot.sh --dry-run\n'
