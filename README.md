![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# Tiny Tapeout Verilog Project Template

- [Read the documentation for project](docs/info.md)

## What is Tiny Tapeout?

Tiny Tapeout is an educational project that aims to make it easier and cheaper than ever to get your digital and analog designs manufactured on a real chip.

To learn more and get started, visit https://tinytapeout.com.

# TinyTapeout: 8-bit Function Generator
**Module:** `tt_um_FG_TOP_Dominik_Brandstetter`

A compact, **programmable 8‑bit function generator** for TinyTapeout. Outputs **DC**, **CORDIC sine**, or **trapezoid/pulse** (rise–hold–fall). Sampling is driven by an on‑chip **timer + prescaler**. Configure via a simple **write‑only 7×8‑bit register map** over TT GPIO. The 8‑bit parallel output feeds an external DAC (e.g., **AD5330**) or an R‑2R ladder.

---

## 🚀 Quick Start
1. **Wire the DAC** (see *AD5330 Hookup*).
2. Power up with **`ENABLE_n=1`** (halted).
3. (Optional) Program **`CR0..CR6`** while halted.
4. Drive **`ENABLE_n=0`** → generator runs (default: **~20 kHz sine**).

**Write protocol:** While **halted** (`ENABLE_n=1`), assert **`WR_n=0` for ≥3 clocks** with stable `ADDR` + `DATA`. Then release `WR_n` and set **`ENABLE_n=0`** to run.

---

## ✨ Features
- 3 modes: **Constant**, **Sine (CORDIC)**, **Trapezoid/Pulse**
- **Timer + Prescaler** timebase
- **7×8‑bit** write‑only config
- **8‑bit parallel** DAC output
- Default on reset: **sine ~20 kHz**

---

## 🧰 Top‑Level I/O
| Signal | Dir | W | Purpose |
|---|---:|---:|---|
| `ui_in[7:0]` | in | 8 | Register **data bus** (write‑only) |
| `uo_out[7:0]` | out | 8 | **DAC data** |
| `uio_in[7]` | in | 1 | **ENABLE_n** (Low = run, High = halt/program) |
| `uio_in[6]` | in | 1 | **WR_n** (active‑low write strobe) |
| `uio_in[5:3]` | in | 3 | **ADDR[2:0]** (select `CR0..CR6`) |
| `clk` | in | 1 | System clock |
| `rst_n` | in | 1 | Async reset (active‑low) |
| `ena` | in | 1 | Always `1` on TinyTapeout |

_Minimal DAC control exposed on `uio_out[2:0]`: `dac_wr_n`, `dac_pd_n` (high = enabled), `dac_clr_n`._

---

## 🔌 AD5330 Hookup (Minimal)
- **Data:** `uo_out[7:0]` → AD5330 `DB[7:0]`
- **Control:** `uio_out[2] → /WR`, `uio_out[1] → PD_n` (**high = enabled**), `uio_out[0] → /CLR` (**high** normal)

> If your board exposes `/CS` or `LDAC`, hard‑wire them.

---

## ✅ Notes
- All DAC control lines are **active‑low**.
- **Write only while halted** to avoid glitches.
- Dial frequency: **Prescaler (coarse)** → **Counter (fine)**.
- Keep headroom: **Amplitude + Offset** must fit 8‑bit.
