#!/bin/bash
# MixOS-GO Build Readiness Check

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTIFACTS="$PROJECT_DIR/artifacts"

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        MixOS-GO Build Readiness Check                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Check 1: Build process
echo "1️⃣  Checking build process..."
if pgrep -f "make all" > /dev/null; then
    PID=$(pgrep -f "make all")
    echo "   ✓ Build is running (PID: $PID)"
    
    # Check what's running
    if pgrep -f "gcc" > /dev/null; then
        echo "   → Currently: Compiling kernel"
    elif pgrep -f "make" > /dev/null; then
        echo "   → Currently: Running make"
    else
        echo "   → Status: Other build phase"
    fi
else
    echo "   ✗ Build is not running"
    echo "   ⚠️  Try: cd $PROJECT_DIR && make all"
fi

echo ""
echo "2️⃣  Checking artifacts..."
if [ -d "$ARTIFACTS" ]; then
    FILES=$(ls -1 "$ARTIFACTS" 2>/dev/null | wc -l)
    echo "   ✓ Artifacts directory exists"
    echo "   Files: $FILES"
    
    if [ -f "$ARTIFACTS/mix" ]; then
        echo "   ✓ mix-cli binary built"
    fi
    
    if ls "$ARTIFACTS"/*.iso 2>/dev/null | grep -q .; then
        echo "   ✓ ISO image ready"
        ISO=$(ls -1 "$ARTIFACTS"/*.iso 2>/dev/null | head -1)
        SIZE=$(du -h "$ISO" | cut -f1)
        echo "      → $(basename "$ISO") ($SIZE)"
    else
        echo "   ⏳ ISO building... (expected after ~20 min)"
    fi
    
    if ls "$ARTIFACTS"/*.viso 2>/dev/null | grep -q .; then
        echo "   ✓ VISO image ready"
        VISO=$(ls -1 "$ARTIFACTS"/*.viso 2>/dev/null | head -1)
        SIZE=$(du -h "$VISO" | cut -f1)
        echo "      → $(basename "$VISO") ($SIZE)"
    fi
else
    echo "   ✗ Artifacts directory missing"
fi

echo ""
echo "3️⃣  Checking dependencies for QEMU..."
if command -v qemu-system-x86_64 &> /dev/null; then
    echo "   ✓ QEMU is installed"
    qemu-system-x86_64 --version | head -1 | sed 's/^/      /'
else
    echo "   ✗ QEMU not installed"
    echo "   Install: apt-get install qemu-system-x86 qemu-utils"
fi

echo ""
echo "4️⃣  Disk space check..."
SPACE=$(df -h /tmp | tail -1 | awk '{print $4}')
echo "   Available in /tmp: $SPACE"

if [ -d /tmp/mixos-build ]; then
    SIZE=$(du -sh /tmp/mixos-build 2>/dev/null | cut -f1)
    echo "   Build directory: $SIZE"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Final status
if pgrep -f "make all" > /dev/null; then
    echo "🔨 BUILD IN PROGRESS"
    echo ""
    echo "Wait for completion, then test with QEMU"
    echo "Monitor: tail -f /tmp/build.log"
    echo ""
elif [ -f "$ARTIFACTS/mixos.iso" ]; then
    echo "✅ READY FOR TESTING"
    echo ""
    echo "Run QEMU test:"
    echo "  bash $PROJECT_DIR/tests/test-viso.sh"
    echo ""
else
    echo "⚙️  BUILD COMPLETED"
    echo ""
    echo "Available images:"
    if [ -f "$ARTIFACTS/mixos-go-v1.0.0.viso" ]; then
        echo "  ✓ VISO: $(du -h "$ARTIFACTS/mixos-go-v1.0.0.viso" | cut -f1)"
    fi
    echo ""
    echo "Run tests:"
    echo "  bash $PROJECT_DIR/tests/run-tests.sh test-viso"
fi

echo "═══════════════════════════════════════════════════════════════"
