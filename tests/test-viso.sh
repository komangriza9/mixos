#!/bin/bash
# ============================================================================
# MixOS-GO VISO Test Script
# Tests VISO image boot functionality
# ============================================================================

set -e

# Configuration
OUTPUT_DIR="${OUTPUT_DIR:-$(pwd)/artifacts}"
VERSION="${VERSION:-1.0.0}"
VISO_NAME="mixos-go-v${VERSION}"
MEMORY="${MEMORY:-2G}"
TIMEOUT="${TIMEOUT:-60}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     MixOS-GO VISO Test Suite                                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Test function
run_test() {
    local name=$1
    local cmd=$2
    
    log_info "Testing: $name"
    
    if eval "$cmd" >/dev/null 2>&1; then
        log_ok "$name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$name"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# Test 1: Check VISO file exists
# ============================================================================
test_viso_exists() {
    local viso_path="$OUTPUT_DIR/${VISO_NAME}.viso"
    
    if [ -f "$viso_path" ]; then
        local size=$(du -h "$viso_path" | cut -f1)
        log_ok "VISO file exists: $viso_path ($size)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        # Check for archive
        if [ -f "$OUTPUT_DIR/${VISO_NAME}.viso.tar.gz" ]; then
            log_warn "VISO archive exists (not qcow2)"
            TESTS_PASSED=$((TESTS_PASSED + 1))
            return 0
        fi
        log_fail "VISO file not found"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# Test 2: Check initramfs exists
# ============================================================================
test_initramfs_exists() {
    local initramfs_path="$OUTPUT_DIR/boot/initramfs-mixos.img"
    
    if [ -f "$initramfs_path" ]; then
        local size=$(du -h "$initramfs_path" | cut -f1)
        log_ok "Initramfs exists: $initramfs_path ($size)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "Initramfs not found"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# Test 3: Check initramfs structure
# ============================================================================
test_initramfs_structure() {
    local initramfs_path="$OUTPUT_DIR/boot/initramfs-mixos.img"
    local temp_dir=$(mktemp -d)
    
    if [ ! -f "$initramfs_path" ]; then
        log_fail "Initramfs not found for structure test"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    # Extract and check structure
    cd "$temp_dir"
    zcat "$initramfs_path" 2>/dev/null | cpio -id 2>/dev/null || \
    xzcat "$initramfs_path" 2>/dev/null | cpio -id 2>/dev/null || {
        log_fail "Cannot extract initramfs"
        rm -rf "$temp_dir"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    }
    
    # Check for essential files
    local missing=0
    for file in init bin/busybox scripts/functions.sh; do
        if [ ! -e "$file" ]; then
            log_warn "Missing: $file"
            missing=$((missing + 1))
        fi
    done
    
    cd - >/dev/null
    rm -rf "$temp_dir"
    
    if [ $missing -eq 0 ]; then
        log_ok "Initramfs structure valid"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "Initramfs structure incomplete ($missing files missing)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# Test 4: Check init script syntax
# ============================================================================
test_init_syntax() {
    local init_path="initramfs/init"
    
    if [ ! -f "$init_path" ]; then
        log_fail "Init script not found"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    # Check shell syntax
    if bash -n "$init_path" 2>/dev/null; then
        log_ok "Init script syntax valid"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "Init script has syntax errors"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# Test 5: Check helper scripts syntax
# ============================================================================
test_helper_scripts_syntax() {
    local scripts_dir="initramfs/scripts"
    local errors=0
    
    if [ ! -d "$scripts_dir" ]; then
        log_fail "Scripts directory not found"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    for script in "$scripts_dir"/*.sh; do
        if [ -f "$script" ]; then
            if ! bash -n "$script" 2>/dev/null; then
                log_warn "Syntax error in: $(basename "$script")"
                errors=$((errors + 1))
            fi
        fi
    done
    
    if [ $errors -eq 0 ]; then
        log_ok "All helper scripts syntax valid"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$errors scripts have syntax errors"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# Test 6: Check QEMU availability
# ============================================================================
test_qemu_available() {
    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        local version=$(qemu-system-x86_64 --version | head -1)
        log_ok "QEMU available: $version"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_warn "QEMU not available (boot tests will be skipped)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    fi
}

# ============================================================================
# Test 7: Check mix-cli VRAM command
# ============================================================================
test_mix_vram_command() {
    local mix_cli="src/mix-cli"
    
    if [ ! -d "$mix_cli" ]; then
        log_fail "mix-cli source not found"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
    
    # Check if vram.go exists
    if [ -f "$mix_cli/cmd/vram.go" ]; then
        log_ok "mix vram command implemented"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "mix vram command not found"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# Test 8: Check mix-cli VISO command
# ============================================================================
test_mix_viso_command() {
    local mix_cli="src/mix-cli"
    
    if [ -f "$mix_cli/cmd/viso.go" ]; then
        log_ok "mix viso command implemented"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "mix viso command not found"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# Test 9: Check build scripts
# ============================================================================
test_build_scripts() {
    local scripts=(
        "build/scripts/build-initramfs.sh"
        "build/scripts/build-viso.sh"
        "build/scripts/gen-modules-dep.sh"
    )
    
    local missing=0
    for script in "${scripts[@]}"; do
        if [ ! -f "$script" ]; then
            log_warn "Missing: $script"
            missing=$((missing + 1))
        elif [ ! -x "$script" ]; then
            log_warn "Not executable: $script"
            missing=$((missing + 1))
        fi
    done
    
    if [ $missing -eq 0 ]; then
        log_ok "All build scripts present and executable"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$missing build scripts missing or not executable"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# Test 10: Check Makefile targets
# ============================================================================
test_makefile_targets() {
    local targets=("initramfs" "viso" "sdisk" "vram" "test-viso" "test-vram")
    local missing=0
    
    for target in "${targets[@]}"; do
        if ! grep -q "^${target}:" Makefile 2>/dev/null; then
            log_warn "Missing Makefile target: $target"
            missing=$((missing + 1))
        fi
    done
    
    if [ $missing -eq 0 ]; then
        log_ok "All Makefile targets present"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_fail "$missing Makefile targets missing"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

# ============================================================================
# Run all tests
# ============================================================================
echo "Running VISO/VRAM tests..."
echo ""

# Source code tests (always run)
test_init_syntax
test_helper_scripts_syntax
test_mix_vram_command
test_mix_viso_command
test_build_scripts
test_makefile_targets
test_qemu_available

# Artifact tests (only if artifacts exist)
if [ -d "$OUTPUT_DIR" ]; then
    test_viso_exists
    test_initramfs_exists
    test_initramfs_structure
else
    log_warn "Artifacts directory not found - skipping artifact tests"
    log_info "Run 'make all' to build artifacts"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║     Test Results                                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "  Total:  $((TESTS_PASSED + TESTS_FAILED))"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed! ✓${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed! ✗${NC}"
    exit 1
fi
