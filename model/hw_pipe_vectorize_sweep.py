"""
Same sweep as hw_vectorize_sweep.py, but targeting the PIPELINED design via
tb/tb_pipe_sweep.v's streaming harness.

Three fixed magnitudes (0.3, 0.7, 1.0), full angle -180 to 180 deg each,
straight into the real pipelined RTL (range reduction / flip included).
Plots: magnitude accuracy and angle accuracy vs. input angle, one line per
magnitude case.
"""
import os
import subprocess
import numpy as np
import matplotlib.pyplot as plt

from script import to_fixed_int, ANGLE_FRAC_BITS, XY_INT_BITS, XY_FRAC_BITS

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM_DIR = os.path.join(PROJECT_ROOT, "sim")
VVP_OUT = os.path.join(SIM_DIR, "tb_pipe_vectorize_sweep.vvp")

MAGNITUDES = [0.3, 0.7, 1.0]
ANGLE_STEP = 1 # degrees


def to_u16(value):
    return value & 0xFFFF


def wrap_deg(diff_deg):
    return (diff_deg + 180) % 360 - 180


def main():
    angles_deg = list(np.arange(-180, 180 + ANGLE_STEP, ANGLE_STEP))

    os.makedirs(SIM_DIR, exist_ok=True)
    sweep_in = os.path.join(SIM_DIR, "sweep_in.txt")
    sweep_out = os.path.join(SIM_DIR, "sweep_out.txt")

    with open(sweep_in, "w") as f:
        for mag in MAGNITUDES:
            for angle_deg in angles_deg:
                angle_rad = np.radians(angle_deg)
                xin = to_fixed_int(mag * np.cos(angle_rad), XY_INT_BITS, XY_FRAC_BITS)
                yin = to_fixed_int(mag * np.sin(angle_rad), XY_INT_BITS, XY_FRAC_BITS)
                f.write(f"{to_u16(xin)} {to_u16(yin)} {to_u16(0)} 1\n")  # mode=1 (vectorize)

    rtl_files = [
        os.path.join(PROJECT_ROOT, "pipelined", "cordic_stage.v"),
        os.path.join(PROJECT_ROOT, "pipelined", "cordic_iterative.v"),
        os.path.join(PROJECT_ROOT, "pipelined", "range_reduce.v"),
        os.path.join(PROJECT_ROOT, "pipelined", "cordic_top.v"),
        os.path.join(PROJECT_ROOT, "tb", "tb_pipe_sweep.v"),
    ]
    subprocess.run(["iverilog", "-g2012", "-o", VVP_OUT] + rtl_files,
                    cwd=PROJECT_ROOT, check=True)
    subprocess.run(["vvp", VVP_OUT], cwd=PROJECT_ROOT, check=True)

    mag_out_all, ang_out_all = [], []
    with open(sweep_out) as f:
        for line in f:
            x_raw, _, z_raw = (int(v) for v in line.split())
            x_raw = x_raw - 0x10000 if x_raw >= 0x8000 else x_raw
            z_raw = z_raw - 0x10000 if z_raw >= 0x8000 else z_raw
            mag_out_all.append(x_raw / (2 ** XY_FRAC_BITS))
            ang_out_all.append(np.degrees(z_raw / (2 ** ANGLE_FRAC_BITS)))

    n = len(angles_deg)
    assert len(mag_out_all) == n * len(MAGNITUDES), \
        f"expected {n * len(MAGNITUDES)} results, got {len(mag_out_all)}"

    results = {}
    for i, mag in enumerate(MAGNITUDES):
        mag_out = np.array(mag_out_all[i * n:(i + 1) * n])
        ang_out = np.array(ang_out_all[i * n:(i + 1) * n])
        ang_in = np.array(angles_deg)
        mag_err = mag_out - mag
        ang_err = wrap_deg(ang_out - ang_in)
        mag_acc = 100.0 - 100.0 * np.abs(mag_err) / 1.0
        ang_acc = 100.0 - 100.0 * np.abs(ang_err) / 180.0
        results[mag] = (mag_out, ang_out, mag_acc, ang_acc)

    fig, axes = plt.subplots(1, 2, figsize=(13, 4.5))

    for mag in MAGNITUDES:
        _, _, mag_acc, _ = results[mag]
        axes[0].plot(angles_deg, mag_acc, label=f"mag={mag}")
    axes[0].set_xlabel("Input angle (deg)")
    axes[0].set_ylabel("Magnitude accuracy (%)")
    axes[0].set_title("Pipelined RTL vectorize: magnitude accuracy vs. input angle")
    axes[0].legend()
    axes[0].grid(alpha=0.3)

    for mag in MAGNITUDES:
        _, _, _, ang_acc = results[mag]
        axes[1].plot(angles_deg, ang_acc, label=f"mag={mag}")
    axes[1].set_xlabel("Input angle (deg)")
    axes[1].set_ylabel("Angle accuracy (%)")
    axes[1].set_title("Pipelined RTL vectorize: angle accuracy vs. input angle")
    axes[1].legend()
    axes[1].grid(alpha=0.3)

    fig.tight_layout()
    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hw_pipe_vectorize_sweep_results.png")
    fig.savefig(out_path, dpi=150)
    print(f"Saved {out_path}")
    for mag in MAGNITUDES:
        _, _, mag_acc, ang_acc = results[mag]
        print(f"mag={mag}: min mag accuracy={mag_acc.min():.4f}%  min angle accuracy={ang_acc.min():.4f}%")


if __name__ == "__main__":
    main()
