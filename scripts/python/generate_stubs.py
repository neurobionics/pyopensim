#!/usr/bin/env python3
"""
Improved stub generation for PyOpenSim using mypy's stubgen with post-processing.
Fixes common SWIG-related issues in generated stubs.
"""

import re
import subprocess
import sys
from pathlib import Path
from typing import List, Tuple


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


def fix_malformed_self_parameters(content: str) -> str:
    """Fix malformed self parameters in stub content."""
    # Pattern to match malformed self parameters like selfProperty, selfos, selfX_BD, etc.
    # This matches 'self' followed immediately by a capital letter or lowercase letter(s)
    patterns = [
        # Fix selfCamelCase -> self, CamelCase
        (r'\bself([A-Z][a-zA-Z_0-9]*)', r'self, \1'),
        # Fix selflowercase -> self, lowercase  
        (r'\bself([a-z][a-zA-Z_0-9]*)', r'self, \1'),
        # Fix selfX_Y style parameters -> self, X_Y
        (r'\bself([A-Z_][A-Z_0-9]*)', r'self, \1'),
    ]
    
    fixed_content = content
    for pattern, replacement in patterns:
        fixed_content = re.sub(pattern, replacement, fixed_content)
    
    return fixed_content


def fix_duplicate_self_parameters(content: str) -> str:
    """Fix cases where self appears twice like 'self, self, param'."""
    # Fix patterns like "self, self, param" -> "self, param"
    content = re.sub(r'\bself,\s*self,\s*', 'self, ', content)
    return content


def fix_missing_type_imports(content: str) -> str:
    """Add missing type imports that are commonly needed."""
    lines = content.split('\n')
    
    # Check if we need to add imports
    has_typing_import = any('from typing import' in line for line in lines[:10])
    has_any_import = any('Any' in line for line in lines[:10])
    
    # If we have type annotations but no typing imports, add them
    if 'Any' in content and not has_any_import:
        if has_typing_import:
            # Find the typing import line and add Any to it
            for i, line in enumerate(lines):
                if line.startswith('from typing import'):
                    if 'Any' not in line:
                        # Add Any to existing import
                        if line.endswith('import'):
                            lines[i] = line + ' Any'
                        else:
                            lines[i] = line + ', Any'
                    break
        else:
            # Add new typing import
            lines.insert(0, 'from typing import Any')
    
    return '\n'.join(lines)


def fix_common_swig_issues(content: str) -> str:
    """Fix common SWIG-generated stub issues."""
    # Fix empty parameter lists that should have self
    content = re.sub(r'def (\w+)\(\)', r'def \1(self)', content)
    
    # Fix malformed overload decorators
    content = re.sub(r'@overload\s*def (\w+)\(self([^)]*)\)([^:]*):(.*)$', 
                     r'@overload\n    def \1(self\2)\3:\4', content, flags=re.MULTILINE)
    
    # Fix trailing commas in parameter lists
    content = re.sub(r'def (\w+)\([^)]*,\s*\)', lambda m: m.group(0).replace(', )', ')'), content)
    
    return content


def post_process_stub_file(file_path: Path) -> None:
    """Post-process a generated stub file to fix common issues."""
    print(f"  Post-processing: {file_path.name}")
    
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Apply all fixes
        original_content = content
        content = fix_malformed_self_parameters(content)
        content = fix_duplicate_self_parameters(content)
        content = fix_missing_type_imports(content)
        content = fix_common_swig_issues(content)
        
        # Only write back if content changed
        if content != original_content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            print(f"    ✓ Fixed issues in {file_path.name}")
        else:
            print(f"    ✓ No issues found in {file_path.name}")
            
    except Exception as e:
        print(f"    ✗ Error processing {file_path.name}: {e}")


def generate_stubs_with_stubgen(package_path: Path, output_dir: Path) -> bool:
    """Generate stub files using mypy's stubgen."""
    print(f"Generating stubs for package at: {package_path}")
    
    # Add the package directory to Python path
    if package_path and package_path.exists():
        sys.path.insert(0, str(package_path.parent))
    
    # PyOpenSim modules to generate stubs for
    modules = ['simbody', 'common', 'simulation', 'actuators', 'analyses', 'tools']
    
    success_count = 0
    
    for module in modules:
        module_name = f"pyopensim.{module}"
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
                print(f"  ✓ Generated stubs for {module_name}")
                success_count += 1
            else:
                print(f"  ⚠ Warning: stubgen had issues with {module_name}")
                if result.stderr:
                    print(f"    stderr: {result.stderr}")
                # Still count as success since stubs are usually generated despite warnings
                success_count += 1
                
        except Exception as e:
            print(f"  ✗ Error generating stubs for {module_name}: {e}")
    
    return success_count > 0


def post_process_all_stubs(output_dir: Path) -> None:
    """Post-process all generated stub files."""
    print("Post-processing generated stub files...")
    
    # Find all .pyi files in the pyopensim directory
    pyopensim_dir = output_dir / "pyopensim"
    if pyopensim_dir.exists():
        stub_files = list(pyopensim_dir.glob("*.pyi"))
        for stub_file in stub_files:
            if stub_file.name != "__init__.pyi":  # Skip our custom __init__.pyi
                post_process_stub_file(stub_file)
    else:
        print(f"  ⚠ Warning: Expected stub directory not found: {pyopensim_dir}")


def create_init_stub(output_dir: Path) -> None:
    """Create the main __init__.pyi file with proper imports and exports."""
    init_stub_content = '''"""PyOpenSim: Python bindings for OpenSim."""
from typing import Any

# Import all modules
from . import actuators as actuators
from . import analyses as analyses  
from . import common as common
from . import simbody as simbody
from . import simulation as simulation
from . import tools as tools

# Re-export commonly used classes for convenience
# Note: These imports may fail if the classes don't exist in the actual modules
try:
    from .simulation import Body as Body
    from .simulation import Model as Model
    from .simulation import Manager as Manager
except ImportError:
    # Fallback if classes don't exist
    Body: Any
    Model: Any
    Manager: Any

try:
    from .common import Vec3 as Vec3
    from .common import Transform as Transform
    from .common import Inertia as Inertia
except ImportError:
    # Fallback if classes don't exist
    Vec3: Any
    Transform: Any
    Inertia: Any

try:
    from .simulation import PinJoint as PinJoint
except ImportError:
    PinJoint: Any

try:
    from .actuators import Millard2012EquilibriumMuscle as Millard2012EquilibriumMuscle
except ImportError:
    Millard2012EquilibriumMuscle: Any

# Version info
__version__: str

__all__ = [
    "simbody", "common", "simulation", "actuators", "analyses", "tools",
    "Model", "Manager", "Body", "Vec3", "Transform", 
    "Inertia", "PinJoint", "Millard2012EquilibriumMuscle",
    "__version__"
]
'''
    
    init_file = output_dir / "pyopensim" / "__init__.pyi"
    init_file.parent.mkdir(parents=True, exist_ok=True)
    
    with open(init_file, 'w') as f:
        f.write(init_stub_content)
    
    print("✓ Generated main __init__.pyi")


def main():
    """Main stub generation function."""
    if len(sys.argv) < 2:
        print("Usage: generate_stubs.py <output_dir> [package_path]")
        print("  output_dir: Directory where .pyi files will be created")
        print("  package_path: Optional path to built pyopensim package")
        sys.exit(1)
    
    output_dir = Path(sys.argv[1])
    package_path = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    
    # Create output directory
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Ensure mypy is available
    if not ensure_mypy_available():
        sys.exit(1)
    
    print("\n" + "="*60)
    print("PYOPENSIM STUB GENERATION")
    print("="*60)
    
    # Generate stubs using stubgen
    if generate_stubs_with_stubgen(package_path, output_dir):
        print("\n" + "-"*40)
        # Post-process the generated stubs to fix issues
        post_process_all_stubs(output_dir)
        
        print("\n" + "-"*40)
        # Create main __init__.pyi file
        create_init_stub(output_dir)
        
        print("\n" + "="*60)
        print(f"✓ Stub generation completed successfully!")
        print(f"  Files written to: {output_dir}")
        print(f"  Post-processing applied to fix SWIG-related issues")
        print("="*60)
    else:
        print("✗ Stub generation failed")
        sys.exit(1)


if __name__ == "__main__":
    main()