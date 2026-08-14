#!/usr/bin/env bash
# Shared paths for ICHA12A13 (A12/A13 SSH ramdisk).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export NEW_RAMDISK_ROOT="$ROOT"
export NR_VERSION="v1.2-ICHA12A13"
export NR_AUTHOR="@Official_I_C_H"
export NR_TELEGRAM="https://t.me/Official_I_C_H"
export NR_TOOLS="$ROOT/tools/darwin"
export NR_PATCH="$ROOT/patch"
export NR_RESOURCES="$ROOT/resources"
export NR_CACHE="$ROOT/cache"
export NR_WORK="$ROOT/work"
export NR_BOOTCHAIN_ROOT="$ROOT/bootchain"
export NR_ARTIFACT_ROOT="${ICH_RAMDISK_ARTIFACT:-$ROOT/artifact}"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin:$NR_TOOLS${PATH:+:$PATH}"
# shellcheck source=scripts/banner.sh
source "$ROOT/scripts/banner.sh"

# Latest successful bootchain name is written here after build.
export NR_LAST_BOOTCHAIN_FILE="$ROOT/.last_bootchain"
if [[ -z "${BOOTCHAIN_NAME:-}" && -f "$NR_LAST_BOOTCHAIN_FILE" ]]; then
    BOOTCHAIN_NAME="$(<"$NR_LAST_BOOTCHAIN_FILE")"
fi
export BOOTCHAIN_NAME="${BOOTCHAIN_NAME:-}"
if [[ -n "${BOOTCHAIN_PATH:-}" ]]; then
    export BOOTCHAIN="$BOOTCHAIN_PATH"
elif [[ -n "$BOOTCHAIN_NAME" ]]; then
    export BOOTCHAIN="$NR_BOOTCHAIN_ROOT/$BOOTCHAIN_NAME"
elif [[ -d "$NR_ARTIFACT_ROOT/bootchain" ]]; then
    export BOOTCHAIN="$NR_ARTIFACT_ROOT/bootchain"
else
    export BOOTCHAIN=""
fi
