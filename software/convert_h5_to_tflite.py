import tensorflow as tf
import sys
import os

def convert_h5_to_tflite(h5_path):
    if not os.path.exists(h5_path):
        print(f"Error: {h5_path} does not exist.")
        return

    # Create tflite path in the same directory with same base name
    base_name = os.path.splitext(h5_path)[0]
    tflite_path = base_name + ".tflite"

    try:
        print(f"Loading model from {h5_path}...")
        model = tf.keras.models.load_model(h5_path)
        
        print("Converting model to TFLite...")
        converter = tf.lite.TFLiteConverter.from_keras_model(model)
        
        # Uncomment the following line if you want to apply post-training quantization
        # converter.optimizations = [tf.lite.Optimize.DEFAULT]
        
        tflite_model = converter.convert()
        
        print(f"Saving TFLite model to {tflite_path}...")
        with open(tflite_path, 'wb') as f:
            f.write(tflite_model)
            
        print("Conversion completed successfully!")
        
    except Exception as e:
        print(f"An error occurred during conversion: {e}")

if __name__ == "__main__":
    # Use the specific .h5 file found in the directory by default
    # Change this if you have a different filename
    default_h5 = "tiny_ai_brain.h5"
    
    # Allow passing filename as argument, e.g., `python convert_h5_to_tflite.py my_model.h5`
    if len(sys.argv) > 1:
        h5_file = sys.argv[1]
    else:
        h5_file = default_h5
        
    convert_h5_to_tflite(h5_file)
