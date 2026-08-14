#!/usr/bin/env bash
# Safe fixture for boot.sh --dry-run. It never sends a USB transfer.
set -euo pipefail
case "${1:-}" in
    -q)
        cat <<EOF
CPID: ${FAKE_CPID:-0x8030}
CPRV: 0x11
BDID: 0x04
ECID: 0x0011590e0a42802e
PWND: ${FAKE_PWND:-usbliter8}
MODE: ${FAKE_MODE:-DFU}
PRODUCT: ${FAKE_PRODUCT:-iPhone12,1}
MODEL: ${FAKE_MODEL:-n104ap}
NAME: iPhone 11
EOF
        ;;
    *)
        printf 'fake irecovery rejects USB operation: %s\n' "$*" >&2
        exit 99
        ;;
esac
