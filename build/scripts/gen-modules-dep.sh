#!/bin/bash
# ============================================================================
# MixOS-GO Module Dependency Generator
# Generates modules.dep and related files for kernel modules
# ============================================================================

set -e

# Configuration
BUILD_DIR="${BUILD_DIR:-$(pwd)/.tmp/mixos-build}"
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts}"
KERNEL_VERSION="${KERNEL_VERSION:-6.6.8-mixos}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     MixOS-GO Module Dependency Generator                     ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Paths
ROOTFS_DIR="$BUILD_DIR/rootfs"
MODULES_DIR="$ROOTFS_DIR/lib/modules/$KERNEL_VERSION"

log_info "Kernel Version: $KERNEL_VERSION"
log_info "Modules Directory: $MODULES_DIR"
echo ""

# Check if modules directory exists
if [ ! -d "$MODULES_DIR" ]; then
    log_warn "Modules directory not found: $MODULES_DIR"
    log_info "Creating empty modules structure..."
    mkdir -p "$MODULES_DIR/kernel"
fi

# Generate modules.dep using depmod
if command -v depmod >/dev/null 2>&1; then
    log_info "Running depmod..."
    
    # Run depmod with base path
    depmod -a -b "$ROOTFS_DIR" "$KERNEL_VERSION" 2>/dev/null || {
        log_warn "depmod failed, creating manual modules.dep"
    }
    
    if [ -f "$MODULES_DIR/modules.dep" ]; then
        log_ok "modules.dep generated"
    fi
else
    log_warn "depmod not found, creating manual modules.dep"
fi

# Create manual modules.dep if not exists
if [ ! -f "$MODULES_DIR/modules.dep" ]; then
    log_info "Creating manual modules.dep..."
    
    # Find all .ko files and create basic dependency file
    : > "$MODULES_DIR/modules.dep"
    
    find "$MODULES_DIR" -name "*.ko" 2>/dev/null | while read mod; do
        rel_path="${mod#$MODULES_DIR/}"
        echo "$rel_path:" >> "$MODULES_DIR/modules.dep"
    done
    
    log_ok "Manual modules.dep created"
fi

# Create modules.alias (empty for now)
if [ ! -f "$MODULES_DIR/modules.alias" ]; then
    log_info "Creating modules.alias..."
    : > "$MODULES_DIR/modules.alias"
    log_ok "modules.alias created"
fi

# Create modules.symbols (empty for now)
if [ ! -f "$MODULES_DIR/modules.symbols" ]; then
    log_info "Creating modules.symbols..."
    : > "$MODULES_DIR/modules.symbols"
    log_ok "modules.symbols created"
fi

# Create modules.order
if [ ! -f "$MODULES_DIR/modules.order" ]; then
    log_info "Creating modules.order..."
    
    # Define module load order for boot
    cat > "$MODULES_DIR/modules.order" << 'EOF'
# MixOS-GO Module Load Order
# Critical modules loaded first

# Crypto (required by some filesystems)
kernel/crypto/crc32c_generic.ko
kernel/lib/crc32c_generic.ko

# Block device support
kernel/drivers/virtio/virtio.ko
kernel/drivers/virtio/virtio_ring.ko
kernel/drivers/virtio/virtio_pci.ko
kernel/drivers/block/virtio_blk.ko

# SCSI/ATA support
kernel/drivers/scsi/scsi_mod.ko
kernel/drivers/ata/libata.ko
kernel/drivers/ata/ata_piix.ko
kernel/drivers/ata/ahci.ko
kernel/drivers/scsi/sd_mod.ko
kernel/drivers/scsi/sr_mod.ko

# CD-ROM support
kernel/drivers/cdrom/cdrom.ko

# Loop device
kernel/drivers/block/loop.ko

# Filesystems
kernel/fs/squashfs/squashfs.ko
kernel/fs/ext4/ext4.ko
kernel/fs/overlayfs/overlay.ko
kernel/fs/isofs/isofs.ko

# Network (optional for boot)
kernel/drivers/net/virtio_net.ko
EOF
    
    log_ok "modules.order created"
fi

# Create modules.builtin (list of built-in modules)
if [ ! -f "$MODULES_DIR/modules.builtin" ]; then
    log_info "Creating modules.builtin..."
    : > "$MODULES_DIR/modules.builtin"
    log_ok "modules.builtin created"
fi

# Create modules.softdep (soft dependencies)
if [ ! -f "$MODULES_DIR/modules.softdep" ]; then
    log_info "Creating modules.softdep..."
    
    cat > "$MODULES_DIR/modules.softdep" << 'EOF'
# MixOS-GO Module Soft Dependencies
# Format: softdep module pre: dep1 dep2 post: dep3 dep4

softdep ext4 pre: crc32c_generic
softdep ahci pre: libata
softdep sd_mod pre: scsi_mod
softdep sr_mod pre: scsi_mod cdrom
softdep virtio_blk pre: virtio virtio_ring
softdep virtio_net pre: virtio virtio_ring
softdep virtio_pci pre: virtio virtio_ring
EOF
    
    log_ok "modules.softdep created"
fi

# Summary
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Module Dependencies Generated                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Files created in $MODULES_DIR:"
ls -la "$MODULES_DIR"/modules.* 2>/dev/null | while read line; do
    echo "  $line"
done
echo ""

# Count modules
MODULE_COUNT=$(find "$MODULES_DIR" -name "*.ko" 2>/dev/null | wc -l)
log_info "Total modules: $MODULE_COUNT"
echo ""
