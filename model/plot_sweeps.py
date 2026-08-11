"""
Plots error-vs-wordlength (rotation and vectoring mode) from the sweeps
defined in script.py. Run standalone: reuses script.py's fixed-point CORDIC
model without re-running its own __main__ block (that block is guarded, so
importing is silent).
"""
import matplotlib.pyplot as plt
import numpy as np

from script import (
    ANGLE_INT_BITS, ANGLE_FRAC_BITS, N,
    _max_rotate_error, _max_vectorize_error,
)

FRAC_RANGE = range(4, 17)
ANGLE_STEP = 1


def collect_error_vs_wordlength():
    return [(frac, _max_rotate_error(N, frac, ANGLE_STEP)) for frac in FRAC_RANGE]


def collect_error_vs_wordlength_vectorize(magnitude=1.0):
    return [(frac, _max_vectorize_error(N, frac, ANGLE_STEP, magnitude)) for frac in FRAC_RANGE]


def plot(data_rotate, data_vectorize, out_path="error_sweeps.png"):
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(13, 4.5))

    r_vals, r_errs = zip(*data_rotate)
    ax1.semilogy(r_vals, r_errs, marker="o")
    ax1.axvline(ANGLE_FRAC_BITS, color="gray", linestyle="--", linewidth=1,
                label=f"chosen frac={ANGLE_FRAC_BITS}")
    ax1.set_xlabel("Angle fractional bits")
    ax1.set_ylabel("Max error (log scale)")
    ax1.set_title(f"Rotation mode: error vs. word length  (N={N})")
    ax1.grid(True, which="both", alpha=0.3)
    ax1.legend()

    v_vals, v_errs = zip(*data_vectorize)
    ax2.semilogy(v_vals, v_errs, marker="o", color="tab:orange")
    ax2.axvline(ANGLE_FRAC_BITS, color="gray", linestyle="--", linewidth=1,
                label=f"chosen frac={ANGLE_FRAC_BITS}")
    ax2.set_xlabel("Angle fractional bits")
    ax2.set_ylabel("Max error (log scale)")
    ax2.set_title(f"Vectoring mode: error vs. word length  (N={N}, magnitude=1)")
    ax2.grid(True, which="both", alpha=0.3)
    ax2.legend()

    fig.tight_layout()
    fig.savefig(out_path, dpi=150)
    print(f"Saved {out_path}")


if __name__ == "__main__":
    data_rotate = collect_error_vs_wordlength()
    data_vectorize = collect_error_vs_wordlength_vectorize()
    plot(data_rotate, data_vectorize)
