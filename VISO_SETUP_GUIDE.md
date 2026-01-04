# VISO Bootable Setup Guide

## Problem Statement

MixOS-GO VISO creation previously required root access for loop device mounting to create fully bootable images. Without proper bootloader installation, QEMU would report "No boot device detected".

## Solutions Implemented

### 1. **Improved build-viso.sh** (Default, No Changes Needed)
- Attempts loop device mount (requires sudo)
- Falls back to qemu-nbd if available
- Falls back to filesystem copy approach
- Creates QCOW2 image even without direct filesystem access
- Includes GRUB bootloader setup when possible
- Graceful degradation with proper error messaging

**Usage:**
```bash
make viso
# OR with sudo for full bootable VISO
sudo make viso
```

**Result:**
- With sudo: Full bootable QCOW2 with GRUB and filesystem
- Without sudo: QCOW2 with fallback structure (requires host kernel for boot)

---

### 2. **Docker Build Environment** (Recommended for Production)

Use privileged Docker container with full bootloader support:

```bash
# Build Docker image (from build/docker/Dockerfile.toolchain)
docker build -f build/docker/Dockerfile.toolchain -t mixos-go-build:latest .

# Run build in container
docker run --rm -it \
  --privileged \
  -v $(pwd):/workspace \
  -w /workspace \
  mixos-go-build:latest \
  bash -c "make all"
```

**Advantages:**
- No sudo required on host
- Full loop device access (privileged mode)
- All bootloader tools available
- Isolated build environment
- Reproducible builds

---

### 3. **Manual VISO Creation** (Advanced Users)

If you need fine-grained control:

```bash
#!/bin/bash
# Create 2GB raw image
dd if=/dev/zero of=viso-raw.img bs=1M count=2048

# Create ext4 filesystem
mkfs.ext4 -F -L "MIXOS-VISO" viso-raw.img

# Mount filesystem
sudo losetup -f --show viso-raw.img
# Note: Keep the returned loop device path (e.g., /dev/loop0)

sudo mount /dev/loop0 /mnt/viso

# Copy VISO structure
sudo cp -r build/viso-build/* /mnt/viso/

# Install GRUB bootloader
sudo grub-install --boot-directory=/mnt/viso/boot \
  --modules="linux ext2 part_msdos biosdisk" \
  --target=i386-pc \
  /dev/loop0

# Create GRUB config
sudo tee /mnt/viso/boot/grub/grub.cfg << 'EOF'
menuentry 'MixOS-GO' {
    linux /boot/vmlinuz-mixos root=/dev/vda1 ro quiet
    initrd /boot/initramfs-mixos.img
}
EOF

# Unmount and convert to QCOW2
sudo umount /mnt/viso
sudo losetup -d /dev/loop0

qemu-img convert -f raw -O qcow2 -c viso-raw.img mixos-go-v1.0.0.viso
rm viso-raw.img
```

---

## Testing VISO Images

### Boot ISO (Most Compatible)
```bash
qemu-system-x86_64 \
  -cdrom artifacts/mixos-go-v1.0.0.iso \
  -m 1G \
  -nographic \
  -serial stdio
```

### Boot VISO with Kernel File
```bash
qemu-system-x86_64 \
  -kernel artifacts/boot/vmlinuz-mixos \
  -initrd artifacts/boot/initramfs-mixos.img \
  -drive file=artifacts/mixos-go-v1.0.0.viso,format=qcow2,if=virtio \
  -m 2G \
  -nographic \
  -serial stdio
```

### Boot VISO with Internal Bootloader (Full VISO)
```bash
qemu-system-x86_64 \
  -drive file=artifacts/mixos-go-v1.0.0.viso,format=qcow2,if=virtio \
  -m 2G \
  -enable-kvm \
  -nographic \
  -serial stdio
```

---

## Troubleshooting

### "No boot device detected" Error
**Cause:** VISO lacks bootloader or kernel  
**Solution:** 
1. Use Docker approach with `--privileged` flag
2. Or boot with external kernel: `qemu-system-x86_64 -kernel`

### "Cannot create loop device" Warning
**Cause:** No root access  
**Solution:**
1. Use `sudo make viso`
2. Or use Docker approach
3. Or use manual method above

### VISO Mount Fails
**Cause:** Image may be corrupted or incompletely formatted  
**Solution:**
```bash
# Verify VISO image
file artifacts/mixos-go-v1.0.0.viso

# Check image integrity
qemu-img check artifacts/mixos-go-v1.0.0.viso

# Repair if needed
qemu-img check -r all artifacts/mixos-go-v1.0.0.viso
```

---

## CI/CD Integration

For automated builds (GitHub Actions, GitLab CI, etc.):

```yaml
# GitHub Actions example
jobs:
  build-viso:
    runs-on: ubuntu-latest
    container:
      image: ubuntu:24.04
      options: --privileged
    steps:
      - uses: actions/checkout@v3
      
      - name: Install dependencies
        run: |
          apt-get update
          apt-get install -y make gcc git grub-pc-bin grub-efi-amd64-bin
      
      - name: Build VISO
        run: make viso
      
      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: viso-images
          path: artifacts/*.viso*
```

---

## Key Changes in build-viso.sh

| Aspect | Before | After |
|--------|--------|-------|
| Loop device | Direct only | + qemu-nbd fallback + filesystem copy |
| Failure behavior | Fallback to tar archive | Create QCOW2 with warnings |
| Bootloader | Not installed | GRUB setup attempted |
| Error messages | Generic | Detailed with solutions |
| Non-root support | Poor | Graceful degradation |

---

## Architecture

```
MixOS-GO VISO Build Pipeline
═══════════════════════════════════════════════════════════

        ┌─────────────────┐
        │  make viso      │
        └────────┬────────┘
                 │
    ┌────────────┴────────────┐
    ▼                         ▼
┌─────────────┐        ┌──────────────┐
│ With Root   │        │ Without Root  │
└──────┬──────┘        └───────┬──────┘
       │                       │
       ▼                       ▼
   ┌────────┐          ┌──────────────┐
   │ losetup│          │ Try qemu-nbd │
   └───┬────┘          └────────┬─────┘
       │               Success  │   Fail
       │                 ▼      │
       │              ┌────┐    │
       │              │NBD │    │
       │              └────┘    ▼
       │                    ┌──────────┐
       │                    │ Mount raw│
       │                    └─────┬────┘
       │                         │
       │        Success          │   Fail
       └────────┬────────────────┘
                ▼
        ┌──────────────┐
        │ Copy VISO    │
        │ structure    │
        └──────┬───────┘
               ▼
        ┌──────────────┐
        │ Install GRUB │
        └──────┬───────┘
               ▼
        ┌──────────────────┐
        │ Convert to QCOW2 │
        │ Bootable VISO! ✓ │
        └──────────────────┘
```

---

## Next Steps

1. **Testing:** Run test suite: `make test-viso`
2. **Optimization:** Profile boot time and memory usage
3. **Documentation:** Update user guide with boot options
4. **CI/CD:** Integrate into GitHub Actions
5. **Distribution:** Package VISO for releases

---

## References

- [QEMU-NBD Documentation](https://wiki.qemu.org/Documentation/Tools/QemuNBD)
- [GRUB Installation Guide](https://www.gnu.org/software/grub/manual/grub/html_node/Installing-GRUB-using-grub_002dinstall.html)
- [Linux Kernel Boot Parameters](https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html)
- MixOS-GO ARCHITECTURE.md
- MixOS-GO VISO_VRAM.md
