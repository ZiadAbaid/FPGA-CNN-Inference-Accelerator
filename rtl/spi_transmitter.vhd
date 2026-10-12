library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity spi_transmitter is
    Generic ( G_DATA_WIDTH : integer := 32 );
    Port (
        clk_100mhz : in STD_LOGIC;
        reset      : in STD_LOGIC;
        cs_n_sync  : in STD_LOGIC;
        sclk_fall  : in STD_LOGIC; -- 1-tick pulse when SCLK goes from 1 to 0
        tx_data    : in STD_LOGIC_VECTOR(G_DATA_WIDTH-1 downto 0);
        tx_load    : in STD_LOGIC; -- Tells the module to latch new data to send
        miso       : out STD_LOGIC
    );
end spi_transmitter;

architecture Behavioral of spi_transmitter is
    signal shift_reg : STD_LOGIC_VECTOR(G_DATA_WIDTH-1 downto 0) := (others => '0');
    signal miso_internal : STD_LOGIC := '0';
begin
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if reset = '1' then
                shift_reg <= (others => '0');
            elsif tx_load = '1' then
                -- Load the new data from the Top Module when ready
                shift_reg <= tx_data;
            elsif cs_n_sync = '0' then
                -- When CS is low, shift data out on the falling edge
                if sclk_fall = '1' then
                    shift_reg <= shift_reg(G_DATA_WIDTH-2 downto 0) & '0';
                end if;
            end if;
        end if;
    end process;

    -- Push the Most Significant Bit (MSB) to the wire
    miso_internal <= shift_reg(G_DATA_WIDTH-1);
    
    -- Tristate MISO when CS is high (standard SPI practice)
    miso <= miso_internal when cs_n_sync = '0' else 'Z';

end Behavioral;