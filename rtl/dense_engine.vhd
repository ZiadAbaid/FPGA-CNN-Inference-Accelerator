library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;
use ieee.std_logic_textio.all;
use work.cnn_config.all;

entity dense_engine is
    generic (
        IN_SIZE       : integer := 512;
        OUT_SIZE      : integer := 32;
        PARALLEL_MACS : integer := 8;
        APPLY_RELU    : boolean := true;
        BIAS_FILE     : string  := "dense1_biases.mem";
        WEIGHT_FILE   : string  := "dense1_weights.mem"
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

architecture rtl of dense_engine is
    type state_type is (IDLE, LOAD_BUFFER, COMPUTE_WAIT, COMPUTE, FLUSH_MAC, DRAIN_OUT);
    signal state : state_type := IDLE;

    -- The Memory Array
    type ram_type is array (0 to IN_SIZE - 1) of signed(DATA_WIDTH-1 downto 0);
    signal input_buf : ram_type := (others => (others => '0'));
    
    attribute ram_style : string;
    attribute ram_style of input_buf : signal is "block";
    
    signal p_in_reg  : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal ram_we    : std_logic;

    signal load_idx  : integer range 0 to IN_SIZE := 0;

    constant NUM_PASSES : integer := (OUT_SIZE + PARALLEL_MACS - 1) / PARALLEL_MACS; 
    signal pass_idx     : integer range 0 to NUM_PASSES := 0;
    
    signal fetch_idx    : integer range 0 to IN_SIZE := 0;
    signal compute_idx  : integer range 0 to IN_SIZE := 0;
    
    signal total_outputs_sent : integer range 0 to OUT_SIZE := 0;

    type accum_array is array (0 to PARALLEL_MACS - 1) of signed(47 downto 0);
    signal accums : accum_array := (others => (others => '0'));
    
    signal valid_prod : std_logic := '0';
    signal prods_reg  : accum_array := (others => (others => '0'));

    signal drain_idx : integer range 0 to PARALLEL_MACS := 0;

    type bias_array is array (0 to OUT_SIZE - 1) of signed(15 downto 0);
    
    impure function init_bias(filename : string) return bias_array is
        file f : text;
        variable l : line;
        variable w : std_logic_vector(15 downto 0);
        variable res : bias_array := (others => (others => '0'));
    begin
        file_open(f, filename, read_mode);
        for i in 0 to OUT_SIZE - 1 loop
            if not endfile(f) then
                readline(f, l);
                hread(l, w);
                res(i) := signed(w);
            end if;
        end loop;
        file_close(f);
        return res;
    end function;
    
    signal biases : bias_array := init_bias(BIAS_FILE);

    signal weight_addr : std_logic_vector(31 downto 0);
    signal weight_data : std_logic_vector(PARALLEL_MACS * 16 - 1 downto 0);

begin

    u_weight_rom: entity work.weight_rom
        generic map (
            WORD_WIDTH => PARALLEL_MACS * 16,
            DEPTH      => NUM_PASSES * IN_SIZE,
            INIT_FILE  => WEIGHT_FILE
        )
        port map (
            clk  => clk,
            addr => weight_addr,
            dout => weight_data
        );

    in_ready <= '1' when (state = IDLE or state = LOAD_BUFFER) and load_idx < IN_SIZE else '0';
    
    weight_addr <= std_logic_vector(to_unsigned(pass_idx * IN_SIZE + fetch_idx, 32));

    -- =========================================================
    -- THE FIX: DEDICATED BRAM PROCESS
    -- This perfectly matches the Xilinx synchronous RAM template
    -- =========================================================
    ram_we <= '1' when (state = IDLE or state = LOAD_BUFFER) and in_valid = '1' else '0';

    process(clk)
    begin
        if rising_edge(clk) then
            -- Port A: Write
            if ram_we = '1' then
                input_buf(load_idx) <= signed(in_data);
            end if;
            
            -- Port B: Read (Free-running, perfectly pipeline aligned)
            p_in_reg <= input_buf(fetch_idx);
        end if;
    end process;


    -- =========================================================
    -- MAIN CONTROL FSM
    -- =========================================================
    process(clk)
        variable final_val : signed(47 downto 0);
        variable shifted_val : signed(47 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state <= IDLE;
                load_idx <= 0; pass_idx <= 0; 
                fetch_idx <= 0; compute_idx <= 0;
                drain_idx <= 0;
                valid_prod <= '0';
                total_outputs_sent <= 0;
                accums <= (others => (others => '0'));
                prods_reg <= (others => (others => '0'));
                out_valid <= '0'; out_data <= (others => '0');
            else
                out_valid <= '0'; 

                case state is
                    when IDLE =>
                        load_idx <= 0;
                        total_outputs_sent <= 0;
                        if in_valid = '1' then
                            load_idx <= 1;
                            state <= LOAD_BUFFER;
                        end if;

                    when LOAD_BUFFER =>
                        if in_valid = '1' then
                            if load_idx = IN_SIZE - 1 then
                                state <= COMPUTE_WAIT; 
                                pass_idx <= 0;
                                fetch_idx <= 0;
                                compute_idx <= 0;
                                valid_prod <= '0';
                                accums <= (others => (others => '0'));
                            else
                                load_idx <= load_idx + 1;
                            end if;
                        end if;

                    when COMPUTE_WAIT =>
                        fetch_idx <= 1;
                        compute_idx <= 0;
                        valid_prod <= '0';
                        state <= COMPUTE;

                    when COMPUTE =>
                        for i in 0 to PARALLEL_MACS - 1 loop
                            prods_reg(i) <= resize(p_in_reg * signed(weight_data((i+1)*16-1 downto i*16)), 48); 
                        end loop;
                        valid_prod <= '1';

                        if valid_prod = '1' then
                            for i in 0 to PARALLEL_MACS - 1 loop
                                accums(i) <= accums(i) + prods_reg(i);
                            end loop;
                        end if;

                        if compute_idx = IN_SIZE - 1 then
                            state <= FLUSH_MAC; 
                        else
                            compute_idx <= compute_idx + 1;
                            if fetch_idx < IN_SIZE - 1 then
                                fetch_idx <= fetch_idx + 1;
                            end if;
                        end if;

                    when FLUSH_MAC =>
                        if valid_prod = '1' then
                            for i in 0 to PARALLEL_MACS - 1 loop
                                accums(i) <= accums(i) + prods_reg(i);
                            end loop;
                        end if;
                        valid_prod <= '0';
                        state <= DRAIN_OUT;
                        drain_idx <= 0;

                    when DRAIN_OUT =>
                        if out_ready = '1' then
                            out_valid <= '1';
                            final_val := accums(drain_idx) + shift_left(resize(biases(total_outputs_sent), 48), 8);
                            shifted_val := shift_right(final_val, 8);

                            if APPLY_RELU and shifted_val < 0 then
                                out_data <= (others => '0');
                            elsif shifted_val > 32767 then
                                out_data <= std_logic_vector(to_signed(32767, 16));
                            elsif shifted_val < -32768 then
                                out_data <= std_logic_vector(to_signed(-32768, 16));
                            else
                                out_data <= std_logic_vector(resize(shifted_val, 16));
                            end if;

                            if total_outputs_sent = OUT_SIZE - 1 then
                                state <= IDLE;
                                total_outputs_sent <= 0;
                            elsif drain_idx = PARALLEL_MACS - 1 then
                                if pass_idx < NUM_PASSES - 1 then
                                    state <= COMPUTE_WAIT; 
                                    pass_idx <= pass_idx + 1;
                                    fetch_idx <= 0;
                                    compute_idx <= 0;
                                    accums <= (others => (others => '0'));
                                    drain_idx <= 0;
                                    total_outputs_sent <= total_outputs_sent + 1;
                                else
                                    state <= IDLE;
                                end if;
                            else
                                drain_idx <= drain_idx + 1;
                                total_outputs_sent <= total_outputs_sent + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;
end architecture;