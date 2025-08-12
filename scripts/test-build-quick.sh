#!/bin/bash

# Quick local test script for development
# This builds only one Python version without tests for faster iteration

echo "🚀 Quick local build test (Python 3.11 only, no tests)"
echo "This is useful for rapid development and debugging"

export CIBW_BUILD="cp311-*"
export CIBW_BUILD_VERBOSITY=1
export CIBW_TEST_COMMAND=""  # Skip tests

# macOS configuration
if [[ "$OSTYPE" == "darwin"* ]]; then
    export CIBW_ARCHS_MACOS="x86_64"  # Build only for current arch for speed
    export CIBW_ENVIRONMENT_MACOS="MACOSX_DEPLOYMENT_TARGET=14.0
CMAKE_OSX_ARCHITECTURES=x86_64
REPAIR_LIBRARY_PATH=./build/opensim-workspace/opensim-install/sdk/lib:./build/opensim-workspace/opensim-install/sdk/Simbody/lib:./build/opensim-workspace/opensim-dependencies-install/simbody/lib:./build/opensim-workspace/opensim-dependencies-install/ezc3d/lib:./build/opensim-workspace/opensim-dependencies-install/spdlog/lib:./build/opensim-workspace/opensim-dependencies-install/ipopt/lib"
    export CIBW_REPAIR_WHEEL_COMMAND_MACOS="echo '=== Architecture Check ===' && file ./build/opensim-workspace/opensim-install/sdk/Simbody/lib/libSimTKmath.3.8.dylib && file ./build/opensim-workspace/opensim-install/sdk/Simbody/lib/libSimTKsimbody.3.8.dylib && echo '=== Delocating Wheel ===' && DYLD_LIBRARY_PATH=\$REPAIR_LIBRARY_PATH delocate-wheel -w {dest_dir} -v {wheel}"
fi

echo "Building wheel..."
time cibuildwheel --output-dir wheelhouse-test

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Quick build successful!"
    echo "Wheel created:"
    ls -la wheelhouse-test/
    echo ""
    echo "To test the wheel:"
    echo "  pip install wheelhouse-test/*.whl"
else
    echo ""
    echo "❌ Build failed. Check the output above for errors."
    exit 1
fi