#!/bin/bash

# Local cibuildwheel test script
# This script mimics the GitHub Actions environment for testing wheel builds locally

set -e

echo "🔧 Setting up local cibuildwheel environment..."

# Export environment variables matching the CI configuration
export CIBW_ARCHS_MACOS="universal2"
export CIBW_ARCHS_LINUX="auto aarch64" 
export CIBW_MANYLINUX_X86_64_IMAGE="manylinux_2_28"
export CIBW_MANYLINUX_I686_IMAGE="manylinux_2_28"
export CIBW_MANYLINUX_AARCH64_IMAGE="manylinux_2_28"
export CIBW_TEST_SKIP="*linux*"

# macOS specific environment
if [[ "$OSTYPE" == "darwin"* ]]; then
    export CIBW_ENVIRONMENT_MACOS="MACOSX_DEPLOYMENT_TARGET=14.0
CMAKE_OSX_ARCHITECTURES=x86_64;arm64
REPAIR_LIBRARY_PATH=./build/opensim-workspace/opensim-install/sdk/Simbody/lib"
    export CIBW_REPAIR_WHEEL_COMMAND_MACOS="echo '=== Architecture Check ===' && file ./build/opensim-workspace/opensim-install/sdk/Simbody/lib/libSimTKmath.3.8.dylib && file ./build/opensim-workspace/opensim-install/sdk/Simbody/lib/libSimTKsimbody.3.8.dylib && echo '=== Delocating Wheel ===' && temp_extract=\$(mktemp -d) && python -m zipfile -e {wheel} \$temp_extract && wheel_lib=\$(find \$temp_extract -name 'lib' -type d | grep pyopensim | head -1) && DYLD_LIBRARY_PATH=\$REPAIR_LIBRARY_PATH:\$wheel_lib delocate-wheel -w {dest_dir} -v {wheel} && rm -rf \$temp_extract"
    echo "🍎 Configured for macOS build"
fi

# Linux specific environment  
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    export CIBW_BEFORE_BUILD_LINUX="dnf install -y pcre-devel pcre2-devel autoconf automake libtool && curl -L https://github.com/swig/swig/archive/v4.1.1.tar.gz | tar xz && cd swig-4.1.1 && ./autogen.sh && ./configure --prefix=/usr/local && make -j\$(nproc) && make install && cd .. && rm -rf swig-4.1.1 && swig -version"
    export CIBW_ENVIRONMENT_LINUX="PATH=/usr/local/bin:\$PATH
SWIG_EXECUTABLE=/usr/local/bin/swig
SWIG_DIR=/usr/local/share/swig
LD_LIBRARY_PATH=/host\$(pwd)/build/opensim-workspace/opensim-install/sdk/lib:/host\$(pwd)/build/opensim-workspace/opensim-install/sdk/Simbody/lib:/host\$(pwd)/build/opensim-workspace/opensim-install/sdk/Simbody/lib64:/host\$(pwd)/build/opensim-workspace/dependencies-install/simbody/lib:/host\$(pwd)/build/opensim-workspace/dependencies-install/simbody/lib64:/host\$(pwd)/build/opensim-workspace/dependencies-install/ezc3d/lib:/host\$(pwd)/build/opensim-workspace/dependencies-install/ezc3d/lib64:/host\$(pwd)/build/opensim-workspace/dependencies-install/spdlog/lib:/host\$(pwd)/build/opensim-workspace/dependencies-install/spdlog/lib64:/host\$(pwd)/build/opensim-workspace/opensim-install/sdk/spdlog/lib:/host\$(pwd)/build/opensim-workspace/opensim-install/sdk/spdlog/lib64"
    export CIBW_REPAIR_WHEEL_COMMAND_LINUX="auditwheel repair -w {dest_dir} {wheel}"
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

# Optional: Build only specific Python version for faster testing
if [ "$1" = "--single" ]; then
    export CIBW_BUILD="cp310-*"  # Test with Python 3.10 only (available locally)
    echo "🚀 Single version mode: Building only Python 3.10 wheels"
fi

# Optional: Skip tests for faster builds during development
if [ "$1" = "--no-tests" ] || [ "$2" = "--no-tests" ]; then
    export CIBW_TEST_COMMAND=""
    echo "⚡ Skipping tests for faster development builds"
fi

echo "🔨 Starting cibuildwheel..."
echo ""

# Run cibuildwheel
cibuildwheel --output-dir wheelhouse

echo ""
echo "✅ Build complete! Wheels are in ./wheelhouse/"
ls -la wheelhouse/