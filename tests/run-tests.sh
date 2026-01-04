#!/bin/bash
# MixOS-GO Test Runner
# Centralized test execution script

set -e

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
TESTS_DIR="$PROJECT_DIR/tests"
ARTIFACTS="$PROJECT_DIR/artifacts"

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

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║ $1${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================================
# Main Test Menu
# ============================================================================

print_header "MixOS-GO Test Suite"

if [ $# -eq 0 ]; then
    echo "Available Tests:"
    echo ""
    echo "  1. test-mix-cli        - Mix CLI package manager tests"
    echo "  2. test-viso           - VISO virtual disk boot test"
    echo "  3. check-build         - Verify build artifacts"
    echo "  4. create-iso-minimal  - Create minimal ISO (no squashfs needed)"
    echo "  5. install-deps        - Install build dependencies"
    echo "  6. all                 - Run all tests"
    echo ""
    echo "Usage: $0 [test-name]"
    echo "Example: $0 test-viso"
    echo ""
    exit 0
fi

TEST_NAME="$1"

case "$TEST_NAME" in
    test-mix-cli)
        log_info "Running Mix CLI tests..."
        bash "$TESTS_DIR/test-mix-cli.sh"
        ;;
    test-viso)
        log_info "Running VISO boot test..."
        bash "$TESTS_DIR/test-viso.sh"
        ;;
    check-build)
        log_info "Checking build artifacts..."
        bash "$TESTS_DIR/check-build.sh"
        ;;
    create-iso-minimal)
        log_info "Creating minimal ISO..."
        bash "$TESTS_DIR/create-iso-minimal.sh"
        ;;
    install-deps)
        log_info "Installing build dependencies..."
        bash "$TESTS_DIR/install-deps.sh"
        ;;
    all)
        log_info "Running all tests..."
        echo ""
        
        bash "$TESTS_DIR/check-build.sh" || log_warn "Build check had issues"
        echo ""
        
        bash "$TESTS_DIR/test-mix-cli.sh" || log_warn "Mix CLI tests had issues"
        echo ""
        
        log_info "To test VISO, run:"
        echo "  bash $TESTS_DIR/test-viso.sh"
        ;;
    *)
        log_error "Unknown test: $TEST_NAME"
        echo ""
        echo "Available tests:"
        echo "  test-mix-cli, test-viso, check-build, create-iso-minimal, install-deps"
        exit 1
        ;;
esac

echo ""
log_ok "Test execution completed"
