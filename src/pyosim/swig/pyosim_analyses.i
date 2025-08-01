%module(package="pyosim", directors="1") analyses

// Enable autodoc feature for better docstrings and type hints
%feature("autodoc", "3");

// Include the original OpenSim analyses interface file
%include "python_analyses.i"