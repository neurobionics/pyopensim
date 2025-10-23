"""Dynamic version provider for scikit-build-core.

This module extracts the OpenSim version from CMakeLists.txt and
creates a PEP 440 compliant version string for the Python package.

Used by scikit-build-core during build via metadata.version.provider setting.
"""

import os
import sys
from pathlib import Path

# Add the scripts directory to path to import our version extraction module
SCRIPT_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

from extract_opensim_version import extract_opensim_version, create_version_string


def dynamic_metadata(field: str, settings: dict | None = None) -> str:
    """Provide dynamic version metadata to scikit-build-core.

    Args:
        field: Metadata field being requested (should be "version")
        settings: Optional build settings

    Returns:
        Version string extracted from OpenSim CMakeLists.txt

    Raises:
        ValueError: If field is not "version" or version cannot be extracted
    """
    if field != "version":
        raise ValueError(f"Only 'version' field is supported, got '{field}'")

    # Find OpenSim CMakeLists.txt (relative to project root)
    # During build, we're executed from the project root
    repo_root = Path.cwd()
    cmake_file = repo_root / "src" / "opensim-core" / "CMakeLists.txt"

    if not cmake_file.exists():
        raise ValueError(
            f"OpenSim CMakeLists.txt not found at {cmake_file}\n"
            f"Current directory: {repo_root}"
        )

    # Extract version from CMakeLists.txt
    major, minor, patch = extract_opensim_version(cmake_file)

    # Check for build number from environment
    build_number = 0
    build_env = os.environ.get("BUILD_NUMBER", "").strip()
    if build_env and build_env.isdigit():
        build_number = int(build_env)

    # Create and return version string
    version = create_version_string(major, minor, patch, build_number)

    print(f"Detected OpenSim version: {version}", file=sys.stderr)

    return version


# For direct testing
if __name__ == "__main__":
    print(f"Version: {dynamic_metadata('version')}")
