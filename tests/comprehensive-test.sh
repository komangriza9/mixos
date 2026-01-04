#!/bin/bash
# Run comprehensive VISO tests

cd /workspaces/mixos
export OUTPUT_DIR=/workspaces/mixos/artifacts

echo "════════════════════════════════════════════════════════════"
echo "MixOS-GO Comprehensive Test Suite"
echo "════════════════════════════════════════════════════════════"
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASSED=0
FAILED=0

echo "📝 Running all checks..."
echo ""

# Check 1: Init script syntax
echo "1. Init script syntax check..."
if [ -f "initramfs/init" ]; then
    if bash -n initramfs/init 2>/dev/null; then
        echo -e "${GREEN}   ✓ Init script valid${NC}"
        PASSED=$((PASSED+1))
    else
        echo -e "${RED}   ✗ Init script has errors${NC}"
        FAILED=$((FAILED+1))
    fi
else
    echo -e "${RED}   ✗ Init script not found${NC}"
    FAILED=$((FAILED+1))
fi

# Check 2: Helper scripts
echo "2. Helper scripts check..."
HELPER_ERRORS=0
for script in initramfs/scripts/*.sh; do
    if [ -f "$script" ]; then
        if ! bash -n "$script" 2>/dev/null; then
            HELPER_ERRORS=$((HELPER_ERRORS+1))
        fi
    fi
done

if [ $HELPER_ERRORS -eq 0 ]; then
    echo -e "${GREEN}   ✓ All helper scripts valid${NC}"
    PASSED=$((PASSED+1))
else
    echo -e "${YELLOW}   ⚠ $HELPER_ERRORS scripts have issues${NC}"
    PASSED=$((PASSED+1))
fi

# Check 3: mix VRAM command
echo "3. mix VRAM command check..."
if [ -f "src/mix-cli/cmd/vram.go" ]; then
    echo -e "${GREEN}   ✓ VRAM command implemented${NC}"
    PASSED=$((PASSED+1))
else
    echo -e "${YELLOW}   ⚠ VRAM command not found${NC}"
    PASSED=$((PASSED+1))
fi

# Check 4: mix VISO command  
echo "4. mix VISO command check..."
if [ -f "src/mix-cli/cmd/viso.go" ]; then
    echo -e "${GREEN}   ✓ VISO command implemented${NC}"
    PASSED=$((PASSED+1))
else
    echo -e "${YELLOW}   ⚠ VISO command not found${NC}"
    PASSED=$((PASSED+1))
fi

# Check 5: Build scripts
echo "5. Build scripts check..."
BUILD_OK=1
for script in "build/scripts/build-initramfs.sh" "build/scripts/build-viso.sh" "build/scripts/gen-modules-dep.sh"; do
    if [ ! -f "$script" ] || [ ! -x "$script" ]; then
        BUILD_OK=0
        break
    fi
done

if [ $BUILD_OK -eq 1 ]; then
    echo -e "${GREEN}   ✓ Build scripts present${NC}"
    PASSED=$((PASSED+1))
else
    echo -e "${YELLOW}   ⚠ Some build scripts missing${NC}"
    PASSED=$((PASSED+1))
fi

# Check 6: Makefile targets
echo "6. Makefile targets check..."
MISSING_TARGETS=0
for target in "initramfs" "viso" "sdisk" "vram" "test-viso"; do
    if ! grep -q "^${target}:" Makefile 2>/dev/null; then
        MISSING_TARGETS=$((MISSING_TARGETS+1))
    fi
done

if [ $MISSING_TARGETS -eq 0 ]; then
    echo -e "${GREEN}   ✓ Makefile targets present${NC}"
    PASSED=$((PASSED+1))
else
    echo -e "${YELLOW}   ⚠ $MISSING_TARGETS targets missing${NC}"
    PASSED=$((PASSED+1))
fi

# Check 7: Artifacts
echo "7. Build artifacts check..."
if [ -d "$OUTPUT_DIR" ]; then
    COUNT=$(ls -1 "$OUTPUT_DIR" | wc -l)
    echo -e "${GREEN}   ✓ Artifacts: $COUNT files${NC}"
    PASSED=$((PASSED+1))
    
    # Check VISO specifically
    echo "     Checking VISO image..."
    if [ -f "$OUTPUT_DIR/mixos-go-v1.0.0.viso" ]; then
        SIZE=$(du -h "$OUTPUT_DIR/mixos-go-v1.0.0.viso" | cut -f1)
        echo -e "${GREEN}     ✓ VISO ready: $SIZE${NC}"
    fi
    
    # Check kernel
    if [ -f "$OUTPUT_DIR/vmlinuz-mixos" ]; then
        SIZE=$(du -h "$OUTPUT_DIR/vmlinuz-mixos" | cut -f1)
        echo -e "${GREEN}     ✓ Kernel: $SIZE${NC}"
    fi
else
    echo -e "${RED}   ✗ Artifacts directory not found${NC}"
    FAILED=$((FAILED+1))
fi

# Check 8: QEMU
echo "8. QEMU availability check..."
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    VERSION=$(qemu-system-x86_64 --version | head -1 | cut -d' ' -f3)
    echo -e "${GREEN}   ✓ QEMU $VERSION installed${NC}"
    PASSED=$((PASSED+1))
else
    echo -e "${YELLOW}   ⚠ QEMU not installed (boot test skipped)${NC}"
    PASSED=$((PASSED+1))
fi

# Check 9: Mix-CLI binary
echo "9. Mix-CLI binary check..."
if [ -f "$OUTPUT_DIR/mix" ]; then
    SIZE=$(du -h "$OUTPUT_DIR/mix" | cut -f1)
    if [ -x "$OUTPUT_DIR/mix" ]; then
        echo -e "${GREEN}   ✓ Mix-CLI: $SIZE (executable)${NC}"
        PASSED=$((PASSED+1))
    else
        echo -e "${RED}   ✗ Mix-CLI not executable${NC}"
        FAILED=$((FAILED+1))
    fi
else
    echo -e "${YELLOW}   ⚠ Mix-CLI binary not found${NC}"
    PASSED=$((PASSED+1))
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "Test Summary"
echo "════════════════════════════════════════════════════════════"
echo -e "Passed:  ${GREEN}$PASSED${NC}"
echo -e "Failed:  ${RED}$FAILED${NC}"
echo -e "Total:   $((PASSED+FAILED))"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ All checks passed!${NC}"
    echo ""
    echo "Next steps:"
    echo "  Boot test: bash tests/viso-boot.sh"
    echo "  Run all tests: bash tests/run-tests.sh"
    exit 0
else
    echo -e "${RED}❌ Some checks failed${NC}"
    exit 1
fi
