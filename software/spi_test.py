# don't forget to run `pip install spidev gpiozero` before executing this script!

import spidev
import time
from gpiozero import Button, DigitalOutputDevice

# 1. Configuration Constants
SPI_BUS = 0
SPI_DEVICE = 0 # The Pi will still blindly toggle GPIO 8 (CE0), but nothing is connected!
SPI_SPEED_HZ = 8000000 
INTERRUPT_PIN = 25 # GPIO 25 (Physical Pin 22)

# --- THE DUMMY CS FIX ---
# We use a standard GPIO pin for CS to completely bypass the Linux kernel restrictions.
CS_PIN = 16 # GPIO 16 (Physical Pin 36). Make sure you moved your wire here!
cs_n = DigitalOutputDevice(CS_PIN, initial_value=True) 
# ------------------------

print("--- FPGA-CNN SPI Communications Test ---")
print(f"Configuring SPI0: Mode 0, {SPI_SPEED_HZ / 1000000} MHz...")

# 2. Initialize SPI
spi = spidev.SpiDev()
spi.open(SPI_BUS, SPI_DEVICE)
spi.max_speed_hz = SPI_SPEED_HZ
spi.mode = 0 # CPOL=0, CPHA=0
# Notice: We removed the spi.no_cs = True line that caused the OSError!

# 3. Initialize Hardware Interrupt (Active High)
data_ready = Button(INTERRUPT_PIN, pull_up=False) 

try:
    # 4. Prepare Dummy Payload (2312 bytes for exactly 1156 16-bit words)
    NUM_PIXELS = 1156
    dummy_image = [0x00] * (NUM_PIXELS * 2) 
    
    print(f"Transmitting {len(dummy_image)} dummy bytes to FPGA...")
    
    # MANUALLY LOWER OUR CUSTOM CS_N
    cs_n.off()
    
    start_time = time.perf_counter()
    spi.xfer2(dummy_image)
    tx_time = time.perf_counter() - start_time
    print(f"Transmission complete in {tx_time*1000000:.2f} µs.")

    # 5. Wait for FSM to assert DATA_READY
    print("Waiting for DATA_READY interrupt from FPGA...")
    if data_ready.wait_for_active(timeout=2.0):
        print(">>> INTERRUPT RECEIVED! <<<")
        
        # 6. Read Results (3 logits * 2 bytes = 6 bytes)
        print("Reading 6 bytes of logit data...")
        raw_results = spi.xfer2([0x00] * 6)
        
        print("\nRaw Hex Dump Received:")
        hex_string = " ".join([f"{byte:02X}" for byte in raw_results])
        print(f"[{hex_string}]")
        print("\nTest Result: SUCCESS. SPI Link is verified.")
        
    else:
        print("\nTest Result: FAILED. Timeout waiting for DATA_READY.")
        print("Check your LEDs to see where the FPGA stalled.")

except Exception as e:
    print(f"\nAn error occurred: {e}")

finally:
    # MANUALLY RAISE OUR CUSTOM CS_N 
    cs_n.on()
    spi.close()
    print("SPI port closed.")