library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity spi_controller is
    Generic (
        G_TX_WIDTH : integer := 8;
        G_RX_WIDTH : integer := 8
    );
    Port (
        clk_100mhz : in  STD_LOGIC;
        reset      : in  STD_LOGIC;
        
        -- Asynchronous SPI Pins from Raspberry Pi
        spi_cs_n   : in  STD_LOGIC;
        spi_sclk   : in  STD_LOGIC;
        spi_mosi   : in  STD_LOGIC;
        spi_miso   : out STD_LOGIC;
        
        -- Interface to Top Module
        tx_data    : in  STD_LOGIC_VECTOR(G_TX_WIDTH-1 downto 0);
        tx_load    : in  STD_LOGIC;
        rx_data    : out STD_LOGIC_VECTOR(G_RX_WIDTH-1 downto 0);
        rx_valid   : out STD_LOGIC
    );
end spi_controller;

architecture Behavioral of spi_controller is
    -- Synchronization Registers
    signal cs_sync   : STD_LOGIC_VECTOR(1 downto 0) := "11";
    signal sclk_sync : STD_LOGIC_VECTOR(2 downto 0) := "000"; -- 3 bits for edge detection
    signal mosi_sync : STD_LOGIC_VECTOR(1 downto 0) := "00";

    -- Internal signals
    signal sclk_rise : STD_LOGIC;
    signal sclk_fall : STD_LOGIC;
    signal cs_n_safe : STD_LOGIC;
    signal mosi_safe : STD_LOGIC;

begin

    -- Clock Domain Crossing (CDC) & Edge Detection Process
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if reset = '1' then
                cs_sync   <= "11";
                sclk_sync <= "000";
                mosi_sync <= "00";
            else
                -- Shift registers for 2-flop synchronization
                cs_sync   <= cs_sync(0) & spi_cs_n;
                sclk_sync <= sclk_sync(1 downto 0) & spi_sclk;
                mosi_sync <= mosi_sync(0) & spi_mosi;
            end if;
        end if;
    end process;

    -- Map safe synchronized signals
    cs_n_safe <= cs_sync(1);
    mosi_safe <= mosi_sync(1);

    -- Edge detection logic using the 3rd flop stage
    sclk_rise <= '1' when (sclk_sync(2 downto 1) = "01") else '0';
    sclk_fall <= '1' when (sclk_sync(2 downto 1) = "10") else '0';

    -- Instantiate Receiver
    Inst_Receiver: entity work.spi_receiver
        generic map ( G_DATA_WIDTH => G_RX_WIDTH )
        port map (
            clk_100mhz => clk_100mhz,
            reset      => reset,
            cs_n_sync  => cs_n_safe,
            sclk_rise  => sclk_rise,
            mosi_sync  => mosi_safe,
            rx_data    => rx_data,
            rx_valid   => rx_valid
        );

    -- Instantiate Transmitter
    Inst_Transmitter: entity work.spi_transmitter
        generic map ( G_DATA_WIDTH => G_TX_WIDTH )
        port map (
            clk_100mhz => clk_100mhz,
            reset      => reset,
            cs_n_sync  => cs_n_safe,
            sclk_fall  => sclk_fall,
            tx_data    => tx_data,
            tx_load    => tx_load,
            miso       => spi_miso
        );

end Behavioral;