%module(package="pyosim", directors="1") simulation

// Enable autodoc feature for better docstrings and type hints
%feature("autodoc", "3");

// Include the original OpenSim simulation interface file
%include "python_simulation.i"