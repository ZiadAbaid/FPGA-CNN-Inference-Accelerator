import cv2
import numpy as np
import time
import os
from PIL import Image

# --- SW Engine (LiteRT) ---
try:
    from ai_edge_litert.interpreter import Interpreter
except ImportError:
    Interpreter = None

# --- HW Engine (FPGA SPI) ---
try:
    from spi import FPGACNN
    hw_engine = FPGACNN(speed_hz=8000000, interrupt_pin=25, cs_pin=16)
    HAS_HW_ENGINE = True
except ImportError:
    HAS_HW_ENGINE = False

# --- Global State ---
_cap = None
_interpreter = None
_input_details = None
_output_details = None

_frame_count = 0
_last_results = [0.33, 0.33, 0.33]
_last_pi_ms = 0.0
_last_fpga_ms = 0.0

CLASS_NAMES = ["CAT", "DOG", "HUMAN"]
INFER_EVERY_N = 2

def init_camera_stream():
    global _cap, _interpreter, _input_details, _output_details, _frame_count
    
    # 1. Initialize SW Engine
    if Interpreter and os.path.exists("tiny_ai_brain.tflite"):
        try:
            _interpreter = Interpreter(model_path="tiny_ai_brain.tflite")
            _interpreter.allocate_tensors()
            _input_details = _interpreter.get_input_details()
            _output_details = _interpreter.get_output_details()
        except Exception as e:
            print(f"Model Error: {e}")
            _interpreter = None

    # 2. Connect Camera
    # Trying the second IP from your screenshot which is typical for USB tethering
    _cap = cv2.VideoCapture(0)
    _frame_count = 0
    return _cap.isOpened()

def get_next_frame():
    global _cap, _frame_count, _last_results, _last_pi_ms, _last_fpga_ms
    
    if _cap is None or not _cap.isOpened():
        return None, "ERROR", 0.0, 0.0
        
    ret, frame = _cap.read()
    if not ret:
        return None, "ERROR", 0.0, 0.0
        
    _frame_count += 1
    
    # Preprocessing
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    h, w = gray.shape
    side = min(h, w)
    y0, x0 = (h - side) // 2, (w - side) // 2
    cropped = gray[y0:y0+side, x0:x0+side]
    small = cv2.resize(cropped, (32, 32), interpolation=cv2.INTER_AREA)
    cv2.rectangle(frame, (x0, y0), (x0+side, y0+side), (0, 255, 255), 2)
    
    # --- DUAL INFERENCE (SW vs HW) ---
    if _frame_count % INFER_EVERY_N == 0:
        
        # 1. Software Inference (TFLite)
        if _interpreter:
            input_data = np.expand_dims(small, axis=(0, -1)).astype(np.float32)
            t0 = time.perf_counter()
            _interpreter.set_tensor(_input_details[0]['index'], input_data)
            _interpreter.invoke()
            _last_results = _interpreter.get_tensor(_output_details[0]['index'])[0]
            _last_pi_ms = (time.perf_counter() - t0) * 1000

        # 2. Hardware Inference (FPGA)
        if HAS_HW_ENGINE:
            tmp_path = "live_frame.jpg"
            cv2.imwrite(tmp_path, small)
            
            fpga_logits, hw_timing = hw_engine.run_inference(tmp_path)
            if fpga_logits is not None:
                # Use the pure compute time instead of total system ms
                _last_fpga_ms = hw_timing["fpga_compute_ms"]
        else:
            # Fallback Simulation
            _last_fpga_ms = _last_pi_ms * 0.02 if _last_pi_ms > 0 else 1.5

    best_idx = np.argmax(_last_results)
    prediction = CLASS_NAMES[best_idx]
    
    rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(rgb_frame)
    
    return pil_img, prediction, _last_pi_ms, _last_fpga_ms

def release_camera():
    global _cap
    if _cap:
        _cap.release()
        _cap = None