import numpy as np

from idr_simulation.pipeline import IDRPipeline, PipelineOptions

pipe = IDRPipeline(PipelineOptions())
rows = []
while not pipe.finished:
    r = pipe.step()
    rows.append(r)

t = np.array([r["t"] for r in rows])
print("backend", pipe.backend)
for tt in (5, 20, 60, 100, 150, 200, 250, 290):
    i = int(np.searchsorted(t, tt))
    if i >= len(rows):
        continue
    r = rows[i]
    print(f"t={r['t']:6.1f} err_idr={r['err_idr']:9.2f} err_cls={r['err_classic']:11.1f} "
          f"v_true={r['truth_speed']:6.2f} v_tcn={r['v_tcn']:7.2f} "
          f"idr_spd={r['idr_speed']:6.2f} yaw_err={np.degrees(r['idr_yaw'])-0:8.2f} "
          f"hdop={r['hdop']:5.2f} used={int(r['gnss_used'])} tun={int(r['is_tunnel'])} "
          f"z_true={r['truth'][2]:6.2f} z_idr={r['idr_pos'][2]:7.2f} conf={r['align_conf']:.2f}")

# alignment check on the true vehicle-frame acceleration
from idr_simulation.sensors.cabin_alignment import CabinAligner
from idr_simulation.sensors.generator import SensorSimulator, SimConfig

sim = SensorSimulator(SimConfig())
al = CabinAligner(dt=sim.cfg.dt)
errs = []
for k in range(6000):
    p = sim.step()
    a = al.update(p["imu_acc"], p["imu_gyro"])
    if k > 1000:
        errs.append(a["acc_vehicle"] - p["acc_vehicle_true"])
errs = np.array(errs)
print("align residual mean", errs.mean(axis=0).round(3), "rms", errs.std(axis=0).round(3))
