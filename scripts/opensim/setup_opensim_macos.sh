#!/bin/bash
# Setup script for OpenSim dependencies on macOS

set -e

# Configuration
DEBUG_TYPE=${CMAKE_BUILD_TYPE:-Release}
NUM_JOBS=${CMAKE_BUILD_PARALLEL_LEVEL:-4}
OPENSIM_ROOT=$(pwd)

# Handle cibuildwheel container environment - use host-mapped cache if available
if [ -n "$PYOPENSIM_HOST_CACHE_DIR" ]; then
    echo "🐳 Detected cibuildwheel container environment"
    echo "   Host cache directory: $PYOPENSIM_HOST_CACHE_DIR"
    
    # Validate that host filesystem is accessible
    if [ -d "$(dirname "$PYOPENSIM_HOST_CACHE_DIR")" ]; then
        # Create cache directory if it doesn't exist
        mkdir -p "$PYOPENSIM_HOST_CACHE_DIR"
        WORKSPACE_DIR="$PYOPENSIM_HOST_CACHE_DIR"
        echo "   ✅ Using host-mapped cache: $WORKSPACE_DIR"
        
        # Create local symlink for easier access
        mkdir -p "$OPENSIM_ROOT/build"
        if [ ! -L "$OPENSIM_ROOT/build/opensim-workspace" ]; then
            ln -sf "$PYOPENSIM_HOST_CACHE_DIR" "$OPENSIM_ROOT/build/opensim-workspace"
            echo "   📁 Created symlink: build/opensim-workspace -> host cache"
        fi
    else
        echo "   ⚠️  Host filesystem not accessible, falling back to container-local cache"
        WORKSPACE_DIR="$OPENSIM_ROOT/build/opensim-workspace"
    fi
else
    WORKSPACE_DIR="$OPENSIM_ROOT/build/opensim-workspace"
fi

echo "Setting up OpenSim with build type: $DEBUG_TYPE using $NUM_JOBS jobs"

Help() {
    echo "Setting up OpenSim with build type $DEBUG_TYPE, using $NUM_JOBS parallel jobs."
    echo "Usage: setup_opensim_macos.sh [OLD_FLAGS] [NEW_FLAGS]"
    echo ""
    echo "Legacy flags:"
    echo "  -s          : Disable MOCO (default: enabled)"
    echo "  -d BuildType: Build type (Release, Debug, RelWithDebInfo, MinSizeRel)"
    echo "  -c Branch   : OpenSim core branch to use (default: main)"
    echo "  -j Jobs     : Number of parallel jobs (default: 4)"
    echo "  -n          : Use Ninja generator instead of Unix Makefiles"
    echo "  -h          : Show this help"
    echo ""
    echo "New flags:"
    echo "  --deps-only       : Install only system dependencies, skip OpenSim build"
    echo "  --dev             : Setup for development with wheel building tools"
    echo "  --with-wheel-tools: Same as --dev"
    echo "  --help            : Show this help"
    exit
}

# Default values for flags
MOCO="on"
CORE_BRANCH="main"
GENERATOR="Unix Makefiles"
WITH_WHEEL_TOOLS=false
DEPS_ONLY=false

# Get flag values if any.
while getopts 'j:d:s:c:nh' flag
do
    case "${flag}" in
        j) NUM_JOBS=${OPTARG};;
        d) DEBUG_TYPE=${OPTARG};;
        s) MOCO="off";;
        c) CORE_BRANCH=${OPTARG};;
        n) GENERATOR="Ninja";;
        h) Help;;
        *) Help;;
    esac
done

# Process remaining arguments for new-style flags
shift $((OPTIND-1))
while [[ $# -gt 0 ]]; do
    case $1 in
        --dev|--with-wheel-tools)
            WITH_WHEEL_TOOLS=true
            shift
            ;;
        --deps-only)
            DEPS_ONLY=true
            shift
            ;;
        --help)
            Help
            ;;
        *)
            echo "Unknown option: $1"
            Help
            ;;
    esac
done

# Check parameters are valid.
if [[ $NUM_JOBS -lt 1 ]]
then
    Help
fi
if [[ $DEBUG_TYPE != "Release" ]] && [[ $DEBUG_TYPE != "Debug" ]] && [[ $DEBUG_TYPE != "RelWithDebInfo" ]] && [[ $DEBUG_TYPE != "MinSizeRel" ]]
then
    Help
fi

# Show values of flags:
echo "DEBUG_TYPE: $DEBUG_TYPE"
echo "NUM_JOBS: $NUM_JOBS"
echo "MOCO: $MOCO"
echo "CORE_BRANCH: $CORE_BRANCH"
echo "GENERATOR: $GENERATOR"
echo "WORKSPACE_DIR: $WORKSPACE_DIR"
echo

# Create workspace
mkdir -p "$WORKSPACE_DIR"

# Cache validation with smart dependency detection
OPENSIM_COMMIT_HASH=""
if [ -d "$OPENSIM_ROOT/src/opensim-core/.git" ]; then
    OPENSIM_COMMIT_HASH=$(git -C "$OPENSIM_ROOT/src/opensim-core" rev-parse HEAD 2>/dev/null || echo "unknown")
fi

CACHE_MARKER="$WORKSPACE_DIR/.opensim_build_complete_${OPENSIM_COMMIT_HASH}"

echo "🔍 Checking for existing OpenSim build cache..."
echo "   Cache marker: $CACHE_MARKER"
echo "   OPENSIM_CACHE_HIT: ${OPENSIM_CACHE_HIT:-unset}"
echo "   Workspace directory: $WORKSPACE_DIR"
if [ "$FORCE_REBUILD_OPENSIM" = "true" ]; then
    echo "⚠ Force rebuild requested, bypassing all caches"
    rm -f "$CACHE_MARKER"
elif [ "$OPENSIM_CACHE_HIT" = "true" ] && [ -f "$CACHE_MARKER" ] && [ -f "$WORKSPACE_DIR/opensim-install/lib/libosimCommon.dylib" ]; then
    echo "✓ OpenSim build cache is valid (commit: ${OPENSIM_COMMIT_HASH:0:8}), skipping rebuild"
    echo "Cache marker found: $CACHE_MARKER"
    
    # Ensure SWIG is still in PATH for subsequent builds
    if [ -d "$HOME/swig/bin" ]; then
        export PATH="$HOME/swig/bin:$PATH"
        echo "SWIG path restored from cache"
    elif [ -d "$WORKSPACE_DIR/swig-install/bin" ]; then
        export PATH="$WORKSPACE_DIR/swig-install/bin:$PATH"
        echo "SWIG path restored from workspace cache"
    fi
    
    exit 0
fi

echo "Cache miss, proceeding with OpenSim build..."
if [ -n "$OPENSIM_COMMIT_HASH" ] && [ "$OPENSIM_COMMIT_HASH" != "unknown" ]; then
    echo "Building for OpenSim commit: ${OPENSIM_COMMIT_HASH:0:8}"
fi

# Smart dependency detection - check if we can skip SWIG/deps rebuild  
SKIP_DEPS=false
if [ "$OPENSIM_CACHE_HIT" = "true" ]; then
    if [ -d "$WORKSPACE_DIR/swig-install/bin" ] || [ -d "$HOME/swig/bin" ]; then
        if [ -d "$WORKSPACE_DIR/dependencies-install" ]; then
            echo "✓ Partial cache hit - SWIG and dependencies available, skipping deps build"
            SKIP_DEPS=true
            # Restore SWIG to PATH
            if [ -d "$HOME/swig/bin" ]; then
                export PATH="$HOME/swig/bin:$PATH"
            elif [ -d "$WORKSPACE_DIR/swig-install/bin" ]; then
                export PATH="$WORKSPACE_DIR/swig-install/bin:$PATH"
            fi
        fi
    fi
fi

# Install system dependencies
echo "Installing system dependencies..."

# Install brew package manager if not present
if ! command -v brew &> /dev/null
then
    echo "Installing Homebrew..."
    # Detect architecture and use appropriate installation method
    if [[ $(uname -m) == "arm64" ]]; then
        echo "Detected Apple Silicon (ARM64) - installing Homebrew for ARM64"
        arch -arm64 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
        # Add Homebrew to PATH for ARM64
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        echo "Detected Intel (x86_64) - installing Homebrew for x86_64"
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
        # Add Homebrew to PATH for x86_64
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/usr/local/bin/brew shellenv)"
    fi
fi

# Check and install dependencies from package manager
echo "Checking build dependencies..."

# List of required packages
REQUIRED_PACKAGES=(
    "pkgconfig"
    "autoconf" 
    "libtool"
    "automake"
    "wget"
    "pcre"
    "doxygen"
    "python"
    "git"
    "ninja"
    "cmake"
    "gcc"
)

# Add wheel building tools if requested
if [ "$WITH_WHEEL_TOOLS" = true ]; then
    echo "Including wheel building tools"
    # On macOS, wheel building tools are typically installed via pip
    # patchelf is not used on macOS (uses install_name_tool instead)
    echo "Note: On macOS, wheel building uses system tools (no additional packages needed)"
fi

# Check which packages are missing
MISSING_PACKAGES=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! brew list "$package" &>/dev/null; then
        MISSING_PACKAGES+=("$package")
    fi
done

# Only install if there are missing packages
if [ ${#MISSING_PACKAGES[@]} -eq 0 ]; then
    echo "All required build dependencies are already installed."
else
    echo "Missing packages: ${MISSING_PACKAGES[*]}"
    echo "Installing build dependencies..."
    # Use architecture-specific brew commands
    if [[ $(uname -m) == "arm64" ]]; then
        arch -arm64 brew install "${MISSING_PACKAGES[@]}"
    else
        brew install "${MISSING_PACKAGES[@]}"
    fi
fi

# # Always reinstall gcc to ensure proper version
# echo "Ensuring correct GCC version..."
# brew reinstall gcc

# Check and install Python packages
echo "Checking Python dependencies..."
PYTHON_PACKAGES=("cython" "numpy")
MISSING_PYTHON_PACKAGES=()

# Detect the correct Python executable to use
# Check if we're in a virtual environment or if a specific Python path is provided
if [[ -n "${VIRTUAL_ENV}" && -x "${VIRTUAL_ENV}/bin/python3" ]]; then
    PYTHON_EXEC="${VIRTUAL_ENV}/bin/python3"
    echo "Using virtual environment Python: $PYTHON_EXEC"
elif [[ -x "/Users/holycow/Projects/pyopensim/.venv/bin/python3" ]]; then
    PYTHON_EXEC="/Users/holycow/Projects/pyopensim/.venv/bin/python3"
    echo "Using project virtual environment Python: $PYTHON_EXEC"
else
    PYTHON_EXEC="python3"
    echo "Using system Python: $PYTHON_EXEC"
fi

for package in "${PYTHON_PACKAGES[@]}"; do
    if ! "$PYTHON_EXEC" -c "import $package" &>/dev/null; then
        MISSING_PYTHON_PACKAGES+=("$package")
    fi
done

if [ ${#MISSING_PYTHON_PACKAGES[@]} -eq 0 ]; then
    echo "All required Python packages are already installed."
else
    echo "Missing Python packages: ${MISSING_PYTHON_PACKAGES[*]}"
    # Try using the detected Python executable with -m pip
    echo "Attempting to install packages with: $PYTHON_EXEC -m pip"
    if ! "$PYTHON_EXEC" -m pip install "${MISSING_PYTHON_PACKAGES[@]}"; then
        echo "WARNING: Failed to install Python packages via pip. Continuing with build..."
        echo "Note: Make sure the required packages (${MISSING_PYTHON_PACKAGES[*]}) are available in your Python environment."
    fi
fi

echo "Checking Java 8 installation..."
# Check if Java 8 is already installed
if /usr/libexec/java_home -v 1.8 &>/dev/null; then
    echo "Java 8 is already installed."
    export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
    echo "JAVA_HOME: $JAVA_HOME"
else
    echo "Installing Java 8..."
    # Install Java 8 from Eclipse Temurin (direct cask)
    if [[ $(uname -m) == "arm64" ]]; then
        arch -arm64 brew install --cask temurin@8
    else
        brew install --cask temurin@8
    fi
    export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
    echo "JAVA_HOME: $JAVA_HOME"
fi

# Exit early if only installing dependencies
if [ "$DEPS_ONLY" = true ]; then
    echo "Dependencies installation complete."
    exit 0
fi

# Download and install SWIG 4.1.1
echo "Installing SWIG 4.1.1..."
mkdir -p "$WORKSPACE_DIR/swig-source"
cd "$WORKSPACE_DIR/swig-source"

# Check if SWIG is already installed in the expected location
if [ -f "$WORKSPACE_DIR/swig-install/bin/swig" ]; then
    echo "SWIG is already installed in workspace."
else
    echo "Downloading and building SWIG 4.1.1..."
    wget -nc -q --show-progress https://github.com/swig/swig/archive/refs/tags/v4.1.1.tar.gz
    tar xzf v4.1.1.tar.gz
    cd swig-4.1.1
    
    sh autogen.sh
    ./configure --prefix="$WORKSPACE_DIR/swig-install" --disable-ccache
    make -j$NUM_JOBS
    make install
fi

# Build OpenSim dependencies
echo "Building OpenSim dependencies..."
# Clean any existing cache to avoid path conflicts during pip builds
rm -rf "$WORKSPACE_DIR/opensim-dependencies-build"
mkdir -p "$WORKSPACE_DIR/opensim-dependencies-build"
cd "$WORKSPACE_DIR/opensim-dependencies-build"

# Detect architecture and set appropriate flags
# Check if we're building universal2 wheels (detected by CMAKE_OSX_ARCHITECTURES environment variable)
if [[ -n "${CMAKE_OSX_ARCHITECTURES}" ]]; then
    CMAKE_ARCH_FLAGS="-DCMAKE_OSX_ARCHITECTURES=${CMAKE_OSX_ARCHITECTURES}"
    echo "Building for architectures specified by CMAKE_OSX_ARCHITECTURES: ${CMAKE_OSX_ARCHITECTURES}"
elif [[ -n "${ARCHFLAGS}" && "${ARCHFLAGS}" == *"universal2"* ]]; then
    CMAKE_ARCH_FLAGS="-DCMAKE_OSX_ARCHITECTURES=x86_64;arm64"
    echo "Building universal2 (x86_64;arm64) from ARCHFLAGS"
else
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        CMAKE_ARCH_FLAGS="-DCMAKE_OSX_ARCHITECTURES=arm64"
        echo "Building for Apple Silicon (arm64)"
    else
        CMAKE_ARCH_FLAGS="-DCMAKE_OSX_ARCHITECTURES=x86_64"
        echo "Building for Intel Mac (x86_64)"
    fi
fi

cmake "$OPENSIM_ROOT/src/opensim-core/dependencies" \
    -DCMAKE_INSTALL_PREFIX="$WORKSPACE_DIR/opensim-dependencies-install" \
    -DCMAKE_BUILD_TYPE=$DEBUG_TYPE \
    -DCMAKE_BUILD_PARALLEL_LEVEL=$NUM_JOBS \
    $CMAKE_ARCH_FLAGS \
    -DSUPERBUILD_ezc3d=ON \
    -DOPENSIM_WITH_CASADI=OFF \
    -DOPENSIM_WITH_TROPTER=OFF \
    -DOPENSIM_WITH_MOCO=OFF

cmake --build . --config $DEBUG_TYPE -j$NUM_JOBS

# Build OpenSim core
echo "Building OpenSim core..."
# Clean any existing cache to avoid path conflicts during pip builds
rm -rf "$WORKSPACE_DIR/opensim-build"
mkdir -p "$WORKSPACE_DIR/opensim-build"
cd "$WORKSPACE_DIR/opensim-build"

cmake "$OPENSIM_ROOT/src/opensim-core" \
    -G"$GENERATOR" \
    -DCMAKE_INSTALL_PREFIX="$WORKSPACE_DIR/opensim-install" \
    -DCMAKE_BUILD_TYPE=$DEBUG_TYPE \
    -DCMAKE_BUILD_PARALLEL_LEVEL=$NUM_JOBS \
    $CMAKE_ARCH_FLAGS \
    -DCMAKE_CXX_FLAGS="-Wno-array-bounds" \
    -DOPENSIM_DEPENDENCIES_DIR="$WORKSPACE_DIR/opensim-dependencies-install" \
    -DBUILD_JAVA_WRAPPING=OFF \
    -DBUILD_PYTHON_WRAPPING=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_API_EXAMPLES=OFF \
    -DOPENSIM_C3D_PARSER=ezc3d \
    -DOPENSIM_WITH_CASADI=OFF \
    -DOPENSIM_WITH_TROPTER=OFF \
    -DOPENSIM_WITH_MOCO=OFF \
    -DOPENSIM_INSTALL_UNIX_FHS=OFF \
    -DSWIG_DIR="$WORKSPACE_DIR/swig-install/share/swig" \
    -DSWIG_EXECUTABLE="$WORKSPACE_DIR/swig-install/bin/swig" \
    -DJAVA_HOME="$JAVA_HOME" \
    -DJAVA_INCLUDE_PATH="$JAVA_HOME/include" \
    -DJAVA_INCLUDE_PATH2="$JAVA_HOME/include/darwin" \
    -DJAVA_AWT_INCLUDE_PATH="$JAVA_HOME/include"

cmake --build . --config $DEBUG_TYPE -j$NUM_JOBS
cmake --install .

# Create cache completion marker
if [ -n "$OPENSIM_COMMIT_HASH" ] && [ "$OPENSIM_COMMIT_HASH" != "unknown" ]; then
    touch "$CACHE_MARKER"
    echo "✓ Cache marker created: $CACHE_MARKER"
fi

echo "OpenSim setup complete. Libraries installed in: $WORKSPACE_DIR/opensim-install"