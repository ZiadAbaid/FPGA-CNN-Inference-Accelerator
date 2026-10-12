library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sync_fifo is
    generic (
        DATA_WIDTH : integer := 8;
        ADDR_WIDTH : integer := 4 -- 16-byte buffer is plenty for SPI speeds
    );
    port (
        clk      : in  std_logic;
        reset    : in  std_logic;
        wr_en    : in  std_logic;
        wr_data  : in  std_logic_vector(DATA_WIDTH-1 downto 0);
        rd_en    : in  std_logic;
        rd_data  : out std_logic_vector(DATA_WIDTH-1 downto 0);
        empty    : out std_logic;
        full     : out std_logic
    );
end entity;

architecture rtl of sync_fifo is
    type ram_type is array (0 to (2**ADDR_WIDTH)-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal mem : ram_type := (others => (others => '0'));
    
    signal wr_ptr, rd_ptr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal count : integer range 0 to 2**ADDR_WIDTH := 0;
begin
    full  <= '1' when count = 2**ADDR_WIDTH else '0';
    empty <= '1' when count = 0 else '0';
    
    rd_data <= mem(to_integer(rd_ptr));

    process(clk)
    begin
        if rising_edge(clk) then
            if reset = '1' then
                wr_ptr <= (others => '0');
                rd_ptr <= (others => '0');
                count  <= 0;
            else
                if wr_en = '1' and count < 2**ADDR_WIDTH then
                    mem(to_integer(wr_ptr)) <= wr_data;
                    wr_ptr <= wr_ptr + 1;
                end if;
                
                if rd_en = '1' and count > 0 then
                    rd_ptr <= rd_ptr + 1;
                end if;
                
                if (wr_en = '1' and count < 2**ADDR_WIDTH) and not (rd_en = '1' and count > 0) then
                    count <= count + 1;
                elsif (rd_en = '1' and count > 0) and not (wr_en = '1' and count < 2**ADDR_WIDTH) then
                    count <= count - 1;
                end if;
            end if;
        end if;
    end process;
end architecture;