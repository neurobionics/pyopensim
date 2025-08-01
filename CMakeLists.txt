cmake_minimum_required(VERSION 3.15...3.27)
project(pyosim VERSION "0.0.1")

# Set C++ standard to 14 (required by OpenSim)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required packages
set(SWIG_EXECUTABLE "$ENV{HOME}/swig/bin/swig")
find_package(SWIG 4.1.1 REQUIRED)
find_package(Python3 REQUIRED COMPONENTS Interpreter Development)

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
    add_compile_options(/utf-8)
endif()

# Options for OpenSim integration
option(PYOSIM_BUILD_WITH_OPENSIM "Build with OpenSim support" ON)
option(PYOSIM_USE_SYSTEM_OPENSIM "Use system-installed OpenSim if available" OFF)

if(PYOSIM_BUILD_WITH_OPENSIM)
    # Try to find system OpenSim first if requested
    set(OPENSIM_FOUND FALSE)
    if(PYOSIM_USE_SYSTEM_OPENSIM)
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
            set(SETUP_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/scripts/setup_opensim_windows.ps1")
            set(TEST_LIB "${OPENSIM_INSTALL_DIR}/lib/osimCommon${LIB_EXT}")
        elseif(APPLE)
            set(LIB_EXT ".dylib")
            set(DLL_EXT ".dylib")
            set(SETUP_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/scripts/setup_opensim_macos.sh")
            set(TEST_LIB "${OPENSIM_BUILD_DIR}/libosimCommon${LIB_EXT}")
        else()
            set(LIB_EXT ".so")
            set(DLL_EXT ".so")
            set(SETUP_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/scripts/setup_opensim_linux.sh")
            set(TEST_LIB "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimCommon${LIB_EXT}")
        endif()

        # Check if OpenSim libraries exist - robust check for multiple critical files
        set(OPENSIM_REQUIRED_LIBS)
        if(WIN32)
            list(APPEND OPENSIM_REQUIRED_LIBS
                "${OPENSIM_INSTALL_DIR}/lib/osimCommon${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/lib/osimSimulation${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/SimTKcommon${LIB_EXT}"
            )
        else()
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
        
        # Also check for a completion marker file to ensure full build completed
        set(OPENSIM_BUILD_COMPLETE_MARKER "${OPENSIM_WORKSPACE}/.opensim_build_complete")
        
        # Check for OpenSim installation completion
        set(OPENSIM_BUILD_NEEDED FALSE)
        
        if(OPENSIM_LIBS_MISSING)
            message(STATUS "OpenSim libraries missing")
            set(OPENSIM_BUILD_NEEDED TRUE)
        elseif(NOT EXISTS "${OPENSIM_BUILD_COMPLETE_MARKER}")
            message(STATUS "OpenSim build completion marker missing")
            set(OPENSIM_BUILD_NEEDED TRUE)
        else()
            # Additional validation: check marker file age vs script modification
            file(TIMESTAMP "${OPENSIM_BUILD_COMPLETE_MARKER}" MARKER_TIME)
            file(TIMESTAMP "${SETUP_SCRIPT}" SCRIPT_TIME)
            if(SCRIPT_TIME STRGREATER MARKER_TIME)
                message(STATUS "OpenSim setup script newer than completion marker")
                set(OPENSIM_BUILD_NEEDED TRUE)
            else()
                message(STATUS "Found complete and up-to-date OpenSim installation")
            endif()
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
            
            # Create completion marker after successful setup
            string(TIMESTAMP CURRENT_TIME "%Y-%m-%d %H:%M:%S UTC" UTC)
            file(WRITE "${OPENSIM_BUILD_COMPLETE_MARKER}" "OpenSim build completed at: ${CURRENT_TIME}\nSetup script: ${SETUP_SCRIPT}\n")
            message(STATUS "OpenSim setup completed successfully")
        endif()
    endif() # Close if(NOT OPENSIM_FOUND)
else()
    message(STATUS "Building PyOSim stubs without OpenSim")
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
        DESTINATION "${CMAKE_INSTALL_PREFIX}/pyosim/${relative_dest_dir}")
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
        "${CMAKE_CURRENT_SOURCE_DIR}/src/opensim-core/Bindings/Python/swig/python_${OSIMSWIGPY_MODULE}.i")

    # SWIG command arguments
    set(_swig_common_args -c++ -python
            -I${CMAKE_CURRENT_SOURCE_DIR}/src/opensim-core
            -I${CMAKE_CURRENT_SOURCE_DIR}/src/opensim-core/Bindings
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
    
    # Python library linking (handle static linking case on macOS)
    execute_process(COMMAND "${Python3_EXECUTABLE}" -c
        "import sysconfig; print(sysconfig.get_config_var('LDSHARED'))"
        OUTPUT_VARIABLE PYTHON_LDSHARED
        OUTPUT_STRIP_TRAILING_WHITESPACE)
    if("${PYTHON_LDSHARED}" MATCHES "dynamic_lookup")
        set_target_properties(${_libname} PROPERTIES LINK_FLAGS
            "-undefined dynamic_lookup")
    else()
        target_link_libraries(${_libname} ${Python3_LIBRARIES})
    endif()

    # Link against OpenSim libraries
    if(PYOSIM_BUILD_WITH_OPENSIM)
        # Platform-specific library paths
        if(WIN32)
            set(OSIM_LIBS
                "${OPENSIM_INSTALL_DIR}/lib/osimCommon${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/lib/osimSimulation${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/lib/osimActuators${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/lib/osimAnalyses${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/lib/osimTools${LIB_EXT}"
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
            list(APPEND OPTIONAL_LIBS 
                "${OPENSIM_INSTALL_DIR}/lib/osimLepton${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/lib/osimdocopt${LIB_EXT}"
                "${OPENSIM_INSTALL_DIR}/lib/ezc3d${LIB_EXT}")
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
        set_target_properties(${_libname} PROPERTIES
            BUILD_RPATH_USE_ORIGIN TRUE
            INSTALL_RPATH "$ORIGIN/lib"
            BUILD_RPATH "$ORIGIN/lib"
        )
    endif()

    # Copy files into the build tree python package.
    add_custom_command(TARGET ${_libname} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:${_libname}>"
            "${OPENSIM_PYTHON_BINARY_DIR}/pyosim/$<TARGET_FILE_NAME:${_libname}>"
        COMMAND ${CMAKE_COMMAND} -E copy "${CMAKE_CURRENT_BINARY_DIR}/${OSIMSWIGPY_MODULE}.py"
            "${OPENSIM_PYTHON_BINARY_DIR}/pyosim/${OSIMSWIGPY_MODULE}.py"
        COMMENT "Copying ${OSIMSWIGPY_MODULE}.py and ${_libname} to python package in build directory."
        VERBATIM
        )

    # Install the python module and compiled library.
    install(TARGETS ${_libname} DESTINATION "${CMAKE_INSTALL_PREFIX}/pyosim")
    install(FILES "${CMAKE_CURRENT_BINARY_DIR}/${OSIMSWIGPY_MODULE}.py"
        DESTINATION "${CMAKE_INSTALL_PREFIX}/pyosim")

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
OpenSimPutFileInPythonPackage("${CMAKE_CURRENT_BINARY_DIR}/version.py" pyosim)

# __init__.py - use our custom pyosim __init__.py instead of OpenSim's
OpenSimPutFileInPythonPackage("${CMAKE_CURRENT_SOURCE_DIR}/src/pyosim/__init__.py" .)

# Umbrella target for assembling the python bindings in the build tree.
add_custom_target(PythonBindings ALL DEPENDS ${OPENSIM_PYTHON_PACKAGE_FILES})

# Require the libraries to be built.
add_dependencies(PythonBindings ${OPENSIM_PYTHON_PACKAGE_LIBRARY_TARGETS})

set_target_properties(PythonBindings PROPERTIES
    PROJECT_LABEL "Python - umbrella target"
    FOLDER "Bindings")

# Install OpenSim libraries into the wheel
if(PYOSIM_BUILD_WITH_OPENSIM AND NOT WIN32)
    # Create lib directory in the install location
    install(DIRECTORY DESTINATION ${CMAKE_INSTALL_PREFIX}/pyosim/lib)
    
    # Install OpenSim libraries
    set(INSTALL_LIBS
        "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimCommon${LIB_EXT}"
        "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimSimulation${LIB_EXT}"
        "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimActuators${LIB_EXT}"
        "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimAnalyses${LIB_EXT}"
        "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimTools${LIB_EXT}"
    )
    
    foreach(LIB ${INSTALL_LIBS})
        if(EXISTS "${LIB}")
            install(FILES "${LIB}" DESTINATION ${CMAKE_INSTALL_PREFIX}/pyosim/lib)
        endif()
    endforeach()
    
    # Install Simbody libraries (including versioned libraries)
    file(GLOB SIMBODY_ALL_LIBS 
        "${OPENSIM_INSTALL_DIR}/sdk/Simbody/lib/libSimTK*.so*"
    )
    if(SIMBODY_ALL_LIBS)
        install(FILES ${SIMBODY_ALL_LIBS}
            DESTINATION ${CMAKE_INSTALL_PREFIX}/pyosim/lib)
    endif()
    
    # Install optional libraries
    set(OPTIONAL_INSTALL_LIBS
        "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimLepton${LIB_EXT}"
        "${OPENSIM_INSTALL_DIR}/sdk/lib/libosimdocopt${LIB_EXT}"
        "${OPENSIM_INSTALL_DIR}/sdk/lib/libezc3d${LIB_EXT}"
    )
    
    foreach(LIB ${OPTIONAL_INSTALL_LIBS})
        if(EXISTS "${LIB}")
            install(FILES "${LIB}" DESTINATION ${CMAKE_INSTALL_PREFIX}/pyosim/lib)
        endif()
    endforeach()
endif()