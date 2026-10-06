----------------------------------------------------------------------
-- Leaf project
-- developed by: Daniel Santos
-- module: SPI master timing (SCK, CS# and shift strobes)
-- 2026
----------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity spi_master is
    generic (
        SCK_DIV        : positive := 1;
        CS_HIGH_CYCLES : positive := 2;
        WIDTH          : positive := 64;
        CNT_BITS       : positive := 7
    );
    port (
        clk_i   : in  std_logic;
        rst_i   : in  std_logic;
        sclk_o  : out std_logic;
        cs_n_o  : out std_logic;
        start_i : in  std_logic;
        ready_o : out std_logic;
        bits_i  : in  std_logic_vector(CNT_BITS-1 downto 0);
        start_o : out std_logic;
        stop_o  : out std_logic;
        rise_o  : out std_logic;
        fall_o  : out std_logic
    );
end entity spi_master;

architecture rtl of spi_master is

    signal busy     : std_logic;
    signal sclk     : std_logic;
    signal cs_n     : std_logic;
    signal div_cnt  : natural range 0 to SCK_DIV-1;
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
    last  <= '1' when fall = '1' and unsigned(bits_i) = WIDTH else '0';

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

    sclk_o  <= sclk;
    cs_n_o  <= cs_n;
    ready_o <= ready;
    start_o <= start;
    stop_o  <= stop_reg;
    rise_o  <= rise;
    fall_o  <= fall;

end architecture rtl;
