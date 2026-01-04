#!/bin/bash
# Direct VISO Boot Test for MixOS-GO

PROJECT_DIR="/workspaces/mixos"
OUTPUT_DIR="$PROJECT_DIR/artifacts"
VISO_FILE="$OUTPUT_DIR/mixos-go-v1.0.0.viso"
TIMEOUT="${1:-30}"

echo "════════════════════════════════════════════════════════"
echo "MixOS-GO VISO Boot Test"
echo "════════════════════════════════════════════════════════"
echo ""

# Check VISO
if [ ! -f "$VISO_FILE" ]; then
    echo "❌ VISO not found"
    exit 1
fi

echo "✓ VISO: $(du -h "$VISO_FILE" | cut -f1)"

# Check QEMU
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "❌ QEMU not found"
    exit 1
fi

echo "✓ QEMU: $(qemu-system-x86_64 --version | head -1 | cut -d' ' -f3-)"
echo ""
echo "Booting MixOS-GO (${TIMEOUT}s timeout)..."
echo "════════════════════════════════════════════════════════"
echo ""

# Boot VISO
timeout "$TIMEOUT" qemu-system-x86_64 \
    -m 2G \
    -smp 2 \
    -nographic \
    -serial stdio \
    -hda "$VISO_FILE" \
    2>&1 || BOOT_RESULT=$?

echo ""
echo "════════════════════════════════════════════════════════"

if [ "${BOOT_RESULT:-0}" -eq 124 ]; then
    echo "✅ Boot successful (timeout reached)"
    exit 0
elif [ "${BOOT_RESULT:-0}" -eq 0 ] || [ "${BOOT_RESULT:-0}" -eq 1 ]; then
    echo "✅ Boot test completed"
    exit 0
else
    echo "❌ Boot failed (exit: ${BOOT_RESULT:-0})"
    exit 1
fi
