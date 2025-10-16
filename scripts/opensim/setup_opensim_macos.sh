#!/bin/bash
# Setup script for OpenSim on macOS
# This script orchestrates the OpenSim build process using common scripts

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$SCRIPT_DIR/common"

# Configuration
DEBUG_TYPE=${CMAKE_BUILD_TYPE:-Release}
NUM_JOBS=${CMAKE_BUILD_PARALLEL_LEVEL:-$(sysctl -n hw.ncpu)}
OPENSIM_ROOT=$(pwd)
WORKSPACE_DIR="$OPENSIM_ROOT/build/opensim-workspace"

# Parse command line arguments
DEPS_ONLY=false
FORCE_REBUILD=false
ARCH_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --deps-only)
            DEPS_ONLY=true
            shift
            ;;
        --force)
            FORCE_REBUILD=true
            shift
            ;;
        --arch)
            ARCH_OVERRIDE="$2"
            shift 2
            ;;
        --with-wheel-tools|--dev)
            # These flags are deprecated but kept for compatibility
            shift
            ;;
        -j)
            NUM_JOBS="$2"
            shift 2
            ;;
        -d)
            DEBUG_TYPE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --deps-only       Install only system dependencies, skip OpenSim build"
            echo "  --force           Force rebuild even if cached build exists"
            echo "  --arch <arch>     Architecture: arm64, x86_64, or universal2"
            echo "  -j <n>            Number of parallel jobs"
            echo "  -d <type>         Build type (Release, Debug, RelWithDebInfo)"
            echo "  -h, --help        Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Detect or set architecture
if [ -n "$ARCH_OVERRIDE" ]; then
    ARCH="$ARCH_OVERRIDE"
elif [ -n "${CMAKE_OSX_ARCHITECTURES}" ]; then
    ARCH="${CMAKE_OSX_ARCHITECTURES}"
elif [ -n "${ARCHFLAGS}" ] && [[ "${ARCHFLAGS}" == *"universal2"* ]]; then
    ARCH="universal2"
else
    ARCH=$(uname -m)
fi

# Determine CMake preset based on architecture
case "$ARCH" in
    "universal2"|"x86_64;arm64"|"arm64;x86_64")
        DEPS_PRESET="opensim-dependencies-macos-universal2"
        CORE_PRESET="opensim-core-macos-universal2"
        echo "Building for macOS universal2 (x86_64 + arm64)"
        ;;
    "arm64")
        DEPS_PRESET="opensim-dependencies-macos-arm64"
        CORE_PRESET="opensim-core-macos-arm64"
        echo "Building for macOS arm64 (Apple Silicon)"
        ;;
    "x86_64")
        DEPS_PRESET="opensim-dependencies-macos-x86_64"
        CORE_PRESET="opensim-core-macos-x86_64"
        echo "Building for macOS x86_64 (Intel)"
        ;;
    *)
        echo "Unknown architecture: $ARCH"
        echo "Defaulting to native architecture: $(uname -m)"
        ARCH=$(uname -m)
        DEPS_PRESET="opensim-dependencies-macos-$ARCH"
        CORE_PRESET="opensim-core-macos-$ARCH"
        ;;
esac

echo "=== OpenSim macOS Setup ==="
echo "Build type: $DEBUG_TYPE"
echo "Architecture: $ARCH"
echo "Jobs: $NUM_JOBS"
echo "Workspace: $WORKSPACE_DIR"

# Create workspace
mkdir -p "$WORKSPACE_DIR"

# Step 1: Install system packages
echo ""
echo "Step 1: Installing system packages..."
"$COMMON_DIR/install_packages.sh"

# Exit early if only installing dependencies
if [ "$DEPS_ONLY" = true ]; then
    echo "Dependencies installation complete."
    exit 0
fi

# Step 2: Install SWIG
echo ""
echo "Step 2: Installing SWIG..."
SWIG_INSTALL_DIR="$WORKSPACE_DIR/swig-install"
SWIG_FLAGS="--install-dir $SWIG_INSTALL_DIR --jobs $NUM_JOBS"

"$COMMON_DIR/install_swig.sh" $SWIG_FLAGS

# Add SWIG to PATH for subsequent steps
export PATH="$SWIG_INSTALL_DIR/bin:$PATH"

# Step 3: Build OpenSim dependencies
echo ""
echo "Step 3: Building OpenSim dependencies..."
DEPS_SOURCE="$OPENSIM_ROOT/src/opensim-core/dependencies"
DEPS_BUILD_DIR="$WORKSPACE_DIR/dependencies-build"
DEPS_INSTALL_DIR="$WORKSPACE_DIR/dependencies-install"

DEPS_FLAGS="--source-dir $DEPS_SOURCE"
DEPS_FLAGS="$DEPS_FLAGS --build-dir $DEPS_BUILD_DIR"
DEPS_FLAGS="$DEPS_FLAGS --install-dir $DEPS_INSTALL_DIR"
DEPS_FLAGS="$DEPS_FLAGS --preset $DEPS_PRESET"
DEPS_FLAGS="$DEPS_FLAGS --jobs $NUM_JOBS"

if [ "$FORCE_REBUILD" = true ]; then
    DEPS_FLAGS="$DEPS_FLAGS --force"
fi

"$COMMON_DIR/build_dependencies.sh" $DEPS_FLAGS

# Step 4: Build OpenSim core
echo ""
echo "Step 4: Building OpenSim core..."
OPENSIM_SOURCE="$OPENSIM_ROOT/src/opensim-core"
OPENSIM_BUILD_DIR="$WORKSPACE_DIR/opensim-build"
OPENSIM_INSTALL_DIR="$WORKSPACE_DIR/opensim-install"

OPENSIM_FLAGS="--source-dir $OPENSIM_SOURCE"
OPENSIM_FLAGS="$OPENSIM_FLAGS --build-dir $OPENSIM_BUILD_DIR"
OPENSIM_FLAGS="$OPENSIM_FLAGS --install-dir $OPENSIM_INSTALL_DIR"
OPENSIM_FLAGS="$OPENSIM_FLAGS --deps-dir $DEPS_INSTALL_DIR"
OPENSIM_FLAGS="$OPENSIM_FLAGS --swig-dir $SWIG_INSTALL_DIR/share/swig"
OPENSIM_FLAGS="$OPENSIM_FLAGS --swig-exe $SWIG_INSTALL_DIR/bin/swig"
OPENSIM_FLAGS="$OPENSIM_FLAGS --preset $CORE_PRESET"
OPENSIM_FLAGS="$OPENSIM_FLAGS --jobs $NUM_JOBS"

if [ "$FORCE_REBUILD" = true ]; then
    OPENSIM_FLAGS="$OPENSIM_FLAGS --force"
fi

"$COMMON_DIR/build_opensim.sh" $OPENSIM_FLAGS

echo ""
echo "✓ OpenSim setup complete!"
echo "  Libraries installed in: $OPENSIM_INSTALL_DIR"
echo ""
echo "Next steps:"
echo "  Run 'make build' to build the Python bindings"
