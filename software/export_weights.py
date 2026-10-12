import os
import numpy as np
import tensorflow as tf

# ─────────────────────────────────────────────
# 1. Configuration & Helper Functions
# ─────────────────────────────────────────────
MODEL_PATH = "tiny_ai_brain.h5"
OUTPUT_DIR = "export_q88"

def quantize_q8_8(x_float):
    """Converts a float array to Q8.8 fixed-point 16-bit integers."""
    x_int = np.round(x_float * 256.0)
    x_clipped = np.clip(x_int, -32768, 32767)
    return x_clipped.astype(np.int16)

def to_hex_16bit(val):
    """Converts an int16 to a 4-char hex string (2's complement)."""
    return f"{int(val) & 0xFFFF:04X}"

def write_mem_file(filepath, data_1d):
    """Writes a .mem file for Vivado simulation ($readmemh)."""
    with open(filepath, 'w') as f:
        for val in data_1d:
            f.write(to_hex_16bit(val) + "\n")

def write_coe_file(filepath, data_1d):
    """Writes a .coe file for Xilinx Block Memory Generator IP."""
    with open(filepath, 'w') as f:
        f.write("memory_initialization_radix=16;\n")
        f.write("memory_initialization_vector=\n")
        # Write all but the last with a comma
        for val in data_1d[:-1]:
            f.write(to_hex_16bit(val) + ",\n")
        # Write the last one with a semicolon
        f.write(to_hex_16bit(data_1d[-1]) + ";\n")

# ─────────────────────────────────────────────
# 2. Setup & Model Loading
# ─────────────────────────────────────────────
if not os.path.exists(OUTPUT_DIR):
    os.makedirs(OUTPUT_DIR)

print(f"Loading model: {MODEL_PATH}...")
model = tf.keras.models.load_model(MODEL_PATH)

conv_counter = 1
dense_counter = 1

# ─────────────────────────────────────────────
# 3. Layer Iteration & Extraction
# ─────────────────────────────────────────────
for layer in model.layers:
    weights_list = layer.get_weights()
    if len(weights_list) == 0:
        continue # Skip Flatten, MaxPooling, etc.

    w_float = weights_list[0]
    b_float = weights_list[1]
    
    layer_type = layer.__class__.__name__
    
    if layer_type == "Conv2D":
        name = f"conv{conv_counter}"
        conv_counter += 1
        
        # Keras format: (H, W, IC, OC) -> FPGA format: (OC, IC, H, W)
        w_float_transposed = np.transpose(w_float, (3, 2, 0, 1))
        
        # Quantize
        w_q88 = quantize_q8_8(w_float_transposed)
        b_q88 = quantize_q8_8(b_float)
        
    elif layer_type == "Dense":
        name = f"dense{dense_counter}"
        dense_counter += 1
        
        # Initial quantization
        w_q88_base = quantize_q8_8(w_float)
        b_q88_base = quantize_q8_8(b_float)
        
        # Hardware formatting: (Passes, Inputs, Parallel_MACs)
        PARALLEL_MACS = 8
        in_size, out_size = w_q88_base.shape
        num_passes = int(np.ceil(out_size / PARALLEL_MACS))
        pad_cols = (num_passes * PARALLEL_MACS) - out_size
        
        # Pad outputs with zeros if not a perfect multiple of 8 (e.g., Dense2)
        if pad_cols > 0:
            w_q88_padded = np.pad(w_q88_base, ((0,0), (0, pad_cols)), mode='constant')
            b_q88_padded = np.pad(b_q88_base, (0, pad_cols), mode='constant')
        else:
            w_q88_padded = w_q88_base
            b_q88_padded = b_q88_base
            
        # Reshape to (Inputs, Passes, MACs), then transpose to (Passes, Inputs, MACs)
        w_reshaped = w_q88_padded.reshape((in_size, num_passes, PARALLEL_MACS))
        w_hw_format = w_reshaped.transpose((1, 0, 2))
        
        # Assign to w_q88 / b_q88 so the rest of the script exports them correctly
        w_q88 = w_hw_format
        b_q88 = b_q88_padded
        
    else:
        print(f"Skipping unsupported layer with weights: {layer_type}")
        continue
        
    # Flatten arrays for 1D file writing
    w_flat = w_q88.flatten()
    b_flat = b_q88.flatten()

    print(f"Exporting {name}: Weights shape {w_q88.shape} ({len(w_flat)} words), Biases shape {b_q88.shape}")

    # 1. Save .npy for the Golden Python Model
    np.save(os.path.join(OUTPUT_DIR, f"{name}_weights.npy"), w_q88)
    np.save(os.path.join(OUTPUT_DIR, f"{name}_biases.npy"), b_q88)
    
    # 2. Save .mem files (for VHDL simulation)
    write_mem_file(os.path.join(OUTPUT_DIR, f"{name}_weights.mem"), w_flat)
    write_mem_file(os.path.join(OUTPUT_DIR, f"{name}_biases.mem"), b_flat)
    
    # 3. Save .coe files (for Vivado BRAM Synthesis)
    write_coe_file(os.path.join(OUTPUT_DIR, f"{name}_weights.coe"), w_flat)
    write_coe_file(os.path.join(OUTPUT_DIR, f"{name}_biases.coe"), b_flat)

print(f"\nSuccess! All weights exported to the '{OUTPUT_DIR}/' directory.")