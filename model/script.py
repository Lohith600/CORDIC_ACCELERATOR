import numpy as np

N = 14  # last two iterations don't contribute given the (3,13) angle format, so 16 buys nothing

ANGLE_INT_BITS, ANGLE_FRAC_BITS = 3, 13   # Q3.13: 3 int bits needed to cover +/-pi
XY_INT_BITS, XY_FRAC_BITS = 2, 14         # 2 int bits: vectoring mode's unscaled x peaks at ~1/K =~ 1.65

ANGLES_ROM_RAW = np.array([
    0.785398163, 0.463647609, 0.244978663, 0.124354995, 0.06241881, 0.0312398334,
    0.0156237286, 0.00781234106, 0.00390623013, 0.00195312252, 0.00097656219,
    0.000488281211, 0.00024414062, 0.000122070312, 0.0000610351562, 0.0000305175781,
])

RAW_CONSTANT_FACTOR = 0.607252935103139


def float_to_fixed(value, int_bits, frac_bits):
    """
    Convert a float to fixed-point, represented explicitly as (int_part, frac_part)
    in Q(int_bits).(frac_bits) format.

    int_bits includes the sign bit (standard Q-notation convention).
    Only checks whether the integer portion fits in int_bits — prints an error
    and returns None if it doesn't.
    """
    max_val = 2 ** (int_bits - 1) - 1
    min_val = -2 ** (int_bits - 1)

    int_part = int(value)  # truncate toward zero

    if int_part > max_val or int_part < min_val:
        print(f"Error: value {value} needs integer part {int_part}, "
              f"but {int_bits} integer bits only supports {min_val} to {max_val}")
        return None

    frac_value = value - int_part
    frac_part = round(frac_value * (2 ** frac_bits))  # rounded to nearest representable step

    return [int_part, frac_part]


def to_fixed_int(value, int_bits, frac_bits):
    """Convert a float to the raw signed integer that would actually be loaded
    into a hardware register in Q(int_bits).(frac_bits) format."""
    int_part, frac_part = float_to_fixed(value, int_bits, frac_bits)
    return (int_part << frac_bits) + frac_part


ANGLES_ROM_INT = [to_fixed_int(a, ANGLE_INT_BITS, ANGLE_FRAC_BITS) for a in ANGLES_ROM_RAW]
CONSTANT_FACTOR_INT = to_fixed_int(RAW_CONSTANT_FACTOR, XY_INT_BITS, XY_FRAC_BITS)


def _check_range(value_int, int_bits, frac_bits, label):
    """
    Warn if value_int (a raw fixed-point integer) doesn't fit in what
    int_bits actually covers -- e.g. [-2, 2) for XY_INT_BITS=2, [-4, 4) for
    ANGLE_INT_BITS=3 -- given the design's own assumption that inputs stay
    with |x|, |y| in [0, 1] and angle in [-180, 180].
    """
    bound = 2 ** (int_bits - 1)
    value = value_int / (2 ** frac_bits)
    if not (-bound <= value < bound):
        print(f"OVERFLOW: {label} = {value:.6f} outside representable range "
              f"[{-bound}, {bound}) for {int_bits} integer bits")


# ---------------------------------------------------------------------------
# Integer-domain CORDIC core — mirrors cordic_stage.v / cordic_iterative.v
# bit-for-bit: x, y, z are plain Python ints the whole way through, shifted
# with `>>` (Python's arithmetic, sign-extending, floor-toward -inf shift on
# an int is identical to Verilog's `>>>` on a signed value) and added with
# exact integer arithmetic -- no rounding step anywhere, matching the RTL,
# which never rounds x/y/z, only truncates through the shift.
#
# rom/bit-width args default to the fixed hardware config but can be
# overridden by the design-space sweeps below, so those sweeps reuse this
# same core instead of duplicating the iteration loop. Every stage is range-
# checked against what the given integer bits can actually represent.
# ---------------------------------------------------------------------------

def cordic_rotate_int(x_int, y_int, z_int, n_iter=None, rom=None,
                       xy_int_bits=None, xy_frac_bits=None,
                       angle_int_bits=None, angle_frac_bits=None):
    """
    Rotation-mode CORDIC core, given already-reduced (x0, y0, z0) -- no range
    reduction here, matching what cordic_iterative.v actually implements today.
    """
    n_iter = N if n_iter is None else n_iter
    rom = ANGLES_ROM_INT[:n_iter] if rom is None else rom
    xy_int_bits = XY_INT_BITS if xy_int_bits is None else xy_int_bits
    xy_frac_bits = XY_FRAC_BITS if xy_frac_bits is None else xy_frac_bits
    angle_int_bits = ANGLE_INT_BITS if angle_int_bits is None else angle_int_bits
    angle_frac_bits = ANGLE_FRAC_BITS if angle_frac_bits is None else angle_frac_bits

    for i in range(n_iter):
        if z_int >= 0:
            z_int = z_int - rom[i]
            x_int, y_int = x_int - (y_int >> i), y_int + (x_int >> i)
        else:
            z_int = z_int + rom[i]
            x_int, y_int = x_int + (y_int >> i), y_int - (x_int >> i)

        _check_range(x_int, xy_int_bits, xy_frac_bits, f"rotate x[i={i}]")
        _check_range(y_int, xy_int_bits, xy_frac_bits, f"rotate y[i={i}]")
        _check_range(z_int, angle_int_bits, angle_frac_bits, f"rotate z[i={i}]")

    return x_int, y_int, z_int


def cordic_vectorize_int(x_int, y_int, n_iter=None, rom=None,
                          xy_int_bits=None, xy_frac_bits=None,
                          angle_int_bits=None, angle_frac_bits=None):
    """Vectoring-mode CORDIC core on a vector already in the right half-plane."""
    n_iter = N if n_iter is None else n_iter
    rom = ANGLES_ROM_INT[:n_iter] if rom is None else rom
    xy_int_bits = XY_INT_BITS if xy_int_bits is None else xy_int_bits
    xy_frac_bits = XY_FRAC_BITS if xy_frac_bits is None else xy_frac_bits
    angle_int_bits = ANGLE_INT_BITS if angle_int_bits is None else angle_int_bits
    angle_frac_bits = ANGLE_FRAC_BITS if angle_frac_bits is None else angle_frac_bits
    z_int = 0

    for i in range(n_iter):
        if y_int >= 0:
            z_int = z_int + rom[i]
            x_int, y_int = x_int + (y_int >> i), y_int - (x_int >> i)
        else:
            z_int = z_int - rom[i]
            x_int, y_int = x_int - (y_int >> i), y_int + (x_int >> i)

        _check_range(x_int, xy_int_bits, xy_frac_bits, f"vectorize x[i={i}]")
        _check_range(y_int, xy_int_bits, xy_frac_bits, f"vectorize y[i={i}]")
        _check_range(z_int, angle_int_bits, angle_frac_bits, f"vectorize z[i={i}]")

    return x_int, y_int, z_int


# ---------------------------------------------------------------------------
# Full-range wrappers (range reduction + magnitude scale) -- currently
# software-only per the phasing decision in project.md, but built on the same
# bit-exact integer core above.
# ---------------------------------------------------------------------------

def rotate_int(angle_rad, n_iter=None, angle_frac=None, xy_frac=None):
    """Full rotation-mode path: quantize -> range-reduce -> CORDIC -> de-negate.
    Returns (x, y) as floats for comparison against true cos/sin."""
    n_iter = N if n_iter is None else n_iter
    angle_frac = ANGLE_FRAC_BITS if angle_frac is None else angle_frac
    # Keep x/y and angle fractional widths offset by the same fixed 1 bit
    # implied by their different integer-bit allocations (2 vs 3), so sweeping
    # "word length" grows both formats together, not just the angle's.
    xy_frac = angle_frac + (ANGLE_INT_BITS - XY_INT_BITS) if xy_frac is None else xy_frac

    rom = [to_fixed_int(a, ANGLE_INT_BITS, angle_frac) for a in ANGLES_ROM_RAW[:n_iter]]
    k = to_fixed_int(RAW_CONSTANT_FACTOR, XY_INT_BITS, xy_frac)
    half_pi_int = to_fixed_int(np.pi / 2, ANGLE_INT_BITS, angle_frac)
    pi_int = to_fixed_int(np.pi, ANGLE_INT_BITS, angle_frac)

    z = to_fixed_int(angle_rad, ANGLE_INT_BITS, angle_frac)
    negate = False
    if z > half_pi_int:
        z, negate = z - pi_int, True
    elif z < -half_pi_int:
        z, negate = z + pi_int, True

    x, y, _ = cordic_rotate_int(k, 0, z, n_iter, rom,
                                 xy_int_bits=XY_INT_BITS, xy_frac_bits=xy_frac,
                                 angle_int_bits=ANGLE_INT_BITS, angle_frac_bits=angle_frac)
    if negate:
        x, y = -x, -y

    return x / (2 ** xy_frac), y / (2 ** xy_frac)


def vectorize_int(x_in, y_in, n_iter=None, angle_frac=None, xy_frac=None):
    """Full vectoring-mode path: quantize -> range-reduce (flip left half-plane
    vectors) -> CORDIC -> magnitude scale -> angle correction.
    Returns (magnitude, angle_rad) as floats."""
    n_iter = N if n_iter is None else n_iter
    angle_frac = ANGLE_FRAC_BITS if angle_frac is None else angle_frac
    # Same word-length pairing as rotate_int(): xy_frac tracks angle_frac,
    # offset by the fixed 1 bit implied by the different integer-bit splits.
    xy_frac = angle_frac + (ANGLE_INT_BITS - XY_INT_BITS) if xy_frac is None else xy_frac

    rom = [to_fixed_int(a, ANGLE_INT_BITS, angle_frac) for a in ANGLES_ROM_RAW[:n_iter]]
    k = to_fixed_int(RAW_CONSTANT_FACTOR, XY_INT_BITS, xy_frac)

    x_int = to_fixed_int(x_in, XY_INT_BITS, xy_frac)
    y_int = to_fixed_int(y_in, XY_INT_BITS, xy_frac)

    flip = x_int < 0
    x0, y0 = (-x_int, -y_int) if flip else (x_int, y_int)

    x_raw, _, z_raw = cordic_vectorize_int(x0, y0, n_iter, rom,
                                            xy_int_bits=XY_INT_BITS, xy_frac_bits=xy_frac,
                                            angle_int_bits=ANGLE_INT_BITS, angle_frac_bits=angle_frac)

    # fixed-point multiply: product has 2*xy_frac fractional bits, shift back down to renormalize
    magnitude_int = (x_raw * k) >> xy_frac

    pi_int = to_fixed_int(np.pi, ANGLE_INT_BITS, angle_frac)
    if flip:
        angle_int = z_raw + pi_int if z_raw <= 0 else z_raw - pi_int
    else:
        angle_int = z_raw

    return magnitude_int / (2 ** xy_frac), angle_int / (2 ** angle_frac)


def verify_sweep(angle_range=(-180, 180), step=1):
    """
    Sweep across a range of angles, run each through rotate_int(), and
    compare against numpy's true cos/sin.
    """
    max_error_x = 0.0
    max_error_y = 0.0
    worst_angle = None

    for angle_deg in np.arange(angle_range[0], angle_range[1] + step, step):
        angle_rad = np.radians(angle_deg)

        x_calc, y_calc = rotate_int(angle_rad)
        x_true, y_true = np.cos(angle_rad), np.sin(angle_rad)

        err_x = abs(x_calc - x_true)
        err_y = abs(y_calc - y_true)

        if err_x > max_error_x or err_y > max_error_y:
            max_error_x = max(max_error_x, err_x)
            max_error_y = max(max_error_y, err_y)
            worst_angle = angle_deg

    print(f"Swept {angle_range[0]}° to {angle_range[1]}° in steps of {step}°")
    print(f"Max error in x (cos): {max_error_x:.8f}")
    print(f"Max error in y (sin): {max_error_y:.8f}")
    print(f"Worst-case angle: {worst_angle}°")


def verify_vectorize_sweep(angle_range=(-180, 180), step=1, magnitude=1):
    """
    Sweep unit-ish vectors (magnitude, angle) around the full circle, run each
    through vectorize_int(), and compare the recovered (magnitude, angle)
    against the true values.
    """
    max_error_mag = 0.0
    max_error_angle = 0.0
    worst_angle = None

    for angle_deg in np.arange(angle_range[0], angle_range[1] + step, step):
        angle_rad = np.radians(angle_deg)
        x_in, y_in = magnitude * np.cos(angle_rad), magnitude * np.sin(angle_rad)

        mag_calc, angle_calc = vectorize_int(x_in, y_in)

        err_mag = abs(mag_calc - magnitude)
        err_angle = abs((angle_calc - angle_rad + np.pi) % (2 * np.pi) - np.pi)  # wrap to +/-pi important as -180 degree and 180 degree might be same so instead of reproting 
                                                                                #that error as 360 to report it as 0.

        if err_mag > max_error_mag or err_angle > max_error_angle:
            max_error_mag = max(max_error_mag, err_mag)
            max_error_angle = max(max_error_angle, err_angle)
            worst_angle = angle_deg

    print(f"Swept {angle_range[0]}° to {angle_range[1]}° in steps of {step}° at magnitude {magnitude}")
    print(f"Max error in magnitude: {max_error_mag:.8f}")
    print(f"Max error in angle: {max_error_angle:.8f} rad")
    print(f"Worst-case angle: {worst_angle}°")


def _max_rotate_error(n_iter, angle_frac, angle_step=1):
    """Max |error| in x or y from rotate_int() over a full +/-180 sweep."""
    max_err = 0.0
    for angle_deg in np.arange(-180, 180 + angle_step, angle_step):
        angle_rad = np.radians(angle_deg)
        x_calc, y_calc = rotate_int(angle_rad, n_iter=n_iter, angle_frac=angle_frac)
        err = max(abs(x_calc - np.cos(angle_rad)), abs(y_calc - np.sin(angle_rad)))
        max_err = max(max_err, err)
    return max_err


def sweep_error_vs_wordlength(frac_range=range(4, 17), angle_step=1, n_iter=None):#for vectorizing mode error is max(mag error,angle error)
    """
    Fix N and vary BOTH the angle and xy fractional bit widths together,
    keeping them offset by the same fixed 1 bit the hardware already uses
    (xy_frac = angle_frac + 1, since ANGLE_INT_BITS=3 vs XY_INT_BITS=2), to
    find where adding more fractional bits stops reducing error (the point
    where N's algorithmic truncation, not fixed-point truncation, is the
    error floor).
    """
    n_iter = N if n_iter is None else n_iter
    print(f"\n--- error vs. word length (N fixed at {n_iter}) ---")
    prev_err = None
    for angle_frac in frac_range:
        xy_frac = angle_frac + (ANGLE_INT_BITS - XY_INT_BITS)
        err = _max_rotate_error(n_iter, angle_frac, angle_step)
        angle_bits = ANGLE_INT_BITS + angle_frac
        xy_bits = XY_INT_BITS + xy_frac
        improvement = "" if prev_err is None else f"  ({(1 - err / prev_err) * 100:+.1f}% vs. previous width)"
        print(f"angle=Q{ANGLE_INT_BITS}.{angle_frac} ({angle_bits}-bit) / "
              f"xy=Q{XY_INT_BITS}.{xy_frac} ({xy_bits}-bit): max error = {err:.8f}{improvement}")
        prev_err = err


def _max_vectorize_error(n_iter, angle_frac, angle_step=1, magnitude=1.0):
    """Max |error| in magnitude or angle from vectorize_int() over a full +/-180 sweep."""
    max_err = 0.0
    for angle_deg in np.arange(-180, 180 + angle_step, angle_step):
        angle_rad = np.radians(angle_deg)
        x_in, y_in = magnitude * np.cos(angle_rad), magnitude * np.sin(angle_rad)
        mag_calc, angle_calc = vectorize_int(x_in, y_in, n_iter=n_iter, angle_frac=angle_frac)
        err_mag = abs(mag_calc - magnitude)
        err_angle = abs((angle_calc - angle_rad + np.pi) % (2 * np.pi) - np.pi)
        max_err = max(max_err, err_mag, err_angle)
    return max_err


def sweep_error_vs_wordlength_vectorize(frac_range=range(4, 17), angle_step=1, n_iter=None, magnitude=1.0):
    """
    Vectoring-mode counterpart to sweep_error_vs_wordlength(): magnitude=1
    vectors swept around the full circle, same angle_frac/xy_frac pairing.
    """
    n_iter = N if n_iter is None else n_iter
    print(f"\n--- vectorize error vs. word length (N fixed at {n_iter}, magnitude={magnitude}) ---")
    prev_err = None
    for angle_frac in frac_range:
        xy_frac = angle_frac + (ANGLE_INT_BITS - XY_INT_BITS)
        err = _max_vectorize_error(n_iter, angle_frac, angle_step, magnitude)
        angle_bits = ANGLE_INT_BITS + angle_frac
        xy_bits = XY_INT_BITS + xy_frac
        improvement = "" if prev_err is None else f"  ({(1 - err / prev_err) * 100:+.1f}% vs. previous width)"
        print(f"angle=Q{ANGLE_INT_BITS}.{angle_frac} ({angle_bits}-bit) / "
              f"xy=Q{XY_INT_BITS}.{xy_frac} ({xy_bits}-bit): max error = {err:.8f}{improvement}")
        prev_err = err





if __name__ == "__main__":
    verify_sweep(angle_range=(-180, 180), step=0.01)
    verify_vectorize_sweep(angle_range=(-180, 180), step=0.01)
    sweep_error_vs_wordlength(frac_range=range(4, 17), angle_step=1)
    sweep_error_vs_wordlength_vectorize(frac_range=range(4, 17), angle_step=1)
    
