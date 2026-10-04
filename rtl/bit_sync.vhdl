----------------------------------------------------------------------
-- Leaf project
-- developed by: Daniel Santos
-- module: single-bit synchroniser (flip-flop chain)
-- 2026
----------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;

entity bit_sync is
    generic (
        STAGES  : positive  := 2;  -- flip-flops in the chain (at least 2)
        RST_VAL : std_logic := '0' -- value of the whole chain during reset
    );
    port (
        clk_i : in  std_logic;
        rst_i : in  std_logic;
        d_i   : in  std_logic;  -- asynchronous input
        q_o   : out std_logic   -- d_i in the clk_i domain, STAGES cycles later
    );
end entity bit_sync;

architecture rtl of bit_sync is

    signal sync : std_logic_vector(STAGES-1 downto 0);

begin

    assert STAGES >= 2 report "bit_sync: STAGES must be at least 2." severity failure;

    sync_proc: process(clk_i)
    begin
        if rising_edge(clk_i) then
            if rst_i = '1' then
                sync <= (others => RST_VAL);
            else
                sync <= sync(STAGES-2 downto 0) & d_i;
            end if;
        end if;
    end process sync_proc;

    q_o <= sync(STAGES-1);

end architecture rtl;
