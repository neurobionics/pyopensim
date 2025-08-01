#!/bin/bash
# Setup script for OpenSim dependencies on macOS

set -e

# Configuration
DEBUG_TYPE=${CMAKE_BUILD_TYPE:-Release}
NUM_JOBS=${CMAKE_BUILD_PARALLEL_LEVEL:-4}
OPENSIM_ROOT=$(pwd)
WORKSPACE_DIR="$OPENSIM_ROOT/build/opensim-workspace"

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

# Install system dependencies
echo "Installing system dependencies..."

# Install brew package manager if not present
if ! command -v brew &> /dev/null
then
    echo "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" < /dev/null
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
    brew install "${MISSING_PACKAGES[@]}"
fi

# Always reinstall gcc to ensure proper version
echo "Ensuring correct GCC version..."
brew reinstall gcc

# Check and install Python packages
echo "Checking Python dependencies..."
PYTHON_PACKAGES=("cython" "numpy")
MISSING_PYTHON_PACKAGES=()

for package in "${PYTHON_PACKAGES[@]}"; do
    if ! python3 -c "import $package" &>/dev/null; then
        MISSING_PYTHON_PACKAGES+=("$package")
    fi
done

if [ ${#MISSING_PYTHON_PACKAGES[@]} -eq 0 ]; then
    echo "All required Python packages are already installed."
else
    echo "Missing Python packages: ${MISSING_PYTHON_PACKAGES[*]}"
    pip3 install "${MISSING_PYTHON_PACKAGES[@]}"
fi

echo "Checking Java 8 installation..."
# Check if Java 8 is already installed
if /usr/libexec/java_home -v 1.8 &>/dev/null; then
    echo "Java 8 is already installed."
    export JAVA_HOME=$(/usr/libexec/java_home -v 1.8)
    echo "JAVA_HOME: $JAVA_HOME"
else
    echo "Installing Java 8..."
    # Install Java 8 from temurin repositories
    brew install --cask temurin8
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
mkdir -p "$WORKSPACE_DIR/opensim-dependencies-build"
cd "$WORKSPACE_DIR/opensim-dependencies-build"

cmake "$OPENSIM_ROOT/opensim-core/dependencies" \
    -DCMAKE_INSTALL_PREFIX="$WORKSPACE_DIR/opensim-dependencies-install" \
    -DCMAKE_BUILD_TYPE=$DEBUG_TYPE \
    -DSUPERBUILD_ezc3d=ON \
    -DOPENSIM_WITH_CASADI=$MOCO

cmake --build . --config $DEBUG_TYPE -j$NUM_JOBS

# Build OpenSim core
echo "Building OpenSim core..."
mkdir -p "$WORKSPACE_DIR/opensim-build"
cd "$WORKSPACE_DIR/opensim-build"

cmake "$OPENSIM_ROOT/opensim-core" \
    -G"$GENERATOR" \
    -DCMAKE_INSTALL_PREFIX="$WORKSPACE_DIR/opensim-install" \
    -DCMAKE_BUILD_TYPE=$DEBUG_TYPE \
    -DOPENSIM_DEPENDENCIES_DIR="$WORKSPACE_DIR/opensim-dependencies-install" \
    -DBUILD_JAVA_WRAPPING=OFF \
    -DBUILD_PYTHON_WRAPPING=OFF \
    -DBUILD_TESTING=OFF \
    -DOPENSIM_C3D_PARSER=ezc3d \
    -DOPENSIM_WITH_CASADI=$MOCO \
    -DOPENSIM_INSTALL_UNIX_FHS=OFF \
    -DSWIG_DIR="$WORKSPACE_DIR/swig-install/share/swig" \
    -DSWIG_EXECUTABLE="$WORKSPACE_DIR/swig-install/bin/swig" \
    -DJAVA_HOME="$JAVA_HOME" \
    -DJAVA_INCLUDE_PATH="$JAVA_HOME/include" \
    -DJAVA_INCLUDE_PATH2="$JAVA_HOME/include/darwin" \
    -DJAVA_AWT_INCLUDE_PATH="$JAVA_HOME/include"

cmake --build . --config $DEBUG_TYPE -j$NUM_JOBS
cmake --install .

echo "OpenSim setup complete. Libraries installed in: $WORKSPACE_DIR/opensim-install"