# ICH_A12_plus_Ramdisk `V2.0`

> **Apple A12 / A13 SSH Ramdisk Toolkit** for pwned DFU mode via [usbliter8](https://github.com/prdgmshift/usbliter8).

Linux Port & Maintenance by **[20obb](https://github.com/20obb)**  
Copyright (c) 20obb. All rights reserved.

---

> [!NOTE]
> **Research Use Only:** This is not a jailbreak. Only use on devices you own for research purposes.
>
> 🚀 **Linux Build Note:** Building bootchain artifacts natively on Linux requires macOS-only tools. If you are using Linux, build your artifacts via **GitHub Actions** (see `.github/workflows/`) or download pre-built artifacts, extract them into `./artifact/bootchain/`, and run `sudo ./boot.sh --debug --with-fw`.
>
> ✅ **SSH Status:** **Fully TESTED & WORKING on Linux and macOS** with automatic port forwarding and `mount_ich` support.

---

## ✨ What’s New in V2.0

- **Linux Backend & Full SSH Support:** Cross-platform Linux boot runtime (`sudo ./boot.sh --debug --with-fw`).
- **One-Click SSH Connector:** Dedicated `./ssh.sh` helper that automatically manages `iproxy` in the background and opens the interactive SSH shell.
- **Dropbear 0600 Hostkey Validation:** Clean payload permissions and automatic verification during build.
- **Automatic Kernel Patch Routing:** Dynamic patch path based on target iOS major version for A12/A13.
- **On-Device `mount_ich`:** Automatically mounts **all** APFS filesystems over SSH (System, Preboot, Data, xART, etc.).

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

> **Building on Linux:** Build your artifacts via **GitHub Actions**, extract the generated bootchain files into `./artifact/bootchain/`, then run:

```bash
# 1. Install Linux runtime dependencies & udev rules
./setup-linux.sh --install --install-udev

# 2. Install Python requirements
pip install -r requirements.txt
# or: ./requirements.sh

# 3. Check connected device and artifact status
./status.sh

# 4. Boot pwned DFU device into Ramdisk
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
sudo ./boot.sh --with-fw
```

---

## 🌐 Connecting & Mounting (SSH)

Once booted into Ramdisk (the device displays the ICH ASCII art banner):

### Option 1: Using the automated helper (Recommended)

```bash
./ssh.sh
```

### Option 2: Manual connection

```bash
# 1. On Linux, ensure usbmuxd runs with --no-preflight (-p) as root for ramdisk:
sudo killall usbmuxd 2>/dev/null || sudo systemctl stop usbmuxd
sudo usbmuxd -p -U root

# 2. Forward SSH port
iproxy 2222 22

# 3. Connect via SSH (Password: alpine)
ssh root@127.0.0.1 -p 2222
```

### 💽 Mounting Partitions

Once connected to the SSH shell:

```bash
mount_ich
```

`mount_ich` automatically detects and mounts all APFS volumes (System, Preboot, Data, xART, Hardware, etc.) seamlessly across **A12 & A13** devices running **iOS 17 through 27+**.

---

## 🛠️ Advanced Options

### Force a Specific Kernel Patch Path

```bash
./build.sh --build <BUILD> --with-fw --kpf-set ios18   # Finder
./build.sh --build <BUILD> --with-fw --kpf-set ios26   # Byte table
./build.sh --build <BUILD> --with-fw --kernel stock    # Stock kernel (no patches)
```

---

## 🔧 Troubleshooting & Common Errors

### 1. SSH Connection Reset (`kex_exchange_identification: read: Connection reset by peer`)
- **Cause:** `usbmuxd` is not running with `--no-preflight` (`-p`), was started as an unprivileged user without permission on the `/dev/bus/usb/` node, or has not detected the ramdisk device yet.
- **Fix:**
  ```bash
  # 1. Stop any running usbmuxd instance
  sudo killall usbmuxd 2>/dev/null || sudo systemctl stop usbmuxd

  # 2. Start usbmuxd as root in no-preflight mode
  sudo usbmuxd -p -U root

  # 3. Verify device detection (should list your device UDID)
  idevice_id -l

  # 4. Connect via SSH
  ./ssh.sh
  ```

---

### 2. `usbmuxd: command not found` / `Unit usbmuxd.service not loaded`
- **Cause:** The `usbmuxd` package is not installed on the host machine.
- **Fix:**
  - **Arch / CachyOS / Manjaro:**
    ```bash
    sudo pacman -S --needed usbmuxd libusbmuxd libimobiledevice sshpass
    ```
  - **Debian / Ubuntu / Mint:**
    ```bash
    sudo apt-get update && sudo apt-get install -y usbmuxd libusbmuxd-tools libimobiledevice-utils sshpass
    ```
  - Or run `./setup-linux.sh --install`.

---

### 3. `Error creating socket for listen port 2222: Address already in use`
- **Cause:** A previous background `iproxy` process is still bound to port `2222`.
- **Fix:**
  ```bash
  pkill -9 -f "iproxy"
  ```

---

### 4. Python Module Missing (`MISS PyUSB module`, `No module named 'pyimg4'`, etc.)
- **Cause:** Python dependencies are not installed in your current environment or virtual environment.
- **Fix:**
  ```bash
  pip install -r requirements.txt
  # or: ./requirements.sh
  ```

---

### 5. `MISS usbliter8ctl (set USBLITER8CTL=/path/to/usbliter8ctl)`
- **Cause:** `usbliter8ctl` is not in the default lookup paths.
- **Fix:**
  ```bash
  # Option A: Place usbliter8ctl in tools/linux/
  mkdir -p tools/linux
  cp /path/to/usbliter8ctl tools/linux/usbliter8ctl
  chmod +x tools/linux/usbliter8ctl

  # Option B: Export the path
  export USBLITER8CTL="/path/to/usbliter8ctl"
  ```

---

### 6. USB Permissions / Device Not Detected (Linux)
- **Cause:** Missing or un-reloaded udev rules for Apple DFU/Recovery modes.
- **Fix:**
  ```bash
  ./setup-linux.sh --install-udev
  # Or manually:
  sudo install -Dm0644 udev/39-ich-apple-recovery.rules /etc/udev/rules.d/39-ich-apple-recovery.rules
  sudo udevadm control --reload-rules && sudo udevadm trigger
  ```

---

## 📂 Repository Layout

| File / Folder | Description |
|---------------|-------------|
| `boot.sh` | Cross-platform boot runtime (Linux & Darwin) with post-boot monitoring |
| `ssh.sh` | One-click SSH connector and background `iproxy` manager |
| `build.sh` | Artifact builder with native `--device` support (macOS / GitHub Actions) |
| `setup-linux.sh` | Linux dependency setup & udev rule installer |
| `backends/` | OS-specific boot drivers (`linux.sh`, `darwin.sh`, `common.sh`) |
| `patch/` | Kernel & iBoot patchfinders |
| `udev/` | Linux udev rules for Apple DFU/Recovery devices |
| `tools/` | Platform tool binaries |

---

## 📜 Copyright & Credits
- **Linux Port & Maintenance:** [20obb](https://github.com/20obb)
- **Copyright:** © 20obb ([GitHub: @20obb](https://github.com/20obb)). All rights reserved.
