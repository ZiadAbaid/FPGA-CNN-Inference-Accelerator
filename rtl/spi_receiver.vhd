library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_receiver is
    Generic ( G_DATA_WIDTH : integer := 32 );
    Port (
        clk_100mhz : in STD_LOGIC;
        reset      : in STD_LOGIC;
        cs_n_sync  : in STD_LOGIC; -- Synchronized Active-Low Chip Select
        sclk_rise  : in STD_LOGIC; -- 1-tick pulse when SCLK goes from 0 to 1
        mosi_sync  : in STD_LOGIC; -- Synchronized MOSI data
        rx_data    : out STD_LOGIC_VECTOR(G_DATA_WIDTH-1 downto 0);
        rx_valid   : out STD_LOGIC -- Pulses HIGH for 1 clock cycle when data is fully received
    );
end spi_receiver;

architecture Behavioral of spi_receiver is
    signal shift_reg : STD_LOGIC_VECTOR(G_DATA_WIDTH-1 downto 0) := (others => '0');
    signal bit_count : integer range 0 to G_DATA_WIDTH := 0;
begin
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if reset = '1' or cs_n_sync = '1' then
                -- CS going High acts as a hard reset for the SPI transaction
                bit_count <= 0;
                rx_valid <= '0';
            else
                rx_valid <= '0'; -- Default state
                
                if sclk_rise = '1' then
                    -- Shift data to the left (MSB first)
                    shift_reg <= shift_reg(G_DATA_WIDTH-2 downto 0) & mosi_sync;
                    bit_count <= bit_count + 1;
                    
                    -- Check if we received the full word
                    if bit_count = G_DATA_WIDTH - 1 then
                        rx_data <= shift_reg(G_DATA_WIDTH-2 downto 0) & mosi_sync;
                        rx_valid <= '1';
                        bit_count <= 0; -- Reset for the next word
                    end if;
                end if;
            end if;
        end if;
    end process;
end Behavioral;