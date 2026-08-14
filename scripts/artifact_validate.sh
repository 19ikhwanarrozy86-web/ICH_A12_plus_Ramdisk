#!/usr/bin/env bash
# Artifact-only validation. It never talks to USB or creates IMG4 files.

artifact_field() {
    local key="$1"
    awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$BOOTCHAIN/chain.info"
}

artifact_nonempty() {
    local file="$1"
    [[ -s "$BOOTCHAIN/$file" ]] || {
        backend_error "Invalid boot artifact" "Required file is missing or empty: $BOOTCHAIN/$file." \
            "A non-empty $file in the selected bootchain." \
            "Download/extract a complete artifact or rebuild it on macOS/GitHub Actions."
        return 1
    }
}

artifact_img4_marker() {
    local file="$1" type="$2"
    python3 - "$BOOTCHAIN/$file" "$type" <<'PY'
from pathlib import Path
import sys
data = Path(sys.argv[1]).read_bytes()[:65536]
raise SystemExit(0 if b"IMG4" in data and sys.argv[2].encode("ascii") in data else 1)
PY
}

artifact_validate() {
    local required=(iBoot.patched.bin devicetree.img4 trustcache.img4 ramdisk.img4 kernelcache.img4 chain.info kernel.mode kpf.set)
    local file product model cpid kernel with_fw artifact_dir build_info
    [[ -d "$BOOTCHAIN" ]] || {
        backend_error "Bootchain not found" "Selected path does not exist: ${BOOTCHAIN:-unset}." \
            "artifact/bootchain or BOOTCHAIN_PATH pointing at a bootchain." \
            "Extract the artifact, or set BOOTCHAIN_PATH explicitly."
        return 1
    }
    for file in "${required[@]}"; do artifact_nonempty "$file"; done
    product="$(artifact_field product)"; model="$(artifact_field model)"; cpid="$(artifact_field cpid)"; kernel="$(<"$BOOTCHAIN/kernel.mode")"; with_fw="$(artifact_field with_fw)"
    [[ -n "$product" && -n "$model" && -n "$cpid" ]] || {
        backend_error "Invalid artifact metadata" "chain.info lacks product, model, or cpid." \
            "A bootchain produced by the supported build pipeline." "Do not boot an incomplete artifact."
        return 1
    }
    [[ "$kernel" == "patched" || "$kernel" == "stock" ]] || {
        backend_error "Invalid kernel metadata" "kernel.mode is $kernel." "patched or stock." "Rebuild the artifact."
        return 1
    }
    artifact_img4_marker devicetree.img4 rdtr || { backend_error "Invalid IMG4" "devicetree.img4 has no rdtr IMG4 marker." "A valid DeviceTree IMG4." "Re-extract the artifact."; return 1; }
    artifact_img4_marker trustcache.img4 rtsc || { backend_error "Invalid IMG4" "trustcache.img4 has no rtsc IMG4 marker." "A valid trustcache IMG4." "Re-extract the artifact."; return 1; }
    artifact_img4_marker ramdisk.img4 rdsk || { backend_error "Invalid IMG4" "ramdisk.img4 has no rdsk IMG4 marker." "A valid ramdisk IMG4." "Re-extract the artifact."; return 1; }
    artifact_img4_marker kernelcache.img4 rkrn || { backend_error "Invalid IMG4" "kernelcache.img4 has no rkrn IMG4 marker." "A valid kernelcache IMG4." "Re-extract the artifact."; return 1; }
    if [[ "$with_fw" == "1" ]]; then
        for file in AOP.img4 ANE.img4 AVE.img4 GFX.img4 ISP.img4 SIO.img4; do artifact_nonempty "$file"; done
        [[ "$(backend_normalize "$cpid")" != "0x8030" ]] || artifact_nonempty PMP.img4
    fi
    artifact_dir="$(dirname "$BOOTCHAIN")"
    if [[ "$artifact_dir" == "$NR_ARTIFACT_ROOT" ]]; then
        build_info="$artifact_dir/BUILD-INFO.txt"
        artifact_nonempty "../BUILD-INFO.txt"
        artifact_nonempty "../source-commit.txt"
        local info_product info_model info_cpid
        info_product="$(awk -F': ' '$1 == "ProductType" { print $2; exit }' "$build_info")"
        info_model="$(awk -F': ' '$1 == "BoardConfig" { print $2; exit }' "$build_info")"
        info_cpid="$(awk -F': ' '$1 == "CPID" { print $2; exit }' "$build_info")"
        [[ "$info_product" == "$product" && "$(backend_normalize "$info_model")" == "$(backend_normalize "$model")" && "$(backend_normalize "$info_cpid")" == "$(backend_normalize "$cpid")" ]] || {
            backend_error "Inconsistent artifact metadata" "BUILD-INFO.txt does not match chain.info." \
                "Identical ProductType, BoardConfig, and CPID metadata." "Re-download the complete artifact as one unit."
            return 1
        }
    fi
    printf 'Artifact: valid\nProduct: %s\nBoard: %s\nCPID: %s\nKernel: %s\nRamdisk: present\niBoot: patched\nFirmware: %s\n' \
        "$product" "$model" "$cpid" "$kernel" "$([[ "$with_fw" == 1 ]] && echo present || echo absent)"
}

artifact_validate_device() {
    local info="$1" expected_product expected_model expected_cpid found_product found_model found_cpid
    expected_product="$(artifact_field product)"; expected_model="$(backend_normalize "$(artifact_field model)")"; expected_cpid="$(backend_normalize "$(artifact_field cpid)")"
    found_product="$(backend_field PRODUCT "$info")"; found_model="$(backend_normalize "$(backend_field MODEL "$info")")"; found_cpid="$(backend_normalize "$(backend_field CPID "$info")")"
    [[ "$found_product" == "$expected_product" && "$found_model" == "$expected_model" && "$found_cpid" == "$expected_cpid" ]] || {
        backend_error "Unexpected device" \
            "Artifact expects $expected_product / $expected_model / $expected_cpid; device reports ${found_product:-unknown} / ${found_model:-unknown} / ${found_cpid:-unknown}." \
            "An exact Product, board, and CPID match." "Use the matching artifact; do not continue."
        return 1
    }
}
