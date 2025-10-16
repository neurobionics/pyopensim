#!/bin/bash
# Common SWIG installation script
# Installs SWIG 4.1.1 from source for Linux/macOS or downloads precompiled for Windows
#
# Usage:
#   install_swig.sh --install-dir <path> [--jobs <n>]
#
# Environment variables:
#   SWIG_VERSION: SWIG version to install (default: 4.1.1)

set -e

# Defaults
SWIG_VERSION=${SWIG_VERSION:-4.1.1}
NUM_JOBS=${CMAKE_BUILD_PARALLEL_LEVEL:-4}
INSTALL_DIR=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --jobs)
            NUM_JOBS="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --install-dir <path> [--jobs <n>]"
            echo ""
            echo "Options:"
            echo "  --install-dir <path>  Directory to install SWIG (required)"
            echo "  --jobs <n>            Number of parallel jobs (default: 4)"
            echo "  -h, --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$INSTALL_DIR" ]; then
    echo "Error: --install-dir is required"
    exit 1
fi

# Check if SWIG is already installed
if [ -f "$INSTALL_DIR/bin/swig" ]; then
    INSTALLED_VERSION=$("$INSTALL_DIR/bin/swig" -version | grep -oP 'SWIG Version \K[0-9.]+')
    if [ "$INSTALLED_VERSION" = "$SWIG_VERSION" ]; then
        echo "✓ SWIG $SWIG_VERSION already installed at $INSTALL_DIR"
        exit 0
    else
        echo "Found SWIG $INSTALLED_VERSION, but need $SWIG_VERSION. Reinstalling..."
        rm -rf "$INSTALL_DIR"
    fi
fi

echo "Installing SWIG $SWIG_VERSION to $INSTALL_DIR..."

# Create temporary build directory
BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

cd "$BUILD_DIR"

# Download SWIG source
echo "Downloading SWIG $SWIG_VERSION..."
if command -v wget >/dev/null 2>&1; then
    wget -q --show-progress "https://github.com/swig/swig/archive/refs/tags/v${SWIG_VERSION}.tar.gz"
elif command -v curl >/dev/null 2>&1; then
    curl -L -o "v${SWIG_VERSION}.tar.gz" "https://github.com/swig/swig/archive/refs/tags/v${SWIG_VERSION}.tar.gz"
else
    echo "Error: Neither wget nor curl is available for downloading SWIG"
    exit 1
fi

# Extract
echo "Extracting SWIG..."
tar xzf "v${SWIG_VERSION}.tar.gz"
cd "swig-${SWIG_VERSION}"

# Build and install
echo "Building SWIG (this may take a few minutes)..."
./autogen.sh
./configure --prefix="$INSTALL_DIR"
make -j"$NUM_JOBS"
make install

echo "✓ SWIG $SWIG_VERSION installed successfully to $INSTALL_DIR"
echo "  Executable: $INSTALL_DIR/bin/swig"
echo "  Share dir: $INSTALL_DIR/share/swig"

# Verify installation
if [ -f "$INSTALL_DIR/bin/swig" ]; then
    "$INSTALL_DIR/bin/swig" -version
else
    echo "Error: SWIG installation failed"
    exit 1
fi
