"""Module 6: V2X Collaborative Telemetry Mesh (BLE / Wi-Fi Aware).

Formulation (Whitepaper Section 8):
- Decentralized micro-telemetry packet exchange (Eqn 34):
    M_i = { ID_i, p_i^N, Tr(P_{p, i}), tau_{outage, i} }
- Ranging estimation (BLE RSSI log-distance path loss or Wi-Fi RTT) (Eqn 35):
    d_AB = 10^((RSSI_0 - RSSI) / (10 * eta))
- Relative ranging constraint (Eqns 36-37):
    z_range = d_AB = ||p_B - p_A|| + nu_range
    H_range = [ (p_B - p_A)^T / ||p_B - p_A||,  0_{1x3} ]
"""

from __future__ import annotations

from dataclasses import dataclass
import numpy as np


@dataclass
class V2XTelemetryPacket:
    """Micro-telemetry packet exchanged via BLE/Wi-Fi Aware (Eqn 34)."""
    vehicle_id: str
    position_enu: np.ndarray      # [x, y, z] in local ENU
    covariance_trace: float       # Tr(P_pos): uncertainty metric
    tunnel_outage_s: float        # Duration spent inside tunnel
    timestamp: float

    def __post_init__(self) -> None:
        self.position_enu = np.asarray(self.position_enu, dtype=float)[:3]


class V2XMeshNode:
    """Collaborative Mesh Peer Handler for Inter-Vehicle Ranging."""

    def __init__(
        self,
        node_id: str = "vehicle_ego",
        rssi_0: float = -42.0,  # Calibrated RSSI at 1 meter [dBm]
        path_loss_eta: float = 2.4,  # Environmental path loss exponent
        ranging_noise_std: float = 1.5,  # 1-sigma distance error [m]
    ):
        self.node_id = node_id
        self.rssi_0 = rssi_0
        self.path_loss_eta = path_loss_eta
        self.ranging_noise_std = ranging_noise_std

        self._peers: dict[str, V2XTelemetryPacket] = {}

    def rssi_to_distance(self, rssi: float) -> float:
        """Estimate distance from BLE RSSI log-distance path loss (Eqn 35)."""
        exponent = (self.rssi_0 - rssi) / (10.0 * self.path_loss_eta)
        return float(10.0 ** exponent)

    def receive_packet(self, packet: V2XTelemetryPacket) -> None:
        """Ingest peer micro-telemetry packet."""
        if packet.vehicle_id != self.node_id:
            self._peers[packet.vehicle_id] = packet

    def evaluate_peer_constraints(
        self,
        ego_pos: np.ndarray,
        ego_cov_trace: float,
        ego_outage_s: float,
    ) -> list[tuple[V2XTelemetryPacket, float]]:
        """Identify trusted peers with lower covariance trace to tether drift."""
        constraints = []
        for peer_id, pkt in self._peers.items():
            # A peer is trusted if its position covariance trace is significantly lower
            # (e.g. peer just entered tunnel while ego has been inside for minutes)
            if pkt.covariance_trace < 0.6 * ego_cov_trace or pkt.tunnel_outage_s < ego_outage_s - 15.0:
                dist_true = float(np.linalg.norm(ego_pos[:3] - pkt.position_enu))
                # Add measurement noise to simulate physical BLE/RTT ranging
                measured_dist = max(0.5, dist_true + np.random.normal(0.0, self.ranging_noise_std))
                constraints.append((pkt, measured_dist))
        return constraints

    def clear_stale_peers(self, current_time: float, max_age_s: float = 5.0) -> None:
        stale = [pid for pid, p in self._peers.items() if current_time - p.timestamp > max_age_s]
        for pid in stale:
            del self._peers[pid]
