library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.cnn_config.all;

entity cnn_datapath_top is
    generic (
        C1_W_FILE       : string  := "../../FPGA_Accelerated_CNN_Inference.srcs/sources_1/imports/export_q88/conv1_weights.mem";
        C1_B_FILE       : string  := "../../FPGA_Accelerated_CNN_Inference.srcs/sources_1/imports/export_q88/conv1_biases.mem";
        C2_W_FILE       : string  := "../../FPGA_Accelerated_CNN_Inference.srcs/sources_1/imports/export_q88/conv2_weights.mem";
        C2_B_FILE       : string  := "../../FPGA_Accelerated_CNN_Inference.srcs/sources_1/imports/export_q88/conv2_biases.mem";
        C3_W_FILE       : string  := "../../FPGA_Accelerated_CNN_Inference.srcs/sources_1/imports/export_q88/conv3_weights.mem";
        C3_B_FILE       : string  := "../../FPGA_Accelerated_CNN_Inference.srcs/sources_1/imports/export_q88/conv3_biases.mem";
        D1_W_FILE       : string  := "../../FPGA_Accelerated_CNN_Inference.srcs/sources_1/imports/export_q88/dense1_weights.mem";
        D1_B_FILE       : string  := "../../FPGA_Accelerated_CNN_Inference.srcs/sources_1/imports/export_q88/dense1_biases.mem";
        D2_W_FILE       : string  := "../../FPGA_Accelerated_CNN_Inference.srcs/sources_1/imports/export_q88/dense2_weights.mem";
        D2_B_FILE       : string  := "../../FPGA_Accelerated_CNN_Inference.srcs/sources_1/imports/export_q88/dense2_biases.mem"
    );
    port (
        clk       : in  std_logic;
        reset     : in  std_logic;
        
        -- AXI-Stream Input
        in_data   : in  std_logic_vector(15 downto 0);
        in_valid  : in  std_logic;
        in_ready  : out std_logic;
        
        -- AXI-Stream Output
        out_data  : out std_logic_vector(15 downto 0);
        out_valid : out std_logic;
        out_ready : in  std_logic
    );
end entity;

architecture struct of cnn_datapath_top is

    -- Interconnect signals (Data, Valid, Ready)
    signal s1_data, s2_data, s3_data, s4_data, s5_data   : std_logic_vector(15 downto 0);
    signal s1_valid, s2_valid, s3_valid, s4_valid, s5_valid : std_logic;
    signal s1_ready, s2_ready, s3_ready, s4_ready, s5_ready : std_logic;

    signal s6_data, s7_data, s8_data, s9_data, s10_data  : std_logic_vector(15 downto 0);
    signal s6_valid, s7_valid, s8_valid, s9_valid, s10_valid : std_logic;
    signal s6_ready, s7_ready, s8_ready, s9_ready, s10_ready : std_logic;

    signal flatten_done_open : std_logic;

begin

    -- =========================================================
    -- STAGE 1: Feature Extraction
    -- =========================================================
    u_conv1: entity work.conv_layer
        generic map(
            NUM_IN_CH   => CONV1_IN_CH,
            NUM_OUT_CH  => CONV1_OUT_CH,
            IMG_W       => PADDED_IMG_W,
            IMG_H       => PADDED_IMG_H,
            OC_PARALLEL => CONV_OC_PARALLEL,
            WEIGHT_FILE => C1_W_FILE,
            BIAS_FILE   => C1_B_FILE
        )
        port map(
            clk => clk, reset => reset,
            in_data => in_data, in_valid => in_valid, in_ready => in_ready,
            out_data => s1_data, out_valid => s1_valid, out_ready => s1_ready
        );

    u_pool1: entity work.pool_layer
        generic map(IMG_W => CONV1_OUT_W, IMG_H => CONV1_OUT_W, CHANNELS => CONV1_OUT_CH)
        port map(clk => clk, reset => reset, in_data => s1_data, in_valid => s1_valid, in_ready => s1_ready, out_data => s2_data, out_valid => s2_valid, out_ready => s2_ready);

    u_pad1: entity work.padder
        generic map(IMG_W => POOL1_OUT_W, IMG_H => POOL1_OUT_W, CHANNELS => CONV1_OUT_CH)
        port map(clk => clk, reset => reset, in_data => s2_data, in_valid => s2_valid, in_ready => s2_ready, out_data => s3_data, out_valid => s3_valid, out_ready => s3_ready);

    -- =========================================================
    -- STAGE 2: Mid-Level Features
    -- =========================================================
    u_conv2: entity work.conv_layer
        generic map(
            NUM_IN_CH   => CONV2_IN_CH,
            NUM_OUT_CH  => CONV2_OUT_CH,
            IMG_W       => CONV2_IN_W,
            IMG_H       => CONV2_IN_W,
            OC_PARALLEL => CONV_OC_PARALLEL,
            WEIGHT_FILE => C2_W_FILE,
            BIAS_FILE   => C2_B_FILE
        )
        port map(
            clk => clk, reset => reset,
            in_data => s3_data, in_valid => s3_valid, in_ready => s3_ready,
            out_data => s4_data, out_valid => s4_valid, out_ready => s4_ready
        );

    u_pool2: entity work.pool_layer
        generic map(IMG_W => CONV2_OUT_W, IMG_H => CONV2_OUT_W, CHANNELS => CONV2_OUT_CH)
        port map(clk => clk, reset => reset, in_data => s4_data, in_valid => s4_valid, in_ready => s4_ready, out_data => s5_data, out_valid => s5_valid, out_ready => s5_ready);

    u_pad2: entity work.padder
        generic map(IMG_W => POOL2_OUT_W, IMG_H => POOL2_OUT_W, CHANNELS => CONV2_OUT_CH)
        port map(clk => clk, reset => reset, in_data => s5_data, in_valid => s5_valid, in_ready => s5_ready, out_data => s6_data, out_valid => s6_valid, out_ready => s6_ready);

    -- =========================================================
    -- STAGE 3: High-Level Features
    -- =========================================================
    u_conv3: entity work.conv_layer
        generic map(
            NUM_IN_CH   => CONV3_IN_CH,
            NUM_OUT_CH  => CONV3_OUT_CH,
            IMG_W       => CONV3_IN_W,
            IMG_H       => CONV3_IN_W,
            OC_PARALLEL => CONV_OC_PARALLEL,
            WEIGHT_FILE => C3_W_FILE,
            BIAS_FILE   => C3_B_FILE
        )
        port map(
            clk => clk, reset => reset,
            in_data => s6_data, in_valid => s6_valid, in_ready => s6_ready,
            out_data => s7_data, out_valid => s7_valid, out_ready => s7_ready
        );

    u_pool3: entity work.pool_layer
        generic map(IMG_W => CONV3_OUT_W, IMG_H => CONV3_OUT_W, CHANNELS => CONV3_OUT_CH)
        port map(clk => clk, reset => reset, in_data => s7_data, in_valid => s7_valid, in_ready => s7_ready, out_data => s8_data, out_valid => s8_valid, out_ready => s8_ready);

    -- =========================================================
    -- BRIDGE & CLASSIFIER
    -- =========================================================
    u_flatten: entity work.flatten
        port map(clk => clk, reset => reset, in_data => s8_data, in_valid => s8_valid, in_ready => s8_ready, out_data => s9_data, out_valid => s9_valid, out_ready => s9_ready, flatten_done => flatten_done_open);

    u_dense1: entity work.dense_engine
        generic map(
            IN_SIZE       => DENSE1_IN,
            OUT_SIZE      => DENSE1_OUT,
            PARALLEL_MACS => DENSE_PARALLEL,
            APPLY_RELU    => true,
            BIAS_FILE     => D1_B_FILE,
            WEIGHT_FILE   => D1_W_FILE
        )
        port map(
            clk => clk, reset => reset,
            in_data => s9_data, in_valid => s9_valid, in_ready => s9_ready,
            out_data => s10_data, out_valid => s10_valid, out_ready => s10_ready
        );

    u_dense2: entity work.dense_engine
        generic map(
            IN_SIZE       => DENSE2_IN,
            OUT_SIZE      => DENSE2_OUT,
            PARALLEL_MACS => DENSE_PARALLEL,
            APPLY_RELU    => false,
            BIAS_FILE     => D2_B_FILE,
            WEIGHT_FILE   => D2_W_FILE
        )
        port map(
            clk => clk, reset => reset,
            in_data => s10_data, in_valid => s10_valid, in_ready => s10_ready,
            out_data => out_data, out_valid => out_valid, out_ready => out_ready
        );

end architecture;