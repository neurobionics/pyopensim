%module(package="pyopensim", directors="1") tools

// Enable autodoc feature for better docstrings and type hints
%feature("autodoc", "3");

// Include the original OpenSim tools interface file
%include "python_tools.i"