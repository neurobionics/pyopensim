# Contributing to pyopensim

Thank you for your interest in contributing to pyopensim! This project provides portable Python bindings for OpenSim with comprehensive type hints, and we welcome contributions of all kinds.

## How to Help Improve Type Stubs

One of the key features of pyopensim is its comprehensive type stub files (`.pyi` files) that provide IDE support and type checking. Here's how you can help improve them:

### Understanding the Type Stub System

- **Location**: Type stubs are located in `src/pyopensim/*.pyi`
- **Modules**: We maintain stubs for all major OpenSim modules:
  - `simbody.pyi` - SimTK/Simbody physics engine bindings
  - `common.pyi` - Core OpenSim utilities and data structures
  - `simulation.pyi` - Simulation and solver functionality
  - `actuators.pyi` - Muscle and actuator models
  - `analyses.pyi` - Analysis tools and reporters
  - `tools.pyi` - High-level tools (IK, ID, CMC, etc.)

### Ways to Contribute to Type Stubs

1. **Report Missing or Incorrect Type Annotations**
   - Use pyopensim in your IDE (VS Code, PyCharm, etc.)
   - Report when type hints are missing, incorrect, or incomplete
   - Include specific examples of the problematic code

2. **Improve Method Signatures**
   - Many SWIG-generated bindings have generic signatures
   - Help specify more precise parameter types and return types
   - Add missing optional parameters and default values

3. **Add Docstrings**
   - Type stubs can include docstrings for better IDE support
   - Add concise descriptions for classes and methods
   - Include parameter descriptions and usage examples

4. **Test Type Checking**
   - Run `mypy` on your pyopensim code and report issues
   - Help ensure type stubs work correctly with static type checkers
   - Test edge cases and complex usage patterns

### Type Stub Generation Process

We use an automated process to generate initial stubs:
- **Script**: `scripts/python/generate_stubs.py`
- **Tool**: Uses `mypy.stubgen` to generate base stubs from compiled modules
- **Manual refinement**: Generated stubs are then manually improved for accuracy

### Contributing Type Improvements

1. **Fork the repository** and create a feature branch
2. **Modify the relevant `.pyi` files** in `src/pyopensim/`
3. **Test your changes**:
   ```bash
   # Install in development mode
   pip install -e .
   
   # Test type checking on your code
   mypy your_test_file.py
   ```
4. **Submit a pull request** with:
   - Clear description of the improvements
   - Examples showing the before/after behavior
   - Any test code that validates the changes

## Versioning Policy

PyOpenSim uses a 4-digit versioning scheme that directly tracks the OpenSim core version:

### Version Format

```
<MAJOR>.<MINOR>.<PATCH>.<BUILD>
```

- **Base version** (e.g., `4.5.2`): First 3 digits match the bundled OpenSim core version exactly
- **Build number** (4th digit): Python binding-specific fixes or improvements (defaults to 0)

### When to Bump Versions

**Never manually edit version numbers!** Versions are automatically extracted from OpenSim's CMakeLists.txt.

**For OpenSim core updates:**
1. Update the `src/opensim-core` git submodule to the desired OpenSim version
2. The version is automatically detected from OpenSim's CMakeLists.txt during build
3. Example: Updating submodule to OpenSim 4.6.0 → PyOpenSim becomes 4.6.0.0

**For Python binding fixes (without OpenSim update):**
1. Set the `BUILD_NUMBER` environment variable before building
2. This sets the 4th digit of the version
3. Example: Fix type stubs for OpenSim 4.5.2 → Build with `BUILD_NUMBER=1` → Version becomes 4.5.2.1

### Building with Custom Build Numbers

**Local development:**
```bash
# Build with build number for binding fix
BUILD_NUMBER=1 make build
```

**CI/CD (GitHub Actions):**
```yaml
env:
  BUILD_NUMBER: 1  # Set when needed for binding fixes
```

### Release Process

1. **For OpenSim version updates:**
   ```bash
   # Update OpenSim submodule
   cd src/opensim-core
   git checkout <opensim-tag-or-commit>
   cd ../..
   git add src/opensim-core
   git commit -m "chore: update OpenSim to version X.Y.Z"
   ```

2. **For binding-only fixes:**
   - Increment `BUILD_NUMBER` from previous release
   - Example: `4.5.2.1` → `4.5.2.2`
   - Document changes in release notes

3. **Version verification:**
   ```python
   import pyopensim
   print(pyopensim.__version__)         # Full version (e.g., "4.5.2.1")
   print(pyopensim.__opensim_version__)  # OpenSim core version (e.g., "4.5.2")
   ```

### Examples

**Scenario 1: New OpenSim release**
- OpenSim releases 4.6.0
- Update submodule to OpenSim 4.6.0
- Build → PyOpenSim 4.6.0.0

**Scenario 2: Fix type stubs**
- Current: PyOpenSim 4.5.2.0
- Fix type stubs, improve bindings
- Build with `BUILD_NUMBER=1` → PyOpenSim 4.5.2.1

**Scenario 3: Another binding fix**
- Current: PyOpenSim 4.5.2.1
- Fix build system, update documentation
- Build with `BUILD_NUMBER=2` → PyOpenSim 4.5.2.2

## General Contributing Guidelines

### Setting Up Development Environment

1. **Clone the repository**:
   ```bash
   git clone https://github.com/neurobionics/pyopensim.git
   cd pyopensim
   ```

2. **Install dependencies**:
   ```bash
   pip install -e ".[dev]"  # Install in development mode
   ```

3. **Build OpenSim w/ its dependencies** (if needed):
   ```bash
   make setup
   ```
4. **Run the build**:
   ```bash
   make build
   ```

### Code Quality Standards

- **Follow PEP 8** for Python code style
- **Use type hints** in all new Python code
- **Add tests** for new functionality
- **Update documentation** as needed

### Testing

- **Run basic tests**:
  ```bash
  pytest tests/
  ```

- **Test type checking**:
  ```bash
  mypy src/pyopensim/
  ```

### Areas Where We Need Help

1. **Type Stub Improvements** (highest priority)
   - More accurate type annotations
   - Better method signatures
   - Documentation strings

2. **Documentation and Examples**
   - Usage examples for different OpenSim workflows
   - Migration guides from opensim-python
   - Jupyter notebooks demonstrating features

3. **Testing**
   - Unit tests for different OpenSim components
   - Integration tests with real biomechanical models
   - Cross-platform testing

4. **Build System Improvements**
   - CMake configuration optimizations
   - CI/CD pipeline enhancements
   - Packaging and distribution improvements

### Reporting Issues

When reporting issues, please include:

- **Python version** and operating system
- **pyopensim version**: `python -c "import pyopensim; print(pyopensim.__version__)"`
- **Minimal code example** that reproduces the issue
- **Expected vs actual behavior**
- **Full error messages** and stack traces

### Community Guidelines

- **Be respectful** and constructive in all interactions
- **Search existing issues** before creating new ones
- **Provide context** when asking questions or reporting problems
- **Help others** when you can - sharing knowledge benefits everyone

### Getting Help

- **GitHub Issues**: For bug reports and feature requests
- **Discussions**: For questions and community support
- **OpenSim Forum**: For general OpenSim usage questions

## Recognition

Contributors who help improve the type stubs and overall project quality will be acknowledged in:
- Release notes
- Contributors list
- Project documentation

Thank you for helping make pyopensim better for the entire biomechanics and simulation community!