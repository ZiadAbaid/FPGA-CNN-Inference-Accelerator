import sys
import time
import threading
import numpy as np
import tensorflow as tf
import psutil
from scapy.all import conf, Ether, IP, UDP, sendp

# =========================================================================
# 1. NETWORK & INTERFACE CONFIGURATION
# =========================================================================
INTERFACE = "Realtek PCIe GbE Family Controller" 

PC_MAC = "c8:53:09:fa:62:38" 
FPGA_MAC = "e8:6a:64:e7:e8:30"
PC_IP = "192.168.1.10"
FPGA_IP = "192.168.1.20"

# =========================================================================
# 2. HARDWARE & BENCHMARK DESIGN CONSTANTS
# =========================================================================
FPGA_CLOCK_MHZ = 100.0   # 10 ns clock period
NUM_CLASSES = 3          # 3 target classification layers
RESPONSE_LEN = NUM_CLASSES * 2  # 16-bit elements (6 bytes total)

# Hardcoded true Turbo Boost reference clock for your i7-14700HX P-cores
MANUAL_CPU_FREQ_MHZ = 5200.0

# Fixed compensation factor for OS network stack driver traversal
NETWORK_LATENCY_OFFSET = 0.002 

# =========================================================================
# 3. FILE PATHS
# =========================================================================
INPUT_FILE = "cat_0_input.hex"
EXPECTED_OUTPUT_FILE = "cat_11_logits.hex"
TFLITE_MODEL = "tiny_ai_brain.tflite"


class CnnEthernetTester:
    def __init__(self):
        self.running = True
        self.received_logits_bytes = b""
        
        # Load expected testbench metrics
        self.expected_bytes = self.read_hex_logits(EXPECTED_OUTPUT_FILE)
        print(f"Loaded expected logits: {self.expected_bytes.hex().upper()}")

        # Metric and time tracking
        self.fpga_send_time = 0
        self.fpga_recv_time = 0
        self.fpga_rtt = 0
        self.software_time = 0

        # Initialize TensorFlow Lite inference engine
        self.interpreter = tf.lite.Interpreter(model_path=TFLITE_MODEL)
        self.interpreter.allocate_tensors()

        try:
            self.sock = conf.L2socket(iface=INTERFACE)
        except Exception as e:
            print(f"CRITICAL ERROR Opening Layer 2 Socket: {e}")
            sys.exit(1)

        # Spawn isolated concurrent background receiver thread
        self.listener_thread = threading.Thread(target=self.listen_for_fpga)
        self.listener_thread.daemon = True
        self.listener_thread.start()

    def read_hex_image(self, filepath):
        """Extracts the lower 8 bits of pixel data to match VHDL stream layout."""
        byte_data = bytearray()
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if line:
                    byte_data.append(bytes.fromhex(line)[1])
        return bytes(byte_data)

    def read_hex_logits(self, filepath):
        """Reads expected 16-bit logits maintaining full precision window."""
        byte_data = bytearray()
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if line:
                    byte_data.extend(bytes.fromhex(line))
        return bytes(byte_data[:RESPONSE_LEN])

    def run_software_inference(self, input_bytes):
        print("\n--- RUNNING SOFTWARE INFERENCE ---")
        input_details = self.interpreter.get_input_details()
        output_details = self.interpreter.get_output_details()
        input_shape = input_details[0]['shape']

        try:
            # Parse 1156 bytes into a 34x34 padded array
            padded_array = np.frombuffer(input_bytes, dtype=np.uint8).reshape((34, 34))
            
            # Crop out the 1-pixel outer border to retrieve the valid 32x32 image matrix
            cropped_array = padded_array[1:33, 1:33]
            
            # Normalize to [0.0, 1.0] float representation matching Q8.8 design logic
            normalized_array = cropped_array.astype(np.float32) / 255.0
            input_array = normalized_array.reshape(input_shape)
            
        except ValueError as e:
            print(f"Matrix parsing or reshape transformation failed: {e}")
            return

        self.interpreter.set_tensor(input_details[0]['index'], input_array)

        # Isolated execution timing window
        start_time = time.perf_counter()
        self.interpreter.invoke()
        end_time = time.perf_counter()

        self.software_time = end_time - start_time
        software_output = self.interpreter.get_tensor(output_details[0]['index'])
        
        print(f"Software Execution Time: {self.software_time:.6f} seconds")
        print(f"Software Output Array:   {software_output.flatten()}")

    def listen_for_fpga(self):
        expected_src_mac = bytes.fromhex(FPGA_MAC.replace(':', ''))
        expected_dst_mac = bytes.fromhex(PC_MAC.replace(':', ''))
        
        print("Listening for FPGA response...")
        while self.running:
            try:
                pkt = self.sock.recv(timeout=1)
                if pkt:
                    raw_bytes = bytes(pkt)
                    
                    if len(raw_bytes) >= 42:
                        actual_dst = raw_bytes[0:6]
                        actual_src = raw_bytes[6:12]
                        
                        if actual_dst == expected_dst_mac and actual_src == expected_src_mac:
                            # Immediate arrival timestamp capture
                            self.fpga_recv_time = time.perf_counter()
                            
                            # Bypass L2/L3 protocol headers (14 Eth + 20 IP + 8 UDP)
                            payload = raw_bytes[42:] 
                            
                            if len(payload) >= RESPONSE_LEN:
                                self.received_logits_bytes = payload[:RESPONSE_LEN]
                                self.compare_and_exit()
            except Exception:
                pass 

    def send_input_image(self):
        input_payload = self.read_hex_image(INPUT_FILE)
        print(f"Loaded {len(input_payload)} correct pixel bytes from {INPUT_FILE}")

        # Compute software benchmark configuration
        self.run_software_inference(input_payload)

        # Construct frame forcing static identifiers and checksums to match VHDL simulation
        frame = Ether(src=PC_MAC, dst=FPGA_MAC) / \
                IP(src=PC_IP, dst=FPGA_IP, id=0, chksum=0) / \
                UDP(sport=4660, dport=17767, chksum=0) / \
                input_payload
        
        print("\n--- RUNNING HARDWARE INFERENCE ---")
        print("Sending UDP CNN Input Data...")
        
        self.fpga_send_time = time.perf_counter()
        sendp(frame, iface=INTERFACE, verbose=False)

    def compare_performance(self):
        print("\n--- PERFORMANCE & CLOCK SCALING ANALYSIS ---")
        
        # Calculate true hardware execution window 
        self.fpga_rtt = self.fpga_recv_time - self.fpga_send_time
        hw_time_adjusted = max(self.fpga_rtt - NETWORK_LATENCY_OFFSET, 0.000001)
        
        print(f"FPGA Round Trip Time (RTT)   : {self.fpga_rtt:.6f} sec")
        print(f"FPGA Est. Time (w/o network) : {hw_time_adjusted:.6f} sec")
        print(f"CPU Time                     : {self.software_time:.6f} sec")
        
        print(f"\nCPU Active Operational Clock : {MANUAL_CPU_FREQ_MHZ:.2f} MHz")
        print(f"FPGA Reference Design Clock  : {FPGA_CLOCK_MHZ:.2f} MHz")

        # Temporal domain converted to absolute core clock cycle counts
        cpu_cycles = self.software_time * (MANUAL_CPU_FREQ_MHZ * 1e6)
        fpga_cycles = hw_time_adjusted * (FPGA_CLOCK_MHZ * 1e6)
        
        print(f"\nCalculated Active CPU Cycles : {int(cpu_cycles):,}")
        print(f"Calculated Running FPGA Cycles: {int(fpga_cycles):,}")
        
        speedup_absolute = self.software_time / hw_time_adjusted
        speedup_scaled = cpu_cycles / fpga_cycles

        print(f"\nAbsolute Speedup (Time-domain)     : {speedup_absolute:.2f}x")
        print(f"Architectural Speedup (Cycle-scale): {speedup_scaled:.2f}x")

    def compare_and_exit(self):
        print("\n--- FUNCTIONAL COMPARISON RESULTS ---")
        print(f"Expected (Hex) : {self.expected_bytes.hex().upper()}")
        print(f"Received (Hex) : {self.received_logits_bytes.hex().upper()}")

        if self.received_logits_bytes == self.expected_bytes:
            print("\n✅ SUCCESS! The FPGA outputs match the testbench perfectly.")
        else:
            print("\n❌ MISMATCH DETECTED!")
        
        self.compare_performance()
        
        # Explicitly clean up Layer 2 socket binding to decrease teardown warning noise
        try:
            self.sock.close()
        except Exception:
            pass
            
        self.running = False

    def wait(self):
        timeout_timer = 5
        while self.running and timeout_timer > 0:
            time.sleep(1)
            timeout_timer -= 1
        
        if timeout_timer == 0 and self.running:
            print("\n[!] TIMEOUT: Did not receive a response from the FPGA in time.")
            self.running = False


if __name__ == "__main__":
    tester = CnnEthernetTester()
    tester.send_input_image()
    tester.wait()