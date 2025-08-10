cmake_minimum_required(VERSION 3.15...3.27)
project(pyopensim VERSION "0.0.1")

# Set C++ standard to 14 (required by OpenSim)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Set architecture for macOS builds
if(APPLE)
    # Check if CMAKE_OSX_ARCHITECTURES is already set (e.g., by cibuildwheel for universal2)
    if(NOT CMAKE_OSX_ARCHITECTURES)
        # Only auto-detect if not already specified
        execute_process(COMMAND uname -m OUTPUT_VARIABLE MACHINE_ARCH OUTPUT_STRIP_TRAILING_WHITESPACE)
        message(STATUS "Auto-detected architecture: ${MACHINE_ARCH}")
        if(MACHINE_ARCH STREQUAL "arm64")
            set(CMAKE_OSX_ARCHITECTURES "arm64")
            message(STATUS "Building for Apple Silicon (arm64)")
        else()
            set(CMAKE_OSX_ARCHITECTURES "x86_64")  
            message(STATUS "Building for Intel Mac (x86_64)")
        endif()
    else()
        message(STATUS "Using pre-configured architectures: ${CMAKE_OSX_ARCHITECTURES}")
    endif()
endif()

# Find required packages
# Set SWIG paths - check workspace first, then fallback to system paths
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/build/opensim-workspace/swig-install/bin/swig")
    set(SWIG_EXECUTABLE "${CMAKE_CURRENT_SOURCE_DIR}/build/opensim-workspace/swig-install/bin/swig")
    # Find the versioned SWIG directory
    file(GLOB SWIG_VERSION_DIRS "${CMAKE_CURRENT_SOURCE_DIR}/build/opensim-workspace/swig-install/share/swig/*")
    list(GET SWIG_VERSION_DIRS 0 SWIG_DIR)
    if(NOT SWIG_DIR)
        set(SWIG_DIR "${CMAKE_CURRENT_SOURCE_DIR}/build/opensim-workspace/swig-install/share/swig")
    endif()
    message(STATUS "Using workspace SWIG_EXECUTABLE: ${SWIG_EXECUTABLE}")
    message(STATUS "Using workspace SWIG_DIR: ${SWIG_DIR}")
elseif(EXISTS "${CMAKE_CURRENT_BINARY_DIR}/../build/opensim-workspace/swig-install/bin/swig")
    set(SWIG_EXECUTABLE "${CMAKE_CURRENT_BINARY_DIR}/../build/opensim-workspace/swig-install/bin/swig")
    # Find the versioned SWIG directory
    file(GLOB SWIG_VERSION_DIRS "${CMAKE_CURRENT_BINARY_DIR}/../build/opensim-workspace/swig-install/share/swig/*")
    list(GET SWIG_VERSION_DIRS 0 SWIG_DIR)
    if(NOT SWIG_DIR)
        set(SWIG_DIR "${CMAKE_CURRENT_BINARY_DIR}/../build/opensim-workspace/swig-install/share/swig")
    endif()
    message(STATUS "Using workspace SWIG_EXECUTABLE: ${SWIG_EXECUTABLE}")
    message(STATUS "Using workspace SWIG_DIR: ${SWIG_DIR}")
elseif(EXISTS "$ENV{HOME}/swig/bin/swig")
    set(SWIG_EXECUTABLE "$ENV{HOME}/swig/bin/swig")
else()
    # Let find_package try to locate SWIG
    message(STATUS "SWIG not found in workspace, will search system paths")
endif()
find_package(SWIG 4.1.1 REQUIRED)

# Try to find Python3 with Development components, fallback gracefully for cibuildwheel
find_package(Python3 REQUIRED COMPONENTS Interpreter)
find_package(Python3 COMPONENTS Development QUIET)

# If Development component wasn't found, try alternative approach for cibuildwheel/manylinux
if(NOT Python3_Development_FOUND)
    message(STATUS "Python3 Development component not found via find_package, trying manual detection...")
    
    # Get Python include directory manually
    execute_process(
        COMMAND "${Python3_EXECUTABLE}" -c "import sysconfig; print(sysconfig.get_path('include'))"
        OUTPUT_VARIABLE Python3_INCLUDE_DIRS
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE PYTHON_INCLUDE_RESULT
    )
    
    # Get Python library path manually
    execute_process(
        COMMAND "${Python3_EXECUTABLE}" -c "import sysconfig; print(sysconfig.get_config_var('LIBDIR') or '')"
        OUTPUT_VARIABLE PYTHON_LIBDIR
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    
    execute_process(
        COMMAND "${Python3_EXECUTABLE}" -c "import sysconfig; print(sysconfig.get_config_var('LDLIBRARY') or sysconfig.get_config_var('LIBRARY') or '')"
        OUTPUT_VARIABLE PYTHON_LIBRARY_NAME
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    
    if(PYTHON_INCLUDE_RESULT EQUAL 0 AND Python3_INCLUDE_DIRS AND EXISTS "${Python3_INCLUDE_DIRS}")
        message(STATUS "Found Python include directory: ${Python3_INCLUDE_DIRS}")
        
        # Try to find the library file
        if(PYTHON_LIBDIR AND PYTHON_LIBRARY_NAME)
            set(Python3_LIBRARY_CANDIDATES
                "${PYTHON_LIBDIR}/${PYTHON_LIBRARY_NAME}"
                "${PYTHON_LIBDIR}/lib${PYTHON_LIBRARY_NAME}"
            )
            
            foreach(candidate ${Python3_LIBRARY_CANDIDATES})
                if(EXISTS "${candidate}")
                    set(Python3_LIBRARIES "${candidate}")
                    message(STATUS "Found Python library: ${Python3_LIBRARIES}")
                    break()
                endif()
            endforeach()
        endif()
        
        # If we found includes but not libraries, that's often OK for SWIG bindings
        # Many Python installations (especially in containers) use dynamic linking
        if(NOT Python3_LIBRARIES)
            message(STATUS "Python development libraries not found, but includes are available")
            message(STATUS "This is often acceptable for SWIG bindings in containerized environments")
            set(Python3_LIBRARIES "") # Set empty to avoid undefined variable errors
        endif()
        
        set(Python3_Development_FOUND TRUE)
    else()
        message(FATAL_ERROR "Could not find Python development headers. Please install python3-dev or python3-devel package.")
    endif()
else()
    message(STATUS "Found Python3 Development component via find_package")
endif()

# Find NumPy headers manually (as CMake NumPy component may not be available)
execute_process(
    COMMAND "${Python3_EXECUTABLE}" -c "import numpy; print(numpy.get_include())"
    OUTPUT_VARIABLE Python3_NumPy_INCLUDE_DIRS
    OUTPUT_STRIP_TRAILING_WHITESPACE
    RESULT_VARIABLE NumPy_FIND_RESULT
)

if(NOT NumPy_FIND_RESULT EQUAL 0)
    message(FATAL_ERROR "NumPy not found - required for SWIG bindings")
endif()

message(STATUS "Found NumPy include directory: ${Python3_NumPy_INCLUDE_DIRS}")

# Windows-specific compiler flags
if(WIN32 AND MSVC)
    # Add UTF-8 support flag to fix Unicode compilation issues
    # Add /bigobj flag to handle large object files (needed for spdlog and SWIG)
    add_compile_options(/utf-8 /bigobj)
endif()

# Options for OpenSim integration
option(PYOPENSIM_BUILD_WITH_OPENSIM "Build with OpenSim support" ON)
option(PYOPENSIM_USE_SYSTEM_OPENSIM "Use system-installed OpenSim if available" OFF)

if(PYOPENSIM_BUILD_WITH_OPENSIM)
    # Try to find system OpenSim first if requested
    set(OPENSIM_FOUND FALSE)
    if(PYOPENSIM_USE_SYSTEM_OPENSIM)
        find_package(OpenSim QUIET)
        if(OpenSim_FOUND)
            message(STATUS "Found system OpenSim installation")
            set(OPENSIM_FOUND TRUE)
        else()
            message(STATUS "System OpenSim not found, will build from source")
        endif()
    endif()
    
    if(NOT OPENSIM_FOUND)
        # Set OpenSim paths - check both source and binary directories for workspace
        # During uv build, the workspace might be in the original source directory
        if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/build/opensim-workspace")
            set(OPENSIM_WORKSPACE "${CMAKE_CURRENT_SOURCE_DIR}/build/opensim-workspace")
        elseif(EXISTS "${CMAKE_CURRENT_BINARY_DIR}/../build/opensim-workspace")
            set(OPENSIM_WORKSPACE "${CMAKE_CURRENT_BINARY_DIR}/../build/opensim-workspace")
        else()
            set(OPENSIM_WORKSPACE "${CMAKE_CURRENT_SOURCE_DIR}/build/opensim-workspace")
        endif()
        set(OPENSIM_BUILD_DIR "${OPENSIM_WORKSPACE}/opensim-build")
        set(OPENSIM_INSTALL_DIR "${OPENSIM_WORKSPACE}/opensim-install")
        set(OPENSIM_DEPENDENCIES_DIR "${OPENSIM_WORKSPACE}/dependencies-install")

        # Platform-specific library extensions and setup scripts
        if(WIN32)
            set(LIB_EXT ".lib")
            set(DLL_EXT ".dll")
            set(SETUP_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/scripts/opensim/setup_opensim_windows.ps1")
            set(TEST_LIB "${OPENSIM_INSTALL_DIR}/sdk/lib/osimCommon${LIB_EXT}")
        elseif(APPLE)
            set(LIB_EXT ".dylib")
            set(DLL_EXT ".dylib")
            set(SETUP_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/scripts/opensim/setup_opensim_macos.sh")
            set(TEST_LIB "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimCommon${LIB_EXT}")
        else()
            # Linux and other Unix-like systems
            set(LIB_EXT ".so")
            set(DLL_EXT ".so")
            set(SETUP_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/scripts/opensim/setup_opensim_linux.sh")
            set(TEST_LIB "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimCommon${LIB_EXT}")
        endif()

        # Check if OpenSim libraries exist - robust check for multiple critical files
        set(OPENSIM_REQUIRED_LIBS)
        if(WIN32)
            # Windows: OpenSim libraries in sdk/lib/, Simbody in sdk/Simbody/lib/
            list(APPEND OPENSIM_REQUIRED_LIBS
                "${OPENSIM_INSTALL_DIR}/sdk/lib/osimCommon${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/osimSimulation${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/SimTKcommon${LIB_EXT}"
            )
        else()
            # Linux and macOS use same library structure after OpenSim install
            list(APPEND OPENSIM_REQUIRED_LIBS
                "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimCommon${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimSimulation${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/libSimTKcommon${LIB_EXT}"
            )
        endif()
        
        # Check if all required libraries exist
        set(OPENSIM_LIBS_MISSING FALSE)
        foreach(REQUIRED_LIB ${OPENSIM_REQUIRED_LIBS})
            if(NOT EXISTS "${REQUIRED_LIB}")
                set(OPENSIM_LIBS_MISSING TRUE)
                message(STATUS "Missing OpenSim library: ${REQUIRED_LIB}")
                break()
            endif()
        endforeach()
        
        # Check for OpenSim installation completion
        set(OPENSIM_BUILD_NEEDED FALSE)
        
        if(OPENSIM_LIBS_MISSING)
            message(STATUS "OpenSim libraries missing")
            set(OPENSIM_BUILD_NEEDED TRUE)
        else()
            message(STATUS "Found OpenSim installation")
        endif()
        
        # Only run setup if actually needed
        if(OPENSIM_BUILD_NEEDED)
            message(STATUS "Running OpenSim setup...")
            if(WIN32)
                execute_process(
                    COMMAND powershell.exe -ExecutionPolicy Bypass -File ${SETUP_SCRIPT}
                    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
                    RESULT_VARIABLE SETUP_RESULT
                )
            else()
                execute_process(
                    COMMAND ${SETUP_SCRIPT}
                    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
                    RESULT_VARIABLE SETUP_RESULT
                )
            endif()
            
            if(NOT SETUP_RESULT EQUAL 0)
                message(FATAL_ERROR "OpenSim setup failed with code ${SETUP_RESULT}")
            endif()
            
            message(STATUS "OpenSim setup completed successfully")
        endif()
    endif() # Close if(NOT OPENSIM_FOUND)
else()
    message(STATUS "Building PyOpenSim stubs without OpenSim")
endif()

# ==============================================================================
# SWIG BINDINGS CONFIGURATION
# ==============================================================================

# Location of the opensim python package in the build directory, for testing.
if(MSVC OR XCODE)
    # Multi-configuration generators like MSVC and XCODE use one build tree for
    # all configurations.
    set(OPENSIM_PYTHON_BINARY_DIR
        "${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_CFG_INTDIR}")
else()
    set(OPENSIM_PYTHON_BINARY_DIR
        "${CMAKE_CURRENT_BINARY_DIR}/${CMAKE_BUILD_TYPE}")
endif()

# Helper function to for copying files into the python package.
macro(OpenSimPutFileInPythonPackage source_full_path relative_dest_dir)
    # Python package in the build tree.
    # ---------------------------------
    get_filename_component(file_name "${source_full_path}" NAME)
    set(binary_dest_full_path
        "${OPENSIM_PYTHON_BINARY_DIR}/${relative_dest_dir}/${file_name}")
    add_custom_command(
        DEPENDS "${source_full_path}"
        OUTPUT "${binary_dest_full_path}"
        COMMAND ${CMAKE_COMMAND} -E copy "${source_full_path}"
                                         "${binary_dest_full_path}"
        COMMENT "Copying ${source_full_path} to python package in build directory"
        VERBATIM
        )
    # This list is used to specify dependencies for the PythonBindings target.
    list(APPEND OPENSIM_PYTHON_PACKAGE_FILES "${binary_dest_full_path}")

    # Python package in the installation.
    # -----------------------------------
    install(FILES "${source_full_path}"
        DESTINATION "${CMAKE_INSTALL_PREFIX}/pyopensim/${relative_dest_dir}")
endmacro()

# Set SWIG options
set(SWIG_FLAGS "")
if(EXISTS "${OPENSIM_INSTALL_DIR}/sdk/lib/libezc3d${LIB_EXT}")
    set(SWIG_FLAGS "-DWITH_EZC3D")
endif()

# Function to add SWIG Python modules
macro(OpenSimAddPythonModule)
    # Parse arguments.
    set(options)
    set(oneValueArgs MODULE)
    set(multiValueArgs DEPENDS)
    cmake_parse_arguments(
        OSIMSWIGPY "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # Generate source code for wrapper using SWIG.
    set(_output_file_prefix
        "${CMAKE_CURRENT_BINARY_DIR}/python_${OSIMSWIGPY_MODULE}_wrap")
    set(_output_cxx_file "${_output_file_prefix}.cxx")
    set(_output_header_file "${_output_file_prefix}.h")
    set(_interface_file
        "${CMAKE_CURRENT_SOURCE_DIR}/src/pyopensim/swig/pyopensim_${OSIMSWIGPY_MODULE}.i")

    # SWIG command arguments
    set(_swig_common_args -c++ -python
            -I${CMAKE_CURRENT_SOURCE_DIR}/src/opensim-core
            -I${CMAKE_CURRENT_SOURCE_DIR}/src/opensim-core/Bindings
            -I${CMAKE_CURRENT_SOURCE_DIR}/src/opensim-core/Bindings/Python/swig
            -I${CMAKE_CURRENT_SOURCE_DIR}/src/opensim-core/Vendors/lepton/include
            -I${OPENSIM_INSTALL_DIR}/sdk/Simbody/include
            -I${OPENSIM_INSTALL_DIR}/sdk/Simbody/include/simbody
            -I${OPENSIM_INSTALL_DIR}/sdk/include
            -I${OPENSIM_INSTALL_DIR}/sdk/include/OpenSim
            -v
            ${SWIG_FLAGS}
            ${_interface_file}
            )

    # Run swig.
    add_custom_command(
        OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${OSIMSWIGPY_MODULE}.py"
            ${_output_cxx_file} ${_output_header_file}
        COMMAND ${SWIG_EXECUTABLE}
            -v # verbose
            -o ${_output_cxx_file}
            -outdir "${CMAKE_CURRENT_BINARY_DIR}"
            ${_swig_common_args}
        DEPENDS ${_interface_file}
            COMMENT "Generating python bindings source code with SWIG: ${OSIMSWIGPY_MODULE} module."
        )

    # Compile python wrapper files into a library.
    set(_libname _${OSIMSWIGPY_MODULE}) 

    # Used for specifying dependencies for PythonBindings.
    list(APPEND OPENSIM_PYTHON_PACKAGE_LIBRARY_TARGETS ${_libname})

    # Compiler flags for SWIG wrapper code
    if(${CMAKE_CXX_COMPILER_ID} MATCHES "GNU" OR
            ${CMAKE_CXX_COMPILER_ID} MATCHES "Clang")
        # Turn off optimization for SWIG wrapper code
        set(_COMPILE_FLAGS "-O0 -Wno-deprecated-declarations")
    elseif(${CMAKE_CXX_COMPILER_ID} MATCHES "MSVC")
        # Don't warn about deprecated functions and const const T
        set(_COMPILE_FLAGS "/wd4996 /wd4114")
    endif()
    if(${CMAKE_CXX_COMPILER_ID} MATCHES "Clang" AND
            NOT (${CMAKE_CXX_COMPILER_VERSION} VERSION_LESS "10"))
        # SWIG uses the register keyword, which is deprecated in C++17.
        set(_COMPILE_FLAGS "${_COMPILE_FLAGS} -Wno-deprecated-register")
    endif()
    set_source_files_properties("${_output_cxx_file}"
        PROPERTIES COMPILE_FLAGS "${_COMPILE_FLAGS} -DSWIG_PYTHON")

    add_library(${_libname} SHARED ${_output_cxx_file} ${_output_header_file})

    target_include_directories(${_libname} PRIVATE
            "${Python3_INCLUDE_DIRS}"
            "${Python3_NumPy_INCLUDE_DIRS}")
    
    # Python library linking (handle static linking case on macOS and missing libraries)
    execute_process(COMMAND "${Python3_EXECUTABLE}" -c
        "import sysconfig; print(sysconfig.get_config_var('LDSHARED'))"
        OUTPUT_VARIABLE PYTHON_LDSHARED
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    if("${PYTHON_LDSHARED}" MATCHES "dynamic_lookup")
        set_target_properties(${_libname} PROPERTIES LINK_FLAGS
            "-undefined dynamic_lookup")
    elseif(Python3_LIBRARIES)
        target_link_libraries(${_libname} ${Python3_LIBRARIES})
    else()
        # No Python libraries found, but this is often OK for SWIG bindings
        # in containerized environments where Python symbols are resolved at runtime
        message(STATUS "Skipping Python library linking (symbols resolved at runtime)")
    endif()

    # Link against OpenSim libraries
    if(PYOPENSIM_BUILD_WITH_OPENSIM)
        # Platform-specific library paths
        if(WIN32)
            # Windows: OpenSim libraries in sdk/lib/, Simbody libraries in sdk/Simbody/lib/
            set(OSIM_LIBS
                "${OPENSIM_INSTALL_DIR}/sdk/lib/osimCommon${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/osimSimulation${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/osimActuators${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/osimAnalyses${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/osimTools${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/SimTKcommon${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/SimTKmath${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/SimTKsimbody${LIB_EXT}"
            )
        else()
            set(OSIM_LIBS
                "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimCommon${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimSimulation${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimActuators${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimAnalyses${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimTools${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/libSimTKcommon${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/libSimTKmath${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/libSimTKsimbody${LIB_EXT}"
            )
        endif()

        # Add optional libraries if they exist
        set(OPTIONAL_LIBS)
        if(WIN32)
            # Windows: Optional libraries in sdk/lib/
            list(APPEND OPTIONAL_LIBS 
                "${OPENSIM_INSTALL_DIR}/sdk/lib/osimLepton${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/osimdocopt${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/ezc3d${LIB_EXT}")
        else()
            list(APPEND OPTIONAL_LIBS 
                "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimLepton${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimdocopt${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/lib/libezc3d${LIB_EXT}")
        endif()

        # Filter existing libraries
        set(EXISTING_LIBS)
        foreach(LIB ${OSIM_LIBS})
            if(EXISTS "${LIB}")
                list(APPEND EXISTING_LIBS "${LIB}")
            endif()
        endforeach()
        foreach(LIB ${OPTIONAL_LIBS})
            if(EXISTS "${LIB}")
                list(APPEND EXISTING_LIBS "${LIB}")
            endif()
        endforeach()

        target_link_libraries(${_libname} ${EXISTING_LIBS})
        
        # Include directories
        target_include_directories(${_libname} PRIVATE 
            ${CMAKE_CURRENT_SOURCE_DIR}/src/opensim-core
            ${CMAKE_CURRENT_SOURCE_DIR}/src/opensim-core/Bindings
            ${CMAKE_CURRENT_SOURCE_DIR}/src/opensim-core/Vendors/lepton/include
            ${OPENSIM_INSTALL_DIR}/sdk/include
            ${OPENSIM_INSTALL_DIR}/sdk/include/OpenSim
            ${OPENSIM_INSTALL_DIR}/sdk/Simbody/include
            ${OPENSIM_INSTALL_DIR}/sdk/Simbody/include/simbody
            ${OPENSIM_INSTALL_DIR}/sdk/spdlog/include
            ${OPENSIM_DEPENDENCIES_DIR}/spdlog/include
            ${OPENSIM_DEPENDENCIES_DIR}/simbody/include
            ${OPENSIM_DEPENDENCIES_DIR}/simbody/include/simbody
        )
    endif()
    
    # Set target properties for various platforms.
    set_target_properties(${_libname} PROPERTIES
        PROJECT_LABEL "Python - ${_libname}"
        FOLDER "Bindings"
        PREFIX ""
    )
    if(WIN32)
        set_target_properties(${_libname} PROPERTIES SUFFIX ".pyd")
    elseif(APPLE)
        # Defaults to .dylib; change to .so.
        set_target_properties(${_libname} PROPERTIES SUFFIX ".so")
    endif()
    
    # Configure RPATH for self-contained wheel
    if(NOT WIN32)
        if(APPLE)
            set_target_properties(${_libname} PROPERTIES
                BUILD_RPATH_USE_ORIGIN TRUE
                INSTALL_RPATH "@loader_path/lib"
                BUILD_RPATH "@loader_path/lib"
            )
        else()
            set_target_properties(${_libname} PROPERTIES
                BUILD_RPATH_USE_ORIGIN TRUE
                INSTALL_RPATH "$ORIGIN/lib"
                BUILD_RPATH "$ORIGIN/lib"
            )
        endif()
    endif()

    # Copy files into the build tree python package.
    add_custom_command(TARGET ${_libname} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:${_libname}>"
            "${OPENSIM_PYTHON_BINARY_DIR}/pyopensim/$<TARGET_FILE_NAME:${_libname}>"
        COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/${OSIMSWIGPY_MODULE}.py"
            "${OPENSIM_PYTHON_BINARY_DIR}/pyopensim/${OSIMSWIGPY_MODULE}.py"
        COMMENT "Copying ${OSIMSWIGPY_MODULE}.py and ${_libname} to python package in build directory."
        VERBATIM
        )

    # Install the python module and compiled library.
    install(TARGETS ${_libname} DESTINATION "${CMAKE_INSTALL_PREFIX}/pyopensim")
    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/${OSIMSWIGPY_MODULE}.py"
        DESTINATION "${CMAKE_INSTALL_PREFIX}/pyopensim")

endmacro()

# Build python modules (generate binding source code and compile it).
OpenSimAddPythonModule(MODULE simbody)
OpenSimAddPythonModule(MODULE common)
OpenSimAddPythonModule(MODULE simulation)
OpenSimAddPythonModule(MODULE actuators)
OpenSimAddPythonModule(MODULE analyses)
OpenSimAddPythonModule(MODULE tools)

# Copy files to create complete package in the build tree.
# Configure version.py.
configure_file(${CMAKE_CURRENT_SOURCE_DIR}/src/opensim-core/Bindings/Python/version.py.in
    "${CMAKE_CURRENT_BINARY_DIR}/version.py" @ONLY)

# Copy the configured version.py for each build configuration.
OpenSimPutFileInPythonPackage("${CMAKE_CURRENT_BINARY_DIR}/version.py" pyopensim)

# __init__.py - use our custom pyopensim __init__.py instead of OpenSim's
OpenSimPutFileInPythonPackage("${CMAKE_CURRENT_SOURCE_DIR}/src/pyopensim/__init__.py" .)

# py.typed marker file for PEP 561 compliance
OpenSimPutFileInPythonPackage("${CMAKE_CURRENT_SOURCE_DIR}/src/pyopensim/py.typed" .)

# Generate stub files for IDE support
set(STUB_FILES_DIR "${CMAKE_CURRENT_BINARY_DIR}/stubs")
add_custom_command(
    OUTPUT "${STUB_FILES_DIR}/pyopensim/__init__.pyi"
    DEPENDS ${OPENSIM_PYTHON_PACKAGE_LIBRARY_TARGETS}
    COMMAND ${Python3_EXECUTABLE} "${CMAKE_CURRENT_SOURCE_DIR}/scripts/python/generate_stubs.py"
        "${OPENSIM_PYTHON_BINARY_DIR}"
        "${STUB_FILES_DIR}"
    COMMENT "Generating Python stub files for IDE support"
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
)

# Copy stub files to the python package directory
add_custom_command(
    OUTPUT "${OPENSIM_PYTHON_BINARY_DIR}/pyopensim-stubs"
    DEPENDS "${STUB_FILES_DIR}/pyopensim/__init__.pyi"
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${STUB_FILES_DIR}/pyopensim"
        "${OPENSIM_PYTHON_BINARY_DIR}/pyopensim-stubs"
    COMMENT "Copying stub files to package directory"
)

# Umbrella target for assembling the python bindings in the build tree.
add_custom_target(PythonBindings ALL DEPENDS ${OPENSIM_PYTHON_PACKAGE_FILES} "${OPENSIM_PYTHON_BINARY_DIR}/pyopensim-stubs")

# Require the libraries to be built.
add_dependencies(PythonBindings ${OPENSIM_PYTHON_PACKAGE_LIBRARY_TARGETS})

set_target_properties(PythonBindings PROPERTIES
    PROJECT_LABEL "Python - umbrella target"
    FOLDER "Bindings")

# Install OpenSim libraries into the wheel
if(PYOPENSIM_BUILD_WITH_OPENSIM)
    message(STATUS "=== PYOPENSIM: Installing libraries into wheel ===")
    message(STATUS "=== PYOPENSIM: CMAKE_SYSTEM_NAME = ${CMAKE_SYSTEM_NAME} ===")
    message(STATUS "=== PYOPENSIM: OPENSIM_INSTALL_DIR = ${OPENSIM_INSTALL_DIR} ===")
    # Create lib directory in the install location
    install(DIRECTORY DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
    
    # Install OpenSim libraries - platform specific paths
    if(WIN32)
        # Windows: OpenSim libraries in sdk/lib/ directory, need both .lib and .dll
        set(INSTALL_LIBS
            "${OPENSIM_INSTALL_DIR}/sdk/lib/osimCommon${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/lib/osimSimulation${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/lib/osimActuators${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/lib/osimAnalyses${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/lib/osimTools${LIB_EXT}"
        )
        # Also install runtime DLLs for Windows
        set(INSTALL_DLLS
            "${OPENSIM_INSTALL_DIR}/bin/osimCommon.dll"
            "${OPENSIM_INSTALL_DIR}/bin/osimSimulation.dll"
            "${OPENSIM_INSTALL_DIR}/bin/osimActuators.dll"
            "${OPENSIM_INSTALL_DIR}/bin/osimAnalyses.dll"
            "${OPENSIM_INSTALL_DIR}/bin/osimTools.dll"
        )
    else()
        # Linux/macOS: OpenSim libraries in sdk/lib/ directory
        set(INSTALL_LIBS
            "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimCommon${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimSimulation${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimActuators${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimAnalyses${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimTools${LIB_EXT}"
        )
    endif()
    
    foreach(LIB ${INSTALL_LIBS})
        if(EXISTS "${LIB}")
            install(FILES "${LIB}" DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
        endif()
    endforeach()
    
    # Install Windows DLLs if they exist
    if(WIN32 AND INSTALL_DLLS)
        foreach(DLL ${INSTALL_DLLS})
            if(EXISTS "${DLL}")
                install(FILES "${DLL}" DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
            endif()
        endforeach()
    endif()
    
    # Install Simbody libraries (including versioned libraries)
    if(WIN32)
        # Windows: Install both .lib and .dll files for Simbody
        set(SIMBODY_LIBS
            "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/SimTKcommon${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/SimTKmath${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/SimTKsimbody${LIB_EXT}"
        )
        set(SIMBODY_DLLS
            "${OPENSIM_INSTALL_DIR}/sdk/Simbody/bin/SimTKcommon.dll"
            "${OPENSIM_INSTALL_DIR}/sdk/Simbody/bin/SimTKmath.dll"
            "${OPENSIM_INSTALL_DIR}/sdk/Simbody/bin/SimTKsimbody.dll"
        )
        foreach(LIB ${SIMBODY_LIBS})
            if(EXISTS "${LIB}")
                install(FILES "${LIB}" DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
            endif()
        endforeach()
        foreach(DLL ${SIMBODY_DLLS})
            if(EXISTS "${DLL}")
                install(FILES "${DLL}" DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
            endif()
        endforeach()
    elseif(APPLE)
        # Debug: List all directories that might contain SimTK libraries
        message(STATUS "=== DEBUG: Searching for SimTK libraries ===")
        message(STATUS "OPENSIM_INSTALL_DIR: ${OPENSIM_INSTALL_DIR}")
        message(STATUS "OPENSIM_DEPENDENCIES_DIR: ${OPENSIM_DEPENDENCIES_DIR}")
        
        # Check what's actually in the OpenSim Simbody lib directory
        if(EXISTS "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib")
            file(GLOB ALL_FILES_IN_SIMBODY_LIB "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/*")
            message(STATUS "All files in ${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib: ${ALL_FILES_IN_SIMBODY_LIB}")
        else()
            message(STATUS "Directory does not exist: ${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib")
        endif()
        
        # Check dependencies Simbody lib directory
        if(EXISTS "${OPENSIM_DEPENDENCIES_DIR}/simbody/lib")
            file(GLOB ALL_FILES_IN_DEPS_SIMBODY_LIB "${OPENSIM_DEPENDENCIES_DIR}/simbody/lib/*")
            message(STATUS "All files in ${OPENSIM_DEPENDENCIES_DIR}/simbody/lib: ${ALL_FILES_IN_DEPS_SIMBODY_LIB}")
        else()
            message(STATUS "Directory does not exist: ${OPENSIM_DEPENDENCIES_DIR}/simbody/lib")
        endif()
        
        # Install both versioned and unversioned SimTK libraries for macOS
        file(GLOB SIMBODY_ALL_LIBS 
            "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/libSimTK*.dylib*"
        )
        message(STATUS "Found SimTK libraries in OpenSim install: ${SIMBODY_ALL_LIBS}")
        if(SIMBODY_ALL_LIBS)
            install(FILES ${SIMBODY_ALL_LIBS}
                DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
        endif()
        
        # Also check dependencies directory for any additional SimTK libraries
        file(GLOB SIMBODY_DEPS_LIBS 
            "${OPENSIM_DEPENDENCIES_DIR}/simbody/lib/libSimTK*.dylib*"
        )
        message(STATUS "Found SimTK libraries in dependencies: ${SIMBODY_DEPS_LIBS}")
        if(SIMBODY_DEPS_LIBS)
            install(FILES ${SIMBODY_DEPS_LIBS}
                DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
        endif()
        
        # Additional search in case libraries are in different locations
        file(GLOB_RECURSE RECURSIVE_SIMBODY_LIBS 
            "${OPENSIM_INSTALL_DIR}/**/libSimTK*.dylib*"
            "${OPENSIM_DEPENDENCIES_DIR}/**/libSimTK*.dylib*"
        )
        message(STATUS "Recursive search found SimTK libraries: ${RECURSIVE_SIMBODY_LIBS}")
        
        # Install any additional libraries found recursively that weren't already included
        foreach(LIB ${RECURSIVE_SIMBODY_LIBS})
            list(FIND SIMBODY_ALL_LIBS "${LIB}" FOUND_IN_INSTALL)
            list(FIND SIMBODY_DEPS_LIBS "${LIB}" FOUND_IN_DEPS)
            if(FOUND_IN_INSTALL EQUAL -1 AND FOUND_IN_DEPS EQUAL -1)
                message(STATUS "Installing additional SimTK library: ${LIB}")
                install(FILES "${LIB}" DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
            endif()
        endforeach()
        message(STATUS "=== END DEBUG ===")
        
        # Specifically check for the missing versioned libraries
        set(REQUIRED_VERSIONED_LIBS
            "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/libSimTKmath.3.8.dylib"
            "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/libSimTKcommon.3.8.dylib"
            "${OPENSIM_DEPENDENCIES_DIR}/simbody/lib/libSimTKmath.3.8.dylib"
            "${OPENSIM_DEPENDENCIES_DIR}/simbody/lib/libSimTKcommon.3.8.dylib"
        )
        foreach(LIB ${REQUIRED_VERSIONED_LIBS})
            if(EXISTS "${LIB}")
                message(STATUS "FOUND required versioned library: ${LIB}")
                install(FILES "${LIB}" DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
            else()
                message(STATUS "MISSING required versioned library: ${LIB}")
            endif()
        endforeach()
    else()
        # Linux - ensure both versioned and symlinked libraries are installed
        message(STATUS "Installing SimTK libraries for Linux...")
        
        # Check both lib and lib64 directories for SimTK libraries
        set(SIMBODY_SEARCH_PATHS
            "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib"
            "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib64"
        )
        
        set(SIMBODY_ALL_LIBS)
        foreach(SEARCH_PATH ${SIMBODY_SEARCH_PATHS})
            message(STATUS "Searching for SimTK libraries in: ${SEARCH_PATH}")
            file(GLOB FOUND_LIBS "${SEARCH_PATH}/libSimTK*.so*")
            if(FOUND_LIBS)
                message(STATUS "Found SimTK libraries in ${SEARCH_PATH}: ${FOUND_LIBS}")
                list(APPEND SIMBODY_ALL_LIBS ${FOUND_LIBS})
            else()
                message(STATUS "No SimTK libraries in ${SEARCH_PATH}")
            endif()
        endforeach()
        
        message(STATUS "All found SimTK libraries: ${SIMBODY_ALL_LIBS}")
        
        if(SIMBODY_ALL_LIBS)
            # Install all found libraries (both versioned and symlinks)
            foreach(LIB ${SIMBODY_ALL_LIBS})
                message(STATUS "Installing SimTK library: ${LIB}")
                install(FILES "${LIB}" DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
            endforeach()
        else()
            message(WARNING "No SimTK libraries found in any search paths: ${SIMBODY_SEARCH_PATHS}")
        endif()
        
        # Also check dependencies-install directory as fallback
        file(GLOB DEPS_SIMBODY_LIBS 
            "${OPENSIM_DEPENDENCIES_DIR}/simbody/lib*/libSimTK*.so*"
        )
        if(DEPS_SIMBODY_LIBS)
            message(STATUS "Found additional SimTK libraries in dependencies: ${DEPS_SIMBODY_LIBS}")
            foreach(LIB ${DEPS_SIMBODY_LIBS})
                message(STATUS "Installing dependency SimTK library: ${LIB}")
                install(FILES "${LIB}" DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
            endforeach()
        endif()
    endif()
    
    # Install optional libraries - platform specific paths
    if(WIN32)
        set(OPTIONAL_INSTALL_LIBS
            "${OPENSIM_INSTALL_DIR}/sdk/lib/osimLepton${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/lib/osimdocopt${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/lib/ezc3d${LIB_EXT}"
        )
        set(OPTIONAL_INSTALL_DLLS
            "${OPENSIM_INSTALL_DIR}/bin/osimLepton.dll"
            "${OPENSIM_INSTALL_DIR}/bin/osimdocopt.dll"
            "${OPENSIM_INSTALL_DIR}/bin/ezc3d.dll"
        )
    else()
        set(OPTIONAL_INSTALL_LIBS
            "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimLepton${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimdocopt${LIB_EXT}"
            "${OPENSIM_INSTALL_DIR}/sdk/lib/libezc3d${LIB_EXT}"
        )
    endif()
    
    foreach(LIB ${OPTIONAL_INSTALL_LIBS})
        if(EXISTS "${LIB}")
            install(FILES "${LIB}" DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
        endif()
    endforeach()
    
    # Install optional Windows DLLs if they exist
    if(WIN32 AND OPTIONAL_INSTALL_DLLS)
        foreach(DLL ${OPTIONAL_INSTALL_DLLS})
            if(EXISTS "${DLL}")
                install(FILES "${DLL}" DESTINATION ${CMAKE_INSTALL_PREFIX}/pyopensim/lib)
            endif()
        endforeach()
    endif()
endif()

# Install stub files for IDE support
install(DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/stubs/pyopensim/"
    DESTINATION "${CMAKE_INSTALL_PREFIX}/pyopensim-stubs"
    FILES_MATCHING PATTERN "*.pyi")