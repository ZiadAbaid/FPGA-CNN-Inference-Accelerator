library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;
use ieee.std_logic_textio.all;

entity tb_system is
end entity;

architecture sim of tb_system is

    -- =========================================================
    -- TEST CONFIGURATION
    -- =========================================================
    -- IMPORTANT: Set this to the absolute path where generate_testbench_data.py saves files.
    -- Use forward slashes (/) for VHDL paths, even on Windows.
    constant DATA_DIR   : string := "../../../../testbench_data/"; 
    
    -- Change this prefix to test different images (e.g., "cat", "dog", "human")
    constant TEST_IMAGE : string := "cat"; 

    -- =========================================================
    -- CLOCKS & TIMEOUTS
    -- =========================================================
    constant SYS_CLK_PERIOD : time := 10 ns;   -- 100 MHz FPGA Clock
    constant SPI_CLK_HALF   : time := 50 ns;   -- 10 MHz SPI Clock
    constant TIMEOUT        : time := 50 ms;   -- Failsafe timeout

    -- UUT Signals
    signal clk_100mhz : std_logic := '0';
    signal reset_n    : std_logic := '0';
    signal spi_cs_n   : std_logic := '1';
    signal spi_sclk   : std_logic := '0';
    signal spi_mosi   : std_logic := '0';
    signal spi_miso   : std_logic;
    signal data_ready : std_logic;

    -- Simulation Tracking
    signal sim_done : boolean := false;

    -- 3-Class Arrays for Verification
    type logit_array is array (0 to 2) of std_logic_vector(15 downto 0);
    signal expected_logits : logit_array := (others => (others => '0'));
    signal received_logits : logit_array := (others => (others => '0'));
    -- Add this signal right below your other signals
    signal led : std_logic_vector(15 downto 0);

begin

    -- 100 MHz System Clock Generation
    clk_100mhz <= not clk_100mhz after SYS_CLK_PERIOD/2 when not sim_done else '0';

    -- ... Inside your architecture ...
    uut: entity work.system_top
        port map (
            clk_100mhz => clk_100mhz,
            reset_n    => reset_n,
            spi_cs_n   => spi_cs_n,
            spi_sclk   => spi_sclk,
            spi_mosi   => spi_mosi,
            spi_miso   => spi_miso,
            data_ready => data_ready,
            led        => led  -- Mapped the new port!
        );

    -- =========================================================
    -- MAIN STIMULUS (THE RASPBERRY PI ROLEPLAY)
    -- =========================================================
    pi_sim_proc: process
        file f_expected  : text;
        file f_in        : text;
        variable l       : line;
        variable hex_val : std_logic_vector(15 downto 0);
        variable rx_word : std_logic_vector(15 downto 0);
        variable errors  : integer := 0;
        
        -- Inline Procedure to act as the SPI Master (Mode 0: CPOL=0, CPHA=0)
        procedure spi_transfer_16(
            tx_data : in  std_logic_vector(15 downto 0);
            rx_data : out std_logic_vector(15 downto 0)
        ) is
        begin
            for i in 15 downto 0 loop
                -- 1. Setup data on MOSI
                spi_mosi <= tx_data(i);
                wait for SPI_CLK_HALF;
                
                -- 2. Rising Edge (Sample MISO)
                spi_sclk <= '1';
                rx_data(i) := spi_miso;
                wait for SPI_CLK_HALF;
                
                -- 3. Falling Edge
                spi_sclk <= '0';
            end loop;
        end procedure;

    begin
        report "==================================================";
        report "--- STARTING SYSTEM LEVEL SPI TESTBENCH ---";
        report "Testing Image Prefix: " & TEST_IMAGE;
        report "==================================================";

        -- 1. Load Expected Golden Logits
        report "Loading expected logits from Golden Model...";
        file_open(f_expected, DATA_DIR & TEST_IMAGE & "_11_logits.hex", read_mode);
        for i in 0 to 2 loop
            readline(f_expected, l);
            hread(l, hex_val);
            expected_logits(i) <= hex_val;
        end loop;
        file_close(f_expected);

        -- 2. Hardware Reset
        reset_n  <= '0';
        spi_cs_n <= '1';
        spi_sclk <= '0';
        spi_mosi <= '0';
        wait for 200 ns;
        reset_n  <= '1';
        wait for 200 ns;

        -- 3. Start SPI Transaction
        report "Initiating SPI Transaction (Lowering CS_N)...";
        spi_cs_n <= '0';
        wait for SPI_CLK_HALF * 2;

        -- 4. Transmit the Image (1156 Pixels)
        file_open(f_in, DATA_DIR & TEST_IMAGE & "_0_input.hex", read_mode);
        report "Streaming 1156 Image Words over SPI...";
        
        while not endfile(f_in) loop
            readline(f_in, l);
            hread(l, hex_val);
            spi_transfer_16(hex_val, rx_word); -- Ignore rx_word during image send
        end loop;
        file_close(f_in);
        
        report "Transmission Complete. Waiting for FPGA DATA_READY...";

        -- 5. Wait for CNN Inference (Timeout protection)
        wait until data_ready = '1' for TIMEOUT;
        if data_ready = '0' then
            report "!!! FATAL ERROR: Timeout waiting for DATA_READY !!!" severity failure;
        end if;
        report "DATA_READY Interrupt Received! Reading 3 Class Logits...";

        wait for SPI_CLK_HALF * 4;

        -- 6. Read the 3 Output Logits (Cat, Dog, Human)
        for i in 0 to 2 loop
            spi_transfer_16(x"0000", rx_word);
            received_logits(i) <= rx_word;
        end loop;

        -- 7. End Transaction
        wait for SPI_CLK_HALF * 2;
        spi_cs_n <= '1';
        report "SPI Transaction Closed.";

        -- 8. Bit-Exact Verification
        report "==================================================";
        report "--- VERIFICATION RESULTS ---";
        for i in 0 to 2 loop
            if received_logits(i) = expected_logits(i) then
                report "Logit " & integer'image(i) & " MATCH! Expected/Received: " & to_hex_string(expected_logits(i));
            else
                report "Logit " & integer'image(i) & " MISMATCH! " & 
                       " Expected: " & to_hex_string(expected_logits(i)) & 
                       " Received: " & to_hex_string(received_logits(i)) severity error;
                errors := errors + 1;
            end if;
        end loop;

        report "==================================================";
        if errors = 0 then
            report " >>> SUCCESS: ALL LOGITS MATCH GOLDEN MODEL EXACTLY! <<< ";
        else
            report " >>> FAILURE: " & integer'image(errors) & " LOGIT(S) MISMATCHED <<< " severity error;
        end if;
        report "==================================================";

        sim_done <= true;
        wait;
    end process;

end architecture;