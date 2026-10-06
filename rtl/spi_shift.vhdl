----------------------------------------------------------------------
-- Leaf project
-- developed by: Daniel Santos
-- module: SPI shift core (one word each way per frame)
-- 2026
----------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity spi_shift is
    generic (
        WIDTH    : positive := 64;
        CNT_BITS : positive := 7
    );
    port (
        clk_i      : in  std_logic;
        rst_i      : in  std_logic;
        len_i      : in  std_logic_vector(CNT_BITS-1 downto 0);
        start_i    : in  std_logic;
        stop_i     : in  std_logic;
        rise_i     : in  std_logic;
        fall_i     : in  std_logic;
        din_i      : in  std_logic;
        dout_o     : out std_logic;
        tx_data_i  : in  std_logic_vector(WIDTH-1 downto 0);
        rx_data_o  : out std_logic_vector(WIDTH-1 downto 0);
        rx_bits_o  : out std_logic_vector(CNT_BITS-1 downto 0);
        rx_valid_o : out std_logic
    );
end entity spi_shift;

architecture rtl of spi_shift is

    signal bit_cnt : unsigned(CNT_BITS-1 downto 0);
    signal rx_sh   : std_logic_vector(WIDTH-1 downto 0);
    signal tx_sh   : std_logic_vector(WIDTH-1 downto 0);

begin

    assert WIDTH >= 2 report "SPI shift: WIDTH must be at least 2." severity failure;
    assert 2**CNT_BITS > WIDTH report "SPI shift: CNT_BITS too small to count WIDTH." severity failure;

    cnt_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                bit_cnt <= (others => '0');
            elsif start_i = '1' then
                bit_cnt <= (others => '0');
            elsif rise_i = '1' and bit_cnt /= unsigned(len_i) then
                bit_cnt <= bit_cnt + 1;
            end if;
        end if;
    end process cnt_proc;

    rx_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                rx_sh <= (others => '0');
            elsif start_i = '1' then
                rx_sh <= (others => '0');
            elsif rise_i = '1' and bit_cnt /= unsigned(len_i) then
                rx_sh <= rx_sh(WIDTH-2 downto 0) & din_i;
            end if;
        end if;
    end process rx_proc;

    tx_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                tx_sh <= (others => '0');
            elsif start_i = '1' then
                tx_sh <= tx_data_i;
            elsif fall_i = '1' then
                tx_sh <= tx_sh(WIDTH-2 downto 0) & '0';
            end if;
        end if;
    end process tx_proc;

    dout_o     <= tx_sh(WIDTH-1);
    rx_data_o  <= rx_sh;
    rx_bits_o  <= std_logic_vector(bit_cnt);
    rx_valid_o <= stop_i;

end architecture rtl;
