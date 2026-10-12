library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.cnn_config.all;

entity conv_layer is
    generic (
        NUM_IN_CH   : integer := 1; 
        NUM_OUT_CH  : integer := 16;
        IMG_W       : integer := 34;
        IMG_H       : integer := 34;
        OC_PARALLEL : integer := 1;
        WEIGHT_FILE : string  := "conv1_weights.mem";
        BIAS_FILE   : string  := "conv1_biases.mem"
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

architecture rtl of conv_layer is
    type state_t is (SHIFT_IN, CALC_MAC, PRE_STREAM, STREAM_OUT);
    signal state : state_t := SHIFT_IN;

    signal col_cnt : integer range 0 to IMG_W - 1 := 0;
    signal row_cnt : integer range 0 to IMG_H - 1 := 0;
    signal ic_cnt  : integer range 0 to NUM_IN_CH - 1 := 0;

    constant BUF_DEPTH : integer := IMG_W * NUM_IN_CH;
    type ram_type is array (0 to BUF_DEPTH - 1) of signed(DATA_WIDTH-1 downto 0);
    signal line_buf_1 : ram_type := (others => (others => '0'));
    signal line_buf_2 : ram_type := (others => (others => '0'));
    signal rd_addr    : integer range 0 to BUF_DEPTH - 1 := 0;

    constant DELAY_LEN : integer := 2 * NUM_IN_CH;
    type delay_line_t is array (0 to DELAY_LEN) of signed(DATA_WIDTH-1 downto 0);
    signal delay_row0 : delay_line_t := (others => (others => '0'));
    signal delay_row1 : delay_line_t := (others => (others => '0'));
    signal delay_row2 : delay_line_t := (others => (others => '0'));

    signal rom_addr : std_logic_vector(31 downto 0) := (others => '0');
    signal rom_dout : std_logic_vector(143 downto 0);
    type weight_array_t is array (0 to 8) of signed(15 downto 0);
    signal real_weights : weight_array_t := (others => (others => '0'));
    
    signal bias_addr : std_logic_vector(31 downto 0) := (others => '0');
    signal bias_dout : std_logic_vector(15 downto 0);
    
    -- NEW: Extended pipeline registers for the Binary Adder Tree
    signal bias_reg_1  : signed(15 downto 0) := (others => '0');
    signal bias_reg_2  : signed(15 downto 0) := (others => '0');
    signal bias_reg_3  : signed(15 downto 0) := (others => '0');
    
    signal sum_A       : signed(47 downto 0) := (others => '0');
    signal sum_B       : signed(47 downto 0) := (others => '0');
    signal sum_C       : signed(47 downto 0) := (others => '0');
    signal mac_sum_reg : signed(47 downto 0) := (others => '0');
    
    type prod_array_t is array (0 to 8) of signed(31 downto 0);
    signal prods : prod_array_t := (others => (others => '0'));

    -- NEW: Expanded pipeline tracker (5 stages now: 0 to 4)
    type pipeline_track_t is array (0 to 4) of integer range -1 to NUM_OUT_CH;
    signal oc_pipe : pipeline_track_t := (others => -1);
    signal oc_req  : integer range 0 to NUM_OUT_CH := 0;
    
    type accum_array_t is array (0 to NUM_OUT_CH - 1) of signed(47 downto 0);
    signal accums : accum_array_t := (others => (others => '0'));
    
    signal out_ch_cnt : integer range 0 to NUM_OUT_CH := 0;

begin

    weight_inst : entity work.weight_rom
        generic map(WORD_WIDTH => 144, DEPTH => NUM_OUT_CH * NUM_IN_CH, INIT_FILE => WEIGHT_FILE)
        port map(clk => clk, addr => rom_addr, dout => rom_dout);

    bias_inst : entity work.weight_rom
        generic map(WORD_WIDTH => 16, DEPTH => NUM_OUT_CH, INIT_FILE => BIAS_FILE)
        port map(clk => clk, addr => bias_addr, dout => bias_dout);

    process(rom_dout)
    begin
        for i in 0 to 8 loop
            real_weights(i) <= signed(rom_dout((i+1)*16-1 downto i*16));
        end loop;
    end process;

    in_ready  <= '1' when state = SHIFT_IN else '0';

    process(clk)
        variable temp_accum   : signed(47 downto 0);
        variable temp_shifted : signed(47 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= SHIFT_IN;
                col_cnt <= 0; row_cnt <= 0; ic_cnt <= 0; rd_addr <= 0;
                oc_pipe <= (others => -1); oc_req <= 0; out_ch_cnt <= 0;
                out_valid <= '0';
                out_data <= (others => '0');
            else
                case state is
                    when SHIFT_IN =>
                        out_valid <= '0'; 
                        if in_valid = '1' then
                            line_buf_1(rd_addr) <= signed(in_data);
                            line_buf_2(rd_addr) <= line_buf_1(rd_addr);
                            
                            delay_row0(1 to DELAY_LEN) <= delay_row0(0 to DELAY_LEN - 1); delay_row0(0) <= line_buf_2(rd_addr);
                            delay_row1(1 to DELAY_LEN) <= delay_row1(0 to DELAY_LEN - 1); delay_row1(0) <= line_buf_1(rd_addr);
                            delay_row2(1 to DELAY_LEN) <= delay_row2(0 to DELAY_LEN - 1); delay_row2(0) <= signed(in_data);
                            
                            if rd_addr = BUF_DEPTH - 1 then rd_addr <= 0; else rd_addr <= rd_addr + 1; end if;

                            if row_cnt >= 2 and col_cnt >= 2 then
                                state <= CALC_MAC;
                                oc_req <= 0;
                                oc_pipe <= (others => -1);
                            else
                                if ic_cnt = NUM_IN_CH - 1 then
                                    ic_cnt <= 0;
                                    if col_cnt = IMG_W - 1 then
                                        col_cnt <= 0;
                                        if row_cnt = IMG_H - 1 then row_cnt <= 0; else row_cnt <= row_cnt + 1; end if;
                                    else col_cnt <= col_cnt + 1; end if;
                                else ic_cnt <= ic_cnt + 1; end if;
                            end if;
                        end if;

                    when CALC_MAC =>
                        -- Pipeline Stage 0: Issue Memory Addresses
                        if oc_req < NUM_OUT_CH then
                            rom_addr  <= std_logic_vector(to_unsigned(oc_req * NUM_IN_CH + ic_cnt, 32));
                            bias_addr <= std_logic_vector(to_unsigned(oc_req, 32)); 
                            oc_pipe(0) <= oc_req;
                            oc_req <= oc_req + 1;
                        else
                            oc_pipe(0) <= -1;
                        end if;

                        -- Pipeline Stage 1: Wait for BRAM latency, then Multiply
                        oc_pipe(1) <= oc_pipe(0);
                        if oc_pipe(1) >= 0 then
                            prods(0) <= delay_row0(2 * NUM_IN_CH) * real_weights(0);
                            prods(1) <= delay_row0(NUM_IN_CH)     * real_weights(1);
                            prods(2) <= delay_row0(0)             * real_weights(2);
                            prods(3) <= delay_row1(2 * NUM_IN_CH) * real_weights(3);
                            prods(4) <= delay_row1(NUM_IN_CH)     * real_weights(4);
                            prods(5) <= delay_row1(0)             * real_weights(5);
                            prods(6) <= delay_row2(2 * NUM_IN_CH) * real_weights(6);
                            prods(7) <= delay_row2(NUM_IN_CH)     * real_weights(7);
                            prods(8) <= delay_row2(0)             * real_weights(8);
                            bias_reg_1 <= signed(bias_dout);
                        end if;

                        -- Pipeline Stage 2: Binary Adder Tree (Part 1 - Partial Sums)
                        oc_pipe(2) <= oc_pipe(1);
                        if oc_pipe(2) >= 0 then
                            sum_A <= resize(prods(0),48) + resize(prods(1),48) + resize(prods(2),48) + resize(prods(3),48);
                            sum_B <= resize(prods(4),48) + resize(prods(5),48) + resize(prods(6),48) + resize(prods(7),48);
                            sum_C <= resize(prods(8),48);
                            bias_reg_2 <= bias_reg_1; 
                        end if;

                        -- Pipeline Stage 3: Binary Adder Tree (Part 2 - Final MAC Sum)
                        oc_pipe(3) <= oc_pipe(2);
                        if oc_pipe(3) >= 0 then
                            mac_sum_reg <= sum_A + sum_B + sum_C;
                            bias_reg_3 <= bias_reg_2;
                        end if;

                        -- Pipeline Stage 4: Accumulation
                        oc_pipe(4) <= oc_pipe(3);
                        if oc_pipe(4) >= 0 then
                            if ic_cnt = 0 then
                                accums(oc_pipe(4)) <= mac_sum_reg + shift_left(resize(bias_reg_3, 48), 8); 
                            else
                                accums(oc_pipe(4)) <= accums(oc_pipe(4)) + mac_sum_reg; 
                            end if;
                        end if;

                        -- Flow Control: Triggered on final stage of pipeline (Stage 4)
                        if oc_pipe(4) = NUM_OUT_CH - 1 then
                            if ic_cnt = NUM_IN_CH - 1 then
                                state <= PRE_STREAM;
                                out_ch_cnt <= 0;
                            else
                                state <= SHIFT_IN;
                            end if;
                            
                            if ic_cnt = NUM_IN_CH - 1 then
                                ic_cnt <= 0;
                                if col_cnt = IMG_W - 1 then
                                    col_cnt <= 0;
                                    if row_cnt = IMG_H - 1 then row_cnt <= 0; else row_cnt <= row_cnt + 1; end if;
                                else col_cnt <= col_cnt + 1; end if;
                            else ic_cnt <= ic_cnt + 1; end if;
                        end if;

                    when PRE_STREAM =>
                        temp_accum := accums(out_ch_cnt);
                        temp_shifted := shift_right(temp_accum, 8);
                        if temp_shifted < 0 then
                            out_data <= (others => '0'); 
                        elsif temp_shifted > 32767 then
                            out_data <= std_logic_vector(to_signed(32767, 16)); 
                        else
                            out_data <= std_logic_vector(resize(temp_shifted, 16));
                        end if;
                        out_valid <= '1';
                        state <= STREAM_OUT;

                    when STREAM_OUT =>
                        if out_ready = '1' then
                            if out_ch_cnt = NUM_OUT_CH - 1 then
                                out_valid <= '0';
                                state <= SHIFT_IN;
                            else
                                out_ch_cnt <= out_ch_cnt + 1;
                                temp_accum := accums(out_ch_cnt + 1);
                                temp_shifted := shift_right(temp_accum, 8);
                                if temp_shifted < 0 then
                                    out_data <= (others => '0');
                                elsif temp_shifted > 32767 then
                                    out_data <= std_logic_vector(to_signed(32767, 16));
                                else
                                    out_data <= std_logic_vector(resize(temp_shifted, 16));
                                end if;
                            end if;
                        end if;
                        
                end case;
            end if;
        end if;
    end process;
end architecture;