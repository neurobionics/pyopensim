"""
PyOSim: Python bindings for OpenSim using SWIG

This package provides Python bindings for the OpenSim biomechanical modeling
and simulation toolkit.
"""

import sys
import os
import ctypes

# Get the current directory
_curFolder = os.path.dirname(os.path.realpath(__file__))
_lib_path = os.path.join(_curFolder, 'lib')

# Set up library loading - CRITICAL: must be done before importing SWIG modules
if sys.platform.startswith('win'):
    # Windows: add DLL directory
    if os.path.exists(_lib_path):
        os.add_dll_directory(_lib_path)
else:
    # Unix-like: preload essential libraries and update LD_LIBRARY_PATH
    if os.path.exists(_lib_path):
        # Add to LD_LIBRARY_PATH for subprocess
        if 'LD_LIBRARY_PATH' in os.environ:
            os.environ['LD_LIBRARY_PATH'] = _lib_path + os.pathsep + os.environ['LD_LIBRARY_PATH']
        else:
            os.environ['LD_LIBRARY_PATH'] = _lib_path
        
        # Preload critical libraries in correct order
        try:
            ctypes.CDLL(os.path.join(_lib_path, 'libSimTKcommon.so'), mode=ctypes.RTLD_GLOBAL)
            ctypes.CDLL(os.path.join(_lib_path, 'libSimTKmath.so'), mode=ctypes.RTLD_GLOBAL)
            ctypes.CDLL(os.path.join(_lib_path, 'libSimTKsimbody.so'), mode=ctypes.RTLD_GLOBAL)
        except OSError as e:
            print(f"Warning: Could not preload SimTK libraries: {e}")

# Make pyosim appear as opensim for SWIG module compatibility
import sys
sys.modules['opensim'] = sys.modules[__name__]

# Import SWIG-generated modules as submodules (preserving structure)
try:
    from . import simbody
except ImportError as e:
    print(f"Warning: Could not import simbody module: {e}")
    simbody = None

try:
    from . import common
except ImportError as e:
    print(f"Warning: Could not import common module: {e}")
    common = None

try:
    from . import simulation
except ImportError as e:
    print(f"Warning: Could not import simulation module: {e}")
    simulation = None

try:
    from . import actuators
except ImportError as e:
    print(f"Warning: Could not import actuators module: {e}")
    actuators = None

try:
    from . import analyses
except ImportError as e:
    print(f"Warning: Could not import analyses module: {e}")
    analyses = None

try:
    from . import tools
except ImportError as e:
    print(f"Warning: Could not import tools module: {e}")
    tools = None

# Try to import optional modules
try:
    from . import examplecomponents
except ImportError:
    examplecomponents = None  # Optional module

try:
    from . import moco
except ImportError:
    moco = None  # Optional module

try:
    from . import report
except ImportError:
    report = None  # Optional module

# For backwards compatibility with OpenSim's flat namespace,
# also import commonly used classes at the top level
if common:
    # Core modeling classes
    try:
        from .common import Component, Property
        from .common import Vec3, Rotation, Transform
        from .common import Storage, Array
    except (ImportError, AttributeError):
        pass

if simulation:
    # Simulation classes
    try:
        from .simulation import Model, Manager, State
        from .simulation import InverseKinematicsSolver, InverseDynamicsSolver
    except (ImportError, AttributeError):
        pass

if actuators:
    # Common actuator classes
    try:
        from .actuators import Muscle, CoordinateActuator, PointActuator
    except (ImportError, AttributeError):
        pass

if tools:
    # Analysis tools
    try:
        from .tools import InverseKinematicsTool, InverseDynamicsTool
        from .tools import ForwardTool, AnalyzeTool
    except (ImportError, AttributeError):
        pass

# Import version
try:
    from .version import __version__
except ImportError:
    __version__ = "0.0.1"

# Set up geometry path if available
_geometry_path = os.path.join(_curFolder, 'Geometry')
if os.path.exists(_geometry_path):
    try:
        ModelVisualizer.addDirToGeometrySearchPaths(_geometry_path)
    except NameError:
        pass  # ModelVisualizer not available

# Define what's available when using 'from pyosim import *'
__all__ = [
    # Core modules
    'simbody', 'common', 'simulation', 'actuators', 'analyses', 'tools',
    # Optional modules (if available)
    'examplecomponents', 'moco', 'report',
    # Common classes at top level for convenience
    'Model', 'Component', 'Property',
    'Vec3', 'Rotation', 'Transform',
    'Storage', 'Array',
    'Manager', 'State',
    'InverseKinematicsSolver', 'InverseDynamicsSolver',
    'Muscle', 'CoordinateActuator', 'PointActuator',
    'InverseKinematicsTool', 'InverseDynamicsTool',
    'ForwardTool', 'AnalyzeTool',
    '__version__'
]

# Filter out None values from __all__ (for optional modules that failed to import)
__all__ = [item for item in __all__ if globals().get(item) is not None]