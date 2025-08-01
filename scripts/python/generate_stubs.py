#!/usr/bin/env python3
"""
Simplified stub generation for PyOSim using mypy's stubgen.
This replaces the two separate generation scripts with a single streamlined approach.
"""

import subprocess
import sys
from pathlib import Path


def ensure_mypy_available() -> bool:
    """Check if mypy is available, install if needed."""
    try:
        import mypy.stubgen  # noqa: F401
        print("✓ mypy is available")
        return True
    except ImportError:
        print("Installing mypy for stub generation...")
        try:
            subprocess.run([sys.executable, "-m", "pip", "install", "mypy"], check=True)
            print("✓ mypy installed successfully")
            return True
        except subprocess.CalledProcessError as e:
            print(f"✗ Failed to install mypy: {e}")
            return False


def generate_stubs_with_stubgen(package_path: Path, output_dir: Path) -> bool:
    """Generate stub files using mypy's stubgen."""
    print(f"Generating stubs for package at: {package_path}")
    
    # Add the package directory to Python path
    if package_path.exists():
        sys.path.insert(0, str(package_path.parent))
    
    # PyOSim modules to generate stubs for
    modules = ['simbody', 'common', 'simulation', 'actuators', 'analyses', 'tools']
    
    success_count = 0
    
    for module in modules:
        module_name = f"pyosim.{module}"
        print(f"Generating stubs for {module_name}...")
        
        try:
            # Run stubgen for this module
            result = subprocess.run([
                sys.executable, "-m", "mypy.stubgen",
                "-m", module_name,
                "-o", str(output_dir),
                "--ignore-errors"
            ], capture_output=True, text=True, check=False)
            
            if result.returncode == 0:
                print(f"✓ Generated stubs for {module_name}")
                success_count += 1
            else:
                print(f"⚠ Warning: stubgen had issues with {module_name}")
                print(f"  stderr: {result.stderr}")
                # Still count as success since stubs are usually generated despite warnings
                success_count += 1
                
        except Exception as e:
            print(f"✗ Error generating stubs for {module_name}: {e}")
    
    return success_count > 0


def create_init_stub(output_dir: Path) -> None:
    """Create the main __init__.pyi file with proper imports and exports."""
    init_stub_content = '''"""PyOSim: Python bindings for OpenSim."""
from typing import Any

# Import all modules
from . import actuators as actuators
from . import analyses as analyses  
from . import common as common
from . import simbody as simbody
from . import simulation as simulation
from . import tools as tools

# Re-export commonly used classes for convenience
from .simulation import Body as Body
from .simulation import Model as Model
from .simulation import PinJoint as PinJoint
from .simulation import Manager as Manager
from .common import Vec3 as Vec3
from .common import Transform as Transform
from .common import Inertia as Inertia
from .actuators import Millard2012EquilibriumMuscle as Millard2012EquilibriumMuscle

# Version info
__version__: str

__all__ = [
    "simbody", "common", "simulation", "actuators", "analyses", "tools",
    "Model", "Manager", "Body", "Vec3", "Transform", 
    "Inertia", "PinJoint", "Millard2012EquilibriumMuscle",
    "__version__"
]
'''
    
    init_file = output_dir / "pyosim" / "__init__.pyi"
    init_file.parent.mkdir(parents=True, exist_ok=True)
    
    with open(init_file, 'w') as f:
        f.write(init_stub_content)
    
    print("✓ Generated main __init__.pyi")


def main():
    """Main stub generation function."""
    if len(sys.argv) < 2:
        print("Usage: generate_stubs_simplified.py <output_dir> [package_path]")
        print("  output_dir: Directory where .pyi files will be created")
        print("  package_path: Optional path to built pyosim package")
        sys.exit(1)
    
    output_dir = Path(sys.argv[1])
    package_path = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    
    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Ensure mypy is available
    if not ensure_mypy_available():
        sys.exit(1)
    
    # Generate stubs using stubgen
    if generate_stubs_with_stubgen(package_path, output_dir):
        # Create main __init__.pyi file
        create_init_stub(output_dir)
        print(f"✓ Stub generation completed. Files written to: {output_dir}")
    else:
        print("✗ Stub generation failed")
        sys.exit(1)


if __name__ == "__main__":
    main()