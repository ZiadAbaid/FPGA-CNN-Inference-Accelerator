library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.cnn_config.all;

entity flatten is
    port (
        clk          : in  std_logic;
        reset        : in  std_logic;
        
        -- Input Stream (From Pool3)
        in_data      : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        in_valid     : in  std_logic;
        in_ready     : out std_logic;
        
        -- Output Stream (To Dense1)
        out_data     : out std_logic_vector(DATA_WIDTH-1 downto 0);
        out_valid    : out std_logic;
        out_ready    : in  std_logic;
        
        -- Status Flag
        flatten_done : out std_logic
    );
end entity;

architecture rtl of flatten is
    -- Counter sized perfectly for the flatten size defined in your config
    signal count : integer range 0 to FLATTEN_SIZE := 0;
begin
    
    -- 1. Pure Combinatorial Pass-Through
    out_data  <= in_data;
    out_valid <= in_valid;
    in_ready  <= out_ready;

    -- 2. Synchronous Counting Logic
    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                count <= 0;
                flatten_done <= '0';
            else
                -- Default state: no pulse
                flatten_done <= '0'; 
                
                -- Only count when data is actively transferring
                if in_valid = '1' and out_ready = '1' then
                    if count = FLATTEN_SIZE - 1 then
                        count <= 0;
                        flatten_done <= '1'; -- Pulse high for 1 cycle when a full map is flattened
                    else
                        count <= count + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;