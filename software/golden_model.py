import numpy as np
import os
from PIL import Image

# golden_model.py
# Master Plan Phase 1: Integer-Only Reference Model
# Updated: Input pixels are now properly scaled to Q8.8 to match spi.py hardware inputs!

# ─────────────────────────────────────────────
#  Phase 1.1: Core Arithmetic Engine (Bit-Exact Q8.8)
# ─────────────────────────────────────────────
def dsp48_mac(inputs, weights, bias, apply_relu=True):
    """Simulates the FPGA DSP48E1 48-bit MAC engine."""
    accumulator = 0 
    
    for i, w in zip(inputs, weights):
        accumulator += int(i) * int(w)
        
    accumulator += (int(bias) << 8)
    result = accumulator >> 8
    
    if result > 32767:
        result = 32767
    elif result < -32768:
        result = -32768
        
    if apply_relu and result < 0:
        result = 0
        
    return result

# ─────────────────────────────────────────────
#  Phase 1.2: Spatial & Dense Operations
# ─────────────────────────────────────────────
def conv2d_valid(input_map, weights, biases, apply_relu=True):
    in_h = len(input_map)
    in_w = len(input_map[0])
    in_c = len(input_map[0][0])
    out_c = len(weights)
    
    out_h = in_h - 2
    out_w = in_w - 2
    
    out_map = [[[0 for _ in range(out_c)] for _ in range(out_w)] for _ in range(out_h)]
    
    for y in range(out_h):
        for x in range(out_w):
            for oc in range(out_c):
                window_flat = []
                kernel_flat = []
                for ic in range(in_c):
                    for dy in range(3):
                        for dx in range(3):
                            window_flat.append(input_map[y + dy][x + dx][ic])
                            kernel_flat.append(weights[oc][ic][dy][dx])
                            
                out_map[y][x][oc] = dsp48_mac(window_flat, kernel_flat, biases[oc], apply_relu)
    return out_map

def padder2d(input_map):
    in_h = len(input_map)
    in_w = len(input_map[0])
    in_c = len(input_map[0][0])
    out_h = in_h + 2
    out_w = in_w + 2
    out_map = [[[0 for _ in range(in_c)] for _ in range(out_w)] for _ in range(out_h)]
    for y in range(in_h):
        for x in range(in_w):
            for c in range(in_c):
                out_map[y + 1][x + 1][c] = input_map[y][x][c]
    return out_map

def max_pool2d_2x2(input_map):
    in_h = len(input_map)
    in_w = len(input_map[0])
    in_c = len(input_map[0][0])
    out_h = in_h // 2
    out_w = in_w // 2
    out_map = [[[0 for _ in range(in_c)] for _ in range(out_w)] for _ in range(out_h)]
    for y in range(out_h):
        for x in range(out_w):
            for c in range(in_c):
                val1 = input_map[y*2][x*2][c]
                val2 = input_map[y*2][x*2 + 1][c]
                val3 = input_map[y*2 + 1][x*2][c]
                val4 = input_map[y*2 + 1][x*2 + 1][c]
                out_map[y][x][c] = max(val1, val2, val3, val4)
    return out_map

def flatten3d(input_map):
    out_flat = []
    for y in range(len(input_map)):
        for x in range(len(input_map[0])):
            for c in range(len(input_map[0][0])):
                out_flat.append(input_map[y][x][c])
    return out_flat

def dense_layer(input_vector, weights, biases, out_c, apply_relu=True):
    """
    Computes Dense output using hardware-aligned transposed weights:
    weights shape: (num_passes, in_size, parallel_macs)
    """
    in_size = len(input_vector)
    parallel_macs = len(weights[0][0]) # Expected to be 8 based on hardware
    
    out_vector = [0] * out_c
    
    for oc in range(out_c):
        # Calculate exactly where this neuron's weights are in the 3D hardware matrix
        pass_idx = oc // parallel_macs
        mac_idx = oc % parallel_macs
        
        # Extract the weight vector for this specific output neuron across all inputs
        weights_flat = [weights[pass_idx][ic][mac_idx] for ic in range(in_size)]
        
        # Run through the bit-exact MAC
        out_vector[oc] = dsp48_mac(input_vector, weights_flat, biases[oc], apply_relu)
        
    return out_vector

# ─────────────────────────────────────────────
#  Phase 1.3: Full Network Forward Pass
# ─────────────────────────────────────────────
def load_q88_weights(layer_name):
    w = np.load(f"export_q88/{layer_name}_weights.npy").tolist()
    b = np.load(f"export_q88/{layer_name}_biases.npy").tolist()
    return w, b

def run_full_inference(img_path):
    print(f"\n--- Starting Full Hardware Simulation for: {img_path} ---")
    
    # 1. Load Image
    img = Image.open(img_path).convert('L').resize((32, 32))
    pixel_data = np.array(img, dtype=int)
    
    # 2. Pi-Side Padding (32x32 -> 34x34)
    padded_img = np.pad(pixel_data, pad_width=1, mode='constant', constant_values=0)
    
    # --- THE FIX: SCALE TO Q8.8 ---
    # Keras trained with 0.0-1.0. Our spi.py divides by 255.0 and multiplies by 256.0.
    # We use np.round() and cast to int to exactly mimic the hardware payload.
    hw_map = [[[int(np.round((padded_img[y][x] / 255.0) * 256.0))] for x in range(34)] for y in range(34)]
    
    # 3. Load All Weights 
    print("Loading exported weights...")
    try:
        c1_w, c1_b = load_q88_weights("conv1")
        c2_w, c2_b = load_q88_weights("conv2")
        c3_w, c3_b = load_q88_weights("conv3")
        d1_w, d1_b = load_q88_weights("dense1")
        d2_w, d2_b = load_q88_weights("dense2")
    except FileNotFoundError:
        print("Error: Could not find weight files. Run export_weights.py first.")
        return None

    # 4. Execute Pipeline
    print("Running Pipeline...")
    x = conv2d_valid(hw_map, c1_w, c1_b, apply_relu=True)
    x = max_pool2d_2x2(x)
    x = padder2d(x)
    x = conv2d_valid(x, c2_w, c2_b, apply_relu=True)
    x = max_pool2d_2x2(x)
    x = padder2d(x)
    x = conv2d_valid(x, c3_w, c3_b, apply_relu=True)
    x = max_pool2d_2x2(x)
    x = flatten3d(x)
    
    # Updated to pass out_c parameter
    x = dense_layer(x, d1_w, d1_b, out_c=32, apply_relu=True)
    logits = dense_layer(x, d2_w, d2_b, out_c=3, apply_relu=False) 
    
    return logits

if __name__ == "__main__":
    # Test a Dog image this time!
    test_image = "Doglets/Human/9_Press_Conference_Press_Conference_9_466.jpg"  # Change to your test image path
    
    if os.path.exists(test_image):
        final_logits = run_full_inference(test_image)
        if final_logits:
            print("\n==================================")
            print(" FPGA SIMULATION COMPLETE")
            print("==================================")
            print(f" Raw Q8.8 Logits : {final_logits}")
            print(f" Predicted Class : {['Cat', 'Dog', 'Human'][np.argmax(final_logits)]}")
            print("==================================")
    else:
        print(f"FAIL: Could not find image at '{test_image}'.")

# ... (Keep all your existing golden_model.py functions above this!)

class GoldenModel:
    def __init__(self):
        self.classes = ["Cat", "Dog", "Human"]

    def predict(self, image_path):
        logits = run_full_inference(image_path)
        if logits is None:
            return "Error"
        # Return the string name of the winning class
        return self.classes[np.argmax(logits)]