----------------------------------------------------------------------
-- Leaf project
-- developed by: Daniel Santos
-- module: SPI slave (mode 0, word per frame)
-- 2026
----------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;

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

begin

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

    spi_slave_shift: entity work.spi_shift generic map (
        WIDTH    => WIDTH,
        CNT_BITS => CNT_BITS
    ) port map (
        clk_i      => clk_i,
        rst_i      => rst_i,
        start_i    => start,
        stop_i     => stop,
        rise_i     => sclk_rise,
        fall_i     => sclk_fall,
        din_i      => mosi_i,
        dout_o     => miso_o,
        tx_data_i  => tx_data_i,
        rx_data_o  => rx_data_o,
        rx_bits_o  => rx_bits_o,
        rx_valid_o => rx_valid_o
    );

end architecture rtl;
