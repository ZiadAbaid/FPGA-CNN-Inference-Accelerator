import glob
import numpy as np
import time
import random
from PIL import Image
from gpiozero import Button, DigitalOutputDevice

# Import Custom Hardware & SW Reference
from spi import FPGACNN
from golden_model import run_full_inference

# Import LiteRT (TensorFlow Lite)
try:
    from ai_edge_litert.interpreter import Interpreter
except ImportError:
    print("Error: LiteRT not found. Please install tflite_runtime or ai_edge_litert.")
    exit()

# --- THE LOOPBACK CALIBRATION SETUP ---
# Wire GPIO 17 (Physical Pin 11) directly to GPIO 27 (Physical Pin 13)!
fake_fpga_out = DigitalOutputDevice(17, initial_value=False)
os_listener = Button(27, pull_up=False)

def measure_os_overhead():
    """Forces the Pi to interrupt itself to measure the current OS latency."""
    fake_fpga_out.off()
    time.sleep(0.01) # Let the line settle
    
    t_start = time.perf_counter()
    fake_fpga_out.on() # Trigger the interrupt!
    os_listener.wait_for_active(timeout=1.0)
    t_end = time.perf_counter()
    
    fake_fpga_out.off()
    return (t_end - t_start) * 1000.0 # Return overhead in ms

def prep_tflite_image(image_path):
    """Prepares the image exactly how TFLite expects it: (1, 32, 32, 1) Float32"""
    img = Image.open(image_path).convert('L').resize((32, 32))
    img_array = np.array(img, dtype=np.float32)
    return np.expand_dims(img_array, axis=(0, -1))

def main():
    print("======================================================")
    print("  HARDWARE vs SOFTWARE PERFORMANCE BENCHMARK SUITE  ")
    print("======================================================")
    
    # 1. Initialize Hardware Engine
    fpga_engine = FPGACNN(speed_hz=8000000, interrupt_pin=25, cs_pin=16)
    
    # 2. Initialize TFLite Software Engine
    interpreter = Interpreter(model_path="tiny_ai_brain.tflite")
    interpreter.allocate_tensors()
    in_idx = interpreter.get_input_details()[0]['index']
    out_idx = interpreter.get_output_details()[0]['index']
    
    # --- WARM UP THE CPU ---
    print("Warming up the CPU cache...")
    dummy_input = np.zeros((1, 32, 32, 1), dtype=np.float32)
    interpreter.set_tensor(in_idx, dummy_input)
    interpreter.invoke()
    
    # 3. Find and Randomize Test Images
    test_images = glob.glob("Doglets/*/*.jpg")
    if not test_images:
        print("Error: Could not find test images in 'Doglets/*/*.jpg'")
        return
        
    random.shuffle(test_images) # THE FIX: Randomize the testing order!
    
    matches = 0
    total_images = min(10, len(test_images)) 
    classes = ["Cat", "Dog", "Human"]
    
    for img_path in test_images[:total_images]: 
        print(f"\nEvaluating: {img_path}")
        
        # ----------------------------------------------------
        # TEST A: THE SOFTWARE BENCHMARK (TFLite)
        # ----------------------------------------------------
        sw_input = prep_tflite_image(img_path)
        t0_sw = time.perf_counter()
        interpreter.set_tensor(in_idx, sw_input)
        interpreter.invoke()
        sw_raw = interpreter.get_tensor(out_idx)[0]
        sw_time_ms = (time.perf_counter() - t0_sw) * 1000.0
        sw_pred = classes[np.argmax(sw_raw)]
        
        # ----------------------------------------------------
        # DYNAMIC OS CALIBRATION
        # ----------------------------------------------------
        current_os_overhead = measure_os_overhead()
        
        # ----------------------------------------------------
        # TEST B: THE HARDWARE BENCHMARK (FPGA)
        # ----------------------------------------------------
        fpga_logits, hw_timing = fpga_engine.run_inference(img_path)
        if fpga_logits is None:
            continue
        fpga_pred = classes[np.argmax(fpga_logits)]
        
        # ----------------------------------------------------
        # TEST C: THE ACCURACY BENCHMARK (Golden Model)
        # ----------------------------------------------------
        golden_logits = run_full_inference(img_path)
        is_exact = "YES" if fpga_logits == golden_logits else "NO"
        if is_exact == "YES":
            matches += 1

        # ----------------------------------------------------
        # CALCULATE TRUE FPGA MATH TIME
        # ----------------------------------------------------
        raw_measured = hw_timing['fpga_compute_ms']
        true_fpga_math = raw_measured - current_os_overhead
        
        # Prevent "negative time" caused by Linux Scheduler Jitter
        if true_fpga_math < 0.001:
            true_fpga_math = 0.001 

        # ----------------------------------------------------
        # PRINT THE RESULTS TABLE
        # ----------------------------------------------------
        print(f"| Metric                   | Pi 5 SW (TFLite) | FPGA HW (Artix-7) |")
        print(f"|--------------------------|------------------|-------------------|")
        print(f"| Prediction               | {sw_pred:<16} | {fpga_pred:<17} |")
        print(f"| 100% Bit-Exact Parity?   | N/A              | {is_exact:<17} |")
        print(f"| Compute Time (Pure Math) | {sw_time_ms:>13.3f} ms | {true_fpga_math:>14.3f} ms |")
        print(f"| SPI Transfer Time (I/O)  | N/A              | {hw_timing['spi_tx_ms'] + hw_timing['spi_rx_ms']:>14.3f} ms |")
        print(f"| Linux OS Overhead Delay  | N/A              | {current_os_overhead:>14.3f} ms |") 
        print(f"| Total System Latency     | {sw_time_ms:>13.3f} ms | {hw_timing['total_system_ms']:>14.3f} ms |")
        print(f"|--------------------------|------------------|-------------------|")
        
    print("\n======================================================")
    print(f" BENCHMARK COMPLETE ")
    print(f" Verified Math Parity: {matches}/{total_images} ({(matches/total_images)*100}%)")
    print("======================================================")
    
    fpga_engine.close()

if __name__ == "__main__":
    main()