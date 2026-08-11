# Configurable CORDIC Accelerator — Project Plan

## 1. Project Overview

**What you're building:** A parameterized, pipelined CORDIC (COordinate Rotation DIgital Computer) hardware accelerator in Verilog, supporting both **rotation mode** (angle → sin/cos) and **vectoring mode** (vector → magnitude/angle), with full ±180° input range support via internal range reduction, verified against a Python golden model and characterized through FPGA synthesis.

**Why this project fits ADI/TI internships:** CORDIC is foundational to DSP, DDS (direct digital synthesis), ADC/DAC phase processing, and RF signal chains — exactly the domains these companies build silicon for. The project demonstrates the full hardware design flow: algorithm understanding → fixed-point design → RTL implementation → verification → synthesis/characterization.

**Time budget:** ~25-30 hours over multiple days.

---

## 2. Core Algorithm Recap

CORDIC computes rotations using only shifts, adds, and compares — no multipliers. The unified recurrence:

```
x_{i+1} = x_i - d_i · y_i · 2^-i
y_{i+1} = y_i + d_i · x_i · 2^-i
z_{i+1} = z_i - d_i · atan(2^-i)
```

- `d_i = +1 or -1`, the direction of rotation at step i
- `atan(2^-i)` values are precomputed and stored in a small ROM (one entry per pipeline stage)
- After N iterations, x and y converge to the rotated vector; z converges to zero (rotation mode) or holds the accumulated angle (vectoring mode)

**Two modes, same hardware, different direction logic and initial conditions:**

| | Rotation Mode | Vectoring Mode |
|---|---|---|
| Inputs | x0=1, y0=0, z0=θ | x0=x_in, y0=y_in, z0=0 |
| Direction `d` | sign(z) | sign(y) (opposite convention) |
| Drives to zero | z | y |
| Outputs | x≈cos(θ), y≈sin(θ) | x≈magnitude (×K), z≈atan2(y,x) |

**Gain factor:** Each iteration scales the vector by √(1+2^-2i). Cumulative gain K ≈ 0.6072529. As implemented, both modes run unscaled (x0=1 for rotation, x0=x_in/y0=y_in for vectoring) and the same shared output stage multiplies by K afterward for both — a single K-scale block reused by both modes, not a separate pre-scale trick for rotation. That K-multiply itself needs no multiplier hardware either: since K is a fixed compile-time constant, it's computed via shift-add (K in Q2.14 = 9949 = 2^13+2^11-2^9+2^8-2^6+2^5-2^2+2^0), so the design uses zero general-purpose multipliers end to end, not just in the CORDIC core.

**Convergence range:** The arctan lookup table sums to ≈99.7°, so reliable convergence is guaranteed only within roughly ±90°. Inputs outside this range must be folded in before running CORDIC, then corrected on the way out (see Section 4).

---

## 3. Fixed-Point Design Decisions (lock these before writing RTL)

| Parameter | Recommendation | Notes |
|---|---|---|
| Word length | 16-bit | Good balance of precision vs. area for a resume project; parameterize it if time allows |
| Angle format | Q3.13 (or similar) | Needs enough integer bits to represent ±π (~±3.14159) plus sign |
| x/y format | Q2.14 or Q1.15 | Values stay within roughly ±1.2 (accounting for pre-scale and gain drift), so 1-2 integer bits is enough |
| Iterations (N) | 16 | Matches "n bits precision ≈ n iterations" rule of thumb for 16-bit design |
| ROM depth | N entries | Each entry = atan(2^-i) in your angle Q-format |

Confirm these numbers against your Python model's error-vs-iteration sweep before finalizing (Section 6).

---

## 4. Range Reduction (Full ±180° Support)

**Phasing decision:** the ±90°→±180° folding and the negate/flip sign correction below are done in **software (Python)** for the first hardware milestone — the RTL core only ever sees an angle already within ±90° (rotation) or a vector already in the right half-plane (vectoring). Range reduction moves into hardware as a later add-on stage (see Section 5.2a) once the core datapath is verified. This keeps the first RTL milestone to just the iterative single-stage core + FSM, with no extra flag-pipelining/negate logic to debug at the same time.

### Rotation mode (input angle out of ±90° range)
```
if θ > 90°:  θ' = θ - 180°,  negate_flag = 1
if θ < -90°: θ' = θ + 180°,  negate_flag = 1
else:        θ' = θ,          negate_flag = 0

... run CORDIC on θ' ...

if negate_flag: x_out = -x_raw, y_out = -y_raw
else:           x_out = x_raw,  y_out = y_raw
```

### Vectoring mode (input vector in left half-plane, x_in < 0)
```
if x_in < 0:
    x' = -x_in, y' = -y_in, flip_flag = 1
else:
    x' = x_in, y' = y_in, flip_flag = 0

... run CORDIC vectoring on x', y' ...

if flip_flag: z_out = z_raw ± 180°   (sign chosen to land back in -180..180)
else:         z_out = z_raw
x_out = K × x_raw
```

**Hardware implication (once range reduction moves into RTL):** `negate_flag`/`flip_flag` is a single bit that must stay aligned with x, y, z — a parallel 1-bit shift register matching pipeline depth for the pipelined architecture, or just one extra held register (no shifting needed) for the iterative architecture. Not needed for the first RTL milestone, since range reduction is software-only until then.

---

## 5. Hardware Architecture

### 5.1 Single CORDIC stage (the repeating building block)
- Inputs: x_i, y_i, z_i, mode (0=rotation/1=vectoring)
- Shifters: y_i >> i, x_i >> i (hardwired shift amount per stage index)
- Direction logic: `d = mode ? sign_based_on_y : sign_based_on_z`
- Two adder/subtractors → x_{i+1}, y_{i+1}
- One adder/subtractor with ROM constant atan(2^-i) → z_{i+1}
- Registers on all outputs (x, y, z, mode, flag bit)
- **First milestone:** built and verified assuming the caller already did range reduction in software — inputs are always within ±90° (rotation) / right half-plane (vectoring), so no negate/flip flag needed yet.

### 5.2 Top-level iterative/folded module (build this first)
- ONE physical copy of the Section 5.1 stage, reused N times
- Iteration counter drives the shift amount / ROM address each cycle; FSM (idle → load → iterate ×N → done)
- Result after N cycles; new input can't be accepted until done (throughput = 1 result per N cycles)
- Smallest area, fewest moving parts to debug first — this is the "single-cycle-per-stage, compute each state once" version
- Range reduction stays in Python for this milestone (see Section 4 phasing decision)

### 5.2a (Follow-on) Hardware range reduction
- Once the core iterative datapath is verified against the golden model, add the pre-stage (fold ±180°→±90°, set negate/flip flag) and post-stage (apply negate flag / angle correction) around the core from 5.2
- For the iterative architecture this is just two extra FSM states (PRE, POST) plus one held flag register — no shift-register flag pipeline needed since there's only one in-flight sample at a time

### 5.3 (Optional/Extension) Pipelined version
```
[Range/Quadrant Pre-Stage] → [Stage 0] → [Stage 1] → ... → [Stage N-1] → [Output Correction Stage]
```
- N physical copies of the stage, each with a different hardwired shift amount and ROM constant
- New input accepted every clock cycle once pipeline is full (steady-state throughput = 1 result/cycle)
- Latency = N cycles
- Build after the iterative version is working, if time/area comparison is still wanted (see Section 7's comparison table)

---

## 6. Verification Plan

### 6.1 Python golden model (build this first, before RTL)
- Floating-point implementation of both modes + range reduction, iteration-by-iteration (so you can trace stage-by-stage values for debugging)
- Cross-check against `numpy.cos/sin/arctan2` across full angle sweep (-180° to 180°, fine steps)
- Sweep iteration count N and word length to produce **error vs. N** and **error vs. word length** plots — this becomes real data for your report
- ~~Export a table of test vectors~~ — decided not needed: testbenches compute expected values on-the-fly from the bit-exact Python model instead of reading a static exported table, and the hardware sweep scripts compare RTL output directly against `numpy` in real time. Same verification goal, no intermediate file.

### 6.2 RTL testbench
- Self-checking: compare RTL outputs against the bit-exact Python model within a defined error tolerance (e.g., ±2-3 LSB)
- Cover both modes (mode=0, mode=1)
- Cover range-reduction edge cases: angles near ±90°, ±180°, vectors in all four quadrants
- Dump per-stage x/y/z (not just final output) in at least one debug run, to cross-check against Python's per-iteration trace if something fails

---

## 7. Synthesis & Characterization

- Synthesize both the iterative and pipelined designs (Vivado, or Yosys if no board/tool access) — synthesis-only reports are sufficient, physical board bring-up is optional
- Metrics to extract:
  - Max frequency (Fmax)
  - LUT / FF utilization
  - Confirm zero DSP/multiplier blocks used — the K-scale multiply is implemented as shift-add against the fixed constant, so this should hold with no exceptions, unlike the earlier plan which assumed one constant-multiply block
- Build the direct comparison table (both designs are already built and verified):

| Metric | Pipelined | Iterative |
|---|---|---|
| Area (LUTs/FFs) | 1040 / 875 (5.00% / 2.10%) | 491 / 292 (2.36% / 0.70%) |
| Throughput (results/sec) | ~149.8M (1 result/cycle steady-state @ ~149.8 MHz) | ~7.4M (1 result/17 cycles @ ~126.1 MHz) |
| Latency (cycles) | 17 (1 load + N=14 stages + 2 output-register stages) | 17 (1 load + 14 iterations + 2 output-register stages) |
| Fmax | ~149.8 MHz (WNS +3.323 ns @ 100 MHz target) | ~126.1 MHz (WNS +2.069 ns @ 100 MHz target) |

Both meet timing at the 100 MHz target with margin, on Artix-7 `xc7a35tcpg236-1`
(Basys3), post-synthesis. Zero DSP48 usage on both. Full breakdown in
`synth/results.md`. The pipelined design trades ~2x LUTs / ~3x FFs for a
~20x higher steady-state throughput (1 result/cycle vs. 1 result/17 cycles)
and a meaningfully higher Fmax, since its per-stage critical path is just
one `cordic_stage` hop rather than the iterative version's shared,
counter-driven stage.

This comparison table is the single highest-leverage artifact for interview conversations — it's evidence of understanding tradeoffs, not just following a recipe.

---

## 8. Build Order & Time Budget (~25-30 hrs)

| Step | Task | Hours |
|---|---|---|
| 1 | Understand algorithm: read references, hand-compute 3-4 iterations on paper | 2-3 |
| 2 | Draw block diagrams (single stage + iterative FSM + range reduction stages) | 1-2 |
| 3 | Python golden model: both modes, range reduction, error sweeps | 4-5 |
| 4 | Verilog: single-stage module (datapath + mode mux), no range reduction yet | 3-4 |
| 5 | Verilog: iterative/folded top module (FSM + counter reusing the stage N times) | 3-4 |
| 6 | Testbench (core only): self-check both modes against the bit-exact Python model, inputs pre-reduced in software | 3-4 |
| 7 | Verilog: add hardware range reduction pre/post stages + negate/flip flag register | 3-4 |
| 8 | Testbench (full ±180°): re-run self-check with range-reduction edge cases | 2-3 |
| 9 | Synthesis (iterative design) + pull area/timing numbers | 2-3 |
| 10 | *(If time remains)* Pipelined version + comparison table | 4-6 |
| 11 | Writeup/README: diagrams, error plots, synthesis table, design rationale | 2-3 |

**Total core scope (steps 1-9, 11):** ~25-30 hrs
**With extension (step 10):** ~29-36 hrs — trim step 8 or 11 slightly if needed to stay in budget

---

## 9. Deliverables Checklist

- [ ] Python golden model (both modes + range reduction) with error-vs-N and error-vs-wordlength plots
- [ ] Verilog RTL: parameterized pipelined CORDIC core (mode-selectable)
- [ ] Range reduction pre/post stages (both modes)
- [ ] Self-checking testbench with full coverage (both modes, quadrant/angle edge cases)
- [ ] Synthesis report (Fmax, area, zero-multiplier confirmation)
- [ ] *(Optional)* Iterative/folded version + pipelined-vs-iterative comparison table
- [ ] README with: block diagrams, design rationale (word length/N choice), error plots, synthesis results, and (if done) architecture comparison

## 10. Resume/Interview Framing

> "Designed and verified a parameterized, mode-selectable (rotation/vectoring) pipelined CORDIC accelerator in Verilog with full ±180° input range support via internal range reduction, achieving [X] MHz on [FPGA/synthesis tool] using zero general-purpose multipliers — validated against a Python floating-point reference model across the full input range."

Be ready to explain, unprompted: why you chose your word length and N, how the gain compensation works and why you avoided a multiplier, how range reduction works and why it's necessary, and (if built) the pipelined-vs-iterative area/throughput tradeoff with real numbers.