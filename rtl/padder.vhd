library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.cnn_config.all;

entity padder is
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

architecture rtl of padder is
    type state_type is (IDLE, STREAMING);
    signal state : state_type := IDLE;
    
    -- Counters map the new dimensions (e.g., 18x18 instead of 16x16)
    signal col_cnt : integer range 0 to IMG_W + 1 := 0;
    signal row_cnt : integer range 0 to IMG_H + 1 := 0;
    signal ch_cnt  : integer range 0 to CHANNELS - 1 := 0;
    
    signal is_pad  : std_logic;
begin

    -- Geographical check: Are we in the 1-pixel zero border?
    is_pad <= '1' when (row_cnt = 0 or row_cnt = IMG_H + 1 or col_cnt = 0 or col_cnt = IMG_W + 1) else '0';

    -- Handshake Wiring
    -- We are only ready to accept real data if we are NOT in a padding region AND the downstream is ready
    in_ready  <= out_ready when (state = STREAMING and is_pad = '0') else '0';
    
    -- We are valid if we are streaming padding zeros, OR if we are streaming real data and the input is valid
    out_valid <= '1'       when (state = STREAMING and is_pad = '1') else
                 in_valid  when (state = STREAMING and is_pad = '0') else '0';
                 
    -- Multiplex the output data between zeros and the actual input stream
    out_data  <= (others => '0') when is_pad = '1' else in_data;

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                state   <= IDLE;
                col_cnt <= 0;
                row_cnt <= 0;
                ch_cnt  <= 0;
            else
                case state is
                    when IDLE =>
                        -- Wait for the very first pixel of a new image to arrive before turning on the tap
                        if in_valid = '1' then
                            state <= STREAMING;
                        end if;

                    when STREAMING =>
                        -- Advance counters ONLY when a successful transmission happens
                        if (out_ready = '1' and is_pad = '1') or (out_ready = '1' and in_valid = '1' and is_pad = '0') then
                            
                            if ch_cnt = CHANNELS - 1 then
                                ch_cnt <= 0;
                                
                                if col_cnt = IMG_W + 1 then
                                    col_cnt <= 0;
                                    
                                    if row_cnt = IMG_H + 1 then
                                        row_cnt <= 0;
                                        state   <= IDLE; -- Finished sending the entire padded image
                                    else
                                        row_cnt <= row_cnt + 1;
                                    end if;
                                else
                                    col_cnt <= col_cnt + 1;
                                end if;
                            else
                                ch_cnt <= ch_cnt + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture;