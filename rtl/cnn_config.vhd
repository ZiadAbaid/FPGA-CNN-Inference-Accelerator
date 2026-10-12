library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package cnn_config is
    -- Image dimensions
    constant IMG_W            : integer := 32;
    constant IMG_H            : integer := 32;
    constant PADDED_IMG_W     : integer := 34; -- Pi-side padding
    constant PADDED_IMG_H     : integer := 34;
    constant IMG_SIZE         : integer := 1156; -- 34*34

    -- Layer output dimensions (after valid conv, before pool)
    constant CONV1_OUT_W      : integer := 32; -- 34-2
    constant POOL1_OUT_W      : integer := 16; -- 32/2
    constant CONV2_IN_W       : integer := 18; -- 16+2 (Padder1)
    constant CONV2_OUT_W      : integer := 16; -- 18-2
    constant POOL2_OUT_W      : integer := 8;  -- 16/2
    constant CONV3_IN_W       : integer := 10; -- 8+2 (Padder2)
    constant CONV3_OUT_W      : integer := 8;  -- 10-2
    constant POOL3_OUT_W      : integer := 4;  -- 8/2
    constant FLATTEN_SIZE     : integer := 512; -- 4*4*32

    -- Channel counts
    constant CONV1_IN_CH      : integer := 1;
    constant CONV1_OUT_CH     : integer := 16;
    constant CONV2_IN_CH      : integer := 16;
    constant CONV2_OUT_CH     : integer := 32;
    constant CONV3_IN_CH      : integer := 32;
    constant CONV3_OUT_CH     : integer := 32;
    constant DENSE1_IN        : integer := 512;
    constant DENSE1_OUT       : integer := 32;
    constant DENSE2_IN        : integer := 32;
    constant DENSE2_OUT       : integer := 3;

    -- Arithmetic
    constant DATA_WIDTH       : integer := 16; -- Q8.8
    constant ACCUM_WIDTH      : integer := 48; -- DSP48 P register
    constant FRAC_BITS        : integer := 8;  -- fractional bits

    -- SPI
    constant SPI_DATA_WIDTH   : integer := 16;

    -- Parallelism (set to 2 for recommended configuration)
    constant CONV_OC_PARALLEL : integer := 1; -- output channels computed in parallel
    constant DENSE_PARALLEL   : integer := 8; -- MACs in dense engine

    -- Derived: number of classes
    constant NUM_CLASSES      : integer := 3;
end package cnn_config;