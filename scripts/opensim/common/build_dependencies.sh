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

# Get CMake flags from CMakePresets.json
# Note: We can't use --preset here because the dependencies directory doesn't have CMakePresets.json
# Instead, we extract the flags from the preset using parse_preset.py and pass them directly
echo "Configuring dependencies with flags from preset: $PRESET"

# Get script directory to locate parse_preset.py
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Find the repository root (CMakePresets.json location)
# The common directory is at scripts/opensim/common/, so go up 3 levels
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PRESETS_FILE="$REPO_ROOT/CMakePresets.json"

if [ ! -f "$PRESETS_FILE" ]; then
    echo "Error: CMakePresets.json not found at: $PRESETS_FILE"
    exit 1
fi

# Extract CMake flags from preset using Python parser
CMAKE_FLAGS=$(python3 "$SCRIPT_DIR/parse_preset.py" "$PRESETS_FILE" "$PRESET")

if [ $? -ne 0 ]; then
    echo "Error: Failed to parse preset '$PRESET'"
    exit 1
fi

echo "  CMake flags: $CMAKE_FLAGS"

# Use eval to properly handle quoted arguments in CMAKE_FLAGS
eval cmake "$SOURCE_DIR" \
    $CMAKE_FLAGS \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"

# Build
echo "Building dependencies (this may take 15-30 minutes)..."
cmake --build . --config Release -j"$NUM_JOBS"

# Mark as complete
touch "$INSTALL_DIR/.build_complete"

echo "✓ Dependencies build complete"
echo "  Installed to: $INSTALL_DIR"
