#!/bin/bash
# Test script to validate the container-native build approach locally
# This simulates what happens in the cibuildwheel environment

set -e

echo "=== Testing Container-Native OpenSim Build ==="

# Simulate the cache directory structure
CACHE_DIR="$(pwd)/opensim-cache/linux-$(uname -m)"
OPENSIM_INSTALL="$CACHE_DIR/opensim-install"

echo "Cache directory: $CACHE_DIR"
echo "OpenSim install: $OPENSIM_INSTALL"

# Check if we have cached build
if [ -d "$OPENSIM_INSTALL" ] && [ -f "$OPENSIM_INSTALL/.build_complete" ]; then
    echo "✓ Using cached OpenSim build from $OPENSIM_INSTALL"
    ls -la "$OPENSIM_INSTALL/sdk/lib/" 2>/dev/null || echo "No lib directory found"
else
    echo "❌ No cached OpenSim build found"
    echo "In CI, this would trigger a full build inside the container"
fi

# Test environment variables
export OPENSIM_INSTALL_DIR="$OPENSIM_INSTALL"
echo "OPENSIM_INSTALL_DIR set to: $OPENSIM_INSTALL_DIR"

# Test CMake configuration detection
echo "=== Testing CMake OpenSim Detection ==="
if [ -f "CMakeLists.txt" ]; then
    # This would normally be done by CMake, but we can simulate the logic
    if [ -n "$OPENSIM_INSTALL_DIR" ] && [ -d "$OPENSIM_INSTALL_DIR" ]; then
        echo "✓ CMake would detect OpenSim from environment variable"
        echo "  OPENSIM_INSTALL_DIR: $OPENSIM_INSTALL_DIR"
        CACHE_DIR_PARENT=$(dirname "$OPENSIM_INSTALL_DIR")
        echo "  Dependencies would be found at: $CACHE_DIR_PARENT/dependencies-install"
    else
        echo "❌ CMake would not find OpenSim from environment"
    fi
else
    echo "❌ Not in project root directory"
fi

echo "=== Test Complete ==="