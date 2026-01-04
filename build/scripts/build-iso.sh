#!/bin/bash
# ============================================================================
# MixOS-GO ISO Build Script
# Creates bootable ISO/VISO image with GRUB bootloader
# Supports: Traditional ISO, VISO, VRAM mode
# ============================================================================

set -e

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

log_info "Checking required tools..."
MISSING_TOOLS=0

# Check for mksquashfs
if ! command -v mksquashfs >/dev/null 2>&1; then
    log_error "mksquashfs not found"
    echo "  Install: apt-get install squashfs-tools"
    MISSING_TOOLS=1
else
    log_ok "Found: mksquashfs"
fi

# Check for ISO creation tools
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

log_info "Build Directory: $BUILD_DIR"
log_info "Rootfs Directory: $ROOTFS_DIR"
log_info "ISO Directory: $ISO_DIR"
log_info "Output: $OUTPUT_DIR/$ISO_NAME"
echo ""

# Verify prerequisites
if [ ! -d "$ROOTFS_DIR" ]; then
    log_error "Rootfs not found at $ROOTFS_DIR"
    log_info "Run build-rootfs.sh first"
    exit 1
fi

# Check for kernel (optional - can use enhanced initramfs)
KERNEL_PATH=""
if [ -f "$OUTPUT_DIR/boot/vmlinuz-mixos" ]; then
    KERNEL_PATH="$OUTPUT_DIR/boot/vmlinuz-mixos"
elif [ -f "$OUTPUT_DIR/vmlinuz-mixos" ]; then
    KERNEL_PATH="$OUTPUT_DIR/vmlinuz-mixos"
else
    log_warn "Kernel not found, will create ISO without kernel"
fi

# Check for enhanced initramfs
INITRAMFS_PATH=""
if [ -f "$OUTPUT_DIR/boot/initramfs-mixos.img" ]; then
    INITRAMFS_PATH="$OUTPUT_DIR/boot/initramfs-mixos.img"
    log_ok "Using enhanced initramfs with VISO/VRAM support"
fi

# Clean previous ISO build
rm -rf "$ISO_DIR"
mkdir -p "$ISO_DIR"/{boot/grub,live,config}

# ============================================================================
# Step 1: Prepare initramfs
# ============================================================================
log_info "Preparing initramfs..."

if [ -n "$INITRAMFS_PATH" ]; then
    # Use enhanced initramfs with VISO/VRAM support
    cp "$INITRAMFS_PATH" "$ISO_DIR/boot/initramfs.img"
    log_ok "Using enhanced initramfs"
else
    # Create basic initramfs from rootfs
    log_info "Creating basic initramfs from rootfs..."
    cd "$ROOTFS_DIR"

    # Create init script for initramfs
    cat > init << 'INITEOF'
#!/bin/sh
# MixOS-GO Init Script (Basic)

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# Parse kernel command line
BOOT_DEV=""
ROOT_TYPE="squashfs"
VRAM_MODE=""
SDISK_VALUE=""

for param in $(cat /proc/cmdline); do
    case "$param" in
        root=*)
            BOOT_DEV="${param#root=}"
            ;;
        rootfstype=*)
            ROOT_TYPE="${param#rootfstype=}"
            ;;
        VRAM=*)
            VRAM_MODE="${param#VRAM=}"
            ;;
        SDISK=*)
            SDISK_VALUE="${param#SDISK=}"
            ;;
    esac
done

# Find and mount the live filesystem
echo "Searching for live filesystem..."

# Wait for devices to settle (give CD-ROM more time to appear)
sleep 15

mkdir -p /mnt/cdrom /mnt/root
# Try to find the squashfs
mkdir -p /mnt/cdrom /mnt/root /mnt/vram

# Try virtio devices first (VISO)
for dev in /dev/vda /dev/vdb; do
    if [ -b "$dev" ]; then
        mount -o ro "$dev" /mnt/cdrom 2>/dev/null && break
    fi
done

# Helper to attempt mounting a device as ISO9660 with retries
try_mount_iso() {
    local dev="$1"
    local i
    for i in 1 2 3 4 5; do
        if [ -b "$dev" ]; then
            echo "Trying to mount $dev (attempt $i)..."
            if mount -t iso9660 -o ro "$dev" /mnt/cdrom; then
                echo "Mounted $dev -> /mnt/cdrom"
                ls -l /mnt/cdrom || true
                return 0
            else
                echo "Mount failed for $dev (attempt $i)" >&2
            fi
        fi
        sleep 2
    done
    return 1
}

# Try common CD-ROM and block devices
for dev in /dev/sr0 /dev/cdrom /dev/hdc /dev/scd0 /dev/vda /dev/vdb /dev/sda /dev/sdb; do
    if try_mount_iso "$dev"; then
        break
# Try common CD-ROM devices
if [ ! -f /mnt/cdrom/live/filesystem.squashfs ]; then
    for dev in /dev/sr0 /dev/cdrom /dev/hdc /dev/scd0; do
        if [ -b "$dev" ]; then
            mount -t iso9660 -o ro "$dev" /mnt/cdrom 2>/dev/null && break
        fi
    done
fi

# Also try SATA/IDE devices
if [ ! -f /mnt/cdrom/live/filesystem.squashfs ]; then
    for dev in /dev/sda /dev/sdb; do
        if [ -b "$dev" ]; then
            mount -o ro "$dev" /mnt/cdrom 2>/dev/null || true
        fi
    done
fi

# Find squashfs
SQUASHFS_PATH=""
for path in /mnt/cdrom/live/filesystem.squashfs /mnt/cdrom/rootfs/rootfs.squashfs /mnt/cdrom/rootfs.squashfs; do
    if [ -f "$path" ]; then
        SQUASHFS_PATH="$path"
        break
    fi
done

# If mounted, look for filesystem.squashfs; also scan the mounted tree
if [ -d /mnt/cdrom ] && [ -f /mnt/cdrom/live/filesystem.squashfs ]; then
    echo "Found live filesystem at /mnt/cdrom/live/filesystem.squashfs, mounting..."
    mount -t squashfs -o ro /mnt/cdrom/live/filesystem.squashfs /mnt/root
# Mount squashfs
if [ -n "$SQUASHFS_PATH" ]; then
    echo "Found live filesystem: $SQUASHFS_PATH"
    
    # Check VRAM mode
    if [ "$VRAM_MODE" = "auto" ] || [ "$VRAM_MODE" = "1" ] || [ "$VRAM_MODE" = "yes" ]; then
        # Get available RAM
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
else
    # Try to find filesystem.squashfs anywhere under /mnt/cdrom if mounted
    if [ -d /mnt/cdrom ]; then
        fs=$(find /mnt/cdrom -maxdepth 3 -type f -name filesystem.squashfs 2>/dev/null | head -n1 || true)
        if [ -n "$fs" ]; then
            echo "Found live filesystem at $fs, mounting..."
            mount -t squashfs -o ro "$fs" /mnt/root
        fi
    fi
fi

# If mounting didn't succeed, fall back to initramfs root
if [ ! -d /mnt/root ] || [ -z "$(ls -A /mnt/root 2>/dev/null)" ]; then
    echo "Live filesystem not found, using initramfs as root"
    exec /sbin/init
fi

# Switch to real root
echo "Switching to root filesystem..."
cd /mnt/root

# Move mounts
mkdir -p /mnt/root/mnt/cdrom
mount --move /mnt/cdrom /mnt/root/mnt/cdrom 2>/dev/null || true

# Pivot root
exec switch_root /mnt/root /sbin/init
INITEOF
    chmod +x init

    # Create initramfs cpio archive
    log_info "Packing initramfs..."
    find . -print0 | cpio --null -ov --format=newc 2>/dev/null | gzip -9 > "$ISO_DIR/boot/initramfs.img"
    cd "$REPO_ROOT"
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
# Step 3: Create SquashFS from rootfs
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
# Step 4: Create ISO metadata
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
# Step 5: Create GRUB configuration
# ============================================================================
log_info "Creating GRUB configuration..."
cat > "$ISO_DIR/boot/grub/grub.cfg" << EOF
# MixOS-GO GRUB Configuration
# Version: $VERSION

set timeout=10
set default=0

# Set colors
set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "MixOS-GO v1.0.0" {
    linux /boot/vmlinuz quiet console=tty0 console=ttyS0,115200
# Custom theme
insmod gfxterm
insmod png

menuentry "🚀 MixOS-GO v$VERSION (Installer)" {
    linux /boot/vmlinuz console=ttyS0 quiet mixos.mode=installer
    initrd /boot/initramfs.img
}

menuentry "⚡ MixOS-GO v$VERSION (VRAM Mode - Maximum Performance)" {
    linux /boot/vmlinuz console=ttyS0 VRAM=auto quiet
    initrd /boot/initramfs.img
}

menuentry "💿 MixOS-GO v$VERSION (Standard Boot)" {
    linux /boot/vmlinuz console=ttyS0 quiet
    initrd /boot/initramfs.img
}

menuentry "🔧 MixOS-GO v$VERSION (Verbose)" {
    linux /boot/vmlinuz console=ttyS0
    initrd /boot/initramfs.img
}

menuentry "MixOS-GO v1.0.0 (verbose)" {
    linux /boot/vmlinuz console=tty0 console=ttyS0,115200
menuentry "🛠️ MixOS-GO v$VERSION (Recovery Shell)" {
    linux /boot/vmlinuz console=ttyS0 single init=/bin/sh
    initrd /boot/initramfs.img
}

menuentry "MixOS-GO v1.0.0 (recovery)" {
    linux /boot/vmlinuz single init=/bin/sh console=tty0 console=ttyS0,115200
    initrd /boot/initramfs.img
}

# Automatic installer entry (uses /etc/mixos/install.yaml on the live image)
menuentry "MixOS-GO Automatic Install" {
    linux /boot/vmlinuz console=tty0 console=ttyS0,115200 mixos.autoinstall=1 mixos.config=/etc/mixos/install.yaml
menuentry "📖 MixOS-GO v$VERSION (Debug Mode)" {
    linux /boot/vmlinuz console=ttyS0 debug
    initrd /boot/initramfs.img
}
EOF

# Create ISO
echo "Creating ISO image..."
# Ensure filesystem buffers are flushed so xorriso/grub see final files
sync

# Prefer grub-mkrescue (works on many systems). If it fails or to avoid
# subtle truncation issues when mixing internal temp dirs, fall back to an
# explicit xorriso invocation that grafts exact files from $ISO_DIR.
if grub-mkrescue -o "$OUTPUT_DIR/$ISO_NAME" "$ISO_DIR" \
log_ok "GRUB configuration created"

# ============================================================================
# Step 6: Create ISO image
# ============================================================================
log_info "Creating ISO image..."

grub-mkrescue -o "$OUTPUT_DIR/$ISO_NAME" "$ISO_DIR" \
    --product-name="MixOS-GO" \
    --product-version="1.0.0" 2>/dev/null; then
    true
else
    echo "grub-mkrescue failed or unavailable; using explicit xorriso graft-points..."
    # Use explicit graft-points so we control exact source files copied into the ISO
    if command -v xorriso >/dev/null 2>&1; then
        xorriso -as mkisofs \
            -o "$OUTPUT_DIR/$ISO_NAME" \
            -isohybrid-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
            -c boot/boot.cat \
            -b boot/grub/i386-pc/eltorito.img \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
            --grub2-boot-info \
            --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
            -eltorito-alt-boot \
            -e boot/grub/efi.img \
            -no-emul-boot \
            -isohybrid-gpt-basdat \
            -V "MIXOS_GO" \
            -graft-points \
                /boot/initramfs.img="$ISO_DIR/boot/initramfs.img" \
                /boot/vmlinuz="$ISO_DIR/boot/vmlinuz" \
                /boot/grub/grub.cfg="$ISO_DIR/boot/grub/grub.cfg" \
                /live="$ISO_DIR/live" \
            2>/dev/null || {
                echo "xorriso fallback failed; creating basic tarball instead..."
                cd "$ISO_DIR"
                tar -czf "$OUTPUT_DIR/mixos-go-v1.0.0.tar.gz" .
                echo "Created tarball instead: $OUTPUT_DIR/mixos-go-v1.0.0.tar.gz"
            }
    else
        echo "xorriso not installed; creating basic tarball instead..."
        cd "$ISO_DIR"
        tar -czf "$OUTPUT_DIR/mixos-go-v1.0.0.tar.gz" .
        echo "Created tarball instead: $OUTPUT_DIR/mixos-go-v1.0.0.tar.gz"
    fi
fi
    --product-version="$VERSION" \
    2>/dev/null || {
    # Fallback method using xorriso directly
    log_warn "grub-mkrescue failed, using xorriso fallback..."
    xorriso -as mkisofs \
        -o "$OUTPUT_DIR/$ISO_NAME" \
        -isohybrid-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -c boot/boot.cat \
        -b boot/grub/i386-pc/eltorito.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --grub2-boot-info \
        --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -V "MIXOS_GO" \
        "$ISO_DIR" 2>/dev/null || {
            # Simple ISO creation
            log_warn "xorriso failed, using genisoimage..."
            genisoimage -o "$OUTPUT_DIR/$ISO_NAME" \
                -b boot/grub/i386-pc/eltorito.img \
                -c boot/boot.cat \
                -no-emul-boot \
                -boot-load-size 4 \
                -boot-info-table \
                -J -R -V "MIXOS_GO" \
                "$ISO_DIR" 2>/dev/null || {
                    log_warn "Creating tarball instead of ISO..."
                    cd "$ISO_DIR"
                    tar -czf "$OUTPUT_DIR/mixos-go-v${VERSION}.tar.gz" .
                    log_ok "Created tarball: mixos-go-v${VERSION}.tar.gz"
                }
        }
}

# ============================================================================
# Step 7: Generate checksums and summary
# ============================================================================
cd "$OUTPUT_DIR"
if [ -f "$ISO_NAME" ]; then
    log_info "Generating checksums..."
    sha256sum "$ISO_NAME" > "$ISO_NAME.sha256"
    md5sum "$ISO_NAME" > "$ISO_NAME.md5"
    
    # Get ISO size
    ISO_SIZE=$(du -h "$ISO_NAME" | cut -f1)
    ISO_SIZE_BYTES=$(stat -c%s "$ISO_NAME")
    ISO_SIZE_MB=$((ISO_SIZE_BYTES / 1024 / 1024))
    
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║     ISO Build Complete!                                      ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Output: $OUTPUT_DIR/$ISO_NAME ($ISO_SIZE)"
    echo "SHA256: $(cat $ISO_NAME.sha256 | cut -d' ' -f1)"
    echo ""
    
    # Verify size target
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
