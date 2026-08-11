"""
Sweeps rotation-mode angle from -180 to 180 deg straight into the real RTL
(cordic_top.v, which now includes range_reduce.v internally -- no software
pre-reduction needed, the full +/-180 range goes directly to hardware) via
tb/tb_sweep.v, and compares against numpy's cos/sin.

Plot 1: RTL x/y output across the full sweep (with numpy's true cos/sin
overlaid as a thin reference line).
Plot 2: accuracy, in percent, of the RTL output vs. numpy -- defined as
100 - 100*|error|, i.e. error expressed as percentage points of full-scale
(+/-1.0), not relative error (which blows up near the zero-crossings).
"""
import os
import subprocess
import numpy as np
import matplotlib.pyplot as plt

from script import to_fixed_int, ANGLE_INT_BITS, ANGLE_FRAC_BITS, XY_FRAC_BITS

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIM_DIR = os.path.join(PROJECT_ROOT, "sim")
VVP_OUT = os.path.join(SIM_DIR, "tb_rotate_sweep.vvp")

ANGLE_STEP = 1  # degrees


def to_u16(value):
    """Wrap a signed int into 0..65535 the way Verilog's %d read into a
    16-bit reg will reinterpret it (two's complement)."""
    return value & 0xFFFF


def main():
    angles_deg = list(np.arange(-180, 180 + ANGLE_STEP, ANGLE_STEP))

    # write stimulus to the filenames tb_sweep.v actually reads/writes
    os.makedirs(SIM_DIR, exist_ok=True)
    sweep_in = os.path.join(SIM_DIR, "sweep_in.txt")
    sweep_out = os.path.join(SIM_DIR, "sweep_out.txt")
    with open(sweep_in, "w") as f:
        for angle_deg in angles_deg:
            zin = to_fixed_int(np.radians(angle_deg), ANGLE_INT_BITS, ANGLE_FRAC_BITS)
            f.write(f"{to_u16(16384)} {to_u16(0)} {to_u16(zin)} 0\n")

    rtl_files = [
        os.path.join(PROJECT_ROOT, "rtl", "atan_rom.v"),
        os.path.join(PROJECT_ROOT, "rtl", "cordic_stage.v"),
        os.path.join(PROJECT_ROOT, "rtl", "cordic_iterative.v"),
        os.path.join(PROJECT_ROOT, "rtl", "range_reduce.v"),
        os.path.join(PROJECT_ROOT, "rtl", "cordic_top.v"),
        os.path.join(PROJECT_ROOT, "tb", "tb_sweep.v"),
    ]
    subprocess.run(["iverilog", "-g2012", "-o", VVP_OUT] + rtl_files,
                    cwd=PROJECT_ROOT, check=True)
    subprocess.run(["vvp", VVP_OUT], cwd=PROJECT_ROOT, check=True)

    x_rtl, y_rtl = [], []
    with open(sweep_out) as f:
        for line in f:
            x_raw, y_raw, z_raw = (int(v) for v in line.split())
            x_raw = x_raw - 0x10000 if x_raw >= 0x8000 else x_raw
            y_raw = y_raw - 0x10000 if y_raw >= 0x8000 else y_raw
            x_rtl.append(x_raw / (2 ** XY_FRAC_BITS))
            y_rtl.append(y_raw / (2 ** XY_FRAC_BITS))

    x_rtl = np.array(x_rtl)
    y_rtl = np.array(y_rtl)
    angles_rad = np.radians(angles_deg)
    x_true = np.cos(angles_rad)
    y_true = np.sin(angles_rad)

    # accuracy in percent, as percentage points of full-scale (+/-1.0) error,
    # NOT relative error (which is undefined/explosive right at the zero-crossings)
    acc_x = 100.0 - 100.0 * (np.abs(x_rtl - x_true)/1)
    acc_y = 100.0 - 100.0 * (np.abs(y_rtl - y_true)/1)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 4.5))

    ax1.plot(angles_deg, x_rtl, label="x (RTL)", color="tab:blue")
    ax1.plot(angles_deg, y_rtl, label="y (RTL)", color="tab:orange")
    ax1.set_xlabel("Input angle (deg)")
    ax1.set_ylabel("Output value")
    ax1.set_title("RTL rotation-mode output, full +/-180 sweep")
    ax1.legend()
    ax1.grid(alpha=0.3)

    ax2.plot(angles_deg, acc_x, label="x accuracy", color="tab:blue")
    ax2.plot(angles_deg, acc_y, label="y accuracy", color="tab:orange")
    ax2.set_xlabel("Input angle (deg)")
    ax2.set_ylabel("Accuracy (%)")
    ax2.set_title("RTL vs. numpy accuracy (% of full-scale)")
    ax2.legend()
    ax2.grid(alpha=0.3)

    fig.tight_layout()
    out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hw_rotate_sweep_results.png")
    fig.savefig(out_path, dpi=150)
    print(f"Saved {out_path}")
    print(f"Min accuracy: x={acc_x.min():.4f}% y={acc_y.min():.4f}%")


if __name__ == "__main__":
    main()
