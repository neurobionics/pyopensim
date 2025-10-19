#!/usr/bin/env python3
"""
Parse CMake presets and extract cache variables as CMake -D flags.

This script reads a CMakePresets.json file, resolves preset inheritance,
and outputs the cache variables as CMake command-line flags.

Usage:
    parse_preset.py <presets_file> <preset_name>

Example:
    parse_preset.py CMakePresets.json opensim-dependencies-linux

Output format:
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-pthread -fPIC" ...
"""

import json
import sys
import os
from typing import Dict, Any, List, Union


def resolve_preset_inheritance(
    presets: List[Dict[str, Any]],
    preset_name: str,
    resolved_vars: Dict[str, Any] = None
) -> Dict[str, Any]:
    """
    Recursively resolve preset inheritance and merge cache variables.

    Child presets override parent preset values.

    Args:
        presets: List of all configure presets from CMakePresets.json
        preset_name: Name of the preset to resolve
        resolved_vars: Accumulated cache variables (used in recursion)

    Returns:
        Dictionary of all cache variables with inheritance resolved
    """
    if resolved_vars is None:
        resolved_vars = {}

    # Find the preset by name
    preset = None
    for p in presets:
        if p.get('name') == preset_name:
            preset = p
            break

    if preset is None:
        raise ValueError(f"Preset '{preset_name}' not found in CMakePresets.json")

    # Skip hidden presets in error messages (they're meant to be inherited from)
    if preset.get('hidden', False):
        pass  # Still process them for inheritance

    # Recursively resolve parent presets first
    if 'inherits' in preset:
        parent = preset['inherits']
        # Handle both string and list formats
        if isinstance(parent, list):
            # Process parents in order (first parent is resolved first)
            for parent_name in parent:
                resolved_vars = resolve_preset_inheritance(presets, parent_name, resolved_vars)
        else:
            resolved_vars = resolve_preset_inheritance(presets, parent, resolved_vars)

    # Merge this preset's cache variables (child overrides parent)
    if 'cacheVariables' in preset:
        resolved_vars.update(preset['cacheVariables'])

    return resolved_vars


def format_cmake_value(value: Any) -> str:
    """
    Format a cache variable value for CMake command line.

    Handles proper quoting for strings with spaces, semicolons, etc.

    Args:
        value: The cache variable value (string, bool, number, or dict)

    Returns:
        Formatted string suitable for CMake -D flag
    """
    # Handle typed cache variables (dict with 'type' and 'value' keys)
    if isinstance(value, dict):
        if 'value' in value:
            value = value['value']
        else:
            # Some presets might have other dict structures, stringify them
            value = str(value)

    # Convert booleans to CMake format
    if isinstance(value, bool):
        return "ON" if value else "OFF"

    # Convert to string
    value_str = str(value)

    # Quote if contains spaces or special characters
    # CMake semicolon is used for lists, so we need to preserve it
    if ' ' in value_str or '"' in value_str:
        # Escape any existing quotes
        value_str = value_str.replace('"', '\\"')
        return f'"{value_str}"'

    return value_str


def generate_cmake_flags(cache_variables: Dict[str, Any]) -> str:
    """
    Convert cache variables to CMake -D flags.

    Args:
        cache_variables: Dictionary of CMake cache variables

    Returns:
        Space-separated string of -D flags
    """
    flags = []

    for key, value in cache_variables.items():
        formatted_value = format_cmake_value(value)
        flags.append(f"-D{key}={formatted_value}")

    return " ".join(flags)


def main():
    """Main entry point for the script."""
    if len(sys.argv) != 3:
        print("Usage: parse_preset.py <presets_file> <preset_name>", file=sys.stderr)
        print("", file=sys.stderr)
        print("Example:", file=sys.stderr)
        print("  parse_preset.py CMakePresets.json opensim-dependencies-linux", file=sys.stderr)
        sys.exit(1)

    presets_file = sys.argv[1]
    preset_name = sys.argv[2]

    # Validate that the presets file exists
    if not os.path.exists(presets_file):
        print(f"Error: CMakePresets.json not found at: {presets_file}", file=sys.stderr)
        sys.exit(1)

    try:
        # Load the presets file
        with open(presets_file, 'r') as f:
            data = json.load(f)

        # Get configure presets
        if 'configurePresets' not in data:
            print("Error: No 'configurePresets' found in CMakePresets.json", file=sys.stderr)
            sys.exit(1)

        presets = data['configurePresets']

        # Resolve the preset with inheritance
        cache_variables = resolve_preset_inheritance(presets, preset_name)

        # Generate CMake flags
        cmake_flags = generate_cmake_flags(cache_variables)

        # Output the flags (stdout, so it can be captured by bash)
        print(cmake_flags)

    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
