cmake_minimum_required(VERSION 3.20)
project(idr_native_app LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_options(-O3 -Wall -Wextra -ffast-math)

# Path to core
set(CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../core)
set(EIGEN_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/eigen)

# Core static library
add_library(idr_core_static STATIC
    ${CORE_DIR}/src/common.cpp
    ${CORE_DIR}/src/cabin_aligner.cpp
    ${CORE_DIR}/src/vibration_gate.cpp
    ${CORE_DIR}/src/tcn_speed_engine.cpp
    ${CORE_DIR}/src/ekf_3d.cpp
    ${CORE_DIR}/src/baseline_dr.cpp
    ${CORE_DIR}/src/pipeline.cpp
    ${CORE_DIR}/src/c_api.cpp
)
target_include_directories(idr_core_static PUBLIC
    ${CORE_DIR}/include
    ${EIGEN_DIR}
)

# Android Native App Shared Library
# IMPORTANT: Include android_native_app_glue.c directly so ANativeActivity_onCreate is exported!
add_library(idr_native_app SHARED
    src/main_native.cpp
    src/native_sensor_service.cpp
    src/native_renderer.cpp
    ${ANDROID_NDK}/sources/android/native_app_glue/android_native_app_glue.c
)

target_include_directories(idr_native_app PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CORE_DIR}/include
    ${EIGEN_DIR}
    ${ANDROID_NDK}/sources/android/native_app_glue
)

# Force export of ANativeActivity_onCreate
set_target_properties(idr_native_app PROPERTIES
    LINK_FLAGS "-u ANativeActivity_onCreate"
)

target_link_libraries(idr_native_app PRIVATE
    idr_core_static
    android
    log
    EGL
    GLESv2
    GLESv3
)
