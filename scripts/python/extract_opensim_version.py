#!/usr/bin/env python3
"""Extract OpenSim version from CMakeLists.txt and generate Python version string.

This script reads the OpenSim core CMakeLists.txt to extract the version numbers
and creates a PEP 440 compliant version string for the Python package.

The version format is: <MAJOR>.<MINOR>.<PATCH>.<BUILD>
- Base version (MAJOR.MINOR.PATCH) comes from OpenSim's CMakeLists.txt
- Build number (4th digit) can be set via BUILD_NUMBER environment variable
  for Python binding-specific fixes (defaults to 0)
"""

import re
import sys
from pathlib import Path


def extract_opensim_version(cmake_file: Path) -> tuple[int, int, int]:
    """Extract MAJOR, MINOR, PATCH version from OpenSim CMakeLists.txt.

    Args:
        cmake_file: Path to OpenSim's CMakeLists.txt

    Returns:
        Tuple of (major, minor, patch) version numbers

    Raises:
        ValueError: If version numbers cannot be found or parsed
    """
    content = cmake_file.read_text(encoding='utf-8')

    # Extract version components using regex
    major_match = re.search(r'set\(OPENSIM_MAJOR_VERSION\s+(\d+)\)', content)
    minor_match = re.search(r'set\(OPENSIM_MINOR_VERSION\s+(\d+)\)', content)
    patch_match = re.search(r'set\(OPENSIM_PATCH_VERSION\s+(\d+)\)', content)

    if not all([major_match, minor_match, patch_match]):
        raise ValueError(
            f"Could not find all version components in {cmake_file}\n"
            f"Found: major={major_match}, minor={minor_match}, patch={patch_match}"
        )

    major = int(major_match.group(1))
    minor = int(minor_match.group(1))
    patch = int(patch_match.group(1))

    return major, minor, patch


def create_version_string(major: int, minor: int, patch: int, build: int = 0) -> str:
    """Create PEP 440 compliant version string.

    Args:
        major: Major version number
        minor: Minor version number
        patch: Patch version number
        build: Build number for Python binding fixes (default: 0)

    Returns:
        Version string like "4.5.2.0" or "4.5.2.1"
    """
    return f"{major}.{minor}.{patch}.{build}"


def main():
    """Main entry point for version extraction."""
    import argparse
    import os

    parser = argparse.ArgumentParser(
        description="Extract OpenSim version and generate Python version string"
    )
    parser.add_argument(
        "--cmake-file",
        type=Path,
        help="Path to OpenSim CMakeLists.txt (default: src/opensim-core/CMakeLists.txt)",
    )
    parser.add_argument(
        "--build-number",
        type=int,
        help="Build number for Python binding fixes (default: from BUILD_NUMBER env var, or 0)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Write version to file instead of stdout",
    )

    args = parser.parse_args()

    # Determine CMakeLists.txt path
    if args.cmake_file:
        cmake_file = args.cmake_file
    else:
        # Default: assume script is in scripts/python/ and find src/opensim-core/CMakeLists.txt
        script_dir = Path(__file__).parent
        repo_root = script_dir.parent.parent
        cmake_file = repo_root / "src" / "opensim-core" / "CMakeLists.txt"

    if not cmake_file.exists():
        print(f"Error: CMakeLists.txt not found at {cmake_file}", file=sys.stderr)
        sys.exit(1)

    # Extract version from CMake
    try:
        major, minor, patch = extract_opensim_version(cmake_file)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    # Get build number (from argument or environment variable)
    build_number = args.build_number
    if build_number is None:
        build_env = os.environ.get("BUILD_NUMBER", "").strip()
        if build_env and build_env.isdigit():
            build_number = int(build_env)
        else:
            build_number = 0  # Default to 0

    # Create version string
    version = create_version_string(major, minor, patch, build_number)

    # Output version
    if args.output:
        args.output.write_text(version, encoding='utf-8')
        print(f"Version {version} written to {args.output}", file=sys.stderr)
    else:
        print(version)

    return 0


if __name__ == "__main__":
    sys.exit(main())
