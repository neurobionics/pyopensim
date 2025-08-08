%module(package="pyopensim", directors="1") common

// Enable autodoc feature for better docstrings and type hints
%feature("autodoc", "3");

// Include the original OpenSim common interface file
%include "python_common.i"