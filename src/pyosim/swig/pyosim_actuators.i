%module(package="pyosim", directors="1") actuators

// Enable autodoc feature for better docstrings and type hints
%feature("autodoc", "3");

// Include the original OpenSim actuators interface file
%include "python_actuators.i"