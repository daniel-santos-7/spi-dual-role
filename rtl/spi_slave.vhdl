----------------------------------------------------------------------
-- Leaf project
-- developed by: Daniel Santos
-- module: SPI slave timing (shift strobes from SCK and CS#)
-- 2026
----------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;

entity spi_slave is
    port (
        clk_i   : in  std_logic;
        rst_i   : in  std_logic;
        sclk_i  : in  std_logic;  -- sclk_i and cs_n_i must already be
        cs_n_i  : in  std_logic;  -- synchronised to clk_i (spi_port does it)
        start_o : out std_logic;
        stop_o  : out std_logic;
        rise_o  : out std_logic;
        fall_o  : out std_logic
    );
end entity spi_slave;

architecture rtl of spi_slave is

    signal sclk_reg : std_logic;
    signal cs_n_reg : std_logic;

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

    start_o <= cs_n_reg and not cs_n_i;
    stop_o  <= cs_n_i and not cs_n_reg;
    rise_o  <= sclk_i and not sclk_reg and not cs_n_i;
    fall_o  <= sclk_reg and not sclk_i and not cs_n_i;

end architecture rtl;
