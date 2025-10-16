#!/bin/bash
# Common OpenSim dependencies build script
# Builds OpenSim dependencies using CMake presets
#
# Usage:
#   build_dependencies.sh --source-dir <path> --build-dir <path> --install-dir <path> --preset <name> [--jobs <n>]
#
# Required arguments:
#   --source-dir:  Path to opensim-core/dependencies directory
#   --build-dir:   Directory for build files
#   --install-dir: Directory to install dependencies
#   --preset:      CMake preset name (e.g., opensim-dependencies-linux)
#
# Optional arguments:
#   --jobs:        Number of parallel jobs (default: 4)
#   --force:       Force rebuild even if build_complete marker exists

set -e

# Defaults
NUM_JOBS=${CMAKE_BUILD_PARALLEL_LEVEL:-4}
SOURCE_DIR=""
BUILD_DIR=""
INSTALL_DIR=""
PRESET=""
FORCE_REBUILD=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --source-dir)
            SOURCE_DIR="$2"
            shift 2
            ;;
        --build-dir)
            BUILD_DIR="$2"
            shift 2
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --preset)
            PRESET="$2"
            shift 2
            ;;
        --jobs)
            NUM_JOBS="$2"
            shift 2
            ;;
        --force)
            FORCE_REBUILD=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 --source-dir <path> --build-dir <path> --install-dir <path> --preset <name> [--jobs <n>] [--force]"
            echo ""
            echo "Required arguments:"
            echo "  --source-dir <path>   Path to opensim-core/dependencies directory"
            echo "  --build-dir <path>    Directory for build files"
            echo "  --install-dir <path>  Directory to install dependencies"
            echo "  --preset <name>       CMake preset name (e.g., opensim-dependencies-linux)"
            echo ""
            echo "Optional arguments:"
            echo "  --jobs <n>            Number of parallel jobs (default: 4)"
            echo "  --force               Force rebuild even if already built"
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
if [ -z "$SOURCE_DIR" ] || [ -z "$BUILD_DIR" ] || [ -z "$INSTALL_DIR" ] || [ -z "$PRESET" ]; then
    echo "Error: Missing required arguments"
    echo "Run with --help for usage information"
    exit 1
fi

# Validate source directory
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

# Check if already built
if [ -f "$INSTALL_DIR/.build_complete" ] && [ "$FORCE_REBUILD" = false ]; then
    echo "✓ Dependencies already built at $INSTALL_DIR"
    echo "  Use --force to rebuild"
    exit 0
fi

if [ "$FORCE_REBUILD" = true ]; then
    echo "Force rebuild requested - removing existing build and install directories"
    rm -rf "$BUILD_DIR" "$INSTALL_DIR"
fi

echo "=== Building OpenSim Dependencies ==="
echo "  Source:  $SOURCE_DIR"
echo "  Build:   $BUILD_DIR"
echo "  Install: $INSTALL_DIR"
echo "  Preset:  $PRESET"
echo "  Jobs:    $NUM_JOBS"

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Get CMake flags based on preset name
# Note: We can't use --preset here because the dependencies directory doesn't have CMakePresets.json
# Instead, we extract the flags from the preset and pass them directly
echo "Configuring dependencies with flags from preset: $PRESET"

case "$PRESET" in
    opensim-dependencies-linux)
        CMAKE_FLAGS=(
            -DCMAKE_BUILD_TYPE=Release
            -DCMAKE_CXX_FLAGS="-pthread -fPIC"
            -DCMAKE_C_FLAGS="-pthread -fPIC"
            -DSUPERBUILD_ezc3d=ON
            -DOPENSIM_WITH_CASADI=OFF
            -DOPENSIM_WITH_TROPTER=OFF
        )
        ;;
    opensim-dependencies-macos-x86_64)
        CMAKE_FLAGS=(
            -DCMAKE_BUILD_TYPE=Release
            -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
            -DCMAKE_OSX_ARCHITECTURES=x86_64
            -DSUPERBUILD_ezc3d=ON
            -DOPENSIM_WITH_CASADI=OFF
            -DOPENSIM_WITH_TROPTER=OFF
        )
        ;;
    opensim-dependencies-macos-arm64)
        CMAKE_FLAGS=(
            -DCMAKE_BUILD_TYPE=Release
            -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
            -DCMAKE_OSX_ARCHITECTURES=arm64
            -DSUPERBUILD_ezc3d=ON
            -DOPENSIM_WITH_CASADI=OFF
            -DOPENSIM_WITH_TROPTER=OFF
        )
        ;;
    opensim-dependencies-macos-universal2)
        CMAKE_FLAGS=(
            -DCMAKE_BUILD_TYPE=Release
            -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0
            -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"
            -DSUPERBUILD_ezc3d=ON
            -DOPENSIM_WITH_CASADI=OFF
            -DOPENSIM_WITH_TROPTER=OFF
        )
        ;;
    *)
        echo "Error: Unknown preset: $PRESET"
        echo "Supported presets: opensim-dependencies-linux, opensim-dependencies-macos-{x86_64,arm64,universal2}"
        exit 1
        ;;
esac

cmake "$SOURCE_DIR" \
    "${CMAKE_FLAGS[@]}" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"

# Build
echo "Building dependencies (this may take 15-30 minutes)..."
cmake --build . --config Release -j"$NUM_JOBS"

# Mark as complete
touch "$INSTALL_DIR/.build_complete"

echo "✓ Dependencies build complete"
echo "  Installed to: $INSTALL_DIR"
