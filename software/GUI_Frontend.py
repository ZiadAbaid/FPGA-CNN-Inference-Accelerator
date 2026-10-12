import tkinter as tk
from tkinter import filedialog, font, messagebox
from PIL import Image, ImageTk
import os

# Import BOTH of your custom backend logic files!
import Image_Backend
import Camera_Backend

# ===================================================================== #
# TELEMETRY PANEL COMPONENT
# ===================================================================== #
class BenchmarkPanel(tk.Canvas):
    def __init__(self, parent, width=450, height=380, **kwargs):
        super().__init__(parent, width=width, height=height,
                         bg="#061214", highlightthickness=0, **kwargs)
        self.width = width
        self.height = height

        self.header_font = font.Font(family="Courier", size=11, weight="bold")
        self.sub_font = font.Font(family="Courier", size=9)
        self.tiny_font = font.Font(family="Courier", size=8)
        self.num_font = font.Font(family="Helvetica", size=32, weight="bold")
        self.str_font = font.Font(family="Helvetica", size=24, weight="bold")
        
        # Position scaling based on width
        self.val_x = int(width * 0.35)
        self.icon_x = int(width * 0.85)

        self.live_values = {}
        self.draw_background_grid()

        self.create_metric_block("PRED", 10, "#eccc68", "// OUTPUT", "class", "NET", "AI PREDICTION", "---", "O")
        self.create_metric_block("PI_T", 100, "#ff4757", "// PI HOST", "ms", "SW", "SOFTWARE LATENCY", "---", "SW")
        self.create_metric_block("FPGA_T", 190, "#00e5ff", "// FPGA", "ms", "HW", "HARDWARE LATENCY", "---", "HW")
        self.create_metric_block("SPEED", 280, "#2ecc71", "// RATIO", "x", "ACC", "SPEEDUP MULTIPLIER", "---", ">>")

    def draw_background_grid(self):
        grid_color = "#132c33"
        for x in range(0, self.width, 40):
            self.create_line(x, 0, x, self.height, fill=grid_color, dash=(2, 4))
        for y in range(0, self.height, 40):
            self.create_line(0, y, self.width, y, fill=grid_color, dash=(2, 4))
        for y_pos in [90, 180, 270]:
            self.create_line(10, y_pos, self.width - 10, y_pos, fill="#1c424a", width=1)

    def create_metric_block(self, key, y_base, color, title, unit, sub_title1, sub_title2, default_val, icon):
        self.create_text(20, y_base, text=title, font=self.header_font, fill="#bdc3c7", anchor="nw")
        self.create_text(20, y_base + 18, text=unit, font=self.sub_font, fill="#7f8c8d", anchor="nw")
        self.create_text(20, y_base + 50, text=sub_title1, font=self.header_font, fill="#bdc3c7", anchor="nw")
        self.create_text(20, y_base + 65, text=sub_title2, font=self.tiny_font, fill="#7f8c8d", anchor="nw")

        use_font = self.str_font if key == "PRED" else self.num_font
        val_id = self.create_text(self.val_x, y_base + 10, text=default_val, font=use_font, fill=color, anchor="nw")
        self.live_values[key] = val_id

        self.create_text(self.icon_x, y_base + 15, text=icon, font=self.header_font, fill=color, anchor="nw")
        self.create_line(self.icon_x + 30, y_base + 15, self.icon_x + 30, y_base + 35, fill=color, width=2)

    def update_value(self, key, new_value):
        if key in self.live_values:
            self.itemconfig(self.live_values[key], text=str(new_value))

# ===================================================================== #
# MAIN APPLICATION CONTROLLER
# ===================================================================== #
class App:
    def __init__(self, root):
        self.root = root
        self.root.title("FPGA Vision Accelerator")
        self.root.geometry("800x850")
        self.root.configure(bg="#050e12")

        # Screens
        self.menu_frame = tk.Frame(self.root, bg="#050e12")
        self.image_dashboard_frame = tk.Frame(self.root, bg="#050e12")
        self.camera_dashboard_frame = tk.Frame(self.root, bg="#050e12")

        self.stream_active = False

        self.setup_menu()
        self.setup_image_dashboard()
        self.setup_camera_dashboard()
        self.show_menu()

    def setup_menu(self):
        tk.Label(self.menu_frame, text="VISION ACCELERATOR TELEMETRY", 
                 font=("Courier", 22, "bold"), fg="#00e5ff", bg="#050e12").pack(pady=80)
        
        btn_frame = tk.Frame(self.menu_frame, bg="#050e12")
        btn_frame.pack(expand=True)

        btn_style = {"font": ("Courier", 14, "bold"), "width": 25, "height": 4, 
                     "bg": "#132c33", "fg": "#bdc3c7", "activebackground": "#1c424a", 
                     "activeforeground": "#ffffff", "relief": tk.FLAT, "cursor": "hand2"}

        tk.Button(btn_frame, text="[+]\nLOAD IMAGE", command=self.open_image_dashboard, **btn_style).pack(pady=20)
        tk.Button(btn_frame, text="[O]\nLIVE STREAM", command=self.open_camera_dashboard, **btn_style).pack(pady=20)

    # --- IMAGE DASHBOARD (Unified Side-by-Side Layout) ---
    def setup_image_dashboard(self):
        top_bar = tk.Frame(self.image_dashboard_frame, bg="#050e12")
        top_bar.pack(fill=tk.X, pady=10, padx=20)

        tk.Button(top_bar, text="< ABORT", command=self.show_menu, font=("Courier", 12, "bold"), 
                  bg="#3a0202", fg="#ff4757", relief=tk.FLAT).pack(side=tk.LEFT)
        
        self.lbl_status_img = tk.Label(top_bar, text="SYSTEM IDLE", font=("Courier", 12, "italic"), fg="#7f8c8d", bg="#050e12")
        self.lbl_status_img.pack(side=tk.RIGHT)

        # Split Content Area
        content_area = tk.Frame(self.image_dashboard_frame, bg="#050e12")
        content_area.pack(fill=tk.BOTH, expand=True, padx=20, pady=10)

        # Left Side: Telemetry (Centered dynamically)
        left_container = tk.Frame(content_area, bg="#050e12")
        left_container.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 20))
        
        self.img_telemetry = BenchmarkPanel(left_container, width=450, height=380)
        self.img_telemetry.pack(expand=True) # expand=True auto-centers it!

        # Right Side: Massive Image Frame
        self.img_feed_frame = tk.Frame(content_area, bg="#1c424a", padx=4, pady=4)
        self.img_feed_frame.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)
        
        self.lbl_image = tk.Label(self.img_feed_frame, bg="black", text="NO IMAGE LOADED", fg="#00e5ff", font=("Courier", 16, "bold"))
        self.lbl_image.pack(fill=tk.BOTH, expand=True)

    # --- CAMERA DASHBOARD (Unified Side-by-Side Layout) ---
    def setup_camera_dashboard(self):
        top_bar = tk.Frame(self.camera_dashboard_frame, bg="#050e12")
        top_bar.pack(fill=tk.X, pady=10, padx=20)

        tk.Button(top_bar, text="< ABORT", command=self.show_menu, font=("Courier", 12, "bold"), 
                  bg="#3a0202", fg="#ff4757", relief=tk.FLAT).pack(side=tk.LEFT)
        
        self.lbl_status_cam = tk.Label(top_bar, text="STREAMING ACTIVE", font=("Courier", 12, "italic"), fg="#7f8c8d", bg="#050e12")
        self.lbl_status_cam.pack(side=tk.RIGHT)

        # Split Content Area
        content_area = tk.Frame(self.camera_dashboard_frame, bg="#050e12")
        content_area.pack(fill=tk.BOTH, expand=True, padx=20, pady=10)

        # Left Side: Telemetry (Centered dynamically)
        left_container = tk.Frame(content_area, bg="#050e12")
        left_container.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 20))
        
        self.cam_telemetry = BenchmarkPanel(left_container, width=450, height=380)
        self.cam_telemetry.pack(expand=True) # expand=True auto-centers it!

        # Right Side: Massive Camera Placeholder
        self.cam_feed_frame = tk.Frame(content_area, bg="#1c424a", padx=4, pady=4)
        self.cam_feed_frame.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True)
        
        self.lbl_cam_feed = tk.Label(self.cam_feed_frame, text="CAMERA OFFLINE\n\n[AWAITING OPENCV BINDING]", 
                                     bg="black", fg="#00e5ff", font=("Courier", 16, "bold"))
        self.lbl_cam_feed.pack(fill=tk.BOTH, expand=True)

    # --- ROUTING ---
    def show_menu(self):
        # Stop the camera loop if it's running
        self.stream_active = False 
        try:
            Camera_Backend.release_camera()
        except: pass

        self.root.geometry("800x850") # Tall, centered menu
        self.image_dashboard_frame.pack_forget()
        self.camera_dashboard_frame.pack_forget()
        self.menu_frame.pack(fill=tk.BOTH, expand=True)

    def open_image_dashboard(self):
        # filedialog handles OS-specific paths natively (Windows C:/ vs Linux /home/)
        file_path = filedialog.askopenfilename(filetypes=[("Image Files", "*.png *.jpg *.jpeg *.bmp")])
        if not file_path: return

        # Switch to wide side-by-side resolution
        self.root.geometry("1200x650")
        self.menu_frame.pack_forget()
        self.image_dashboard_frame.pack(fill=tk.BOTH, expand=True)
        
        self.lbl_status_img.config(text="PROCESSING VHDL PIPELINE...", fg="#00e5ff")
        self.root.update()

        # Route to Image Backend
        image_bytes, result_or_img = Image_Backend.format_image(file_path)
        if image_bytes is None:
            messagebox.showerror("Error", f"Backend failed: {result_or_img}")
            self.show_menu()
            return
            
        # Scale the static image up to fill the new massive right-side frame
        img_display = result_or_img.resize((512, 512), resample=Image.NEAREST)
        img_tk = ImageTk.PhotoImage(img_display)
        self.lbl_image.config(image=img_tk, text="") # Clear placeholder text
        self.lbl_image.image = img_tk

        # Route to Image Backend
        pi_res, pi_lat = Image_Backend.run_pi_software_inference(file_path)
        
        # --- FIX: We now capture fpga_res instead of ignoring it with '_'
        fpga_res, fpga_lat = Image_Backend.run_fpga_hardware_inference(file_path)
        
        # --- NEW CLOCK-NORMALIZED RATIO ---
        # Multiply CPU time by 24 to account for the clock speed difference
        speedup = ((pi_lat * 24.0) / fpga_lat) if fpga_lat > 0 else 0.0
        
        # --- FIX: Push the FPGA prediction to the UI instead of the Pi prediction
        self.img_telemetry.update_value("PRED", fpga_res)
        self.img_telemetry.update_value("PI_T", f"{pi_lat:.1f}")
        self.img_telemetry.update_value("FPGA_T", f"{fpga_lat:.2f}")
        self.img_telemetry.update_value("SPEED", f"{speedup:.1f}")
        self.lbl_status_img.config(text="DATA LINK STABLE", fg="#2ecc71")

    def open_camera_dashboard(self):
        # Switch to wide side-by-side resolution
        self.root.geometry("1200x650") 
        self.menu_frame.pack_forget()
        self.camera_dashboard_frame.pack(fill=tk.BOTH, expand=True)
        
        self.lbl_status_cam.config(text="CONNECTING DROIDCAM...", fg="#00e5ff")
        self.root.update()

        # Initialize Camera Hardware via Backend
        success = Camera_Backend.init_camera_stream()
        if not success:
            messagebox.showerror("Camera Error", "Could not connect to /dev/video0. Is DroidCam running?")
            self.show_menu()
            return
            
        self.lbl_status_cam.config(text="STREAM SYNCED", fg="#2ecc71")
        self.stream_active = True
        
        # Start the infinite Tkinter loop
        self.update_camera_feed()

    def update_camera_feed(self):
        if not self.stream_active:
            return # Breaks the loop if user hits < ABORT
            
        # Renamed variable here to 'current_pred' to be neutral
        pil_img, current_pred, pi_lat, fpga_lat = Camera_Backend.get_next_frame()
        
        if pil_img:
            # Resize frame to fit the massive placeholder 
            pil_img = pil_img.resize((640, 480), Image.LANCZOS)
            img_tk = ImageTk.PhotoImage(pil_img)
            
            # Update Video Feed
            self.lbl_cam_feed.config(image=img_tk, text="")
            self.lbl_cam_feed.image = img_tk 
            
            # Update Telemetry (Avoid divide by zero)
            # Multiply CPU time by 24 for the camera feed too
            speedup = ((pi_lat * 24.0) / fpga_lat) if fpga_lat > 0 else 0.0
            
            self.cam_telemetry.update_value("PRED", current_pred)
            self.cam_telemetry.update_value("PI_T", f"{pi_lat:.1f}")
            self.cam_telemetry.update_value("FPGA_T", f"{fpga_lat:.2f}")
            self.cam_telemetry.update_value("SPEED", f"{speedup:.1f}")
            
        # Schedule the next frame capture in 15 milliseconds (~60 FPS cap)
        self.root.after(15, self.update_camera_feed)

if __name__ == "__main__":
    root = tk.Tk()
    app = App(root)
    root.mainloop()
