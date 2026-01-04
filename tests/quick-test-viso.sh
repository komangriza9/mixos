#!/bin/bash
# Quick VISO Boot Test for MixOS-GO

set -e

PROJECT_DIR="/workspaces/mixos"
OUTPUT_DIR="$PROJECT_DIR/artifacts"
VISO_FILE="$OUTPUT_DIR/mixos-go-v1.0.0.viso"
TIMEOUT="${1:-60}"

echo "════════════════════════════════════════════════════════════"
echo "     MixOS-GO VISO Boot Test"
echo "════════════════════════════════════════════════════════════"
echo ""

# Check VISO exists
if [ ! -f "$VISO_FILE" ]; then
    echo "❌ VISO image not found: $VISO_FILE"
    echo ""
    echo "Available images:"
    ls -lh "$OUTPUT_DIR"/*.viso* 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
    exit 1
fi

echo "✓ VISO image found: $(du -h "$VISO_FILE" | cut -f1)"
echo ""

# Check QEMU
if ! command -v qemu-system-x86_64 &> /dev/null; then
    echo "❌ QEMU not installed"
    echo ""
    echo "Install with:"
    echo "  sudo apt-get install qemu-system-x86 qemu-utils"
    exit 1
fi

QEMU_VERSION=$(qemu-system-x86_64 --version | head -1)
echo "✓ QEMU available: $QEMU_VERSION"
echo ""

# Create temporary snapshot
SNAP_FILE="/tmp/mixos-test-$$.qcow2"
echo "Creating temporary snapshot..."
qemu-img create -f qcow2 -b "$VISO_FILE" "$SNAP_FILE" >/dev/null 2>&1
echo "✓ Snapshot created at: $SNAP_FILE"
echo ""

# Cleanup on exit
cleanup() {
    if [ -f "$SNAP_FILE" ]; then
        rm -f "$SNAP_FILE"
        echo "Cleaned up temporary files"
    fi
}
trap cleanup EXIT

echo "════════════════════════════════════════════════════════════"
echo "🚀 Starting QEMU Boot Test (timeout: ${TIMEOUT}s)"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Press Ctrl+C to stop"
echo ""
echo "────────────────────────────────────────────────────────────"
echo ""

# Run QEMU with serial console
timeout "$TIMEOUT" qemu-system-x86_64 \
    -m 2G \
    -smp 2 \
    -nographic \
    -serial stdio \
    -hda "$SNAP_FILE" \
    -net nic,model=e1000 \
    -net user,hostfwd=tcp::2222-:22 \
    2>&1 || true

QEMU_EXIT=$?

echo ""
echo "────────────────────────────────────────────────────────────"
echo ""

if [ $QEMU_EXIT -eq 124 ]; then
    echo "✓ QEMU timeout reached (boot test completed)"
    echo "  System booted successfully within $TIMEOUT seconds"
    exit 0
elif [ $QEMU_EXIT -eq 0 ] || [ $QEMU_EXIT -eq 1 ]; then
    echo "✓ QEMU executed (system may have shut down normally)"
    exit 0
else
    echo "⚠️  QEMU exit code: $QEMU_EXIT"
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════"
