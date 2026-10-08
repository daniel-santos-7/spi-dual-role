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

    type state_t is (IDLE, SCK_LO, SCK_HI, HOLD);

    signal state    : state_t;
    signal cnt      : natural range 0 to SCK_DIV + CS_HIGH_CYCLES;
    signal sclk     : std_logic;
    signal cs_n     : std_logic;
    signal stop_reg : std_logic;

    signal ready    : std_logic;
    signal rise     : std_logic;
    signal fall     : std_logic;
    signal last     : std_logic;

begin

    assert CS_HIGH_CYCLES >= 2 report "SPI master: CS_HIGH_CYCLES must be at least 2." severity failure;

    ready <= '1' when state = IDLE else '0';
    rise  <= '1' when state = SCK_LO and cnt = SCK_DIV-1 else '0';
    fall  <= '1' when state = SCK_HI and cnt = SCK_DIV-1 else '0';
    last  <= '1' when fall = '1' and unsigned(bits_i) = WIDTH else '0';

    fsm_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                state <= IDLE;
                cnt   <= 0;
                sclk  <= '0';
                cs_n  <= '1';
            else
                case state is
                    when IDLE =>
                        if start_i = '1' then
                            state <= SCK_LO;
                            cnt   <= 0;
                            cs_n  <= '0';
                        end if;
                    when SCK_LO =>
                        if cnt = SCK_DIV-1 then
                            state <= SCK_HI;
                            cnt   <= 0;
                            sclk  <= '1';
                        else
                            cnt <= cnt + 1;
                        end if;
                    when SCK_HI =>
                        if cnt = SCK_DIV-1 then
                            cnt  <= 0;
                            sclk <= '0';
                            if unsigned(bits_i) = WIDTH then
                                state <= HOLD;
                                cs_n  <= '1';
                            else
                                state <= SCK_LO;
                            end if;
                        else
                            cnt <= cnt + 1;
                        end if;
                    when HOLD =>
                        if cnt = CS_HIGH_CYCLES-2 then
                            state <= IDLE;
                            cnt   <= 0;
                        else
                            cnt <= cnt + 1;
                        end if;
                end case;
            end if;
        end if;
    end process fsm_proc;

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

    sclk_o  <= sclk;
    cs_n_o  <= cs_n;
    ready_o <= ready;
    start_o <= start_i and ready;
    stop_o  <= stop_reg;
    rise_o  <= rise;
    fall_o  <= fall;

end architecture rtl;
