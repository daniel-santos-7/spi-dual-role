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
        CS_HIGH_CYCLES : positive := 2
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
        m_tx_data_i  : in  std_logic_vector(7 downto 0);
        m_tx_last_i  : in  std_logic;
        m_tx_valid_i : in  std_logic;
        m_tx_ready_o : out std_logic;
        m_rx_data_o  : out std_logic_vector(7 downto 0);
        m_rx_valid_o : out std_logic;
        s_active_o   : out std_logic;
        s_rx_data_o  : out std_logic_vector(7 downto 0);
        s_rx_valid_o : out std_logic;
        s_tx_data_i  : in  std_logic_vector(7 downto 0);
        s_tx_valid_i : in  std_logic;
        s_tx_ready_o : out std_logic
    );
end entity spi_port;

architecture rtl of spi_port is

    signal dbg        : std_logic;
    signal m_tx_valid : std_logic;
    signal s_cs_n     : std_logic;
    signal s_sclk     : std_logic;
    signal s_cs_n_s   : std_logic;
    signal s_mosi     : std_logic;

begin

    u_sync: entity work.spi_sync port map (
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

    m_tx_valid <= m_tx_valid_i and not dbg;
    s_cs_n     <= cs_n_i or not dbg;

    u_master: entity work.spi_master generic map (
        SCK_DIV        => SCK_DIV,
        CS_HIGH_CYCLES => CS_HIGH_CYCLES
    ) port map (
        clk_i      => clk_i,
        rst_i      => rst_i,
        sclk_o     => sclk_o,
        cs_n_o     => cs_n_o,
        mosi_o     => mosi_o,
        miso_i     => miso_i,
        tx_data_i  => m_tx_data_i,
        tx_last_i  => m_tx_last_i,
        tx_valid_i => m_tx_valid,
        tx_ready_o => m_tx_ready_o,
        rx_data_o  => m_rx_data_o,
        rx_valid_o => m_rx_valid_o
    );

    u_slave: entity work.spi_slave port map (
        clk_i      => clk_i,
        rst_i      => rst_i,
        sclk_i     => s_sclk,
        cs_n_i     => s_cs_n_s,
        mosi_i     => s_mosi,
        miso_o     => miso_o,
        active_o   => s_active_o,
        rx_data_o  => s_rx_data_o,
        rx_valid_o => s_rx_valid_o,
        tx_data_i  => s_tx_data_i,
        tx_valid_i => s_tx_valid_i,
        tx_ready_o => s_tx_ready_o
    );

    sclk_oe <= not dbg;
    cs_n_oe <= not dbg;
    mosi_oe <= not dbg;
    miso_oe <= dbg and not cs_n_i;
    dbg_o   <= dbg;

end architecture rtl;
