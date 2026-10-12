import spidev
import time
import numpy as np
from PIL import Image
from gpiozero import Button, DigitalOutputDevice

class FPGACNN:
    # Running at the verified 8 MHz with Dummy CS on GPIO 16
    def __init__(self, bus=0, device=0, speed_hz=8000000, interrupt_pin=25, cs_pin=16):
        self.speed_hz = speed_hz
        self.spi = spidev.SpiDev()
        self.spi.open(bus, device)
        self.spi.max_speed_hz = self.speed_hz
        self.spi.mode = 0
        
        # --- THE DUMMY CS FIX ---
        self.cs_n = DigitalOutputDevice(cs_pin, initial_value=True)
        self.data_ready = Button(interrupt_pin, pull_up=False)

    def preprocess_image(self, image_path):
        """Loads image, zero-pads to 34x34, and converts to Q8.8 byte payload."""
        img = Image.open(image_path).convert('L').resize((32, 32))
        pixel_data = np.array(img, dtype=np.float32)
        
        padded_img = np.pad(pixel_data, pad_width=1, mode='constant', constant_values=0)
        padded_img = (padded_img / 255.0) * 256.0
        fixed_point_pixels = np.round(padded_img).astype(np.int16).flatten().tolist()
        
        spi_payload = []
        for pixel in fixed_point_pixels:
            spi_payload.extend([(pixel >> 8) & 0xFF, pixel & 0xFF])
            
        return spi_payload

    def run_inference(self, image_path):
        payload = self.preprocess_image(image_path)
        
        try:
            self.cs_n.off() # Start Transaction
            
            # --- LAP 1: SPI Transmit ---
            t0 = time.perf_counter()
            self.spi.xfer2(payload)
            
            # --- LAP 2: FPGA Compute ---
            t1 = time.perf_counter() 
            if self.data_ready.wait_for_active(timeout=2.0):
                
                # --- LAP 3: SPI Receive ---
                t2 = time.perf_counter()
                rx_data = self.spi.xfer2([0x00] * 6) 
                t3 = time.perf_counter()
                
                # Calculate the exact millisecond breakdown
                timing = {
                    "spi_tx_ms": (t1 - t0) * 1000.0,
                    "fpga_compute_ms": (t2 - t1) * 1000.0,
                    "spi_rx_ms": (t3 - t2) * 1000.0,
                    "total_system_ms": (t3 - t0) * 1000.0
                }
                
                # Reconstruct 16-bit Signed Q8.8 Logits
                logits = []
                for i in range(0, 6, 2):
                    val = (rx_data[i] << 8) | rx_data[i+1]
                    if val > 32767:
                        val -= 65536 
                    logits.append(val)
                    
                return logits, timing
            else:
                print(f"Timeout waiting for DATA_READY on {image_path}")
                return None, None
                
        finally:
            self.cs_n.on() # End Transaction safely

    def close(self):
        self.spi.close()