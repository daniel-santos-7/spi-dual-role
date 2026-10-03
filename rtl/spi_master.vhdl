----------------------------------------------------------------------
-- Leaf project
-- developed by: Daniel Santos
-- module: SPI master (mode 0, byte interface)
-- 2026
----------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;

entity spi_master is
    generic (
        SCK_DIV        : positive := 1;
        CS_HIGH_CYCLES : positive := 2
    );
    port (
        clk_i      : in  std_logic;
        rst_i      : in  std_logic;
        sclk_o     : out std_logic;
        cs_n_o     : out std_logic;
        mosi_o     : out std_logic;
        miso_i     : in  std_logic;
        tx_data_i  : in  std_logic_vector(7 downto 0);
        tx_last_i  : in  std_logic;
        tx_valid_i : in  std_logic;
        tx_ready_o : out std_logic;
        rx_data_o  : out std_logic_vector(7 downto 0);
        rx_valid_o : out std_logic
    );
end entity spi_master;

architecture rtl of spi_master is

    type state_t is (IDLE, SHIFT, WAIT_TX);

    signal state    : state_t;
    signal sclk     : std_logic;
    signal cs_n     : std_logic;
    signal mosi     : std_logic;
    signal bit_cnt  : natural range 0 to 7;
    signal div_cnt  : natural range 0 to SCK_DIV-1;
    signal hi_cnt   : natural range 0 to CS_HIGH_CYCLES-1;
    signal tx_shift : std_logic_vector(6 downto 0);
    signal rx_shift : std_logic_vector(7 downto 0);
    signal last_reg : std_logic;
    signal rx_valid : std_logic;
    signal hold_ok  : std_logic;
    signal fall     : std_logic;
    signal tx_ready : std_logic;
    signal load     : std_logic;

begin

    assert CS_HIGH_CYCLES >= 2 report "SPI master: CS_HIGH_CYCLES must be at least 2." severity failure;

    hold_ok  <= '1' when hi_cnt = CS_HIGH_CYCLES-1 else '0';
    fall     <= '1' when state = SHIFT and div_cnt = SCK_DIV-1 and sclk = '1' else '0';
    tx_ready <= '1' when (state = IDLE and hold_ok = '1') or state = WAIT_TX or (fall = '1' and bit_cnt = 7 and last_reg = '0') else '0';
    load     <= tx_valid_i and tx_ready;

    shift_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                state    <= IDLE;
                sclk     <= '0';
                cs_n     <= '1';
                mosi     <= '0';
                bit_cnt  <= 0;
                div_cnt  <= 0;
                tx_shift <= (others => '0');
                rx_shift <= (others => '0');
                last_reg <= '0';
                rx_valid <= '0';
            else
                rx_valid <= '0';
                if load = '1' then
                    cs_n     <= '0';
                    mosi     <= tx_data_i(7);
                    tx_shift <= tx_data_i(6 downto 0);
                    last_reg <= tx_last_i;
                    bit_cnt  <= 0;
                    div_cnt  <= 0;
                    sclk     <= '0';
                    state    <= SHIFT;
                    if fall = '1' then
                        rx_valid <= '1';
                    end if;
                elsif state = SHIFT then
                    if div_cnt /= SCK_DIV-1 then
                        div_cnt <= div_cnt + 1;
                    else
                        div_cnt <= 0;
                        if sclk = '0' then
                            sclk     <= '1';
                            rx_shift <= rx_shift(6 downto 0) & miso_i;
                        else
                            sclk <= '0';
                            if bit_cnt = 7 then
                                rx_valid <= '1';
                                if last_reg = '1' then
                                    cs_n  <= '1';
                                    mosi  <= '0';
                                    state <= IDLE;
                                else
                                    state <= WAIT_TX;
                                end if;
                            else
                                mosi     <= tx_shift(6);
                                tx_shift <= tx_shift(5 downto 0) & '0';
                                bit_cnt  <= bit_cnt + 1;
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process shift_proc;

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

    sclk_o     <= sclk;
    cs_n_o     <= cs_n;
    mosi_o     <= mosi;
    tx_ready_o <= tx_ready;
    rx_data_o  <= rx_shift;
    rx_valid_o <= rx_valid;

end architecture rtl;
