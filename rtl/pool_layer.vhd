library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.cnn_config.all;

entity pool_layer is
    generic (
        IMG_W    : integer := 32;
        IMG_H    : integer := 32;
        CHANNELS : integer := 16
    );
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;
        
        in_data     : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        in_valid    : in  std_logic;
        in_ready    : out std_logic;
        
        out_data    : out std_logic_vector(DATA_WIDTH-1 downto 0);
        out_valid   : out std_logic;
        out_ready   : in  std_logic
    );
end entity;

architecture rtl of pool_layer is
    signal col_cnt : integer range 0 to IMG_W - 1 := 0;
    signal row_cnt : integer range 0 to IMG_H - 1 := 0;
    signal ch_cnt  : integer range 0 to CHANNELS - 1 := 0;

    constant BUF_DEPTH : integer := IMG_W * CHANNELS;
    type ram_type is array (0 to BUF_DEPTH - 1) of signed(DATA_WIDTH-1 downto 0);
    signal line_buf : ram_type := (others => (others => '0'));

    type max_array_t is array (0 to CHANNELS - 1) of signed(DATA_WIDTH-1 downto 0);
    signal prev_max_col : max_array_t := (others => (others => '0'));

    -- Pipelining signals (Stage 1 to Stage 2)
    signal current_pixel_reg  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal buffered_pixel_reg : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal valid_pipe         : std_logic := '0';
    signal is_output_pipe     : boolean := false;
    signal ch_cnt_pipe        : integer range 0 to CHANNELS - 1 := 0;
    signal col_even_pipe      : boolean := false;

    -- Stage 2 Combinational signals
    signal current_max_col    : signed(DATA_WIDTH-1 downto 0);
    signal is_output_pixel    : boolean;
    signal stall_pipeline     : std_logic;

begin
    -- ========================================================================
    -- Combinational Logic
    -- ========================================================================
    
    -- Identify if the incoming coordinate is a pooling output trigger (Odd row AND Odd col)
    is_output_pixel <= ((row_cnt mod 2) = 1 and (col_cnt mod 2) = 1);

    -- Flow Control: Stall if Stage 2 holds a valid output pixel, but downstream is NOT ready.
    stall_pipeline <= '1' when (valid_pipe = '1' and is_output_pipe and out_ready = '0') else '0';

    -- Input Ready: We can accept new data if the pipeline isn't stalled.
    in_ready <= '1' when (stall_pipeline = '0') else '0';

    -- Stage 2 Combinational Datapath
    current_max_col <= current_pixel_reg when current_pixel_reg > buffered_pixel_reg else buffered_pixel_reg;

    -- Output assignment (Stage 2)
    out_valid <= '1' when (valid_pipe = '1' and is_output_pipe) else '0';
    out_data  <= std_logic_vector(current_max_col) when (current_max_col > prev_max_col(ch_cnt_pipe)) 
                 else std_logic_vector(prev_max_col(ch_cnt_pipe));

    -- ========================================================================
    -- Synchronous Process
    -- ========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                col_cnt        <= 0;
                row_cnt        <= 0;
                ch_cnt         <= 0;
                prev_max_col   <= (others => (others => '0'));
                valid_pipe     <= '0';
                is_output_pipe <= false;
                col_even_pipe  <= false;
            else
                -- Proceed only if the pipeline is not stalled
                if stall_pipeline = '0' then
                    
                    -- --------------------------------------------------------
                    -- RETIRE STAGE 2
                    -- --------------------------------------------------------
                    -- Pipeline Left Column Max on even columns using Stage 2 data
                    if valid_pipe = '1' and col_even_pipe then
                        prev_max_col(ch_cnt_pipe) <= current_max_col;
                    end if;

                    -- --------------------------------------------------------
                    -- ADVANCE STAGE 1 -> STAGE 2
                    -- --------------------------------------------------------
                    if in_valid = '1' then
                        -- Latch data and control into pipeline registers
                        buffered_pixel_reg <= line_buf(col_cnt * CHANNELS + ch_cnt);
                        current_pixel_reg  <= signed(in_data);
                        ch_cnt_pipe        <= ch_cnt;
                        is_output_pipe     <= is_output_pixel;
                        col_even_pipe      <= ((col_cnt mod 2) = 0);
                        valid_pipe         <= '1';
                        
                        -- Update Line Buffer on even rows
                        if (row_cnt mod 2) = 0 then
                            line_buf(col_cnt * CHANNELS + ch_cnt) <= signed(in_data);
                        end if;

                        -- Interleaved Counter Logic
                        if ch_cnt = CHANNELS - 1 then
                            ch_cnt <= 0;
                            if col_cnt = IMG_W - 1 then
                                col_cnt <= 0;
                                if row_cnt = IMG_H - 1 then
                                    row_cnt <= 0;
                                else
                                    row_cnt <= row_cnt + 1;
                                end if;
                            else
                                col_cnt <= col_cnt + 1;
                            end if;
                        else
                            ch_cnt <= ch_cnt + 1;
                        end if;
                    else
                        -- No valid input, pipeline bubble
                        valid_pipe <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;