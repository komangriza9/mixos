#!/bin/bash
# ============================================================================
# MixOS-GO ISO Build Script
# Creates bootable ISO/VISO image with GRUB bootloader
# Supports: Traditional ISO, VISO, VRAM mode
# ============================================================================

set -e

# Standardized directory structure
# BUILD_DIR: temporary build files
# BUILD_DIR/rootfs: the rootfs being built
# OUTPUT_DIR: final artifacts
# OUTPUT_DIR/boot: kernel and initramfs
BUILD_DIR="${BUILD_DIR:-$(pwd)/.tmp/mixos-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts}"
REPO_ROOT="${REPO_ROOT:-$(pwd)}"
ROOTFS_DIR="$BUILD_DIR/rootfs"
ISO_DIR="$BUILD_DIR/iso"
VERSION="${VERSION:-1.0.0}"
ISO_NAME="mixos-go-v${VERSION}.iso"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     MixOS-GO ISO Builder                                     ║"
echo "║     VISO/SDISK/VRAM Support                                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

log_info "Build Directory: $BUILD_DIR"
log_info "Rootfs Directory: $ROOTFS_DIR"
log_info "ISO Directory: $ISO_DIR"
log_info "Output Directory: $OUTPUT_DIR"
log_info "Output: $OUTPUT_DIR/$ISO_NAME"
echo ""

# ============================================================================
# Check required tools
# ============================================================================
log_info "Checking required tools..."
MISSING_TOOLS=0

if ! command -v mksquashfs >/dev/null 2>&1; then
    log_error "mksquashfs not found"
    echo "  Install: apt-get install squashfs-tools"
    MISSING_TOOLS=1
else
    log_ok "Found: mksquashfs"
fi

if ! command -v xorriso >/dev/null 2>&1 && \
   ! command -v genisoimage >/dev/null 2>&1 && \
   ! command -v mkisofs >/dev/null 2>&1; then
    log_error "No ISO creation tool found (xorriso/genisoimage/mkisofs)"
    echo "  Install one of:"
    echo "    apt-get install xorriso"
    echo "    apt-get install genisoimage"
    MISSING_TOOLS=1
else
    TOOL_FOUND=$(command -v xorriso || command -v genisoimage || command -v mkisofs)
    log_ok "Found: $(basename "$TOOL_FOUND")"
fi

if [ $MISSING_TOOLS -eq 1 ]; then
    log_error "Missing required build tools"
    exit 1
fi

# ============================================================================
# Verify prerequisites
# ============================================================================
if [ ! -d "$ROOTFS_DIR" ]; then
    log_error "Rootfs not found at $ROOTFS_DIR"
    log_info "Run build-rootfs.sh first"
    exit 1
fi

# Check for kernel - look in both boot/ and root of OUTPUT_DIR
KERNEL_PATH=""
if [ -f "$OUTPUT_DIR/boot/vmlinuz-mixos" ]; then
    KERNEL_PATH="$OUTPUT_DIR/boot/vmlinuz-mixos"
    log_ok "Found kernel at $KERNEL_PATH"
elif [ -f "$OUTPUT_DIR/vmlinuz-mixos" ]; then
    KERNEL_PATH="$OUTPUT_DIR/vmlinuz-mixos"
    log_ok "Found kernel at $KERNEL_PATH"
else
    log_warn "Kernel not found, will create ISO without kernel"
fi

# Check for enhanced initramfs
INITRAMFS_PATH=""
if [ -f "$OUTPUT_DIR/boot/initramfs-mixos.img" ]; then
    INITRAMFS_PATH="$OUTPUT_DIR/boot/initramfs-mixos.img"
    log_ok "Found initramfs at $INITRAMFS_PATH"
else
    log_warn "Enhanced initramfs not found, will create basic initramfs"
fi

# Clean previous ISO build
rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR"/{boot/grub,live,config}
mkdir -p "$OUTPUT_DIR"

# ============================================================================
# Step 1: Prepare initramfs
# ============================================================================
log_info "Preparing initramfs..."

if [ -n "$INITRAMFS_PATH" ]; then
    cp "$INITRAMFS_PATH" "$ISO_DIR/boot/initramfs.img"
    log_ok "Using enhanced initramfs"
else
    log_info "Creating basic initramfs from rootfs..."
    cd "$ROOTFS_DIR"

    cat > init << 'INITEOF'
#!/bin/sh
# MixOS-GO Init Script (Basic)

mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

VRAM_MODE=""
for param in $(cat /proc/cmdline); do
    case "$param" in
        VRAM=*) VRAM_MODE="${param#VRAM=}" ;;
    esac
done

echo "Searching for live filesystem..."
sleep 5

mkdir -p /mnt/cdrom /mnt/root /mnt/vram

# Try to mount boot device
for dev in /dev/sr0 /dev/cdrom /dev/vda /dev/vdb /dev/sda /dev/sdb; do
    if [ -b "$dev" ]; then
        mount -o ro "$dev" /mnt/cdrom 2>/dev/null && break
        mount -t iso9660 -o ro "$dev" /mnt/cdrom 2>/dev/null && break
    fi
done

# Find squashfs
SQUASHFS_PATH=""
for path in /mnt/cdrom/live/filesystem.squashfs /mnt/cdrom/rootfs/rootfs.squashfs /mnt/cdrom/rootfs.squashfs; do
    if [ -f "$path" ]; then
        SQUASHFS_PATH="$path"
        break
    fi
done

if [ -z "$SQUASHFS_PATH" ] && [ -d /mnt/cdrom ]; then
    SQUASHFS_PATH=$(find /mnt/cdrom -maxdepth 3 -type f -name "*.squashfs" 2>/dev/null | head -n1)
fi

if [ -n "$SQUASHFS_PATH" ]; then
    echo "Found: $SQUASHFS_PATH"
    
    if [ "$VRAM_MODE" = "auto" ] || [ "$VRAM_MODE" = "1" ] || [ "$VRAM_MODE" = "yes" ]; then
        MEM_TOTAL=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
        if [ "$MEM_TOTAL" -ge 2048 ]; then
            echo "VRAM mode: Loading system into RAM..."
            mount -t tmpfs -o size=1G tmpfs /mnt/vram
            mount -t squashfs -o ro "$SQUASHFS_PATH" /mnt/root
            cp -a /mnt/root/* /mnt/vram/
            umount /mnt/root
            mount --bind /mnt/vram /mnt/root
            echo "VRAM mode: System loaded into RAM!"
        else
            mount -t squashfs -o ro "$SQUASHFS_PATH" /mnt/root
        fi
    else
        mount -t squashfs -o ro "$SQUASHFS_PATH" /mnt/root
    fi
fi

if [ ! -d /mnt/root/bin ]; then
    echo "Live filesystem not found, using initramfs as root"
    exec /sbin/init
fi

echo "Switching to root filesystem..."
cd /mnt/root
mkdir -p /mnt/root/mnt/cdrom
mount --move /mnt/cdrom /mnt/root/mnt/cdrom 2>/dev/null || true
exec switch_root /mnt/root /sbin/init
INITEOF
    chmod +x init

    log_info "Packing initramfs..."
    find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > "$ISO_DIR/boot/initramfs.img"
    rm -f init
    cd "$REPO_ROOT"
    log_ok "Basic initramfs created"
fi

# ============================================================================
# Step 2: Copy kernel
# ============================================================================
log_info "Copying kernel..."
if [ -n "$KERNEL_PATH" ]; then
    cp "$KERNEL_PATH" "$ISO_DIR/boot/vmlinuz"
    log_ok "Kernel copied"
else
    log_warn "No kernel found - ISO will not be bootable without external kernel"
fi

# ============================================================================
# Step 3: Ensure install.yaml is in rootfs for unattended install
# ============================================================================
log_info "Checking for install.yaml..."
PACKAGING_INSTALL_YAML="$REPO_ROOT/packaging/install.yaml"
if [ ! -f "$ROOTFS_DIR/etc/mixos/install.yaml" ]; then
    mkdir -p "$ROOTFS_DIR/etc/mixos"
    if [ -n "$INSTALL_CONFIG" ] && [ -f "$INSTALL_CONFIG" ]; then
        log_info "Copying provided installer config: $INSTALL_CONFIG"
        cp "$INSTALL_CONFIG" "$ROOTFS_DIR/etc/mixos/install.yaml"
        chmod 0644 "$ROOTFS_DIR/etc/mixos/install.yaml"
    elif [ -f "$PACKAGING_INSTALL_YAML" ]; then
        log_info "Copying $PACKAGING_INSTALL_YAML"
        cp "$PACKAGING_INSTALL_YAML" "$ROOTFS_DIR/etc/mixos/install.yaml"
        chmod 0644 "$ROOTFS_DIR/etc/mixos/install.yaml"
    else
        log_warn "No install.yaml found - unattended install will not be available"
    fi
else
    log_ok "install.yaml already present in rootfs"
fi

# ============================================================================
# Step 4: Create SquashFS from rootfs
# ============================================================================
log_info "Creating SquashFS filesystem..."
mksquashfs "$ROOTFS_DIR" "$ISO_DIR/live/filesystem.squashfs" \
    -comp xz \
    -b 1M \
    -Xdict-size 100% \
    -no-exports \
    -noappend \
    -no-recovery \
    -quiet

SQUASHFS_SIZE=$(du -h "$ISO_DIR/live/filesystem.squashfs" | cut -f1)
log_ok "SquashFS created: $SQUASHFS_SIZE"

# ============================================================================
# Step 5: Create ISO metadata
# ============================================================================
log_info "Creating ISO metadata..."

cat > "$ISO_DIR/config/iso.json" << EOF
{
    "name": "MixOS-GO",
    "version": "$VERSION",
    "format": "ISO",
    "created": "$(date -Iseconds)",
    "features": {
        "vram_support": true,
        "sdisk_boot": true,
        "installer": true
    },
    "boot": {
        "kernel": "boot/vmlinuz",
        "initramfs": "boot/initramfs.img",
        "cmdline": "console=ttyS0 quiet"
    }
}
EOF

# ============================================================================
# Step 6: Create GRUB configuration
# ============================================================================
log_info "Creating GRUB configuration..."
cat > "$ISO_DIR/boot/grub/grub.cfg" << EOF
# MixOS-GO GRUB Configuration
# Version: $VERSION

set timeout=10
set default=0

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

insmod gfxterm
insmod png

menuentry "MixOS-GO v$VERSION (Installer)" {
    linux /boot/vmlinuz console=ttyS0 console=tty0 quiet mixos.mode=installer
    initrd /boot/initramfs.img
}

menuentry "MixOS-GO v$VERSION (VRAM Mode - Maximum Performance)" {
    linux /boot/vmlinuz console=ttyS0 console=tty0 VRAM=auto quiet
    initrd /boot/initramfs.img
}

menuentry "MixOS-GO v$VERSION (Standard Boot)" {
    linux /boot/vmlinuz console=ttyS0 console=tty0 quiet
    initrd /boot/initramfs.img
}

menuentry "MixOS-GO v$VERSION (Verbose)" {
    linux /boot/vmlinuz console=ttyS0 console=tty0
    initrd /boot/initramfs.img
}

menuentry "MixOS-GO v$VERSION (Recovery Shell)" {
    linux /boot/vmlinuz console=ttyS0 console=tty0 single init=/bin/sh
    initrd /boot/initramfs.img
}

menuentry "MixOS-GO v$VERSION (Automatic Install)" {
    linux /boot/vmlinuz console=ttyS0 console=tty0 mixos.autoinstall=1 mixos.config=/etc/mixos/install.yaml
    initrd /boot/initramfs.img
}

menuentry "MixOS-GO v$VERSION (Debug Mode)" {
    linux /boot/vmlinuz console=ttyS0 console=tty0 debug
    initrd /boot/initramfs.img
}
EOF

log_ok "GRUB configuration created"

# ============================================================================
# Step 7: Create ISO image
# ============================================================================
log_info "Creating ISO image..."
sync

ISO_CREATED=0

# Try grub-mkrescue first
if command -v grub-mkrescue >/dev/null 2>&1; then
    log_info "Using grub-mkrescue..."
    if grub-mkrescue -o "$OUTPUT_DIR/$ISO_NAME" "$ISO_DIR" \
        --product-name="MixOS-GO" \
        --product-version="$VERSION" 2>/dev/null; then
        ISO_CREATED=1
        log_ok "ISO created with grub-mkrescue"
    else
        log_warn "grub-mkrescue failed"
    fi
fi

# Fallback to xorriso
if [ $ISO_CREATED -eq 0 ] && command -v xorriso >/dev/null 2>&1; then
    log_info "Using xorriso fallback..."
    if xorriso -as mkisofs \
        -o "$OUTPUT_DIR/$ISO_NAME" \
        -V "MIXOS_GO" \
        -J -R \
        "$ISO_DIR" 2>/dev/null; then
        ISO_CREATED=1
        log_ok "ISO created with xorriso"
    else
        log_warn "xorriso failed"
    fi
fi

# Fallback to genisoimage
if [ $ISO_CREATED -eq 0 ] && command -v genisoimage >/dev/null 2>&1; then
    log_info "Using genisoimage fallback..."
    if genisoimage -o "$OUTPUT_DIR/$ISO_NAME" \
        -J -R -V "MIXOS_GO" \
        "$ISO_DIR" 2>/dev/null; then
        ISO_CREATED=1
        log_ok "ISO created with genisoimage"
    else
        log_warn "genisoimage failed"
    fi
fi

# Last resort: create tarball
if [ $ISO_CREATED -eq 0 ]; then
    log_warn "All ISO creation methods failed, creating tarball..."
    cd "$ISO_DIR"
    tar -czf "$OUTPUT_DIR/mixos-go-v${VERSION}.tar.gz" .
    cd "$REPO_ROOT"
    log_ok "Created tarball: mixos-go-v${VERSION}.tar.gz"
fi

# ============================================================================
# Step 8: Generate checksums and summary
# ============================================================================
cd "$OUTPUT_DIR"
if [ -f "$ISO_NAME" ]; then
    log_info "Generating checksums..."
    sha256sum "$ISO_NAME" > "$ISO_NAME.sha256"
    md5sum "$ISO_NAME" > "$ISO_NAME.md5"

    ISO_SIZE=$(du -h "$ISO_NAME" | cut -f1)
    ISO_SIZE_BYTES=$(stat -c%s "$ISO_NAME")
    ISO_SIZE_MB=$((ISO_SIZE_BYTES / 1024 / 1024))

    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     ISO Build Complete!                                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Output: $OUTPUT_DIR/$ISO_NAME ($ISO_SIZE)"
    echo "SHA256: $(cat "$ISO_NAME.sha256" | cut -d' ' -f1)"
    echo ""

    if [ "$ISO_SIZE_MB" -lt 500 ]; then
        log_ok "ISO size ($ISO_SIZE_MB MB) is within target (<500MB)"
    else
        log_warn "ISO size ($ISO_SIZE_MB MB) exceeds target (<500MB)"
    fi

    echo ""
    echo "Boot options:"
    echo "  1. Installer Mode:  Boot and run MixOS Setup"
    echo "  2. VRAM Mode:       Maximum performance (requires 2GB+ RAM)"
    echo "  3. Standard Boot:   Normal boot from squashfs"
    echo "  4. Recovery Shell:  Emergency shell access"
    echo ""
    echo "QEMU test command:"
    echo "  qemu-system-x86_64 -cdrom $OUTPUT_DIR/$ISO_NAME -m 2G -nographic"
    echo ""
else
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     Build Complete (tarball)                                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Tarball: $OUTPUT_DIR/mixos-go-v${VERSION}.tar.gz"
    echo ""
fi

cd "$REPO_ROOT"
