"""Map matching: orthogonal projection of the EKF position onto road branches.

For every candidate segment ``(p1, p2)`` the projection parameter is

    t* = clip( ((p - p1) . (p2 - p1)) / ||p2 - p1||^2 , 0, 1 )

The branch score combines horizontal cross-track distance, altitude agreement
(this is what separates a flyover from the road underneath it) and heading
agreement, so the snapper cannot silently pull the estimate onto a parallel
at-grade road while the vehicle is on the elevated deck.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass
class Branch:
    name: str
    points: np.ndarray            # (M, 3) polyline
    elevated: bool = False

    def __post_init__(self) -> None:
        self.points = np.asarray(self.points, dtype=float)
        if self.points.ndim != 2 or self.points.shape[1] != 3 or len(self.points) < 2:
            raise ValueError("branch polyline must be (M>=2, 3)")
        self.p1 = self.points[:-1]
        self.p2 = self.points[1:]
        self.d = self.p2 - self.p1
        self.len2 = np.einsum("ij,ij->i", self.d[:, :2], self.d[:, :2])
        self.len2 = np.maximum(self.len2, 1e-9)


@dataclass
class MatchResult:
    branch: str
    point: np.ndarray
    tangent: np.ndarray
    normal: np.ndarray
    cross_track: float
    altitude: float
    segment_index: int
    score: float
    confidence: float


class MapSnapper:
    """Multi-branch centre-line matcher with HDOP-scheduled constraint strength."""

    def __init__(self, branches: list[Branch], sigma_lateral: float = 1.1,
                 alt_weight: float = 0.55, heading_weight: float = 6.0,
                 max_lateral: float = 45.0, hdop_gain: float = 1.2,
                 hdop_centre: float = 3.5):
        if not branches:
            raise ValueError("at least one branch is required")
        self.branches = branches
        self.sigma_lateral = sigma_lateral
        self.alt_weight = alt_weight
        self.heading_weight = heading_weight
        self.max_lateral = max_lateral
        self.hdop_gain = hdop_gain
        self.hdop_centre = hdop_centre
        self.last: MatchResult | None = None

    # ----------------------------------------------------------------- matching
    def project_branch(self, branch: Branch, pos: np.ndarray) -> tuple[int, np.ndarray, float]:
        rel = pos[None, :2] - branch.p1[:, :2]
        t = np.clip(np.einsum("ij,ij->i", rel, branch.d[:, :2]) / branch.len2, 0.0, 1.0)
        foot = branch.p1 + t[:, None] * branch.d
        dist = np.linalg.norm(pos[None, :2] - foot[:, :2], axis=1)
        i = int(np.argmin(dist))
        return i, foot[i], float(dist[i])

    def match(self, pos, heading_vec=None, hdop: float | None = None) -> MatchResult | None:
        pos = np.asarray(pos, dtype=float)
        heading = None
        if heading_vec is not None:
            hv = np.asarray(heading_vec, dtype=float)[:2]
            if np.linalg.norm(hv) > 1e-6:
                heading = hv / np.linalg.norm(hv)

        best: MatchResult | None = None
        scores: list[float] = []
        for branch in self.branches:
            i, foot, lateral = self.project_branch(branch, pos)
            tangent = branch.d[i]
            tnorm = float(np.linalg.norm(tangent[:2]))
            if tnorm < 1e-9:
                continue
            tangent2 = tangent[:2] / tnorm
            normal = np.array([-tangent2[1], tangent2[0]])
            signed = float((pos[:2] - foot[:2]) @ normal)

            score = lateral + self.alt_weight * abs(pos[2] - foot[2])
            if heading is not None:
                score += self.heading_weight * (1.0 - abs(float(heading @ tangent2)))
            scores.append(score)

            if best is None or score < best.score:
                best = MatchResult(branch.name, foot,
                                   np.append(tangent2, 0.0), np.append(normal, 0.0),
                                   signed, float(foot[2]), i, score, 0.0)

        if best is None or abs(best.cross_track) > self.max_lateral:
            self.last = None
            return None

        if len(scores) > 1:
            ordered = sorted(scores)
            gap = ordered[1] - ordered[0]
            best.confidence = float(np.clip(gap / max(ordered[1], 1e-6), 0.0, 1.0))
        else:
            best.confidence = 1.0
        self.last = best
        return best

    # ---------------------------------------------------------------- weighting
    def lateral_sigma(self, hdop: float, match: MatchResult | None = None) -> float:
        """Tighter road constraint exactly when GNSS becomes untrustworthy."""
        z = self.hdop_gain * (hdop - self.hdop_centre)
        lam = 1.0 / (1.0 + np.exp(-np.clip(z, -60.0, 60.0)))
        sigma = self.sigma_lateral * (1.0 + 3.0 * (1.0 - lam))
        if match is not None:
            sigma *= 1.0 + 2.0 * (1.0 - match.confidence)
        return float(sigma)


def branches_from_geometry(geometry, step_m: float = 5.0) -> list[Branch]:
    """Main centre line plus the at-grade decoy that runs under the flyover."""
    branches = [Branch("main", geometry.centerline(step_m), elevated=True)]
    decoy = geometry.decoy_branch(step_m)
    if len(decoy) >= 2:
        branches.append(Branch("service_road", decoy, elevated=False))
    return branches
