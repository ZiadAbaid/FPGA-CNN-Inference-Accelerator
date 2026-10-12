import os
import numpy as np
from golden_model import (
    run_full_inference, dsp48_mac, conv2d_valid, 
    padder2d, max_pool2d_2x2, flatten3d, dense_layer, load_q88_weights
)
from PIL import Image

# ─────────────────────────────────────────────
#  Phase 1.4: Testbench Data Generator
# ─────────────────────────────────────────────

OUTPUT_DIR = "testbench_data"

def to_hex_16bit(val):
    """Converts a Q8.8 integer to a 4-char hex string."""
    return f"{int(val) & 0xFFFF:04X}"

def save_map_to_hex(filename, data_map):
    """Flattens a 3D or 1D map and saves as a .hex file for VHDL $readmemh."""
    # Flatten if it's a 3D map (H, W, C)
    if isinstance(data_map[0], list) and isinstance(data_map[0][0], list):
        flat_list = []
        for y in range(len(data_map)):
            for x in range(len(data_map[0])):
                for c in range(len(data_map[0][0])):
                    flat_list.append(data_map[y][x][c])
    else:
        flat_list = data_map # Already 1D (like logits or flattened layer)

    with open(os.path.join(OUTPUT_DIR, filename), 'w') as f:
        for val in flat_list:
            f.write(to_hex_16bit(val) + "\n")

def generate_full_trace(img_path, label):
    print(f"\nTracing layers for: {label} ({img_path})")
    
    # 1. Pre-process Image (Master Plan Sec 7.3)
    img = Image.open(img_path).convert('L').resize((32, 32))
    pixel_data = np.array(img, dtype=int)
    padded_img = np.pad(pixel_data, pad_width=1, mode='constant', constant_values=0)
    hw_map = [[[int(padded_img[y][x])] for x in range(34)] for y in range(34)]
    
    # Save input image hex (34x34 = 1156 words)
    save_map_to_hex(f"{label}_0_input.hex", hw_map)

    # 2. Load Weights
    c1_w, c1_b = load_q88_weights("conv1")
    c2_w, c2_b = load_q88_weights("conv2")
    c3_w, c3_b = load_q88_weights("conv3")
    d1_w, d1_b = load_q88_weights("dense1")
    d2_w, d2_b = load_q88_weights("dense2")

    # 3. Run and Save Every Layer Step
    print("  Processing Conv1...")
    x = conv2d_valid(hw_map, c1_w, c1_b, apply_relu=True)
    save_map_to_hex(f"{label}_1_conv1.hex", x)
    
    print("  Processing Pool1...")
    x = max_pool2d_2x2(x)
    save_map_to_hex(f"{label}_2_pool1.hex", x)
    
    print("  Processing Pad1...")
    x = padder2d(x)
    save_map_to_hex(f"{label}_3_pad1.hex", x)
    
    print("  Processing Conv2...")
    x = conv2d_valid(x, c2_w, c2_b, apply_relu=True)
    save_map_to_hex(f"{label}_4_conv2.hex", x)
    
    print("  Processing Pool2...")
    x = max_pool2d_2x2(x)
    save_map_to_hex(f"{label}_5_pool2.hex", x)
    
    print("  Processing Pad2...")
    x = padder2d(x)
    save_map_to_hex(f"{label}_6_pad2.hex", x)
    
    print("  Processing Conv3...")
    x = conv2d_valid(x, c3_w, c3_b, apply_relu=True)
    save_map_to_hex(f"{label}_7_conv3.hex", x)
    
    print("  Processing Pool3...")
    x = max_pool2d_2x2(x)
    save_map_to_hex(f"{label}_8_pool3.hex", x)
    
    print("  Processing Flatten...")
    x = flatten3d(x)
    save_map_to_hex(f"{label}_9_flatten.hex", x)
    
    print("  Processing Dense1...")
    # UPDATED: Added out_c=32
    x = dense_layer(x, d1_w, d1_b, out_c=32, apply_relu=True)
    save_map_to_hex(f"{label}_10_dense1.hex", x)
    
    print("  Processing Dense2...")
    # UPDATED: Added out_c=3
    logits = dense_layer(x, d2_w, d2_b, out_c=3, apply_relu=False)
    save_map_to_hex(f"{label}_11_logits.hex", logits)
    
    print(f"Done. Files saved to {OUTPUT_DIR}/")

if __name__ == "__main__":
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)

    # We use 3 images for the answer key (one per class)
    test_images = {
        "cat": "Doglets/Cat/0.jpg",
        "dog": "Doglets/Dog/0.jpg",
        "human": "Doglets/Human/image_025556.png" # Update with a real path from your Human folder
    }

    for label, path in test_images.items():
        if os.path.exists(path):
            generate_full_trace(path, label)
        else:
            print(f"Warning: Could not find {path}, skipping {label} trace.")