%module(package="pyopensim", directors="1") simbody

// Enable autodoc feature for better docstrings and type hints
%feature("autodoc", "3");

// Include the original OpenSim simbody interface file
%include "python_simbody.i"