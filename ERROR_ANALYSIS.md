# Error Analysis & Fix Plan

## Error 1: BusyBox tc.c Patch Issue

### Problem
The `busybox-tc-fix-cbq-kernel-6.8.patch` has incorrect patch syntax.

**Line issue:** Line 234 shows:
```
+#else
 static int cbq_print_opt(struct rtattr *opt)
```

This is WRONG - should be:
```
+#endif
 static int cbq_print_opt(struct rtattr *opt)
```

**Root cause:** The `#else` should be `#endif` (closing the conditional block)

### Solution
Fix the patch file to use correct `#endif` instead of `#else`

---

## Error 2: VISO Boot - "No Boot Device Detected"

### Problem
VISO image created but QEMU cannot detect boot device

### Likely Causes

1. **VISO not properly formatted**
   - Check: `qemu-img info mixos-go-v1.0.0.viso`
   - Should show: format=qcow2, virtual size, disk size

2. **Missing bootloader in VISO**
   - VISO is raw disk image, needs bootable partition
   - Need GRUB or syslinux installed
   - MBR boot record missing

3. **QEMU boot order issue**
   - QEMU needs explicit `-boot c` flag
   - Or `-hda` pointing to correct device

4. **Build script issue**
   - `build-viso.sh` may not be creating bootable VISO
   - Missing partition table
   - Missing boot flag on partition

### What to Check

1. **VISO structure:**
   ```bash
   qemu-img info /workspaces/mixos/artifacts/mixos-go-v1.0.0.viso
   ```

2. **Partition table:**
   ```bash
   fdisk -l /workspaces/mixos/artifacts/mixos-go-v1.0.0.viso
   ```

3. **Build script:**
   - Check `/workspaces/mixos/build/scripts/build-viso.sh`
   - Verify it creates proper partition table
   - Verify it installs GRUB bootloader

### Recommended Fix

VISO needs to be created as:
```
1. Create QCOW2 image
2. Create partition table (MBR with boot flag)
3. Install filesystem (ext4)
4. Install GRUB bootloader
5. Copy kernel + initramfs
6. Set boot order in image
```

Current build-viso.sh may be skipping steps 2-4.

---

## Next Steps

1. Fix the tc.c patch file
2. Review build-viso.sh for bootloader installation
3. Test VISO boot with proper GRUB setup
