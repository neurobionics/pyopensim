<p align="center">
  <img src="/pyopensim.jpg" width="100%">
</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/supports-linux,%20macos,%20windows-blue" alt="support"></a>
  <a href="https://github.com/neurobionics/pyopensim/actions"><img src="https://img.shields.io/github/actions/workflow/status/neurobionics/pyopensim/wheels.yml" alt="build"></a>
  <a href="https://opensource.org/licenses/Apache-2.0"><img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" alt="kernel"></a>  
  <a href="https://badge.fury.io/py/pyopensim"><img src="https://badge.fury.io/py/pyopensim.svg" alt="pypi"></a>
  <a href="https://pepy.tech/projects/pyopensim"><img src="https://static.pepy.tech/personalized-badge/pyopensim?period=total&units=INTERNATIONAL_SYSTEM&left_color=BLACK&right_color=GREEN&left_text=downloads" alt="downloads"></a>
</p>

**PyOpenSim**: Unofficial Portable Python bindings for [OpenSim](https://opensim.stanford.edu/), which is an open source software system for biomechanical modeling, simulation and analysis.

## Key Features

- **Portable**: Self-contained Python wheels with bundled OpenSim libraries
- **Type Hints**: Comprehensive `.pyi` stub files for excellent IDE support and type checking
- **Cross-Platform**: Native support for Linux, macOS, and Windows
- **Official Bindings**: Uses OpenSim's native SWIG bindings for full API compatibility

## Installation

Install directly from PyPI:

```bash
pip install pyopensim
```

No additional setup required! All OpenSim dependencies are bundled in the wheel.

## Why pyopensim?

While the OpenSim team provide an excellent [conda package](https://anaconda.org/opensim-org/opensim), pyopensim offers complementary benefits for specific use cases:

- **Enhanced IDE Support**: Comprehensive type hints (`.pyi` stubs) provide excellent autocomplete, type checking, and documentation in modern IDEs
- **Wheel Distribution**: Self-contained wheels make it easy to bundle OpenSim with your applications without requiring users to manage conda environments
- **Flexible Deployment**: Works well in environments where conda isn't preferred (Docker containers, CI/CD pipelines)

## Quick Start

```python
import pyopensim as osim

# Check versions
print(f"PyOpenSim version: {osim.__version__}")
print(f"OpenSim core version: {osim.__opensim_version__}")

# Create a simple model
model = osim.Model()
model.setName("MyModel")

# Add a body
body = osim.Body("body", 1.0, osim.Vec3(0), osim.Inertia(1))
model.addComponent(body)

# Build and initialize
state = model.initSystem()
print(f"Model has {model.getNumBodies()} bodies")
```

## Versioning

PyOpenSim uses a 4-digit versioning scheme that directly tracks the OpenSim core version:

- **Version format**: `<MAJOR>.<MINOR>.<PATCH>.<BUILD>`
  - Example: `4.5.2.0` - Matches OpenSim 4.5.2 exactly
  - Example: `4.5.2.1` - First Python binding fix for OpenSim 4.5.2
  - Example: `4.5.2.2` - Second Python binding fix for OpenSim 4.5.2

- **What the version tells you**:
  - The first 3 digits (e.g., `4.5.2`) match the bundled OpenSim core version exactly
  - The 4th digit indicates Python binding-specific fixes or improvements
  - A build number of `0` means the bindings match OpenSim without additional changes

This makes it easy to know which OpenSim version you're using:
```python
import pyopensim as osim
print(osim.__version__)          # e.g., "4.5.2.0" or "4.5.2.1"
print(osim.__opensim_version__)  # e.g., "4.5.2" (always the core version)
```

## PyPI Distribution

pyopensim is automatically built and deployed to [PyPI](https://pypi.org/project/pyopensim/) using:

- **Automated Builds**: GitHub Actions CI/CD builds wheels for all platforms
- **cibuildwheel**: Ensures compatibility across Python versions and platforms
- **Bundled Libraries**: All OpenSim dependencies are included in the wheels
- **Version Management**: Semantic versioning automatically aligned with OpenSim releases
- **Automated Tests**: Automated testing ensures each release works correctly (work in progress)

This provides an alternative distribution method that complements the official OpenSim library.

## Contributing

We welcome contributions of all kinds! Whether you're fixing bugs, improving type stubs, or enhancing documentation, your help is appreciated.

**[Contributing Guidelines](CONTRIBUTING.md)** - Complete guide for contributors

**Key areas where you can help:**
- **Type Stub Improvements**: Enhance IDE support and type checking
- **Documentation**: Add examples and usage guides  
- **Testing**: Cross-platform validation and edge cases
- **Bug Reports**: Help us improve reliability

## Relationship to OpenSim

pyopensim is an unofficial python package that is built on top of the official [OpenSim](https://github.com/opensim-org/opensim-core) project:

- **Same API**: Identical to the official OpenSim Python bindings
- **Same Functionality**: Full access to all OpenSim features and capabilities
- **Regular Updates**: Tracks OpenSim releases to provide latest features

To use the official OpenSim conda package, checkout this [package](https://anaconda.org/opensim-org/opensim).

## Development

This project builds OpenSim from source to create self-contained Python wheels.

**Linux/macOS:**
```bash
# Clone the repository
git clone https://github.com/neurobionics/pyopensim.git
cd pyopensim

# Build OpenSim and dependencies
make setup

# Build Python wheels
make build
```

**Windows:**
```powershell
# Clone the repository
git clone https://github.com/neurobionics/pyopensim.git
cd pyopensim

# Build OpenSim and dependencies
.\make.ps1 setup

# Build Python wheels
.\make.ps1 build
```

**See [WINDOWS.md](WINDOWS.md) for detailed Windows build instructions.**

The build process includes:
- Compiling OpenSim's C++ libraries and dependencies
- Generating SWIG Python bindings
- Creating comprehensive type stubs for IDE support
- Bundling everything into portable wheels

## License

This project is licensed under [Apache License 2.0](LICENSE). OpenSim is licensed under the Apache License 2.0.
See the [OpenSim license](https://github.com/opensim-org/opensim-core/blob/main/LICENSE.txt) for details.

## Issues

If you encounter any issues or have questions regarding pyopensim, please open an issue [here](https://github.com/neurobionics/pyopensim/issues).

## Community & Support

- **[Report Issues](https://github.com/neurobionics/pyopensim/issues)** - Bug reports and feature requests
- **[Discussions](https://github.com/neurobionics/pyopensim/discussions)** - Questions and community support
- **[OpenSim Documentation](https://simtk-confluence.stanford.edu/display/OpenSim/Documentation)** - Official OpenSim resources
- **[OpenSim Website](https://opensim.stanford.edu/)** - OpenSim project
