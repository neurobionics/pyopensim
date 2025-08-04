#!/bin/bash
# Setup script for OpenSim dependencies

set -e

# Configuration
DEBUG_TYPE=${CMAKE_BUILD_TYPE:-Release}
NUM_JOBS=${CMAKE_BUILD_PARALLEL_LEVEL:-4}
OPENSIM_ROOT=$(pwd)
WORKSPACE_DIR="$OPENSIM_ROOT/build/opensim-workspace"

# Parse command line arguments
DEPS_ONLY=false
EXTRA_PACKAGES=()
WITH_WHEEL_TOOLS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --deps-only)
            DEPS_ONLY=true
            shift
            ;;
        --extra-packages)
            shift
            while [[ $# -gt 0 && ! $1 == --* ]]; do
                EXTRA_PACKAGES+=("$1")
                shift
            done
            ;;
        --with-wheel-tools)
            WITH_WHEEL_TOOLS=true
            shift
            ;;
        --dev)
            # Shorthand for development setup with wheel building tools
            WITH_WHEEL_TOOLS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --deps-only         Install only system dependencies, skip OpenSim build"
            echo "  --with-wheel-tools  Install tools needed for wheel building (patchelf, etc.)"
            echo "  --dev               Alias for --with-wheel-tools"
            echo "  --extra-packages    Additional packages to install"
            echo "  -h, --help          Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "Setting up OpenSim with build type: $DEBUG_TYPE using $NUM_JOBS jobs"
if [ "$DEPS_ONLY" = true ]; then
    echo "Running in dependencies-only mode"
fi

# Create workspace
mkdir -p "$WORKSPACE_DIR"

# Check system dependencies
echo "Checking system dependencies..."

# List of required packages
REQUIRED_PACKAGES=(
    "build-essential"
    "cmake"
    "autotools-dev"
    "autoconf"
    "pkg-config"
    "automake"
    "libopenblas-dev"
    "liblapack-dev"
    "freeglut3-dev"
    "libxi-dev"
    "libxmu-dev"
    "doxygen"
    "python3-dev"
    "git"
    "libssl-dev"
    "libpcre3-dev"
    "libpcre2-dev"
    "libtool"
    "gfortran"
    "ninja-build"
    "patchelf"
    "openjdk-8-jdk"
    "wget"
    "bison"
    "byacc"
)

# Add wheel building tools if requested
if [ "$WITH_WHEEL_TOOLS" = true ]; then
    echo "Including wheel building tools"
    REQUIRED_PACKAGES+=("patchelf")
fi

# Add extra packages if specified
for pkg in "${EXTRA_PACKAGES[@]}"; do
    REQUIRED_PACKAGES+=("$pkg")
done

# Check which packages are missing
MISSING_PACKAGES=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    # Check if package is installed (handles architecture suffixes like :amd64)
    if ! dpkg -l | grep -q "^ii  $package\(:\|[[:space:]]\)"; then
        MISSING_PACKAGES+=("$package")
    fi
done 2>/dev/null

# Only install if there are missing packages
if [ ${#MISSING_PACKAGES[@]} -eq 0 ]; then
    echo "All required system dependencies are already installed."
else
    echo "Missing packages: ${MISSING_PACKAGES[*]}"
    echo "Installing system dependencies..."
    # Check if we're in a container environment (like manylinux) where sudo might not be available
    if command -v sudo >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y "${MISSING_PACKAGES[@]}"
    else
        # Try without sudo (container environments often run as root)
        apt-get update && apt-get install -y "${MISSING_PACKAGES[@]}"
    fi
fi

# Exit early if only installing dependencies
if [ "$DEPS_ONLY" = true ]; then
    echo "Dependencies installation complete."
    exit 0
fi

# Download and install SWIG 4.1.1
echo "Installing SWIG 4.1.1..."
mkdir -p "$WORKSPACE_DIR/swig-source" && cd "$WORKSPACE_DIR/swig-source"
if [ ! -f "v4.1.1.tar.gz" ]; then
    # Try wget first, fallback to curl if not available
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress https://github.com/swig/swig/archive/refs/tags/v4.1.1.tar.gz
    elif command -v curl >/dev/null 2>&1; then
        curl -L -o v4.1.1.tar.gz https://github.com/swig/swig/archive/refs/tags/v4.1.1.tar.gz
    else
        echo "Error: Neither wget nor curl is available for downloading SWIG"
        exit 1
    fi
fi
if [ ! -d "swig-4.1.1" ]; then
    tar xzf v4.1.1.tar.gz
fi
cd swig-4.1.1
if [ ! -f "configure" ]; then
    sh autogen.sh
fi
if [ ! -f "Makefile" ]; then
    ./configure --prefix="$HOME/swig" --disable-ccache
fi
make -j$NUM_JOBS && make install
echo "SWIG installation complete."

# Add SWIG to PATH for the rest of the script
export PATH="$HOME/swig/bin:$PATH"

# Build OpenSim dependencies
echo "Building OpenSim dependencies..."
mkdir -p "$WORKSPACE_DIR/dependencies-build"
cd "$WORKSPACE_DIR/dependencies-build"

cmake "$OPENSIM_ROOT/src/opensim-core/dependencies" \
    -DCMAKE_INSTALL_PREFIX="$WORKSPACE_DIR/dependencies-install" \
    -DCMAKE_BUILD_TYPE=$DEBUG_TYPE \
    -DSUPERBUILD_ezc3d=ON \
    -DOPENSIM_WITH_CASADI=OFF

cmake --build . --config $DEBUG_TYPE -j$NUM_JOBS

# Build OpenSim core
echo "Building OpenSim core..."
mkdir -p "$WORKSPACE_DIR/opensim-build"
cd "$WORKSPACE_DIR/opensim-build"

cmake "$OPENSIM_ROOT/src/opensim-core" \
    -DCMAKE_INSTALL_PREFIX="$WORKSPACE_DIR/opensim-install" \
    -DCMAKE_BUILD_TYPE=$DEBUG_TYPE \
    -DOPENSIM_DEPENDENCIES_DIR="$WORKSPACE_DIR/dependencies-install" \
    -DCMAKE_PREFIX_PATH="$WORKSPACE_DIR/dependencies-install" \
    -DBUILD_JAVA_WRAPPING=OFF \
    -DBUILD_PYTHON_WRAPPING=OFF \
    -DBUILD_TESTING=OFF \
    -DOPENSIM_C3D_PARSER=ezc3d \
    -DOPENSIM_WITH_CASADI=OFF \
    -DOPENSIM_INSTALL_UNIX_FHS=OFF

cmake --build . --config $DEBUG_TYPE -j$NUM_JOBS
cmake --install .

echo "OpenSim setup complete. Libraries installed in: $WORKSPACE_DIR/opensim-install"