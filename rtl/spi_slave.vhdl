----------------------------------------------------------------------
-- Leaf project
-- developed by: Daniel Santos
-- module: SPI slave (mode 0, word per frame)
-- 2026
----------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity spi_slave is
    generic (
        WIDTH    : positive := 32;
        CNT_BITS : positive := 6
    );
    port (
        clk_i      : in  std_logic;
        rst_i      : in  std_logic;
        sclk_i     : in  std_logic;  -- sclk_i, cs_n_i and mosi_i must already be
        cs_n_i     : in  std_logic;  -- synchronised to clk_i (spi_port does it)
        mosi_i     : in  std_logic;
        miso_o     : out std_logic;
        rx_data_o  : out std_logic_vector(WIDTH-1 downto 0);
        rx_bits_o  : out std_logic_vector(CNT_BITS-1 downto 0);
        rx_valid_o : out std_logic;
        tx_data_i  : in  std_logic_vector(WIDTH-1 downto 0)
    );
end entity spi_slave;

architecture rtl of spi_slave is

    signal sclk_reg  : std_logic;
    signal cs_n_reg  : std_logic;
    signal sclk_rise : std_logic;
    signal sclk_fall : std_logic;
    signal start     : std_logic;
    signal stop      : std_logic;

    signal bit_cnt : unsigned(CNT_BITS-1 downto 0);
    signal rx_sh   : std_logic_vector(WIDTH-1 downto 0);
    signal tx_sh   : std_logic_vector(WIDTH-1 downto 0);

begin

    assert WIDTH >= 2 report "SPI slave: WIDTH must be at least 2." severity failure;
    assert 2**CNT_BITS > WIDTH report "SPI slave: CNT_BITS too small to count WIDTH." severity failure;

    edge_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                sclk_reg <= '0';
                cs_n_reg <= '1';
            else
                sclk_reg <= sclk_i;
                cs_n_reg <= cs_n_i;
            end if;
        end if;
    end process edge_proc;

    sclk_rise <= sclk_i and not sclk_reg and not cs_n_i;
    sclk_fall <= sclk_reg and not sclk_i and not cs_n_i;
    start     <= cs_n_reg and not cs_n_i;
    stop      <= cs_n_i and not cs_n_reg;

    cnt_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                bit_cnt <= (others => '0');
            elsif start = '1' then
                bit_cnt <= (others => '0');
            elsif sclk_rise = '1' and bit_cnt /= WIDTH then
                bit_cnt <= bit_cnt + 1;
            end if;
        end if;
    end process cnt_proc;

    rx_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                rx_sh <= (others => '0');
            elsif start = '1' then
                rx_sh <= (others => '0');
            elsif sclk_rise = '1' and bit_cnt /= WIDTH then
                rx_sh <= rx_sh(WIDTH-2 downto 0) & mosi_i;
            end if;
        end if;
    end process rx_proc;

    tx_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                tx_sh <= (others => '0');
            elsif start = '1' then
                tx_sh <= tx_data_i;
            elsif sclk_fall = '1' then
                tx_sh <= tx_sh(WIDTH-2 downto 0) & '0';
            end if;
        end if;
    end process tx_proc;

    miso_o     <= tx_sh(WIDTH-1);
    rx_data_o  <= rx_sh;
    rx_bits_o  <= std_logic_vector(bit_cnt);
    rx_valid_o <= stop;

end architecture rtl;
