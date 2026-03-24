# 2×2 Systolic Array Matrix Multiplier (FPGA | Verilog)

A fully synthesizable **2×2 systolic array matrix multiplier** implemented in **Verilog HDL**, targeted for the **Digilent Nexys 4 DDR (Artix-7 FPGA)**. This project demonstrates the fundamental principles of systolic computation, including **dataflow pipelining, input staggering, and local MAC operations**, which form the backbone of modern AI accelerators (e.g., TPUs, Tensor Cores).

---

## 📌 Key Inspiration

This project was heavily inspired by the following resource:

- https://deep-learning00.tistory.com/27

This reference provides an intuitive visualization of systolic array dataflow, particularly the **time-stepped propagation of operands**, which directly influenced the design and documentation approach used here.

---

## 📖 Overview

Matrix multiplication:
C = A × B

For 2×2 matrices:
|c11 c12| |a11 a12| |b11 b12|
|c21 c22| = |a21 a22| × |b21 b22|

Each output element is computed as:

- c11 = a11·b11 + a12·b21  
- c12 = a11·b12 + a12·b22  
- c21 = a21·b11 + a22·b21  
- c22 = a21·b12 + a22·b22  

Instead of computing sequentially, this design uses a **systolic array** where:

- `A` flows **left → right**
- `B` flows **top → bottom**
- Each Processing Element (PE) performs a **MAC (Multiply-Accumulate)**

---

## 🧠 Architecture

### Processing Elements (PEs)

- 4 PEs arranged in a **2×2 mesh**
- Each PE:
  - Multiplies inputs (`a_in × b_in`)
  - Accumulates result
  - Forwards:
    - `a → right`
    - `b → down`

### Dataflow

- Fully **pipelined**
- No global memory access between PEs
- High data reuse via **neighbor communication**

---

## ⏱️ Time-Stepped Execution

The computation completes in **5 clock-enable pulses** due to pipelining and staggered inputs.

### Time Step 1
- First multiplication starts:
  - `a11 × b11`

### Time Step 2
- Accumulation begins:
  - `a11·b11 + a12·b21`
- New computations start in adjacent PEs

### Time Step 3
- Intermediate values propagate
- Multiple PEs active simultaneously

### Time Step 4
- Final accumulation for last elements

### Time Step 5 (Flush)
- Final result available

---

## ⚙️ Input Staggering (Critical Concept)

To ensure correct operand alignment:

| Input | Timing |
|------|--------|
| Row 0 of A | No delay |
| Row 1 of A | 1-cycle delay |
| Column 0 of B | No delay |
| Column 1 of B | 1-cycle delay |

This guarantees that each PE receives the correct `(a, b)` pair at the right time.

Without staggering → **incorrect multiplication pairing**

---

## 📁 Project Structure
├── pe.v # Processing Element (MAC unit)
├── systolic_2x2.v # FSM controller + data scheduling
├── top_nexys4.v # FPGA integration (I/O, display, debounce)
├── constraints.xdc # Pin mappings for Nexys 4 DDR
├── README.md
---

## 🔧 Hardware Details

- **FPGA**: Xilinx Artix-7 (XC7A100T)
- **Board**: Nexys 4 DDR
- **Clock**: 100 MHz
- **Operands**: 2-bit (0–3)
- **Output**: 5-bit (0–18)

---

## 💡 Features

- ✔ Fully pipelined systolic architecture  
- ✔ Manual clock stepping (button-controlled)  
- ✔ Real-time visualization via:
  - LEDs (approximate values)
  - 7-segment display (exact values)  
- ✔ Debounced button inputs  
- ✔ Clean FSM-based scheduling  

---

## 📊 Example

### Input:A = |2 1|
|1 2|

B = |2 1|
|1 2|
### Output:C = |5 4|
|4 5|
### Clock-by-Clock Evolution:

| Cycle | acc00 | acc01 | acc10 | acc11 |
|------|------|------|------|------|
| 1 | 0 | 0 | 0 | 0 |
| 2 | 4 | 0 | 0 | 0 |
| 3 | 5 | 2 | 2 | 0 |
| 4 | 5 | 4 | 4 | 1 |
| 5 | 5 | 4 | 4 | 5 |

---

## 🧪 Verification

- Simulated and verified in **Vivado**
- Hardware-tested on Nexys 4 DDR
- Outputs match theoretical matrix multiplication exactly

---

## 🚀 Relevance

This small-scale design directly reflects architectures used in:

- Google TPU
- NVIDIA Tensor Cores
- AI accelerators (CNNs, Transformers)

Key advantages:

- High compute efficiency  
- Deterministic latency  
- Scalable architecture  
- Reduced memory bandwidth  

---

## 📈 Scalability

For an `N×N` systolic array:

- PEs required: `N²`
- Latency: `2N - 1` cycles
- Throughput: scales linearly

---

## ⚠️ Limitations

- 2-bit operand precision (demo-focused)
- Manual clocking (not throughput-optimized)
- No DSP utilization (uses LUTs only)

---

## 🔮 Future Improvements

- Increase bit-width (8-bit / FP16)
- Automatic clocking (fully pipelined throughput)
- Larger arrays (4×4, 8×8)
- DSP48 integration
- AXI-based memory interface

---

## 📚 References

- H.T. Kung, “Why systolic architectures?”
- NVIDIA Tensor Core architecture
- Google TPU architecture
- Nexys 4 DDR Reference Manual
- https://deep-learning00.tistory.com/27

---

## 👨‍💻 Author

Roshan Tripathy  
KIIT University, Bhubaneswar  

---

## 📜 License

MIT License (or specify your preferred license)

---

## 🔚 Summary

This project provides a **clear, hardware-level understanding of systolic arrays**, bridging the gap between:

- Academic theory  
- FPGA implementation  
- Real-world AI hardware  

It is intentionally small, deterministic, and observable—making it ideal for **learning, demonstration, and extension**.
