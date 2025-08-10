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

echo "Building OpenSim from scratch..."

# Check system dependencies
echo "Checking system dependencies..."

# Detect package manager and set packages accordingly
if command -v apk >/dev/null 2>&1; then
    echo "Detected Alpine Linux (musllinux) with apk"
    PACKAGE_MANAGER="apk"
    REQUIRED_PACKAGES=(
        "gcc" "g++" "make" "musl-dev"
        "cmake"
        "autoconf" "automake" "libtool"
        "pkgconfig" "pkgconf-dev"
        "openblas-dev"
        "lapack-dev"
        "mesa-dev" "freeglut-dev"
        "libxi-dev"
        "libxmu-dev"
        "doxygen"
        "python3-dev" "py3-setuptools"
        "git"
        "openssl-dev"
        "pcre-dev"
        "pcre2-dev"
        "gcc-gfortran"
        "patchelf"
        "openjdk8-jre-base"
        "wget"
        "bison"
        "byacc"
        "linux-headers"
    )
elif command -v dnf >/dev/null 2>&1; then
    echo "Detected modern RHEL/AlmaLinux (manylinux_2_28+) with dnf"
    PACKAGE_MANAGER="dnf"
    REQUIRED_PACKAGES=(
        "gcc" "gcc-c++" "make"
        "cmake"
        "autoconf" "automake" "libtool"
        "pkgconfig"
        "openblas-devel"
        "lapack-devel" 
        "freeglut-devel"
        "libXi-devel"
        "libXmu-devel"
        "doxygen"
        "python3-devel"
        "git"
        "openssl-devel"
        "pcre-devel"
        "pcre2-devel"
        "gcc-gfortran"
        "patchelf"
        "java-1.8.0-openjdk-devel"
        "wget"
        "bison"
        "byacc"
    )
elif command -v yum >/dev/null 2>&1; then
    echo "Detected legacy RHEL/CentOS (manylinux2014) with yum"
    PACKAGE_MANAGER="yum"
    REQUIRED_PACKAGES=(
        "gcc" "gcc-c++" "make"
        "cmake3"
        "autoconf" "automake" "libtool"
        "pkgconfig"
        "openblas-devel"
        "lapack-devel" 
        "freeglut-devel"
        "libXi-devel"
        "libXmu-devel"
        "doxygen"
        "python3-devel"
        "git"
        "openssl-devel"
        "pcre-devel"
        "pcre2-devel"
        "gcc-gfortran"
        "patchelf"
        "java-1.8.0-openjdk-devel"
        "wget"
        "bison"
        "byacc"
    )
elif command -v apt-get >/dev/null 2>&1; then
    echo "Detected Debian/Ubuntu environment with apt"
    PACKAGE_MANAGER="apt"
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
        "python3-dev" "python3-setuptools"
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
else
    echo "Warning: No supported package manager found (apk/dnf/yum/apt-get)"
    echo "Manual package installation may be required"
    PACKAGE_MANAGER="none"
    REQUIRED_PACKAGES=()
fi

# Add wheel building tools if requested
if [ "$WITH_WHEEL_TOOLS" = true ]; then
    echo "Including wheel building tools"
    REQUIRED_PACKAGES+=("patchelf")
fi

# Add extra packages if specified
for pkg in "${EXTRA_PACKAGES[@]}"; do
    REQUIRED_PACKAGES+=("$pkg")
done

# Check which packages are missing based on package manager
MISSING_PACKAGES=()

if [ "$PACKAGE_MANAGER" = "none" ]; then
    echo "No package manager available - skipping dependency check"
elif [ "$PACKAGE_MANAGER" = "apk" ]; then
    # Check if packages are installed using apk
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! apk info -e "$package" >/dev/null 2>&1; then
            MISSING_PACKAGES+=("$package")
        fi
    done
elif [ "$PACKAGE_MANAGER" = "dnf" ] || [ "$PACKAGE_MANAGER" = "yum" ]; then
    # Check if packages are installed using rpm (works for both yum and dnf)
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! rpm -q "$package" >/dev/null 2>&1; then
            MISSING_PACKAGES+=("$package")
        fi
    done
elif [ "$PACKAGE_MANAGER" = "apt" ]; then
    # Check if packages are installed using dpkg
    for package in "${REQUIRED_PACKAGES[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package\(:\|[[:space:]]\)" 2>/dev/null; then
            MISSING_PACKAGES+=("$package")
        fi
    done
fi

# Only install if there are missing packages
if [ ${#MISSING_PACKAGES[@]} -eq 0 ]; then
    echo "All required system dependencies are already installed."
elif [ "$PACKAGE_MANAGER" = "none" ]; then
    echo "No package manager available - please install dependencies manually"
else
    echo "Missing packages: ${MISSING_PACKAGES[*]}"
    echo "Installing system dependencies using $PACKAGE_MANAGER..."
    
    if [ "$PACKAGE_MANAGER" = "apk" ]; then
        # Alpine Linux (musllinux) - usually running as root
        apk add --no-cache "${MISSING_PACKAGES[@]}"
    elif [ "$PACKAGE_MANAGER" = "dnf" ]; then
        # Modern RHEL/AlmaLinux (manylinux_2_28+) - usually running as root
        echo "Attempting to install packages with dnf..."
        # Try to install packages, allowing some to fail
        for package in "${MISSING_PACKAGES[@]}"; do
            echo "Installing $package..."
            if ! dnf install -y "$package" 2>/dev/null; then
                echo "Warning: Failed to install $package, continuing..."
            fi
        done
    elif [ "$PACKAGE_MANAGER" = "yum" ]; then
        # Legacy RHEL/CentOS (manylinux2014) - usually running as root
        echo "Attempting to install packages with yum..."
        # Try to install packages, allowing some to fail
        for package in "${MISSING_PACKAGES[@]}"; do
            echo "Installing $package..."
            if ! yum install -y "$package" 2>/dev/null; then
                echo "Warning: Failed to install $package, continuing..."
            fi
        done
    elif [ "$PACKAGE_MANAGER" = "apt" ]; then
        # Ubuntu/Debian environment (manylinux_2_31 armv7l or native Ubuntu)
        if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            sudo apt-get update && sudo apt-get install -y "${MISSING_PACKAGES[@]}"
        elif [ "$EUID" -eq 0 ]; then
            apt-get update && apt-get install -y "${MISSING_PACKAGES[@]}"
        else
            echo "Warning: Cannot install packages - no sudo access and not running as root"
        fi
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
# Try wget first, fallback to curl if not available
if command -v wget >/dev/null 2>&1; then
    wget -q --show-progress https://github.com/swig/swig/archive/refs/tags/v4.1.1.tar.gz
elif command -v curl >/dev/null 2>&1; then
    curl -L -o v4.1.1.tar.gz https://github.com/swig/swig/archive/refs/tags/v4.1.1.tar.gz
else
    echo "Error: Neither wget nor curl is available for downloading SWIG"
    exit 1
fi
tar xzf v4.1.1.tar.gz
cd swig-4.1.1
sh autogen.sh
./configure --prefix="$HOME/swig"
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
echo "✓ Dependencies build complete"

# Build OpenSim core
echo "Building OpenSim core..."
mkdir -p "$WORKSPACE_DIR/opensim-build"
cd "$WORKSPACE_DIR/opensim-build"

cmake "$OPENSIM_ROOT/src/opensim-core" \
    -DCMAKE_INSTALL_PREFIX="$WORKSPACE_DIR/opensim-install" \
    -DCMAKE_BUILD_TYPE=$DEBUG_TYPE \
    -DCMAKE_CXX_FLAGS="-pthread -Wno-array-bounds" \
    -DOPENSIM_DEPENDENCIES_DIR="$WORKSPACE_DIR/dependencies-install" \
    -DCMAKE_PREFIX_PATH="$WORKSPACE_DIR/dependencies-install" \
    -DBUILD_JAVA_WRAPPING=OFF \
    -DBUILD_PYTHON_WRAPPING=OFF \
    -DBUILD_TESTING=OFF \
    -DBUILD_API_EXAMPLES=OFF \
    -DOPENSIM_C3D_PARSER=ezc3d \
    -DOPENSIM_WITH_CASADI=OFF \
    -DOPENSIM_WITH_TROPTER=OFF \
    -DOPENSIM_WITH_MOCO=OFF \
    -DOPENSIM_INSTALL_UNIX_FHS=OFF \
    -DSWIG_DIR="$HOME/swig/share/swig" \
    -DSWIG_EXECUTABLE="$HOME/swig/bin/swig"

cmake --build . --config $DEBUG_TYPE -j$NUM_JOBS
cmake --install .


echo "OpenSim setup complete. Libraries installed in: $WORKSPACE_DIR/opensim-install"