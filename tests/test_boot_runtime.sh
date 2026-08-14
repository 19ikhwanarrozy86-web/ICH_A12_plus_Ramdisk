#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

bash -n boot.sh env.sh backends/common.sh backends/linux.sh backends/darwin.sh scripts/artifact_validate.sh
./setup-linux.sh --help | grep -F -- '--install-udev'
./boot.sh --validate | grep -F 'Artifact: valid'

# Dry-run can use a fixture with a tiny importable usb module, so it proves that
# boot.sh queries and compares the device without calling a USB send operation.
fixture_dir="$(mktemp -d)"
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/usb"
printf '%s\n' '# test fixture' > "$fixture_dir/usb/__init__.py"
PYTHONPATH="$fixture_dir" IRECOVERY="$ROOT/tests/fake_irecovery.sh" USBLITER8CTL="$ROOT/tests/fake_usbliter8ctl.py" \
    ./boot.sh --dry-run | grep -F '[DRY-RUN]'

# A matching CPID alone is insufficient: Product/board/mode are safety gates.
if PYTHONPATH="$fixture_dir" FAKE_MODE=Recovery IRECOVERY="$ROOT/tests/fake_irecovery.sh" USBLITER8CTL="$ROOT/tests/fake_usbliter8ctl.py" \
    ./boot.sh --dry-run >/dev/null 2>&1; then
    echo 'expected Recovery dry-run to fail before any send' >&2
    exit 1
fi
if PYTHONPATH="$fixture_dir" FAKE_MODEL=d421ap IRECOVERY="$ROOT/tests/fake_irecovery.sh" USBLITER8CTL="$ROOT/tests/fake_usbliter8ctl.py" \
    ./boot.sh --dry-run >/dev/null 2>&1; then
    echo 'expected mismatched-board dry-run to fail before any send' >&2
    exit 1
fi

if ./boot.sh --backend invalid >/dev/null 2>&1; then
    echo 'expected invalid backend selection to fail' >&2
    exit 1
fi
