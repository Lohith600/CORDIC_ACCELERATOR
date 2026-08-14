# CORDIC Hardware Accelerator

A parameterized, mode-selectable (rotation / vectoring) CORDIC accelerator
in Verilog, in two architectures — **iterative** (one shared stage, reused
over N cycles) and **pipelined** (N unrolled stages, one new result per
cycle) — with full ±180° input range support via internal range reduction,
verified against a Python floating-point golden model, and characterized
through Xilinx Vivado synthesis.

CORDIC computes rotations and vector magnitude/angle using only shifts and
adds — no multipliers — which is why this is the standard technique behind
DDS (direct digital synthesis), phase/frequency processing in RF chains,
and other DSP hardware.

## How it works

CORDIC iteratively rotates a vector `(x, y)` by a sequence of decreasing
angles `atan(2^-i)`, converging after N steps:

```
x_{i+1} = x_i - d_i · y_i · 2^-i
y_{i+1} = y_i + d_i · x_i · 2^-i
z_{i+1} = z_i - d_i · atan(2^-i)
```

`d_i = ±1` (the rotation direction at step i) is chosen from the sign of
`z` (rotation mode) or `y` (vectoring mode). The `atan(2^-i)` constants are
precomputed and stored in a small lookup table, one entry per stage.

| | Rotation mode | Vectoring mode |
|---|---|---|
| Inputs | x0=1, y0=0, z0=θ | x0=x_in, y0=y_in, z0=0 |
| Direction `d` | sign(z) | sign(y) |
| Drives to zero | z | y |
| Outputs | x≈cos(θ), y≈sin(θ) | x≈magnitude, z≈atan2(y,x) |

Each iteration also scales the vector by a fixed gain factor `K ≈ 0.6073`.
Both modes share one output-stage K-multiply, applied after the rotation
loop rather than pre-scaled per mode. Since K is a compile-time constant,
the multiply is implemented as a shift-add sequence
(`K in Q2.14 = 2^13+2^11-2^9+2^8-2^6+2^5-2^2+2^0`) — so the design uses
**zero general-purpose multipliers end to end**, confirmed by 0 DSP48 usage
in synthesis.

**Range reduction:** the arctan table only sums to ≈99.7°, so the core only
converges reliably within ±90°. `range_reduce` folds inputs outside that
range in before the CORDIC loop (angle ± 180° for rotation, negate x/y for
vectoring) and a `flip` flag drives the inverse correction on the way out,
giving full ±180° coverage.

## Architecture

**Iterative** (`rtl/`) — one physical `cordic_stage`, reused N times via a
counter-driven FSM. Smallest area, lowest throughput.

```
xin/yin/zin → [load reg] → range_reduce → [counter-driven single stage,
   reused N times] → [K-scale shift-add, 2 register stages] →
   [mode-correction mux, registered] → x/y/z
```

**Pipelined** (`pipelined/`) — N physical copies of the stage, one per
pipeline register. New input accepted every cycle once full; first result
takes 17 cycles, then one new result per cycle.

```
xin/yin/zin → [load reg] → range_reduce → [stage 0] → [stage 1] → ... →
   [stage N-1] → [K-scale shift-add, registered] →
   [mode-correction mux, registered] → x/y/z
```

Both share the same submodules (`cordic_stage`, `cordic_iterative`,
`range_reduce`) and the same output-stage structure (K-scale split into two
registered partial sums, then a registered mode-correction mux).


## Design decisions

- **Word length:** 16-bit fixed-point. Angle (`z`) is Q3.13, x/y is Q2.14 —
  enough integer bits for ±π and the small gain-related headroom on x/y,
  while keeping area small.
- **Iterations (N):** 14. For the default Q3.13 angle representation, 14 iterations provide the useful precision limit; additional iterations do not improve the represented angle because the remaining atan increments fall below the available fixed-point resolution.
- **Parameterized:** `cordic_top #(parameter WIDTH=16, parameter N=14)`,
  threaded through the whole module hierarchy. `N` can be reduced freely
  (functionally verified down to `N=8`); increasing it needs the arctan
  table extended past 14 entries. `WIDTH` is structurally parameterized
  throughout, but the precomputed Q-format constants (arctan table, π,
  K-gain decomposition) are numerically pinned to the default 16-bit format
  and would need regenerating for other widths — see `synth/results.md`.

## Verification

- **Python golden model** (`model/script.py`): floating-point reference for
  both modes + range reduction, cross-checked against `numpy.cos/sin/arctan2`.
  `model/plot_sweeps.py` produces error-vs-N and error-vs-word-length plots
  (`model/error_sweeps.png`).
- **RTL testbenches** (`tb/`): self-checking against the Python model.
  `tb_cordic_top.v`/`tb_pipelined.v` cover discrete cases (both modes, full
  ±180° angle range, all four quadrants); `tb_sweep.v`/`tb_pipe_sweep.v`
  feed a full angle sweep from `sim/sweep_in.txt` through the real RTL in
  simulation.
- **Hardware-vs-model comparison** (`model/hw_*_sweep.py`): compiles and
  simulates the actual RTL (via Icarus Verilog) for a full ±180° sweep,
  compares directly against `numpy`, and plots the result. Measured
  accuracy: **>99.96%** across the full range on both x/y (rotation) and
  magnitude/angle (vectoring), for both architectures.

Run a sweep + plot yourself:
```bash
cd model
python hw_rotate_sweep.py        # iterative, rotation mode
python hw_vectorize_sweep.py     # iterative, vectoring mode
python hw_pipe_rotate_sweep.py   # pipelined, rotation mode
python hw_pipe_vectorize_sweep.py # pipelined, vectoring mode
```

## Synthesis & implementation results

Target: Xilinx Artix-7 `xc7a35tcpg236-1` (Basys3), Vivado 2024.2,
100 MHz clock constraint. Both designs are fully placed & routed (not just
synthesized); no bitstream, since that needs board-specific pin constraints
this project doesn't target. Full detail and raw reports in
[`synth/results.md`](synth/results.md).

| | Iterative (synth) | Iterative (post-route) | Pipelined (synth) | Pipelined (post-route) |
|---|---|---|---|---|
| WNS (setup slack @ 100 MHz) | +2.069 ns | +1.056 ns | +3.323 ns | +2.757 ns |
| Achievable Fmax | ~126.1 MHz | **~111.8 MHz** | ~149.8 MHz | **~138.1 MHz** |
| Slice LUTs | 491 | 475 | 1040 | 1012 |
| Slice Registers | 292 | 292 | 875 | 875 |
| DSP48 | 0 | 0 | 0 | 0 |
| Latency | 17 cycles | 17 cycles | 17 cycles | 17 cycles |
| Throughput | 1 result / 17 cycles | | 1 result / cycle (steady state) | |

Both meet timing at 100 MHz post-route, not just at the synthesis estimate —
WNS shrinks once real routing delay is accounted for (synthesis uses
generic pre-placement delay estimates), but both still hold real margin. The
pipelined version's shallower per-stage critical path pushes its achievable
Fmax meaningfully higher both pre- and post-route, at the cost of ~2x more
LUTs — the expected area/throughput trade-off from unrolling one shared
stage into N physical copies.

## Repository layout

```
rtl/          iterative architecture (cordic_top, cordic_iterative,
              cordic_stage, range_reduce, atan_rom)
pipelined/    pipelined architecture (same module names, N unrolled stages)
tb/           self-checking testbenches for both architectures
model/        Python golden model, error sweeps, hardware-vs-model
              comparison scripts and plots
synth/        Vivado projects (cordic/, cordic__pipeline/), extracted
              reports, and results writeup (results.md)
sim/          sweep stimulus/output used by the hw_*_sweep.py scripts
```


