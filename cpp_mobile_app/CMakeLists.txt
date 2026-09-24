cmake_minimum_required(VERSION 3.20)
project(idr_native LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Compiler optimization flags
if(MSVC)
    add_compile_options(/O2 /W3 /fp:fast)
else()
    add_compile_options(-O3 -Wall -Wextra -ffast-math)
endif()

# Include directories
set(IDR_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/core/include)
set(EIGEN_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/third_party/eigen)

# Core Sources
set(IDR_CORE_SOURCES
    core/src/common.cpp
    core/src/cabin_aligner.cpp
    core/src/vibration_gate.cpp
    core/src/tcn_speed_engine.cpp
    core/src/ekf_3d.cpp
    core/src/baseline_dr.cpp
    core/src/pipeline.cpp
    core/src/c_api.cpp
)

# 1. Core Shared Library (for Dart FFI, Android NativeActivity, and embedding)
add_library(idr_core SHARED ${IDR_CORE_SOURCES})
target_include_directories(idr_core PUBLIC ${IDR_INCLUDE_DIR} ${EIGEN_INCLUDE_DIR})

# 2. Core Static Library
add_library(idr_core_static STATIC ${IDR_CORE_SOURCES})
target_include_directories(idr_core_static PUBLIC ${IDR_INCLUDE_DIR} ${EIGEN_INCLUDE_DIR})

# 3. Standalone Verification Executable
add_executable(test_core core/test_core.cpp)
target_link_libraries(test_core PRIVATE idr_core_static)
target_include_directories(test_core PRIVATE ${IDR_INCLUDE_DIR} ${EIGEN_INCLUDE_DIR})

# 4. Optional Pybind11 Python Module
find_package(Python3 COMPONENTS Interpreter Development OPTIONAL_COMPONENTS Development.Module)
if(Python3_FOUND)
    execute_process(
        COMMAND "${Python3_EXECUTABLE}" -c "import pybind11; print(pybind11.get_cmake_dir())"
        OUTPUT_VARIABLE PYBIND11_CMAKE_DIR
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(PYBIND11_CMAKE_DIR AND EXISTS "${PYBIND11_CMAKE_DIR}")
        list(APPEND CMAKE_PREFIX_PATH "${PYBIND11_CMAKE_DIR}")
        find_package(pybind11 CONFIG QUIET)
        if(pybind11_FOUND)
            pybind11_add_module(idr_cpp python/bindings.cpp)
            target_link_libraries(idr_cpp PRIVATE idr_core_static)
            target_include_directories(idr_cpp PRIVATE ${IDR_INCLUDE_DIR} ${EIGEN_INCLUDE_DIR})
            message(STATUS "Built pybind11 module: idr_cpp")
        endif()
    endif()
endif()
