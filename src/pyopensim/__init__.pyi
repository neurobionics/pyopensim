from typing import Any
from . import actuators, analyses, common, simbody, simulation, tools

# Version is imported from package metadata
__version__: str
__opensim_version__: str

# Optional modules - mirror the runtime try/except behavior
try:
    from . import examplecomponents
except ImportError:
    examplecomponents = None

try:
    from . import moco
except ImportError:
    moco = None

try:
    from . import report
except ImportError:
    report = None

# Re-exported classes from simbody
from .simbody import Vec3, Rotation, Transform, Inertia, Gray, SimTK_PI

# Re-exported classes from common
from .common import Component, Property, Storage, Array, StepFunction, ConsoleReporter

# Re-exported classes from simulation
from .simulation import (
    Model, 
    Manager, 
    State, 
    Body, 
    PinJoint, 
    PhysicalOffsetFrame,
    Ellipsoid, 
    Millard2012EquilibriumMuscle, 
    PrescribedController,
    InverseKinematicsSolver, 
    InverseDynamicsSolver
)

# Re-exported classes from actuators
from .actuators import Muscle, CoordinateActuator, PointActuator

# Re-exported classes from tools
from .tools import InverseKinematicsTool, InverseDynamicsTool, ForwardTool, AnalyzeTool

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
    '__version__', '__opensim_version__'
]
