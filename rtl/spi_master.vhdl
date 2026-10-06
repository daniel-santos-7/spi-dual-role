----------------------------------------------------------------------
-- Leaf project
-- developed by: Daniel Santos
-- module: SPI master (mode 0, word per frame)
-- 2026
----------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;

entity spi_master is
    generic (
        SCK_DIV        : positive := 1;
        CS_HIGH_CYCLES : positive := 2;
        WIDTH          : positive := 64;
        CNT_BITS       : positive := 7
    );
    port (
        clk_i      : in  std_logic;
        rst_i      : in  std_logic;
        sclk_o     : out std_logic;
        cs_n_o     : out std_logic;
        mosi_o     : out std_logic;
        miso_i     : in  std_logic;
        start_i    : in  std_logic;
        ready_o    : out std_logic;
        tx_data_i  : in  std_logic_vector(WIDTH-1 downto 0);
        rx_data_o  : out std_logic_vector(WIDTH-1 downto 0);
        rx_valid_o : out std_logic
    );
end entity spi_master;

architecture rtl of spi_master is

    signal busy     : std_logic;
    signal sclk     : std_logic;
    signal cs_n     : std_logic;
    signal div_cnt  : natural range 0 to SCK_DIV-1;
    signal bit_cnt  : natural range 0 to WIDTH-1;
    signal hi_cnt   : natural range 0 to CS_HIGH_CYCLES-1;
    signal stop_reg : std_logic;

    signal ready    : std_logic;
    signal start    : std_logic;
    signal tick     : std_logic;
    signal rise     : std_logic;
    signal fall     : std_logic;
    signal last     : std_logic;

begin

    assert CS_HIGH_CYCLES >= 2 report "SPI master: CS_HIGH_CYCLES must be at least 2." severity failure;

    ready <= '1' when busy = '0' and hi_cnt = CS_HIGH_CYCLES-1 else '0';
    start <= start_i and ready;
    tick  <= '1' when busy = '1' and div_cnt = SCK_DIV-1 else '0';
    rise  <= tick and not sclk;
    fall  <= tick and sclk;
    last  <= '1' when fall = '1' and bit_cnt = WIDTH-1 else '0';

    frame_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                busy <= '0';
                cs_n <= '1';
            elsif start = '1' then
                busy <= '1';
                cs_n <= '0';
            elsif last = '1' then
                busy <= '0';
                cs_n <= '1';
            end if;
        end if;
    end process frame_proc;

    div_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                div_cnt <= 0;
            elsif start = '1' then
                div_cnt <= 0;
            elsif busy = '1' and div_cnt /= SCK_DIV-1 then
                div_cnt <= div_cnt + 1;
            elsif tick = '1' then
                div_cnt <= 0;
            end if;
        end if;
    end process div_proc;

    sclk_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                sclk <= '0';
            elsif rise = '1' then
                sclk <= '1';
            elsif fall = '1' then
                sclk <= '0';
            end if;
        end if;
    end process sclk_proc;

    bit_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                bit_cnt <= 0;
            elsif start = '1' then
                bit_cnt <= 0;
            elsif fall = '1' and last = '0' then
                bit_cnt <= bit_cnt + 1;
            end if;
        end if;
    end process bit_proc;

    stop_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                stop_reg <= '0';
            else
                stop_reg <= last;
            end if;
        end if;
    end process stop_proc;

    hi_cnt_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                hi_cnt <= CS_HIGH_CYCLES-1;
            elsif cs_n = '0' then
                hi_cnt <= 0;
            elsif hi_cnt /= CS_HIGH_CYCLES-1 then
                hi_cnt <= hi_cnt + 1;
            end if;
        end if;
    end process hi_cnt_proc;

    spi_master_shift: entity work.spi_shift generic map (
        WIDTH    => WIDTH,
        CNT_BITS => CNT_BITS
    ) port map (
        clk_i      => clk_i,
        rst_i      => rst_i,
        start_i    => start,
        stop_i     => stop_reg,
        rise_i     => rise,
        fall_i     => fall,
        din_i      => miso_i,
        dout_o     => mosi_o,
        tx_data_i  => tx_data_i,
        rx_data_o  => rx_data_o,
        rx_bits_o  => open,
        rx_valid_o => rx_valid_o
    );

    sclk_o  <= sclk;
    cs_n_o  <= cs_n;
    ready_o <= ready;

end architecture rtl;
