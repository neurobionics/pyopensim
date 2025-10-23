#!/bin/bash
# CI-specific OpenSim build orchestrator
# This script wraps the common build scripts with CI-specific caching and path handling
#
# Usage:
#   build_opensim.sh --platform <linux|macos> --cache-dir <path> [--force]
#
# Environment variables expected from CI:
#   OPENSIM_SHA: Git SHA of opensim-core submodule (for cache validation)

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$SCRIPT_DIR/../opensim/common"

# Defaults
PLATFORM=""
CACHE_DIR=""
FORCE_REBUILD=false
NUM_JOBS=${CMAKE_BUILD_PARALLEL_LEVEL:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --cache-dir)
            CACHE_DIR="$2"
            shift 2
            ;;
        --force)
            FORCE_REBUILD=true
            shift
            ;;
        --jobs)
            NUM_JOBS="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --platform <linux|macos> --cache-dir <path> [--force] [--jobs <n>]"
            echo ""
            echo "Required arguments:"
            echo "  --platform <name>     Platform: linux or macos"
            echo "  --cache-dir <path>    Directory for caching OpenSim build"
            echo ""
            echo "Optional arguments:"
            echo "  --force               Force rebuild (ignore cache)"
            echo "  --jobs <n>            Number of parallel jobs"
            echo "  -h, --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate arguments
if [ -z "$PLATFORM" ] || [ -z "$CACHE_DIR" ]; then
    echo "Error: --platform and --cache-dir are required"
    exit 1
fi

# Determine architecture and preset based on platform
case "$PLATFORM" in
    linux)
        DEPS_PRESET="opensim-dependencies-linux"
        CORE_PRESET="opensim-core-linux"
        ;;
    macos)
        # For CI, always build universal2 on macOS
        # Using deployment target 11 to match OpenSim's official CI
        DEPS_PRESET="opensim-dependencies-macos-universal2"
        CORE_PRESET="opensim-core-macos-universal2"
        export CMAKE_OSX_ARCHITECTURES="x86_64;arm64"
        export MACOSX_DEPLOYMENT_TARGET="11.0"
        ;;
    *)
        echo "Error: Unsupported platform: $PLATFORM"
        echo "Supported platforms: linux, macos"
        exit 1
        ;;
esac

echo "=== CI OpenSim Build ==="
echo "Platform: $PLATFORM"
echo "Cache dir: $CACHE_DIR"
echo "Jobs: $NUM_JOBS"
echo "Preset (deps): $DEPS_PRESET"
echo "Preset (core): $CORE_PRESET"

# Get project root (assumes this script is in scripts/ci/)
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Convert CACHE_DIR to absolute path if it's relative
# This is important when called from cibuildwheel where paths may be relative
if [[ "$CACHE_DIR" != /* ]]; then
    echo "Converting relative cache path to absolute..."
    echo "  Input: $CACHE_DIR"
    # Try to cd into it first (if it exists), otherwise make it absolute relative to project root
    if [ -d "$CACHE_DIR" ]; then
        CACHE_DIR="$(cd "$CACHE_DIR" && pwd)"
    else
        CACHE_DIR="$PROJECT_ROOT/$CACHE_DIR"
        # Create it now so subsequent operations have absolute path
        mkdir -p "$CACHE_DIR"
        CACHE_DIR="$(cd "$CACHE_DIR" && pwd)"
    fi
    echo "  Absolute: $CACHE_DIR"
fi

# Set up paths (now using absolute CACHE_DIR)
OPENSIM_INSTALL="$CACHE_DIR/opensim-install"
DEPS_INSTALL="$CACHE_DIR/dependencies-install"
SWIG_INSTALL="$CACHE_DIR/swig"

echo "Resolved paths:"
echo "  CACHE_DIR: $CACHE_DIR"
echo "  SWIG_INSTALL: $SWIG_INSTALL"
echo "  OPENSIM_INSTALL: $OPENSIM_INSTALL"

# Check if we have a cached build
if [ -f "$OPENSIM_INSTALL/.build_complete" ] && [ "$FORCE_REBUILD" = false ]; then
    echo "Cached OpenSim build found, validating..."

    # Verify cache is valid by checking for critical files
    CACHE_VALID=true

    if [ ! -d "$OPENSIM_INSTALL/sdk/lib" ]; then
        echo "⚠ Cache validation failed: sdk/lib directory missing"
        CACHE_VALID=false
    else
        # Check if any libraries exist
        LIB_COUNT=$(find "$OPENSIM_INSTALL/sdk/lib" -name "*.so" -o -name "*.dylib" -o -name "*.a" 2>/dev/null | wc -l)
        if [ "$LIB_COUNT" -lt 5 ]; then
            echo "⚠ Cache validation failed: found only $LIB_COUNT libraries (expected at least 5)"
            CACHE_VALID=false
        fi
    fi

    if [ "$CACHE_VALID" = true ]; then
        echo "✓ Cache validation passed"
        echo "  Libraries: $(find "$OPENSIM_INSTALL/sdk/lib" -name "*.so" -o -name "*.dylib" -o -name "*.a" 2>/dev/null | wc -l)"
        ls -la "$OPENSIM_INSTALL/sdk/lib/" | head -10
    else
        echo "⚠ Cache appears corrupted, forcing rebuild..."
        # Remove corrupted cache to ensure clean rebuild
        rm -rf "$OPENSIM_INSTALL"
        FORCE_REBUILD=true
    fi
fi

if [ "$FORCE_REBUILD" = true ] || [ ! -f "$OPENSIM_INSTALL/.build_complete" ]; then
    echo "Building OpenSim from scratch..."

    # Create cache directory
    mkdir -p "$CACHE_DIR"
    cd "$CACHE_DIR"

    # Step 1: Install system packages (using inline logic for CI containers)
    echo ""
    echo "Step 1: Installing system packages..."
    case "$PLATFORM" in
        linux)
            # In CI, we're typically root in a container
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y gcc gcc-c++ make autoconf automake libtool pkgconfig \
                    openblas-devel lapack-devel freeglut-devel libXi-devel libXmu-devel \
                    python3-devel git openssl-devel pcre-devel pcre2-devel gcc-gfortran \
                    patchelf java-1.8.0-openjdk-devel wget bison byacc || true
            elif command -v apt-get >/dev/null 2>&1; then
                apt-get update && apt-get install -y build-essential autotools-dev \
                    autoconf pkg-config automake libopenblas-dev liblapack-dev freeglut3-dev \
                    libxi-dev libxmu-dev python3-dev git libssl-dev libpcre3-dev libpcre2-dev \
                    libtool gfortran patchelf openjdk-8-jdk wget bison byacc || true
            fi

            # Install newer CMake (manylinux containers often have old CMake)
            # Using 3.22.1 to match OpenSim's ubuntu-22.04 CI environment
            echo "Installing CMake 3.22.1..."
            CMAKE_VERSION="3.22.1"
            CMAKE_INSTALL_DIR="$CACHE_DIR/cmake"

            if [ ! -f "$CMAKE_INSTALL_DIR/bin/cmake" ]; then
                CMAKE_ARCH="x86_64"
                if [ "$(uname -m)" = "aarch64" ]; then
                    CMAKE_ARCH="aarch64"
                fi

                wget -q "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${CMAKE_ARCH}.tar.gz" -O /tmp/cmake.tar.gz
                mkdir -p "$CMAKE_INSTALL_DIR"
                tar -xzf /tmp/cmake.tar.gz -C "$CMAKE_INSTALL_DIR" --strip-components=1
                rm /tmp/cmake.tar.gz
            fi

            export PATH="$CMAKE_INSTALL_DIR/bin:$PATH"
            echo "CMake version: $(cmake --version | head -1)"
            ;;
        macos)
            # On macOS runners, brew is pre-installed
            brew install cmake autoconf automake libtool pkgconfig || true
            ;;
    esac

    # Step 2: Install SWIG
    echo ""
    echo "Step 2: Installing SWIG..."
    "$COMMON_DIR/install_swig.sh" \
        --install-dir "$SWIG_INSTALL" \
        --jobs "$NUM_JOBS"

    export PATH="$SWIG_INSTALL/bin:$PATH"

    # Step 3: Build dependencies
    echo ""
    echo "Step 3: Building OpenSim dependencies..."
    "$COMMON_DIR/build_dependencies.sh" \
        --source-dir "$PROJECT_ROOT/src/opensim-core/dependencies" \
        --build-dir "$CACHE_DIR/dependencies-build" \
        --install-dir "$DEPS_INSTALL" \
        --preset "$DEPS_PRESET" \
        --jobs "$NUM_JOBS" \
        --force

    # Step 4: Build OpenSim core
    echo ""
    echo "Step 4: Building OpenSim core..."
    "$COMMON_DIR/build_opensim.sh" \
        --source-dir "$PROJECT_ROOT/src/opensim-core" \
        --build-dir "$CACHE_DIR/opensim-build" \
        --install-dir "$OPENSIM_INSTALL" \
        --deps-dir "$DEPS_INSTALL" \
        --swig-dir "$SWIG_INSTALL/share/swig" \
        --swig-exe "$SWIG_INSTALL/bin/swig" \
        --preset "$CORE_PRESET" \
        --jobs "$NUM_JOBS" \
        --force

    echo "✓ OpenSim build complete"
fi

# Set environment variables for subsequent build steps
echo ""
echo "Setting up build environment..."

# Add CMake to PATH if on Linux
if [ "$PLATFORM" = "linux" ]; then
    CMAKE_INSTALL_DIR="$CACHE_DIR/cmake"
    export PATH="$CMAKE_INSTALL_DIR/bin:$PATH"
fi

export PATH="$SWIG_INSTALL/bin:$PATH"
export OPENSIM_INSTALL_DIR="$OPENSIM_INSTALL"

echo "  CMake version: $(cmake --version | head -1)"
echo "  PATH includes SWIG: $(which swig 2>/dev/null || echo 'SWIG not in PATH')"
echo "  OPENSIM_INSTALL_DIR: $OPENSIM_INSTALL_DIR"

# Verify SWIG is working
echo "  SWIG version check:"
swig -version || echo "ERROR: SWIG not working"

echo ""
echo "✓ CI build environment ready"
echo "  OpenSim installed at: $OPENSIM_INSTALL"
