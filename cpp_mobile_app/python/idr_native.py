import ctypes
import os
import platform
import sys

class IdrNavSolutionC(ctypes.Structure):
    _fields_ = [
        ("timestamp", ctypes.c_double),
        ("px", ctypes.c_double),
        ("py", ctypes.c_double),
        ("pz", ctypes.c_double),
        ("vx", ctypes.c_double),
        ("vy", ctypes.c_double),
        ("vz", ctypes.c_double),
        ("yawRad", ctypes.c_double),
        ("headingDeg", ctypes.c_double),
        ("rollRad", ctypes.c_double),
        ("pitchRad", ctypes.c_double),
        ("positionStd", ctypes.c_double),
        ("hdop", ctypes.c_double),
        ("trustWeight", ctypes.c_double),
        ("isShock", ctypes.c_int),
        ("isStandstill", ctypes.c_int),
        ("isOutage", ctypes.c_int),
        ("idrDrift", ctypes.c_double),
        ("classicDrift", ctypes.c_double),
    ]

def load_idr_library(lib_path: str = None):
    """Load native C++ idr_core shared library."""
    if lib_path is None:
        base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        # Search candidate locations
        candidates = [
            os.path.join(base_dir, "build", "idr_core.dll"),
            os.path.join(base_dir, "build", "libidr_core.so"),
            os.path.join(base_dir, "android", "build", "intermediates", "cxx", "Release", "obj", "arm64-v8a", "libidr_native_app.so"),
            os.path.join(base_dir, "idr_core.dll"),
        ]
        for c in candidates:
            if os.path.exists(c):
                lib_path = c
                break

    if lib_path and os.path.exists(lib_path):
        lib = ctypes.CDLL(lib_path)
        _setup_signatures(lib)
        return lib
    return None

def _setup_signatures(lib):
    lib.idr_pipeline_create.restype = ctypes.c_void_p
    lib.idr_pipeline_create.argtypes = []

    lib.idr_pipeline_destroy.restype = None
    lib.idr_pipeline_destroy.argtypes = [ctypes.c_void_p]

    lib.idr_pipeline_reset.restype = None
    lib.idr_pipeline_reset.argtypes = [ctypes.c_void_p]

    lib.idr_pipeline_process_imu.restype = None
    lib.idr_pipeline_process_imu.argtypes = [
        ctypes.c_void_p, ctypes.c_double,
        ctypes.c_double, ctypes.c_double, ctypes.c_double,
        ctypes.c_double, ctypes.c_double, ctypes.c_double
    ]

    lib.idr_pipeline_process_gnss.restype = None
    lib.idr_pipeline_process_gnss.argtypes = [
        ctypes.c_void_p, ctypes.c_double,
        ctypes.c_double, ctypes.c_double, ctypes.c_double,
        ctypes.c_double, ctypes.c_double, ctypes.c_double
    ]

    lib.idr_pipeline_set_outage.restype = None
    lib.idr_pipeline_set_outage.argtypes = [ctypes.c_void_p, ctypes.c_int]

    lib.idr_pipeline_toggle_outage.restype = None
    lib.idr_pipeline_toggle_outage.argtypes = [ctypes.c_void_p]

    lib.idr_pipeline_is_outage.restype = ctypes.c_int
    lib.idr_pipeline_is_outage.argtypes = [ctypes.c_void_p]

    lib.idr_pipeline_get_solution.restype = None
    lib.idr_pipeline_get_solution.argtypes = [ctypes.c_void_p, ctypes.POINTER(IdrNavSolutionC)]
