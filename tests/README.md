# MixOS-GO Test Suite

This directory contains all testing and validation scripts for MixOS-GO.

## Quick Start

```bash
# Run all tests
bash run-tests.sh

# Run specific test
bash run-tests.sh test-viso
bash run-tests.sh test-mix-cli

# Check build status
bash check-build.sh

# Auto-monitor build and test
bash auto-test.sh
```

## Test Scripts

### `run-tests.sh` - Main Test Runner
Central test coordinator that orchestrates all test execution.

**Usage:**
```bash
bash run-tests.sh [test-name]
```

**Test Names:**
- `test-viso` - Boot VISO image in QEMU
- `test-mix-cli` - Unit tests for package manager
- `check-build` - Build readiness check
- `create-iso` - Create minimal ISO
- `install-deps` - Check/install dependencies

---

### `test-viso.sh` - VISO Boot Test
Tests VISO (QCOW2 virtual disk) boot capability using QEMU.

**Features:**
- Boots MixOS-GO in QEMU with 2GB RAM, 2 CPU cores
- Validates kernel load
- Tests initramfs initialization
- Checks rootfs mount
- Validates package manager (`mix` command)
- Tests SSH connectivity
- Serial console access for debugging

**Usage:**
```bash
bash test-viso.sh [timeout]
```

**Output:**
- Real-time QEMU console via serial port
- Boot validation messages
- Test results

**Requirements:**
- QEMU (qemu-system-x86_64)
- VISO image built (`artifacts/mixos-go-v1.0.0.viso`)

---

### `test-mix-cli.sh` - Package Manager Tests
Unit tests for the mix-cli package manager binary.

**Tests:**
- Binary existence and permissions
- Version and help commands
- Basic CLI parsing
- Database functionality
- Package operations
- Dependency resolution

**Usage:**
```bash
bash test-mix-cli.sh
```

**Requirements:**
- `mix` binary built (`artifacts/mix`)

---

### `check-build.sh` - Build Status Monitor
Displays comprehensive build progress and readiness information.

**Shows:**
- Active build processes
- Artifact completion status
- QEMU availability
- Disk space availability
- Readiness for testing

**Usage:**
```bash
bash check-build.sh
```

**Output Example:**
```
✓ Build is running (PID: 12345)
✓ Artifacts directory exists (15 files)
✓ VISO image ready (193KB)
⏳ ISO building... (expected after ~20 min)
✓ QEMU is installed (QEMU emulator version x.xx)
Available in /tmp: 50G
```

---

### `auto-test.sh` - Automatic Test Monitor
Continuously monitors build progress and automatically starts tests upon completion.

**Features:**
- Monitors active build process
- Shows artifact progress
- Auto-detects bootable images
- Runs appropriate test suite
- Logs all results

**Usage:**
```bash
# Start monitoring
bash auto-test.sh &

# Or run foreground
bash auto-test.sh
```

**Log Output:**
- Saved to: `auto-test.log`
- Includes timing and progress markers

---

### `install-deps.sh` - Dependency Manager
Checks and installs required build and test dependencies.

**Dependencies Checked:**
- **Build:** gcc, make, flex, bison, bc, libelf-dev, libssl-dev
- **Testing:** qemu-system-x86, qemu-utils
- **ISO Creation (optional):** squashfs-tools, xorriso, genisoimage
- **System:** git, curl, python3

**Usage:**
```bash
# Check dependencies
bash install-deps.sh

# Install with interactive prompt
sudo bash install-deps.sh
```

**Requirements:**
- sudo access (for installation)

---

### `create-iso-minimal.sh` - Minimal ISO Creator
Creates a minimal ISO when mksquashfs is unavailable (fallback method).

**Features:**
- Uses tar.gz instead of squashfs compression
- GRUB bootloader configuration
- Boot from CD-ROM support

**Usage:**
```bash
bash create-iso-minimal.sh
```

**Output:**
- `artifacts/mixos-go-minimal.iso`

**Requirements:**
- genisoimage or xorriso
- Kernel, initramfs, and rootfs artifacts

---

## Test Workflow

### Full Test Cycle
```bash
# 1. Start build
make all

# 2. Monitor build (in separate terminal)
bash check-build.sh

# 3. Auto-run tests on completion
bash auto-test.sh

# Or manually run tests:
bash run-tests.sh test-viso
```

### Selective Testing
```bash
# Only package manager tests
bash test-mix-cli.sh

# Only VISO boot test
bash test-viso.sh 60  # 60 second timeout

# Check build status
bash check-build.sh
```

### Creating Test Images
```bash
# Create minimal ISO (without squashfs)
bash create-iso-minimal.sh

# Test ISO boot
bash test-viso.sh --iso artifacts/mixos-go-minimal.iso
```

---

## Test Results Directory

After running tests, check:
- `auto-test.log` - Automatic test log with timestamps
- QEMU console output - Real-time test execution
- Artifacts - Generated images in `../artifacts/`

---

## Troubleshooting

### QEMU Not Found
```bash
bash install-deps.sh
# Then: sudo apt-get install qemu-system-x86 qemu-utils
```

### Build Still Running
```bash
bash check-build.sh  # Monitor progress
tail -f /tmp/build.log  # Check build log
```

### VISO Test Timeout
```bash
bash test-viso.sh 120  # Increase timeout to 120 seconds
```

### Permission Denied
```bash
# Make scripts executable
chmod +x *.sh

# Or re-create them
make clean-tests
make tests
```

---

## Files Layout

```
tests/
├── README.md                 # This file
├── run-tests.sh             # Main test coordinator
├── test-viso.sh            # VISO boot validation
├── test-mix-cli.sh         # Package manager unit tests
├── check-build.sh          # Build status monitor
├── auto-test.sh            # Automatic test runner
├── install-deps.sh         # Dependency checker
└── create-iso-minimal.sh   # ISO creator (fallback)
```

---

## Return Codes

- **0** - All tests passed ✅
- **1** - Test failed ❌
- **2** - Dependencies missing ⚠️
- **3** - Image not found 🔍
- **4** - QEMU error 🔧

---

## Performance Notes

- **VISO Boot Test:** ~30-45 seconds on typical hardware
- **Mix-CLI Tests:** ~5 seconds
- **Full Test Suite:** ~2-3 minutes
- **Auto-test (with build):** 15-30 minutes total

---

## Related Documentation

- [Build Guide](../docs/ARCHITECTURE.md)
- [Installation](../docs/INSTALLATION.md)
- [User Guide](../docs/USER_GUIDE.md)
- [VISO Documentation](../docs/VISO_VRAM.md)

---

**Last Updated:** 2024
**Version:** 1.0.0
