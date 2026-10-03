----------------------------------------------------------------------
-- Leaf project
-- developed by: Daniel Santos
-- module: SPI slave (mode 0, byte interface)
-- 2026
----------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity spi_slave is
    port (
        clk_i      : in  std_logic;
        rst_i      : in  std_logic;
        sclk_i     : in  std_logic;
        cs_n_i     : in  std_logic;
        mosi_i     : in  std_logic;
        miso_o     : out std_logic;
        active_o   : out std_logic;
        rx_data_o  : out std_logic_vector(7 downto 0);
        rx_valid_o : out std_logic;
        tx_data_i  : in  std_logic_vector(7 downto 0);
        tx_valid_i : in  std_logic;
        tx_ready_o : out std_logic
    );
end entity spi_slave;

architecture rtl of spi_slave is

    signal sclk_s : std_logic_vector(2 downto 0);
    signal cs_s   : std_logic_vector(1 downto 0);
    signal mosi_s : std_logic_vector(1 downto 0);

    signal cs_act    : std_logic;
    signal sclk_rise : std_logic;
    signal sclk_fall : std_logic;

    signal bit_cnt : unsigned(2 downto 0);
    signal rx_sh   : std_logic_vector(6 downto 0);
    signal tx_sh   : std_logic_vector(7 downto 0);
    signal tx_load : std_logic;
    signal tx_buf  : std_logic_vector(7 downto 0);
    signal tx_full : std_logic;

begin

    sync_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                sclk_s <= (others => '0');
                cs_s   <= (others => '1');
                mosi_s <= (others => '0');
            else
                sclk_s <= sclk_s(1 downto 0) & sclk_i;
                cs_s   <= cs_s(0) & cs_n_i;
                mosi_s <= mosi_s(0) & mosi_i;
            end if;
        end if;
    end process sync_proc;

    cs_act    <= not cs_s(1);
    sclk_rise <= sclk_s(1) and not sclk_s(2);
    sclk_fall <= sclk_s(2) and not sclk_s(1);
    tx_load   <= '1' when cs_act = '1' and sclk_fall = '1' and bit_cnt = 0 else '0';

    shift_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                bit_cnt <= (others => '0');
                rx_sh   <= (others => '0');
                tx_sh   <= (others => '0');
                tx_buf  <= (others => '0');
                tx_full <= '0';
            elsif cs_act = '0' then
                bit_cnt <= (others => '0');
                tx_sh   <= (others => '0');
                tx_full <= '0';
            else
                if sclk_rise = '1' then
                    rx_sh   <= rx_sh(5 downto 0) & mosi_s(1);
                    bit_cnt <= bit_cnt + 1;
                end if;
                if tx_load = '1' then
                    tx_full <= '0';
                    if tx_full = '1' then
                        tx_sh <= tx_buf;
                    elsif tx_valid_i = '1' then
                        tx_sh <= tx_data_i;
                    else
                        tx_sh <= (others => '0');
                    end if;
                elsif sclk_fall = '1' then
                    tx_sh <= tx_sh(6 downto 0) & '0';
                elsif (tx_valid_i and not tx_full) = '1' then
                    tx_buf  <= tx_data_i;
                    tx_full <= '1';
                end if;
            end if;
        end if;
    end process shift_proc;

    miso_o     <= tx_sh(7);
    active_o   <= cs_act;
    rx_data_o  <= rx_sh & mosi_s(1);
    rx_valid_o <= '1' when cs_act = '1' and sclk_rise = '1' and bit_cnt = 7 else '0';
    tx_ready_o <= not tx_full;

end architecture rtl;
