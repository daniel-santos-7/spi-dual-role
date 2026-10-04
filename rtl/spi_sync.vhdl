----------------------------------------------------------------------
-- Leaf project
-- developed by: Daniel Santos
-- module: SPI port input synchronisers
-- 2026
----------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;

entity spi_sync is
    port (
        clk_i  : in  std_logic;
        rst_i  : in  std_logic;
        dbg_i  : in  std_logic;  -- role strap
        sclk_i : in  std_logic;
        cs_n_i : in  std_logic;  -- CS# as the slave should see it
        mosi_i : in  std_logic;
        dbg_o  : out std_logic;  -- outputs: inputs in the clk_i domain,
        sclk_o : out std_logic;  -- two cycles later
        cs_n_o : out std_logic;
        mosi_o : out std_logic
    );
end entity spi_sync;

architecture rtl of spi_sync is
begin

    u_dbg_sync: entity work.bit_sync generic map (
        STAGES  => 2,
        RST_VAL => '0'
    ) port map (
        clk_i => clk_i,
        rst_i => rst_i,
        d_i   => dbg_i,
        q_o   => dbg_o
    );

    u_sclk_sync: entity work.bit_sync generic map (
        STAGES  => 2,
        RST_VAL => '0'
    ) port map (
        clk_i => clk_i,
        rst_i => rst_i,
        d_i   => sclk_i,
        q_o   => sclk_o
    );

    u_cs_sync: entity work.bit_sync generic map (
        STAGES  => 2,
        RST_VAL => '1'
    ) port map (
        clk_i => clk_i,
        rst_i => rst_i,
        d_i   => cs_n_i,
        q_o   => cs_n_o
    );

    u_mosi_sync: entity work.bit_sync generic map (
        STAGES  => 2,
        RST_VAL => '0'
    ) port map (
        clk_i => clk_i,
        rst_i => rst_i,
        d_i   => mosi_i,
        q_o   => mosi_o
    );

end architecture rtl;
