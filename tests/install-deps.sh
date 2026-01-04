#!/bin/bash
# MixOS-GO Dependency Installer
# This script helps install missing dependencies for MixOS-GO build and testing

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║     MixOS-GO Dependency Installer                             ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠️  This script requires sudo to install packages${NC}"
    echo "Run: sudo bash $0"
    exit 1
fi

echo "📦 Checking dependencies..."
echo ""

# Track what needs to be installed
PACKAGES_TO_INSTALL=()

# Function to check and report package
check_package() {
    local pkg=$1
    local cmd=$2
    
    if command -v "$cmd" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $pkg (installed)"
    else
        echo -e "${RED}✗${NC} $pkg (missing)"
        PACKAGES_TO_INSTALL+=("$pkg")
    fi
}

echo "Build Dependencies:"
check_package "gcc" "gcc"
check_package "make" "make"
check_package "flex" "flex"
check_package "bison" "bison"
check_package "bc" "bc"
check_package "libelf-dev" "pkg-config"
check_package "libssl-dev" "openssl"

echo ""
echo "Testing Dependencies:"
check_package "qemu-system-x86" "qemu-system-x86_64"
check_package "qemu-utils" "qemu-img"

echo ""
echo "ISO Creation (Optional):"
check_package "squashfs-tools" "mksquashfs"
check_package "xorriso" "xorriso"
check_package "genisoimage" "genisoimage"

echo ""
echo "System Tools:"
check_package "git" "git"
check_package "curl" "curl"
check_package "python3" "python3"

echo ""
echo "═══════════════════════════════════════════════════════════════════"

if [ ${#PACKAGES_TO_INSTALL[@]} -eq 0 ]; then
    echo -e "${GREEN}✅ All dependencies are installed!${NC}"
    echo ""
    exit 0
fi

echo ""
echo "🔧 Missing packages: ${#PACKAGES_TO_INSTALL[@]}"
echo ""
echo "Install with:"
echo "  sudo apt-get update"
echo "  sudo apt-get install -y ${PACKAGES_TO_INSTALL[@]}"
echo ""

read -p "Install now? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Installing..."
    apt-get update
    apt-get install -y "${PACKAGES_TO_INSTALL[@]}"
    echo ""
    echo -e "${GREEN}✅ Installation complete!${NC}"
else
    echo "Skipped"
fi

echo "═══════════════════════════════════════════════════════════════════"
