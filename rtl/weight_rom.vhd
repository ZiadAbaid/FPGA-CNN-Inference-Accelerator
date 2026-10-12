library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use std.textio.all;
use ieee.std_logic_textio.all;

entity weight_rom is
    generic (
        WORD_WIDTH : integer := 144; -- 9 weights * 16 bits
        DEPTH      : integer := 16;  -- Number of filters/kernels
        INIT_FILE  : string  := "conv1_weights.mem"
    );
    port (
        clk  : in  std_logic;
        addr : in  std_logic_vector(31 downto 0); 
        dout : out std_logic_vector(WORD_WIDTH-1 downto 0)
    );
end entity;

architecture rtl of weight_rom is
    type rom_type is array (0 to DEPTH-1) of std_logic_vector(WORD_WIDTH-1 downto 0);

    -- This function reads 9 lines from your script's output to fill 1 hardware word
    impure function init_rom_from_16bit_file(file_name : string) return rom_type is
        file romfile       : text;
        variable romline   : line;
        variable temp_mem  : rom_type := (others => (others => '0'));
        variable temp_16bit : std_logic_vector(15 downto 0);
        constant WORDS_PER_LINE : integer := WORD_WIDTH / 16;
    begin
        file_open(romfile, file_name, read_mode);
        for i in 0 to DEPTH-1 loop
            for j in 0 to WORDS_PER_LINE-1 loop
                if not endfile(romfile) then
                    readline(romfile, romline);
                    hread(romline, temp_16bit); -- Reads hex like "0100"
                    -- Packs it into the wide 144-bit kernel
                    temp_mem(i)((j+1)*16-1 downto j*16) := temp_16bit;
                end if;
            end loop;
        end loop;
        file_close(romfile);
        return temp_mem;
    end function;

    signal rom_data : rom_type := init_rom_from_16bit_file(INIT_FILE);
    
    -- Forces Vivado to use Block RAM as per Master Plan
    attribute ram_style : string;
    attribute ram_style of rom_data : signal is "block";
begin
    process(clk) begin
        if rising_edge(clk) then
            dout <= rom_data(to_integer(unsigned(addr)));
        end if;
    end process;
end architecture;