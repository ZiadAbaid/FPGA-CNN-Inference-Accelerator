library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.cnn_config.all;

entity system_top is
    port (
        clk_100mhz : in  std_logic;
        reset_n    : in  std_logic; 
        
        -- SPI Interface
        spi_cs_n   : in  std_logic;
        spi_sclk   : in  std_logic;
        spi_mosi   : in  std_logic;
        spi_miso   : out std_logic;
        
        -- Hardware Interrupt
        data_ready : out std_logic;
        
        -- NEW: Hardware Debugger LEDs
        led        : out std_logic_vector(15 downto 0)
    );
end entity;

architecture struct of system_top is

    signal sys_reset      : std_logic;
    signal soft_reset     : std_logic;
    signal combined_reset : std_logic;

    -- SPI Controller Signals
    signal spi_rx_data    : std_logic_vector(15 downto 0);
    signal spi_rx_valid   : std_logic;
    signal spi_tx_data    : std_logic_vector(15 downto 0);
    signal spi_tx_load    : std_logic;

    -- Synchronization (The Metastability Fix)
    signal sclk_sync      : std_logic_vector(2 downto 0) := "000";
    signal cs_sync        : std_logic_vector(1 downto 0) := "11";

    -- FIFO and CNN Signals
    signal rx_fifo_wr_en, rx_fifo_rd_en, rx_fifo_empty, rx_fifo_full : std_logic;
    signal rx_fifo_data   : std_logic_vector(15 downto 0);
    signal tx_fifo_wr_en, tx_fifo_rd_en, tx_fifo_empty, tx_fifo_full : std_logic;
    signal tx_fifo_data   : std_logic_vector(15 downto 0);
    signal cnn_in_valid, cnn_in_ready, cnn_out_valid, cnn_out_ready : std_logic;
    signal cnn_out_data   : std_logic_vector(15 downto 0);

    -- FSM Definition
    type system_state_type is (IDLE, CAPTURE_AND_INFERENCE, PRE_LOAD, SEND_RESULTS, WAIT_FOR_SAFE_LOAD);
    signal state : system_state_type := IDLE;

    signal pixel_count : integer range 0 to 2047 := 0;
    signal logit_count : integer range 0 to 15 := 0;
    signal read_count  : integer range 0 to 15 := 0;

begin

    sys_reset <= not reset_n;
    combined_reset <= sys_reset or soft_reset;

    -- Synchronizers for Top-Level FSM (fixes metastability!)
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            sclk_sync <= sclk_sync(1 downto 0) & spi_sclk;
            cs_sync   <= cs_sync(0) & spi_cs_n;
        end if;
    end process;

    u_spi_ctrl: entity work.spi_controller
        generic map(G_TX_WIDTH => 16, G_RX_WIDTH => 16)
        port map(
            clk_100mhz => clk_100mhz, reset => sys_reset,
            spi_cs_n => spi_cs_n, spi_sclk => spi_sclk, spi_mosi => spi_mosi, spi_miso => spi_miso,
            tx_data => spi_tx_data, tx_load => spi_tx_load, rx_data => spi_rx_data, rx_valid => spi_rx_valid
        );

    u_rx_fifo: entity work.sync_fifo
        generic map(DATA_WIDTH => 16, ADDR_WIDTH => 11)
        port map(clk => clk_100mhz, reset => combined_reset, wr_en => rx_fifo_wr_en, wr_data => spi_rx_data, rd_en => rx_fifo_rd_en, rd_data => rx_fifo_data, empty => rx_fifo_empty, full => rx_fifo_full);

    u_cnn_core: entity work.cnn_datapath_top
        port map(clk => clk_100mhz, reset => combined_reset, in_data => rx_fifo_data, in_valid => cnn_in_valid, in_ready => cnn_in_ready, out_data => cnn_out_data, out_valid => cnn_out_valid, out_ready => cnn_out_ready);

    u_tx_fifo: entity work.sync_fifo
        generic map(DATA_WIDTH => 16, ADDR_WIDTH => 4)
        port map(clk => clk_100mhz, reset => combined_reset, wr_en => tx_fifo_wr_en, wr_data => cnn_out_data, rd_en => tx_fifo_rd_en, rd_data => tx_fifo_data, empty => tx_fifo_empty, full => tx_fifo_full);

    -- Routing
    rx_fifo_wr_en <= spi_rx_valid when state = CAPTURE_AND_INFERENCE else '0';
    cnn_in_valid  <= not rx_fifo_empty;
    rx_fifo_rd_en <= cnn_in_ready and not rx_fifo_empty;
    tx_fifo_wr_en <= cnn_out_valid;
    cnn_out_ready <= not tx_fifo_full; 
    spi_tx_data   <= tx_fifo_data;

    -- Master FSM
    process(clk_100mhz)
    begin
        if rising_edge(clk_100mhz) then
            if sys_reset = '1' then
                state <= IDLE;
                data_ready <= '0';
                soft_reset <= '1';
                spi_tx_load <= '0';
                tx_fifo_rd_en <= '0';
                pixel_count <= 0;
                logit_count <= 0;
                read_count <= 0;
            else
                -- Default strobes
                spi_tx_load <= '0';
                tx_fifo_rd_en <= '0';
                soft_reset <= '0';

                case state is
                    when IDLE =>
                        data_ready <= '0';
                        pixel_count <= 0;
                        logit_count <= 0;
                        read_count <= 0;
                        soft_reset <= '1'; -- Hold CNN in reset until Pi starts talking
                        
                        -- Start ONLY when synchronized CS goes low
                        if cs_sync(1) = '0' then
                            state <= CAPTURE_AND_INFERENCE;
                            soft_reset <= '0';
                        end if;

                    when CAPTURE_AND_INFERENCE =>
                        if spi_rx_valid = '1' then 
                            pixel_count <= pixel_count + 1;
                        end if;
                        
                        if cnn_out_valid = '1' then
                            logit_count <= logit_count + 1;
                            if logit_count = NUM_CLASSES - 1 then 
                                state <= PRE_LOAD; 
                            end if;
                        end if;

                        -- Emergency abort if Pi raises CS_N prematurely
                        if cs_sync(1) = '1' and logit_count < NUM_CLASSES - 1 then
                            state <= IDLE;
                        end if;

                    when PRE_LOAD =>
                        spi_tx_load   <= '1';
                        tx_fifo_rd_en <= '1'; 
                        state <= SEND_RESULTS;

                    when SEND_RESULTS =>
                        data_ready <= '1';
                        
                        if spi_rx_valid = '1' then
                            read_count <= read_count + 1;
                            state <= WAIT_FOR_SAFE_LOAD;
                        end if;

                        -- If Pi raises CS_N, the transaction is over!
                        if cs_sync(1) = '1' then
                            state <= IDLE;
                        end if;

                    when WAIT_FOR_SAFE_LOAD =>
                        data_ready <= '1'; -- Keep it high so Pi doesn't drop out
                        if sclk_sync(1) = '0' then
                            tx_fifo_rd_en <= '1';
                            spi_tx_load   <= '1'; 
                            state <= SEND_RESULTS;
                        end if;

                        if cs_sync(1) = '1' then
                            state <= IDLE;
                        end if;

                    when others => 
                        state <= IDLE;
                end case;
            end if;
        end if;
    end process;

    -- ==========================================
    -- HARDWARE LED DEBUGGER
    -- ==========================================
    led(15 downto 12) <= "0000" when state = IDLE else
                         "0001" when state = CAPTURE_AND_INFERENCE else
                         "0010" when state = PRE_LOAD else
                         "0011" when state = SEND_RESULTS else
                         "0100" when state = WAIT_FOR_SAFE_LOAD else 
                         "1111";
                         
    -- LED 11: Flashes if the CNN is stuck waiting for pixels (RX FIFO empty)
    led(11) <= rx_fifo_empty;
    
    -- LEDs 10-0: Binary representation of the Pixel Count
    led(10 downto 0) <= std_logic_vector(to_unsigned(pixel_count, 11));

end architecture;