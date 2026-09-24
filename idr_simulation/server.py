"""Section 8.1: Local Workstation Server Tier (WebSocket & HTTP Server).

The SIH Rapid Deployment Strategy (Whitepaper Section 8.1):
1. Presentation & Sensor Tier (Mobile Device):
   Flutter application polls internal IMU (100 Hz), barometer (10 Hz), and GNSS (1 Hz)
   and streams JSON telemetry packets over a low-latency local WebSocket.
2. Computation Engine Tier (Local Workstation Server):
   A lightweight async Python server receives the WebSocket stream, runs vectorized
   NumPy/SciPy 6-state EKF, performs TCN speed inference, executes 3D map snapping,
   and streams corrected [P_snap_x, P_snap_y, P_snap_z] positions and diagnostics back at 10-200 Hz.
"""

from __future__ import annotations

import asyncio
import json
import logging
from typing import Any
import numpy as np

try:
    import websockets
    from websockets.server import serve
    HAS_WEBSOCKETS = True
except ImportError:
    HAS_WEBSOCKETS = False

from .pipeline import IDRPipeline, PipelineOptions
from .fusion.v2x_mesh import V2XTelemetryPacket

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("IDR-Server")


class IDRServer:
    """Real-Time Local Workstation Server for the IDR Super-Architecture."""

    def __init__(self, host: str = "0.0.0.0", port: int = 8765):
        self.host = host
        self.port = port
        self.pipeline = IDRPipeline()
        self._connected_clients: set[Any] = set()

    async def handle_client(self, websocket: Any) -> None:
        """Handle duplex WebSocket connection for real-time telemetry streaming."""
        self._connected_clients.add(websocket)
        client_addr = getattr(websocket, "remote_address", "unknown")
        logger.info("Mobile / Simulator client connected from %s", client_addr)

        try:
            async for message in websocket:
                try:
                    data = json.loads(message)
                    action = data.get("action", "step")

                    if action == "reset":
                        self.pipeline = IDRPipeline()
                        await websocket.send(json.dumps({"status": "reset_complete"}))
                        continue

                    if action == "v2x_peer":
                        # Ingest peer micro-telemetry packet (Eqn 34)
                        pkt = V2XTelemetryPacket(
                            vehicle_id=data.get("vehicle_id", "peer_sim"),
                            position_enu=data.get("position", [0, 0, 0]),
                            covariance_trace=float(data.get("cov_trace", 1.0)),
                            tunnel_outage_s=float(data.get("outage_s", 0.0)),
                            timestamp=float(data.get("t", 0.0)),
                        )
                        self.pipeline.v2x_node.receive_packet(pkt)
                        await websocket.send(json.dumps({"status": "v2x_peer_registered"}))
                        continue

                    # If client provides its own raw hardware sensor measurements:
                    if "imu_acc" in data and "imu_gyro" in data:
                        raw_acc = np.array(data["imu_acc"], dtype=float)
                        raw_gyro = np.array(data["imu_gyro"], dtype=float)
                        gnss_pos = np.array(data["gnss_pos"], dtype=float) if data.get("gnss_pos") else None
                        hdop = float(data.get("hdop", 1.0))
                        baro_alt = float(data["baro_alt"]) if "baro_alt" in data and data["baro_alt"] is not None else None

                        # Run live step on pipeline components directly
                        align = self.pipeline.aligner.update(raw_acc, raw_gyro)
                        gate = self.pipeline.gate.update(align["acc_vehicle"])
                        spd = self.pipeline.speed_engine.update(align["acc_dynamic"], float(align["gyro_vehicle"][2]), gate["is_shock"], gate["trust_weight"])
                        self.pipeline.ekf.predict(spd["v_hat"], float(align["gyro_vehicle"][2]), w_v=gate["trust_weight"], q_scale=self.pipeline.gate.process_noise_scale())
                        self.pipeline.ekf.update_nhc()
                        if baro_alt is not None:
                            self.pipeline.ekf.update_baro(baro_alt, float(data.get("t", 0.0)))
                        if gnss_pos is not None:
                            self.pipeline.ekf.update_gnss(gnss_pos, hdop)

                        snapped = self.pipeline.snapper.snap(self.pipeline.ekf.position)
                        pos_out = snapped.point if snapped is not None else self.pipeline.ekf.position

                        resp = {
                            "pos_snap": pos_out.tolist(),
                            "ekf_pos": self.pipeline.ekf.position.tolist(),
                            "forward_speed": self.pipeline.ekf.forward_speed,
                            "heading_deg": float(np.degrees(self.pipeline.ekf.yaw)),
                            "cov_trace": self.pipeline.ekf.covariance_trace,
                            "w_v": gate["trust_weight"],
                            "is_shock": gate["is_shock"],
                            "hdop": hdop,
                        }
                        await websocket.send(json.dumps(resp))
                    else:
                        # Otherwise advance synthetic pipeline step
                        rec = self.pipeline.step()
                        resp = {
                            "t": rec["t"],
                            "pos_snap": rec["idr_pos"].tolist(),
                            "ekf_pos": self.pipeline.ekf.position.tolist(),
                            "truth_pos": rec["truth"].tolist(),
                            "classic_pos": rec["classic_pos"].tolist(),
                            "forward_speed": rec["idr_speed"],
                            "truth_speed": rec["truth_speed"],
                            "heading_deg": float(np.degrees(rec["idr_yaw"])),
                            "cov_trace": rec["cov_trace"],
                            "w_v": rec["w_v"],
                            "jerk_var": rec["jerk_var"],
                            "is_shock": rec["shock"],
                            "hdop": rec["hdop"],
                            "is_tunnel": rec["is_tunnel"],
                            "err_idr": rec["err_idr"],
                            "err_classic": rec["err_classic"],
                            "progress": rec["progress"],
                            "finished": rec["finished"],
                        }
                        await websocket.send(json.dumps(resp))

                except Exception as ex:
                    logger.error("Error processing telemetry message: %s", ex)
                    await websocket.send(json.dumps({"error": str(ex)}))

        except websockets.exceptions.ConnectionClosed:
            logger.info("Client disconnected: %s", client_addr)
        finally:
            self._connected_clients.remove(websocket)

    async def start(self) -> None:
        """Start async WebSocket server."""
        if not HAS_WEBSOCKETS:
            logger.error("Websockets package not installed. Run: pip install websockets")
            return

        logger.info("==========================================================")
        logger.info("  AI-Enhanced IDR Workstation Computation Server")
        logger.info("  Listening on ws://%s:%d/ws/telemetry", self.host, self.port)
        logger.info("==========================================================")

        async with serve(self.handle_client, self.host, self.port):
            await asyncio.Future()  # Run forever


def main() -> None:
    server = IDRServer()
    asyncio.run(server.start())


if __name__ == "__main__":
    main()
