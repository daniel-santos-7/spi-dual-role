----------------------------------------------------------------------
-- Leaf project
-- developed by: Daniel Santos
-- module: SPI port (shared pins, master or slave)
-- 2026
----------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;

entity spi_port is
    generic (
        SCK_DIV        : positive := 1;
        CS_HIGH_CYCLES : positive := 2;
        M_WIDTH        : positive := 64;
        M_CNT_BITS     : positive := 7;
        S_WIDTH        : positive := 32;
        S_CNT_BITS     : positive := 6
    );
    port (
        clk_i        : in  std_logic;
        rst_i        : in  std_logic;
        dbg_i        : in  std_logic;
        dbg_o        : out std_logic;
        sclk_i       : in  std_logic;
        sclk_o       : out std_logic;
        sclk_oe      : out std_logic;
        cs_n_i       : in  std_logic;
        cs_n_o       : out std_logic;
        cs_n_oe      : out std_logic;
        mosi_i       : in  std_logic;
        mosi_o       : out std_logic;
        mosi_oe      : out std_logic;
        miso_i       : in  std_logic;
        miso_o       : out std_logic;
        miso_oe      : out std_logic;
        m_start_i    : in  std_logic;
        m_ready_o    : out std_logic;
        m_tx_data_i  : in  std_logic_vector(M_WIDTH-1 downto 0);
        m_rx_data_o  : out std_logic_vector(M_WIDTH-1 downto 0);
        m_rx_valid_o : out std_logic;
        s_rx_data_o  : out std_logic_vector(S_WIDTH-1 downto 0);
        s_rx_bits_o  : out std_logic_vector(S_CNT_BITS-1 downto 0);
        s_rx_valid_o : out std_logic;
        s_tx_data_i  : in  std_logic_vector(S_WIDTH-1 downto 0)
    );
end entity spi_port;

architecture rtl of spi_port is

    signal dbg        : std_logic;
    signal m_start    : std_logic;
    signal s_cs_n     : std_logic;
    signal s_sclk     : std_logic;
    signal s_cs_n_s   : std_logic;
    signal s_mosi     : std_logic;

begin

    spi_port_sync: entity work.spi_sync port map (
        clk_i  => clk_i,
        rst_i  => rst_i,
        dbg_i  => dbg_i,
        sclk_i => sclk_i,
        cs_n_i => s_cs_n,
        mosi_i => mosi_i,
        dbg_o  => dbg,
        sclk_o => s_sclk,
        cs_n_o => s_cs_n_s,
        mosi_o => s_mosi
    );

    m_start    <= m_start_i and not dbg;
    s_cs_n     <= cs_n_i or not dbg;

    spi_port_master: entity work.spi_master generic map (
        SCK_DIV        => SCK_DIV,
        CS_HIGH_CYCLES => CS_HIGH_CYCLES,
        WIDTH          => M_WIDTH,
        CNT_BITS       => M_CNT_BITS
    ) port map (
        clk_i      => clk_i,
        rst_i      => rst_i,
        sclk_o     => sclk_o,
        cs_n_o     => cs_n_o,
        mosi_o     => mosi_o,
        miso_i     => miso_i,
        start_i    => m_start,
        ready_o    => m_ready_o,
        tx_data_i  => m_tx_data_i,
        rx_data_o  => m_rx_data_o,
        rx_valid_o => m_rx_valid_o
    );

    spi_port_slave: entity work.spi_slave generic map (
        WIDTH    => S_WIDTH,
        CNT_BITS => S_CNT_BITS
    ) port map (
        clk_i      => clk_i,
        rst_i      => rst_i,
        sclk_i     => s_sclk,
        cs_n_i     => s_cs_n_s,
        mosi_i     => s_mosi,
        miso_o     => miso_o,
        rx_data_o  => s_rx_data_o,
        rx_bits_o  => s_rx_bits_o,
        rx_valid_o => s_rx_valid_o,
        tx_data_i  => s_tx_data_i
    );

    sclk_oe <= not dbg;
    cs_n_oe <= not dbg;
    mosi_oe <= not dbg;
    miso_oe <= dbg and not cs_n_i;
    dbg_o   <= dbg;

end architecture rtl;
