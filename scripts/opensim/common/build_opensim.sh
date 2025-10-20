#!/bin/bash
# Common OpenSim core build script
# Builds OpenSim core using CMake presets
#
# Usage:
#   build_opensim.sh --source-dir <path> --build-dir <path> --install-dir <path> \
#                    --deps-dir <path> --swig-dir <path> --swig-exe <path> \
#                    --preset <name> [--jobs <n>]
#
# Required arguments:
#   --source-dir:  Path to opensim-core directory
#   --build-dir:   Directory for build files
#   --install-dir: Directory to install OpenSim
#   --deps-dir:    Directory where dependencies are installed
#   --swig-dir:    Path to SWIG share directory
#   --swig-exe:    Path to SWIG executable
#   --preset:      CMake preset name (e.g., opensim-core-linux)
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
DEPS_DIR=""
SWIG_DIR=""
SWIG_EXE=""
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
        --deps-dir)
            DEPS_DIR="$2"
            shift 2
            ;;
        --swig-dir)
            SWIG_DIR="$2"
            shift 2
            ;;
        --swig-exe)
            SWIG_EXE="$2"
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
            echo "Usage: $0 --source-dir <path> --build-dir <path> --install-dir <path> \\"
            echo "          --deps-dir <path> --swig-dir <path> --swig-exe <path> \\"
            echo "          --preset <name> [--jobs <n>] [--force]"
            echo ""
            echo "Required arguments:"
            echo "  --source-dir <path>   Path to opensim-core directory"
            echo "  --build-dir <path>    Directory for build files"
            echo "  --install-dir <path>  Directory to install OpenSim"
            echo "  --deps-dir <path>     Directory where dependencies are installed"
            echo "  --swig-dir <path>     Path to SWIG share directory"
            echo "  --swig-exe <path>     Path to SWIG executable"
            echo "  --preset <name>       CMake preset name (e.g., opensim-core-linux)"
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
if [ -z "$SOURCE_DIR" ] || [ -z "$BUILD_DIR" ] || [ -z "$INSTALL_DIR" ] || \
   [ -z "$DEPS_DIR" ] || [ -z "$SWIG_DIR" ] || [ -z "$SWIG_EXE" ] || [ -z "$PRESET" ]; then
    echo "Error: Missing required arguments"
    echo "Run with --help for usage information"
    exit 1
fi

# Validate paths
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory does not exist: $SOURCE_DIR"
    exit 1
fi

if [ ! -d "$DEPS_DIR" ]; then
    echo "Error: Dependencies directory does not exist: $DEPS_DIR"
    exit 1
fi

if [ ! -f "$SWIG_EXE" ]; then
    echo "Error: SWIG executable not found: $SWIG_EXE"
    exit 1
fi

# Check if already built
if [ -f "$INSTALL_DIR/.build_complete" ] && [ "$FORCE_REBUILD" = false ]; then
    echo "✓ OpenSim already built at $INSTALL_DIR"
    echo "  Use --force to rebuild"
    exit 0
fi

if [ "$FORCE_REBUILD" = true ]; then
    echo "Force rebuild requested - removing existing build and install directories"
    rm -rf "$BUILD_DIR" "$INSTALL_DIR"
fi

echo "=== Building OpenSim Core ==="
echo "  Source:       $SOURCE_DIR"
echo "  Build:        $BUILD_DIR"
echo "  Install:      $INSTALL_DIR"
echo "  Dependencies: $DEPS_DIR"
echo "  SWIG exe:     $SWIG_EXE"
echo "  SWIG dir:     $SWIG_DIR"
echo "  Preset:       $PRESET"
echo "  Jobs:         $NUM_JOBS"

# Create build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Find and copy CMakePresets.json to source directory if it exists in the repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../" && pwd)"
if [ -f "$REPO_ROOT/CMakePresets.json" ]; then
    echo "Copying CMakePresets.json to OpenSim source directory..."
    cp "$REPO_ROOT/CMakePresets.json" "$SOURCE_DIR/"
fi

# Configure using CMake preset
echo "Configuring with CMake preset: $PRESET"
cmake "$SOURCE_DIR" \
    --preset "$PRESET" \
    -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR" \
    -DOPENSIM_INSTALL_DIR="$INSTALL_DIR" \
    -DOPENSIM_DEPENDENCIES_DIR="$DEPS_DIR" \
    -DCMAKE_PREFIX_PATH="$DEPS_DIR" \
    -DSWIG_DIR="$SWIG_DIR" \
    -DSWIG_EXECUTABLE="$SWIG_EXE"

# Build
echo "Building OpenSim core (this may take 20-40 minutes)..."
cmake --build . --config Release -j"$NUM_JOBS"

# Install
echo "Installing OpenSim..."
cmake --install .

# Mark as complete
touch "$INSTALL_DIR/.build_complete"

echo "✓ OpenSim build complete"
echo "  Installed to: $INSTALL_DIR"

# Verify critical libraries exist
echo "Verifying installation..."
if [ -d "$INSTALL_DIR/sdk/lib" ]; then
    echo "✓ Found SDK libraries"
    ls "$INSTALL_DIR/sdk/lib/" | head -10
else
    echo "Warning: SDK lib directory not found"
fi
