## ==============================================================================
## FPGA-Accelerated CNN Inference - Master Constraints File
## Target Board: Digilent Nexys 4 / Nexys A7 (Artix-7 XC7A100T)
## ==============================================================================

## ------------------------------------------------------------------------------
## 1. System Clock (100 MHz Oscillator)
## ------------------------------------------------------------------------------
# Mapped to physical pin E3 (100MHz onboard oscillator)
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk_100mhz }];

# Define the clock for the timing analyzer (10.00 ns period = 100 MHz)
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_100mhz }];


## ------------------------------------------------------------------------------
## 2. System Reset
## ------------------------------------------------------------------------------
# Mapped to the red CPU_RESET button (Active Low)
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { reset_n }];


## ------------------------------------------------------------------------------
## 3. SPI Communication Interface (PMOD JA)
## ------------------------------------------------------------------------------
# JA[1] - MOSI (Pi -> FPGA)
set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33 } [get_ports { spi_mosi }];

# JA[2] - MISO (FPGA -> Pi)
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { spi_miso }];

# JA[3] - SCLK (Pi -> FPGA)
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports { spi_sclk }];

# JA[4] - CS_N / CE0 (Pi -> FPGA, Active Low)
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { spi_cs_n }];


## ------------------------------------------------------------------------------
## 4. Hardware Interrupt (PMOD JB)
## ------------------------------------------------------------------------------
# JB[1] - DATA_READY (FPGA -> Pi)
set_property -dict { PACKAGE_PIN D14   IOSTANDARD LVCMOS33 } [get_ports { data_ready }];


## ------------------------------------------------------------------------------
## 5. Asynchronous Input Constraints
## ------------------------------------------------------------------------------
# Since spi_mosi, spi_sclk, spi_cs_n, and reset_n are external signals asynchronous 
# to the 100MHz clock, we tell the timing analyzer to ignore the setup/hold times 
# from the I/O pads to the first synchronizer flip-flops in spi_controller.vhd.
set_false_path -from [get_ports { spi_mosi spi_sclk spi_cs_n reset_n }]


## ------------------------------------------------------------------------------
## 6. Hardware Debugger LEDs
## ------------------------------------------------------------------------------
# LEDs 15-12: FSM State | LED 11: RX FIFO Empty | LEDs 10-0: Pixel Count
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { led[4] }];
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { led[5] }];
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { led[6] }];
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { led[7] }];
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { led[8] }];
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { led[9] }];
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { led[10] }];
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { led[11] }];
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { led[12] }];
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { led[13] }];
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { led[14] }];
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { led[15] }];