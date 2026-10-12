import numpy as np
from PIL import Image
import time
import random
import os

# ==========================================
# IMPORT REAL HARDWARE & SOFTWARE ENGINES
# ==========================================
try:
    from ai_edge_litert.interpreter import Interpreter
    interpreter = Interpreter(model_path="tiny_ai_brain.tflite")
    interpreter.allocate_tensors()
    in_idx = interpreter.get_input_details()[0]['index']
    out_idx = interpreter.get_output_details()[0]['index']
    HAS_SW_ENGINE = True
except ImportError:
    HAS_SW_ENGINE = False
    print("WARNING: LiteRT not found. Simulating SW engine.")

try:
    from spi import FPGACNN
    # Updated to match the new benchmark.py initialization
    hw_engine = FPGACNN(speed_hz=8000000, interrupt_pin=25, cs_pin=16) 
    HAS_HW_ENGINE = True
except ImportError:
    HAS_HW_ENGINE = False
    print("WARNING: spi.py not found. Simulating HW engine.")

# ==========================================
# OS OVERHEAD LOOPBACK SETUP
# ==========================================
try:
    from gpiozero import Button, DigitalOutputDevice
    fake_fpga_out = DigitalOutputDevice(17, initial_value=False)
    os_listener = Button(27, pull_up=False)
    HAS_LOOPBACK = True
except ImportError:
    HAS_LOOPBACK = False

def measure_os_overhead():
    if not HAS_LOOPBACK: 
        return 0.0
    fake_fpga_out.off()
    time.sleep(0.01)
    t_start = time.perf_counter()
    fake_fpga_out.on()
    os_listener.wait_for_active(timeout=1.0)
    t_end = time.perf_counter()
    fake_fpga_out.off()
    return (t_end - t_start) * 1000.0

# ==========================================
# INFERENCE ROUTINES
# ==========================================
def format_image(image_path):
    """ Used purely by the GUI to get the 256x256 display image """
    try:
        img = Image.open(image_path).convert('L')
        img = img.resize((32, 32))
        img_array = np.array(img)
        return img_array.flatten().tolist(), img
    except Exception as e:
        return None, str(e)

def run_pi_software_inference(image_path):
    if HAS_SW_ENGINE:
        # Prep exactly like benchmark.py
        img = Image.open(image_path).convert('L').resize((32, 32))
        img_array = np.array(img, dtype=np.float32)
        sw_input = np.expand_dims(img_array, axis=(0, -1))
        
        t0_sw = time.perf_counter()
        interpreter.set_tensor(in_idx, sw_input)
        interpreter.invoke()
        sw_raw = interpreter.get_tensor(out_idx)[0]
        sw_time_ms = (time.perf_counter() - t0_sw) * 1000.0
        
        classes = ["CAT", "DOG", "HUMAN"]
        sw_pred = classes[np.argmax(sw_raw)]
        return sw_pred, sw_time_ms
    else:
        # Fallback Simulation (Windows testing)
        time.sleep(0.042)
        return random.choice(["CAT", "DOG", "HUMAN"]), 42.0

def run_fpga_hardware_inference(image_path):
    if HAS_HW_ENGINE:
        # Note: benchmark now returns fpga_logits instead of string prediction
        fpga_logits, hw_timing = hw_engine.run_inference(image_path)
        if fpga_logits is None:
            return "ERROR", 0.0
            
        classes = ["CAT", "DOG", "HUMAN"]
        fpga_pred = classes[np.argmax(fpga_logits)]
        
        # --- CALCULATE PURE MATH TIME ---
        os_overhead = measure_os_overhead()
        true_fpga_math = hw_timing["fpga_compute_ms"] - os_overhead
        
        # Prevent "negative time" caused by Linux Scheduler Jitter
        if true_fpga_math < 0.001:
            true_fpga_math = 0.001
            
        return fpga_pred, true_fpga_math
    else:
        # Fallback Simulation (Windows testing)
        time.sleep(0.0015)
        return random.choice(["CAT", "DOG", "HUMAN"]), 1.5
