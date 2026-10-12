# 5-Layer Q8.8 Fixed-Point Streaming CNN Accelerator on Artix-7 FPGA & Raspberry Pi 5

**Target FPGA:** Digilent Nexys 4 (`Xilinx Artix-7 XC7A100T-1CSG324C` @ 100 MHz)  
**Host Co-Processor:** Raspberry Pi 5 (ARM Cortex-A76 @ 2.4 GHz) via 8 MHz 16-bit Streaming SPI  
**Design Paradigm:** 100% Pure VHDL RTL (14 Custom Modules, AXI-Stream Backpressure, Zero Xilinx IP Cores / Zero HLS)  

---

## Key Achievements

| Metric | Measured Result | Notes |
| :--- | :---: | :--- |
| **Golden-Model Bit-Exact Parity** | **100 / 100 (`100%`)** | Zero bit discrepancies across 100 randomized test images vs. Python Q8.8 reference |
| **Compute Cycle Reduction** | **~15× Fewer Cycles** | `~35,000` cycles on Artix-7 (100 MHz) vs. `~528,000` cycles on Raspberry Pi 5 TFLite FP32 |
| **Post-SPI Pipeline Flush Latency** | **~200 Cycles (`0.002 ms`)** | Concurrent SPI streaming computes 99% of inference while pixels arrive on the wire |
| **Timing Closure (100 MHz)** | **Zero WNS Violations** | Direct 100 MHz oscillator input without MMCM/PLL overhead |
| **Logic Utilization (LUTs)** | **~35,000 / 101,440 (`35%`)** | Includes 3 Conv layers, 3 MaxPool layers, 2 Padders, and 2 Dense engines |
| **DSP48E1 Utilization** | **54 / 240 (`23%`)** | 9-parallel MACs per Conv stage + 8-parallel MACs per Dense stage |
| **Block RAM (36 Kb Tiles)** | **11 / 135 (`8%`)** | Custom 144-bit wide `weight_rom.vhd` fetches full $3 \times 3$ Q8.8 kernels in a single clock cycle |

---

## System & Pipeline Architecture

```text
Raspberry Pi 5 Host (software/spi.py, benchmark.py, GUI_Frontend.py)
  ├── GPIO 16  --> Software-Framed Chip Select (CS)
  ├── SPI0     --> 8 MHz 16-bit Q8.8 Streaming Bus (2,312 bytes / 34×34 padded frame)
  └── GPIO 25  <-- DATA_READY Hardware Interrupt
         │
         ▼  PMOD JA Interconnect
Nexys 4 Artix-7 FPGA (rtl/system_top.vhd @ 100 MHz)
  ├── spi_controller.vhd (2-FF CDC synchronizers, 16-bit shift registers)
  ├── sync_fifo.vhd (RX: 2048×16-bit | TX: 16×16-bit)
  └── cnn_datapath_top.vhd (Self-throttling AXI-Stream Pipeline: in_valid / in_ready)
        ├── Conv1 + ReLU  (34×34×1  → 32×32×16 | 3×3 kernel, 9-parallel MAC + 2-level binary adder tree)
        ├── MaxPool1      (32×32×16 → 16×16×16 | 2×2 window, stall-on-backpressure line buffers)
        ├── Pad1          (16×16×16 → 18×18×16 | Zero-border state machine)
        ├── Conv2 + ReLU  (18×18×16 → 16×16×32 | 144-bit wide single-cycle BRAM kernel ROM)
        ├── MaxPool2      (16×16×32 → 8×8×32   | 2×2 window)
        ├── Pad2          (8×8×32   → 10×10×32 | Zero-border state machine)
        ├── Conv3 + ReLU  (10×10×32 → 8×8×32   | 9-parallel DSP MACs)
        ├── MaxPool3      (8×8×32   → 4×4×32   | 2×2 window)
        ├── Flatten       (4×4×32   → 512      | Element stream serializer)
        ├── Dense1 + ReLU (512      → 32       | 8-parallel MAC engine)
        └── Dense2        (32       → 3 logits | Raw Q8.8 class scores transmitted over SPI)
```

---

## Repository Structure

* [`rtl/`](rtl/) — Complete synthesizable VHDL RTL source files (`system_top.vhd`, `cnn_datapath_top.vhd`, `conv_layer.vhd`, `pool_layer.vhd`, `padder.vhd`, `flatten.vhd`, `dense_engine.vhd`, `weight_rom.vhd`, `spi_controller.vhd`, `spi_receiver.vhd`, `spi_transmitter.vhd`, `sync_fifo.vhd`, `cnn_config.vhd`).
* [`tb/`](tb/) — Full-system VHDL testbench (`tb_system.vhd`) and layer-by-layer golden `.hex` verification vectors (`tb/testbench_data/`).
* [`weights_q88/`](weights_q88/) — Quantized Q8.8 fixed-point weight and bias `.mem` initialization files (`30,600` total parameters).
* [`constraints/`](constraints/) — Digilent Nexys 4 physical pin and 100 MHz timing constraints (`nexys4_top.xdc`).
* [`software/`](software/) — Keras training (`train_cnn.py`), Q8.8 quantizer & ROM exporter (`export_weights.py`), bit-exact integer golden model (`golden_model.py`), Raspberry Pi 5 SPI driver (`spi.py`), hardware-vs-TFLite benchmark suite (`benchmark.py`), and interactive GUI (`GUI_Frontend.py`).
* [`results/`](results/) — Post-implementation Vivado timing closure (`timing_summary.png`), resource utilization (`utililization_summary.png`), power analysis (`Power.png`), and evaluation logs.
* [`docs/`](docs/) — Full project completion report ([`FPGA_CNN_Project_Summary.pdf`](docs/FPGA_CNN_Project_Summary.pdf)) and architecture specification ([`FPGA_CNN_Master_Plan_v3.pdf`](docs/FPGA_CNN_Master_Plan_v3.pdf)).
