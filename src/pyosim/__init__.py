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
if simbody:
    # SimTK and geometry classes from simbody
    for cls_name in ['Vec3', 'Rotation', 'Transform', 'Inertia', 'Gray', 'SimTK_PI']:
        try:
            cls = getattr(simbody, cls_name)
            globals()[cls_name] = cls
        except AttributeError:
            pass  # Class doesn't exist in this module

if common:
    # Core modeling classes
    for cls_name in ['Component', 'Property', 'Storage', 'Array', 'StepFunction', 'ConsoleReporter']:
        try:
            cls = getattr(common, cls_name)
            globals()[cls_name] = cls
        except AttributeError:
            pass  # Class doesn't exist in this module

if simulation:
    # Simulation classes - import each individually to avoid failures
    for cls_name in ['Model', 'Manager', 'State', 'Body', 'PinJoint', 'PhysicalOffsetFrame', 
                     'Ellipsoid', 'Millard2012EquilibriumMuscle', 'PrescribedController',
                     'InverseKinematicsSolver', 'InverseDynamicsSolver']:
        try:
            cls = getattr(simulation, cls_name)
            globals()[cls_name] = cls
        except AttributeError:
            pass  # Class doesn't exist in this module

if actuators:
    # Common actuator classes
    for cls_name in ['Muscle', 'CoordinateActuator', 'PointActuator']:
        try:
            cls = getattr(actuators, cls_name)
            globals()[cls_name] = cls
        except AttributeError:
            pass  # Class doesn't exist in this module

if tools:
    # Analysis tools
    for cls_name in ['InverseKinematicsTool', 'InverseDynamicsTool', 'ForwardTool', 'AnalyzeTool']:
        try:
            cls = getattr(tools, cls_name)
            globals()[cls_name] = cls
        except AttributeError:
            pass  # Class doesn't exist in this module

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
    'Model', 'Manager', 'State', 'Body',
    'Component', 'Property',
    'Vec3', 'Rotation', 'Transform', 'Inertia',
    'PinJoint', 'PhysicalOffsetFrame', 'Ellipsoid',
    'Millard2012EquilibriumMuscle', 'PrescribedController',
    'StepFunction', 'ConsoleReporter',
    'Gray', 'SimTK_PI',
    'Storage', 'Array',
    'InverseKinematicsSolver', 'InverseDynamicsSolver',
    'Muscle', 'CoordinateActuator', 'PointActuator',
    'InverseKinematicsTool', 'InverseDynamicsTool',
    'ForwardTool', 'AnalyzeTool',
    '__version__'
]

# Filter out None values from __all__ (for optional modules that failed to import)
__all__ = [item for item in __all__ if globals().get(item) is not None]