# ICH_A12_plus_Ramdisk `v1.2`

> **Apple A12 / A13 SSH Ramdisk Toolkit** for pwned DFU mode via [usbliter8](https://github.com/prdgmshift/usbliter8).

Original Toolkit by **[@Official_I_C_H](https://t.me/Official_I_C_H)** · [t.me/Official_I_C_H](https://t.me/Official_I_C_H)  
Linux Port & Maintenance by **[20obb](https://github.com/20obb)**  
Copyright (c) 20obb. All rights reserved.

---

> [!WARNING]
> **Research Use Only:** This is not a jailbreak. Only use on devices you own for research purposes.
>
> ⚠️ **Linux Build Note:** Building bootchain artifacts natively on Linux requires macOS-only tools. If you are using Linux, build your artifacts via **GitHub Actions** (see `.github/workflows/`) or download pre-built artifacts, then place them in `./artifact/` and run `./boot.sh`.
>
> ⚠️ **SSH Status:** **SSH is currently UNTESTED on the Linux backend.**



## ✨ What’s New in v1.2

- **Linux Backend Support:** Cross-platform Linux boot runtime (`./boot.sh --backend linux` & `./setup-linux.sh`).
- **Automatic Kernel Patch Routing:** Dynamic patch path based on target iOS major version for A12/A13.
- **On-Device `mount_ich`:** Automatically mounts **all** APFS filesystems over SSH (iOS **17 → 27+**).

| iOS Major | Kernel Patch Strategy |
|-----------|------------------------|
| **17 / 18** | Proven finder (`PE_i_can_has_debugger` + `AMFIIsCDHashInTrustCache`) |
| **26** | Fixed byte-offset table (`patch/ios26_kernel_byte_patches.py`) |
| **27+** | Finder + launch constraints (TXM-era) |

---

## ⚡ Enter Pwned DFU

1. Put device into DFU mode + **RP2350** + [usbliter8](https://github.com/prdgmshift/usbliter8).
2. Connect Lightning cable to your host machine (**Direct USB-A → Lightning** recommended; USB-C adapters can cause USB reset timing issues).
3. Verify pwned DFU connection:

```bash
# macOS
./tools/darwin/irecovery -q

# Linux
irecovery -q
```
Expected output should confirm `MODE: DFU` and `PWND: usbliter8`.

---

## 🚀 Setup & Quick Start

### 🐧 On Linux

> **Building on Linux:** Build your artifacts via **GitHub Actions**, extract/place them in `./artifact/`, then run:

```bash
# 1. Install Linux runtime dependencies & udev rules
./setup-linux.sh --install --install-udev

# 2. Check connected device and artifact status
./status.sh

# 3. Boot pwned DFU device into Ramdisk
sudo ./boot.sh --debug --with-fw
```

### 🍎 On macOS

```bash
# 1. Install dependencies
./setup.sh
# or: brew install python@3 curl blacktop/tap/ipsw && pip3 install -r requirements.txt

# 2. Check status and build artifact locally
./status.sh
./build.sh --with-fw

# 3. Boot into Ramdisk
./boot.sh
```

---

## 🌐 Connecting & Mounting (SSH)

> ⚠️ **Note:** SSH functionality is currently **UNTESTED** on Linux hosts.

Once booted into Ramdisk:

```bash
# Forward SSH port
iproxy 2222 22

# Connect via SSH (Password: alpine)
ssh root@localhost -p 2222

# Mount all filesystems (System, Preboot, xART, Data, etc.)
mount_ich
```

`mount_ich` works seamlessly across **A12 & A13** devices running **iOS 17 through 27+**.

---

## 🛠️ Advanced Options

### Force a Specific Kernel Patch Path

```bash
./build.sh --build <BUILD> --with-fw --kpf-set ios18   # Finder
./build.sh --build <BUILD> --with-fw --kpf-set ios26   # Byte table
./build.sh --build <BUILD> --with-fw --kernel stock    # Stock kernel (no patches)
```

---

## 📂 Repository Layout

| File / Folder | Description |
|---------------|-------------|
| `boot.sh` | Cross-platform boot runtime (Linux & Darwin) |
| `build.sh` | Artifact builder (macOS / GitHub Actions) |
| `setup-linux.sh` | Linux dependency setup & udev rule installer |
| `backends/` | OS-specific boot drivers (`linux.sh`, `darwin.sh`, `common.sh`) |
| `patch/` | Kernel & iBoot patchfinders |
| `udev/` | Linux udev rules for Apple DFU/Recovery devices |
| `tools/` | Platform tool binaries |

---

## 📜 Copyright & Credits

- **Original Toolkit:** [@Official_I_C_H](https://t.me/Official_I_C_H)
- **Linux Port & Maintenance:** [20obb](https://github.com/20obb)
- **Copyright:** © 20obb ([GitHub: @20obb](https://github.com/20obb)). All rights reserved.
