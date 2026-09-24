"""Sensor simulation and in-vehicle alignment modules."""

from .cabin_alignment import CabinAligner
from .generator import SensorSimulator, SimConfig, RoadGeometry

__all__ = ["CabinAligner", "SensorSimulator", "SimConfig", "RoadGeometry"]
