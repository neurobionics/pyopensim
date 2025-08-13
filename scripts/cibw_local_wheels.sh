#!/bin/bash

# Local cibuildwheel test script
# This script mimics the GitHub Actions environment for testing wheel builds locally

set -e

echo "🔧 Setting up local cibuildwheel environment..."

# Ensure cache directory exists to prevent path validation errors
echo "📁 Creating cache directory structure..."
mkdir -p opensim-cache

# Export environment variables matching the CI configuration
export CIBW_ARCHS_MACOS="universal2"
export CIBW_ARCHS_WINDOWS="x86_64"
export CIBW_ARCHS_LINUX="x86_64"
export CIBW_SKIP="*musllinux*"
# Use manylinux_2_28 for broader compatibility while still having modern tooling
export CIBW_MANYLINUX_X86_64_IMAGE="manylinux_2_28"
export CIBW_MANYLINUX_I686_IMAGE="manylinux_2_28"
export CIBW_MANYLINUX_AARCH64_IMAGE="manylinux_2_28"
export CIBW_MANYLINUX_PPC64LE_IMAGE="manylinux_2_28"
export CIBW_MANYLINUX_S390X_IMAGE="manylinux_2_28"

# macOS specific environment
if [[ "$OSTYPE" == "darwin"* ]]; then
    export CIBW_BEFORE_BUILD_MACOS="echo '=== Building OpenSim for macOS ===' && PROJECT_ROOT=\"\$(pwd)\" && CACHE_DIR=\"\$PROJECT_ROOT/opensim-cache/macos-universal2\" && OPENSIM_INSTALL=\"\$CACHE_DIR/opensim-install\" && if [ \"$REBUILD_CACHE\" = \"true\" ]; then echo '🔄 Force rebuild requested - removing existing cache' && rm -rf \"\$OPENSIM_INSTALL\" \"\$CACHE_DIR/dependencies-install\" \"\$CACHE_DIR/swig\"; fi && if [ -d \"\$OPENSIM_INSTALL\" ] && [ -f \"\$OPENSIM_INSTALL/.build_complete\" ]; then echo '✓ Using cached OpenSim build from \$OPENSIM_INSTALL'; else echo 'Building OpenSim from scratch...' && brew install cmake autoconf automake libtool pkgconfig && mkdir -p \"\$CACHE_DIR\" && cd \"\$CACHE_DIR\" && curl -L https://github.com/swig/swig/archive/v4.1.1.tar.gz | tar xz && cd swig-4.1.1 && ./autogen.sh && ./configure --prefix=\"\$CACHE_DIR/swig\" && make -j\$(sysctl -n hw.ncpu) && make install && cd .. && rm -rf swig-4.1.1 && export PATH=\"\$CACHE_DIR/swig/bin:\$PATH\" && mkdir -p dependencies-build && cd dependencies-build && cmake \"\$PROJECT_ROOT/src/opensim-core/dependencies\" -DCMAKE_INSTALL_PREFIX=\"\$CACHE_DIR/dependencies-install\" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=\"x86_64;arm64\" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DSUPERBUILD_ezc3d=ON -DOPENSIM_WITH_CASADI=OFF && cmake --build . --config Release -j\$(sysctl -n hw.ncpu) && cd .. && mkdir -p opensim-build && cd opensim-build && cmake \"\$PROJECT_ROOT/src/opensim-core\" -DCMAKE_INSTALL_PREFIX=\"\$OPENSIM_INSTALL\" -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=\"x86_64;arm64\" -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 -DOPENSIM_DEPENDENCIES_DIR=\"\$CACHE_DIR/dependencies-install\" -DCMAKE_PREFIX_PATH=\"\$CACHE_DIR/dependencies-install\" -DBUILD_JAVA_WRAPPING=OFF -DBUILD_PYTHON_WRAPPING=OFF -DBUILD_TESTING=OFF -DBUILD_API_EXAMPLES=OFF -DOPENSIM_C3D_PARSER=ezc3d -DOPENSIM_WITH_CASADI=OFF -DOPENSIM_WITH_TROPTER=OFF -DOPENSIM_WITH_MOCO=OFF -DOPENSIM_INSTALL_UNIX_FHS=OFF -DSWIG_DIR=\"\$CACHE_DIR/swig/share/swig\" -DSWIG_EXECUTABLE=\"\$CACHE_DIR/swig/bin/swig\" && cmake --build . --config Release -j\$(sysctl -n hw.ncpu) && cmake --install . && touch \"\$OPENSIM_INSTALL/.build_complete\" && echo '✓ OpenSim build complete'; fi && export PATH=\"\$CACHE_DIR/swig/bin:\$PATH\" && export OPENSIM_INSTALL_DIR=\"\$OPENSIM_INSTALL\""
    export CIBW_ENVIRONMENT_MACOS="MACOSX_DEPLOYMENT_TARGET=14.0 CMAKE_OSX_ARCHITECTURES=x86_64;arm64 OPENSIM_INSTALL_DIR=\$(pwd)/opensim-cache/macos-universal2/opensim-install"
    export CIBW_REPAIR_WHEEL_COMMAND_MACOS="echo '=== Repairing macOS wheel ===' && OPENSIM_INSTALL=\"\$(pwd)/opensim-cache/macos-universal2/opensim-install\" && DYLD_LIBRARY_PATH=\"\$OPENSIM_INSTALL/sdk/lib:\$OPENSIM_INSTALL/sdk/Simbody/lib\" delocate-wheel -w {dest_dir} -v {wheel}"
    echo "🍎 Configured for macOS build"
fi

# Linux specific environment  
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    export CIBW_BEFORE_BUILD_LINUX="echo '=== Building OpenSim inside manylinux container ===' && echo 'DEBUG: Container environment info:' && echo '  PWD: \$(pwd)' && echo '  USER: \$(whoami)' && echo '  ARCH: \$(uname -m)' && echo '  OS: \$(cat /etc/os-release | head -2)' && OPENSIM_ROOT=\"\$(pwd)\" && CACHE_DIR=\"/host\$(pwd)/opensim-cache/linux-\$(uname -m)\" && OPENSIM_INSTALL=\"\$CACHE_DIR/opensim-install\" && echo 'DEBUG: Path variables:' && echo '  OPENSIM_ROOT: \$OPENSIM_ROOT' && echo '  CACHE_DIR: \$CACHE_DIR' && echo '  OPENSIM_INSTALL: \$OPENSIM_INSTALL' && echo 'DEBUG: Checking critical paths:' && echo '  ls -la \$OPENSIM_ROOT/src/:' && ls -la \"\$OPENSIM_ROOT/src/\" || echo 'ERROR: src directory not found' && echo '  ls -la \$OPENSIM_ROOT/src/opensim-core/:' && ls -la \"\$OPENSIM_ROOT/src/opensim-core/\" || echo 'ERROR: opensim-core directory not found' && echo '  ls -la \$OPENSIM_ROOT/src/opensim-core/dependencies/:' && ls -la \"\$OPENSIM_ROOT/src/opensim-core/dependencies/\" || echo 'ERROR: dependencies directory not found' && if [ \"$REBUILD_CACHE\" = \"true\" ]; then echo '🔄 Force rebuild requested - removing existing cache' && rm -rf \"\$OPENSIM_INSTALL\" \"\$CACHE_DIR/dependencies-install\" \"\$CACHE_DIR/swig\"; fi && if [ -d \"\$OPENSIM_INSTALL\" ] && [ -f \"\$OPENSIM_INSTALL/.build_complete\" ]; then echo '✓ Using cached OpenSim build from \$OPENSIM_INSTALL' && ls -la \"\$OPENSIM_INSTALL/sdk/lib/\" || true; else echo 'Building OpenSim from scratch...' && dnf install -y gcc gcc-c++ make cmake autoconf automake libtool pkgconfig openblas-devel openblas lapack-devel freeglut-devel libXi-devel libXmu-devel python3-devel git openssl-devel pcre-devel pcre2-devel gcc-gfortran patchelf java-1.8.0-openjdk-devel wget bison byacc && mkdir -p \"\$CACHE_DIR\" && cd \"\$CACHE_DIR\" && curl -L https://github.com/swig/swig/archive/v4.1.1.tar.gz | tar xz && cd swig-4.1.1 && ./autogen.sh && ./configure --prefix=\"\$CACHE_DIR/swig\" && make -j\$(nproc) && make install && cd .. && rm -rf swig-4.1.1 && export PATH=\"\$CACHE_DIR/swig/bin:\$PATH\" && mkdir -p dependencies-build && cd dependencies-build && echo 'DEBUG: About to run dependencies cmake with:' && echo '  Source path: \$OPENSIM_ROOT/src/opensim-core/dependencies' && echo '  Install prefix: \$CACHE_DIR/dependencies-install' && echo '  Current working directory: \$(pwd)' && echo '  Verifying source path exists:' && ls -la \"\$OPENSIM_ROOT/src/opensim-core/dependencies\" || echo 'ERROR: Dependencies source path not found!' && cmake \"\$OPENSIM_ROOT/src/opensim-core/dependencies\" -DCMAKE_INSTALL_PREFIX=\"\$CACHE_DIR/dependencies-install\" -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS=\"-pthread -fPIC\" -DCMAKE_C_FLAGS=\"-pthread -fPIC\" -DSUPERBUILD_ezc3d=ON -DOPENSIM_WITH_CASADI=OFF && cmake --build . --config Release -j\$(nproc) && cd .. && mkdir -p opensim-build && cd opensim-build && echo 'DEBUG: About to run OpenSim core cmake with:' && echo '  Source path: \$OPENSIM_ROOT/src/opensim-core' && echo '  Install prefix: \$OPENSIM_INSTALL' && echo '  Dependencies dir: \$CACHE_DIR/dependencies-install' && echo '  SWIG dir: \$CACHE_DIR/swig/share/swig' && echo '  SWIG executable: \$CACHE_DIR/swig/bin/swig' && echo '  Current working directory: \$(pwd)' && echo '  Verifying source path exists:' && ls -la \"\$OPENSIM_ROOT/src/opensim-core\" || echo 'ERROR: OpenSim core source path not found!' && echo '  Verifying dependencies install exists:' && ls -la \"\$CACHE_DIR/dependencies-install\" || echo 'ERROR: Dependencies install not found!' && cmake \"\$OPENSIM_ROOT/src/opensim-core\" -DCMAKE_INSTALL_PREFIX=\"\$OPENSIM_INSTALL\" -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS=\"-pthread -Wno-array-bounds -fPIC\" -DCMAKE_C_FLAGS=\"-pthread -fPIC\" -DCMAKE_EXE_LINKER_FLAGS=\"-pthread\" -DCMAKE_SHARED_LINKER_FLAGS=\"-pthread\" -DOPENSIM_DEPENDENCIES_DIR=\"\$CACHE_DIR/dependencies-install\" -DCMAKE_PREFIX_PATH=\"\$CACHE_DIR/dependencies-install\" -DBUILD_JAVA_WRAPPING=OFF -DBUILD_PYTHON_WRAPPING=OFF -DBUILD_TESTING=OFF -DBUILD_API_EXAMPLES=OFF -DOPENSIM_C3D_PARSER=ezc3d -DOPENSIM_WITH_CASADI=OFF -DOPENSIM_WITH_TROPTER=OFF -DOPENSIM_WITH_MOCO=OFF -DOPENSIM_INSTALL_UNIX_FHS=OFF -DSWIG_DIR=\"\$CACHE_DIR/swig/share/swig\" -DSWIG_EXECUTABLE=\"\$CACHE_DIR/swig/bin/swig\" && cmake --build . --config Release -j\$(nproc) && cmake --install . && touch \"\$OPENSIM_INSTALL/.build_complete\" && echo '✓ OpenSim build complete'; fi && echo 'Setting up build environment...' && export PATH=\"\$CACHE_DIR/swig/bin:\$PATH\" && export OPENSIM_INSTALL_DIR=\"\$OPENSIM_INSTALL\" && echo 'DEBUG: Final environment setup:' && echo '  PATH includes SWIG: \$(echo \$PATH | grep swig || echo SWIG not in PATH)' && echo '  OPENSIM_INSTALL_DIR: \$OPENSIM_INSTALL_DIR' && echo '  SWIG version check:' && swig -version || echo 'ERROR: SWIG not working'"
    export CIBW_ENVIRONMENT_LINUX="PATH=/host\$(pwd)/opensim-cache/linux-\$(uname -m)/swig/bin:\$PATH OPENSIM_INSTALL_DIR=/host\$(pwd)/opensim-cache/linux-\$(uname -m)/opensim-install"
    export CIBW_REPAIR_WHEEL_COMMAND_LINUX="echo '=== Repairing Linux wheel ===' && OPENSIM_INSTALL=\"/host\$(pwd)/opensim-cache/linux-\$(uname -m)/opensim-install\" && DEPS_INSTALL=\"/host\$(pwd)/opensim-cache/linux-\$(uname -m)/dependencies-install\" && echo 'Available .so files in dependencies:' && find \"\$DEPS_INSTALL\" -name \"*.so*\" -type f 2>/dev/null | head -20 && echo 'Available .so files in OpenSim:' && find \"\$OPENSIM_INSTALL\" -name \"*.so*\" -type f 2>/dev/null | head -20 && echo 'Searching for system OpenBLAS:' && find /usr -name \"*openblas*\" 2>/dev/null | head -10 && find /lib64 -name \"*openblas*\" 2>/dev/null | head -10 && echo 'Library paths being used:' && echo '  LD_LIBRARY_PATH=\$OPENSIM_INSTALL/sdk/lib:\$OPENSIM_INSTALL/sdk/Simbody/lib64:\$OPENSIM_INSTALL/sdk/Simbody/lib:\$DEPS_INSTALL/simbody/lib64:\$DEPS_INSTALL/simbody/lib:\$DEPS_INSTALL/ezc3d/lib64:\$DEPS_INSTALL/ezc3d/lib:\$DEPS_INSTALL/spdlog/lib64:\$DEPS_INSTALL/spdlog/lib:\$DEPS_INSTALL/lib64:\$DEPS_INSTALL/lib:/usr/lib64:/lib64' && LD_LIBRARY_PATH=\"\$OPENSIM_INSTALL/sdk/lib:\$OPENSIM_INSTALL/sdk/Simbody/lib64:\$OPENSIM_INSTALL/sdk/Simbody/lib:\$DEPS_INSTALL/simbody/lib64:\$DEPS_INSTALL/simbody/lib:\$DEPS_INSTALL/ezc3d/lib64:\$DEPS_INSTALL/ezc3d/lib:\$DEPS_INSTALL/spdlog/lib64:\$DEPS_INSTALL/spdlog/lib:\$DEPS_INSTALL/lib64:\$DEPS_INSTALL/lib:/usr/lib64:/lib64:\$LD_LIBRARY_PATH\" auditwheel repair --exclude libSimTKcommon.so.3.8 --exclude libSimTKmath.so.3.8 --exclude libSimTKsimbody.so.3.8 -w {dest_dir} {wheel}"
    echo "🐧 Configured for Linux build"
fi

# Target specific Python versions and build configuration from pyproject.toml
export CIBW_BUILD="cp310-* cp311-* cp312-*"
export CIBW_BUILD_VERBOSITY=1

# Show configuration
echo ""
echo "📋 Build Configuration:"
echo "  Target Python versions: $CIBW_BUILD"
echo "  Architecture: $CIBW_ARCHS_MACOS$CIBW_ARCHS_LINUX"
echo "  Build verbosity: $CIBW_BUILD_VERBOSITY"
echo ""

# Parse command line arguments
REBUILD_CACHE=false
for arg in "$@"; do
    case $arg in
        --single)
            export CIBW_BUILD="cp310-*"  # Test with Python 3.10 only (available locally)
            echo "🚀 Single version mode: Building only Python 3.10 wheels"
            ;;
        --no-tests)
            export CIBW_TEST_SKIP="*linux*"
            echo "⚡ Skipping tests for faster development builds"
            ;;
        --rebuild)
            export REBUILD_CACHE=true
            echo "🔄 Force rebuild mode: Will rebuild OpenSim from scratch (ignoring cache)"
            ;;
    esac
done

echo "🔨 Starting cibuildwheel..."
echo ""

# Run cibuildwheel
cibuildwheel --output-dir wheelhouse

echo ""
echo "✅ Build complete! Wheels are in ./wheelhouse/"
ls -la wheelhouse/