----------------------------------------------------------------------
-- Leaf project
-- developed by: Daniel Santos
-- module: SPI port testbench (two ports on one bus, master <-> slave)
-- 2026
----------------------------------------------------------------------
--
-- Two spi_port instances, A and B, share one set of pads modelled as
-- resolved signals with pull resistors (CS# up, SCK/MOSI/MISO down).
-- Phase 0 straps A as master and B as slave; phase 1 swaps the roles.
--
-- Each frame has a random length (1 to 6 bytes, so shorter, equal and
-- longer than the slave word) and random data. The master client
-- inserts short gaps (SCK keeps running) and long gaps (SCK stalls)
-- and sometimes starts the next frame back to back. The slave client
-- puts a random reply word on tx_data for every frame, changing it
-- as soon as the previous frame ends.
--
-- Checks: the word, bit count and single rx_valid the slave reports
-- after each frame, the reply bits the master receives (the word MSB
-- first, then zeros), CS# high time, SCK phases, MOSI/MISO changing
-- only while SCK is low, frame length with no gaps, pad contention,
-- pin release, and that the unused role inside each port stays silent
-- while its client drives junk.
--
----------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use IEEE.math_real.all;

entity tb_spi_port is
    generic (
        SCK_DIV        : positive := 5;
        CS_HIGH_CYCLES : positive := 2;
        NUM_FRAMES     : positive := 60;
        SEED           : positive := 1;
        S_WIDTH        : positive := 32;
        S_CNT_BITS     : positive := 6
    );
end entity tb_spi_port;

architecture sim of tb_spi_port is

    constant CLK_PERIOD : time    := 10 ns;
    constant MAX_LEN    : integer := 6;
    constant MAX_BYTES  : integer := MAX_LEN * 2 * NUM_FRAMES;
    constant MAX_FRAMES : integer := 2 * NUM_FRAMES + 1;
    constant TIMEOUT    : time    := 2 * NUM_FRAMES * (MAX_LEN * (32 * SCK_DIV + 50) + 50) * CLK_PERIOD;

    subtype byte_t is std_logic_vector(7 downto 0);
    subtype word_t is std_logic_vector(S_WIDTH-1 downto 0);
    type byte_arr_t  is array (natural range <>) of byte_t;
    type word_arr_t  is array (natural range <>) of word_t;
    type int_arr_t   is array (natural range <>) of integer;

    function hex(v : byte_t) return string is
        constant DIGITS : string(1 to 16) := "0123456789ABCDEF";
        variable r      : string(1 to 2);
    begin
        if is_x(v) then
            return "XX";
        end if;
        r(1) := DIGITS(to_integer(unsigned(v(7 downto 4))) + 1);
        r(2) := DIGITS(to_integer(unsigned(v(3 downto 0))) + 1);
        return r;
    end function hex;

    function hexw(v : word_t) return string is
        variable p : std_logic_vector(((S_WIDTH+7)/8)*8-1 downto 0) := (others => '0');
        variable r : string(1 to 2*p'length/8);
    begin
        p(S_WIDTH-1 downto 0) := v;
        for i in 0 to (S_WIDTH+7)/8-1 loop
            r(2*i+1 to 2*i+2) := hex(p(p'high-8*i downto p'high-8*i-7));
        end loop;
        return r;
    end function hexw;

    -- clock, reset, control
    signal clk       : std_logic := '0';
    signal rst       : std_logic := '1';
    signal sim_done  : std_logic := '0';
    signal chk_on    : std_logic := '0';
    signal iso_check : std_logic := '0';
    signal junk_en   : std_logic := '0';
    signal swap      : std_logic := '0';
    signal strap_a   : std_logic := '0';
    signal strap_b   : std_logic := '1';

    -- pads and their logic levels
    signal sclk_pad : std_logic;
    signal cs_n_pad : std_logic;
    signal mosi_pad : std_logic;
    signal miso_pad : std_logic;
    signal sclk_in  : std_logic;
    signal cs_n_in  : std_logic;
    signal mosi_in  : std_logic;
    signal miso_in  : std_logic;

    -- port A
    signal a_dbg_o        : std_logic;
    signal a_sclk_o       : std_logic;
    signal a_sclk_oe      : std_logic;
    signal a_cs_n_o       : std_logic;
    signal a_cs_n_oe      : std_logic;
    signal a_mosi_o       : std_logic;
    signal a_mosi_oe      : std_logic;
    signal a_miso_o       : std_logic;
    signal a_miso_oe      : std_logic;
    signal a_m_tx_data    : byte_t;
    signal a_m_tx_last    : std_logic;
    signal a_m_tx_valid   : std_logic;
    signal a_m_tx_ready   : std_logic;
    signal a_m_rx_data    : byte_t;
    signal a_m_rx_valid   : std_logic;
    signal a_s_rx_data    : word_t;
    signal a_s_rx_bits    : std_logic_vector(S_CNT_BITS-1 downto 0);
    signal a_s_rx_valid   : std_logic;
    signal a_s_tx_data    : word_t;

    -- port B
    signal b_dbg_o        : std_logic;
    signal b_sclk_o       : std_logic;
    signal b_sclk_oe      : std_logic;
    signal b_cs_n_o       : std_logic;
    signal b_cs_n_oe      : std_logic;
    signal b_mosi_o       : std_logic;
    signal b_mosi_oe      : std_logic;
    signal b_miso_o       : std_logic;
    signal b_miso_oe      : std_logic;
    signal b_m_tx_data    : byte_t;
    signal b_m_tx_last    : std_logic;
    signal b_m_tx_valid   : std_logic;
    signal b_m_tx_ready   : std_logic;
    signal b_m_rx_data    : byte_t;
    signal b_m_rx_valid   : std_logic;
    signal b_s_rx_data    : word_t;
    signal b_s_rx_bits    : std_logic_vector(S_CNT_BITS-1 downto 0);
    signal b_s_rx_valid   : std_logic;
    signal b_s_tx_data    : word_t;

    -- master client (whichever port is strapped as master)
    signal m_tx_data  : byte_t    := (others => '0');
    signal m_tx_last  : std_logic := '0';
    signal m_tx_valid : std_logic := '0';
    signal m_tx_ready : std_logic;
    signal m_rx_data  : byte_t;
    signal m_rx_valid : std_logic;
    signal m_rx_cnt   : natural := 0;

    -- slave client (whichever port is strapped as slave)
    signal s_tx_data  : word_t;
    signal s_rx_data  : word_t;
    signal s_rx_bits  : std_logic_vector(S_CNT_BITS-1 downto 0);
    signal s_rx_valid : std_logic;
    signal s_rx_cnt   : natural := 0;

    -- test plan, indexed by byte number (all frames back to back) or frame number
    signal plan_cnt   : natural := 0;
    signal plan_mtx   : byte_arr_t(0 to MAX_BYTES-1);
    signal plan_mexp  : byte_arr_t(0 to MAX_BYTES-1);
    signal plan_last  : std_logic_vector(0 to MAX_BYTES-1) := (others => '0');
    signal plan_fcnt  : natural := 0;
    signal plan_sresp : word_arr_t(0 to MAX_FRAMES-1)      := (others => (others => '0'));
    signal plan_srx   : word_arr_t(0 to MAX_FRAMES-1);
    signal plan_sbits : int_arr_t(0 to MAX_FRAMES-1)       := (others => 0);
    signal plan_fend  : int_arr_t(0 to MAX_FRAMES-1)       := (others => 0);
    signal plan_dur   : int_arr_t(0 to MAX_FRAMES-1)       := (others => -1);
    signal plan_b2b   : std_logic_vector(0 to MAX_FRAMES-1) := (others => '0');

begin

    assert SCK_DIV >= 5 report "TB: the slave needs SCK <= clk/10, so SCK_DIV must be at least 5." severity failure;

    clk <= not clk after CLK_PERIOD / 2 when sim_done = '0' else '0';

    ------------------------------------------------------------------
    -- DUTs and bus
    ------------------------------------------------------------------

    tb_spi_port_a: entity work.spi_port generic map (
        SCK_DIV        => SCK_DIV,
        CS_HIGH_CYCLES => CS_HIGH_CYCLES,
        S_WIDTH        => S_WIDTH,
        S_CNT_BITS     => S_CNT_BITS
    ) port map (
        clk_i        => clk,
        rst_i        => rst,
        dbg_i        => strap_a,
        dbg_o        => a_dbg_o,
        sclk_i       => sclk_in,
        sclk_o       => a_sclk_o,
        sclk_oe      => a_sclk_oe,
        cs_n_i       => cs_n_in,
        cs_n_o       => a_cs_n_o,
        cs_n_oe      => a_cs_n_oe,
        mosi_i       => mosi_in,
        mosi_o       => a_mosi_o,
        mosi_oe      => a_mosi_oe,
        miso_i       => miso_in,
        miso_o       => a_miso_o,
        miso_oe      => a_miso_oe,
        m_tx_data_i  => a_m_tx_data,
        m_tx_last_i  => a_m_tx_last,
        m_tx_valid_i => a_m_tx_valid,
        m_tx_ready_o => a_m_tx_ready,
        m_rx_data_o  => a_m_rx_data,
        m_rx_valid_o => a_m_rx_valid,
        s_rx_data_o  => a_s_rx_data,
        s_rx_bits_o  => a_s_rx_bits,
        s_rx_valid_o => a_s_rx_valid,
        s_tx_data_i  => a_s_tx_data
    );

    tb_spi_port_b: entity work.spi_port generic map (
        SCK_DIV        => SCK_DIV,
        CS_HIGH_CYCLES => CS_HIGH_CYCLES,
        S_WIDTH        => S_WIDTH,
        S_CNT_BITS     => S_CNT_BITS
    ) port map (
        clk_i        => clk,
        rst_i        => rst,
        dbg_i        => strap_b,
        dbg_o        => b_dbg_o,
        sclk_i       => sclk_in,
        sclk_o       => b_sclk_o,
        sclk_oe      => b_sclk_oe,
        cs_n_i       => cs_n_in,
        cs_n_o       => b_cs_n_o,
        cs_n_oe      => b_cs_n_oe,
        mosi_i       => mosi_in,
        mosi_o       => b_mosi_o,
        mosi_oe      => b_mosi_oe,
        miso_i       => miso_in,
        miso_o       => b_miso_o,
        miso_oe      => b_miso_oe,
        m_tx_data_i  => b_m_tx_data,
        m_tx_last_i  => b_m_tx_last,
        m_tx_valid_i => b_m_tx_valid,
        m_tx_ready_o => b_m_tx_ready,
        m_rx_data_o  => b_m_rx_data,
        m_rx_valid_o => b_m_rx_valid,
        s_rx_data_o  => b_s_rx_data,
        s_rx_bits_o  => b_s_rx_bits,
        s_rx_valid_o => b_s_rx_valid,
        s_tx_data_i  => b_s_tx_data
    );

    sclk_pad <= a_sclk_o when a_sclk_oe = '1' else 'Z';
    sclk_pad <= b_sclk_o when b_sclk_oe = '1' else 'Z';
    sclk_pad <= 'L';
    cs_n_pad <= a_cs_n_o when a_cs_n_oe = '1' else 'Z';
    cs_n_pad <= b_cs_n_o when b_cs_n_oe = '1' else 'Z';
    cs_n_pad <= 'H';
    mosi_pad <= a_mosi_o when a_mosi_oe = '1' else 'Z';
    mosi_pad <= b_mosi_o when b_mosi_oe = '1' else 'Z';
    mosi_pad <= 'L';
    miso_pad <= a_miso_o when a_miso_oe = '1' else 'Z';
    miso_pad <= b_miso_o when b_miso_oe = '1' else 'Z';
    miso_pad <= 'L';

    sclk_in <= to_x01(sclk_pad);
    cs_n_in <= to_x01(cs_n_pad);
    mosi_in <= to_x01(mosi_pad);
    miso_in <= to_x01(miso_pad);

    -- Clients go to the port in that role; the port in the other role
    -- gets junk (valid held high) once junk_en is set.
    a_m_tx_data  <= m_tx_data  when swap = '0' else x"FF";
    a_m_tx_last  <= m_tx_last  when swap = '0' else '0';
    a_m_tx_valid <= m_tx_valid when swap = '0' else junk_en;
    b_m_tx_data  <= m_tx_data  when swap = '1' else x"FF";
    b_m_tx_last  <= m_tx_last  when swap = '1' else '0';
    b_m_tx_valid <= m_tx_valid when swap = '1' else junk_en;
    m_tx_ready   <= a_m_tx_ready when swap = '0' else b_m_tx_ready;
    m_rx_data    <= a_m_rx_data  when swap = '0' else b_m_rx_data;
    m_rx_valid   <= a_m_rx_valid when swap = '0' else b_m_rx_valid;

    a_s_tx_data  <= s_tx_data    when swap = '1' else (others => '1');
    b_s_tx_data  <= s_tx_data    when swap = '0' else (others => '1');
    s_rx_data    <= b_s_rx_data  when swap = '0' else a_s_rx_data;
    s_rx_bits    <= b_s_rx_bits  when swap = '0' else a_s_rx_bits;
    s_rx_valid   <= b_s_rx_valid when swap = '0' else a_s_rx_valid;

    ------------------------------------------------------------------
    -- Stimulus: test plan and master client
    ------------------------------------------------------------------

    stim_proc: process
        variable s1      : positive := SEED;
        variable s2      : positive := 7919;
        variable r       : real;
        variable v       : integer;
        variable n       : integer;
        variable g       : integer;
        variable p       : integer;
        variable idx     : natural := 0;
        variable frame   : natural := 0;
        variable stalled : boolean;
        variable fb      : byte_arr_t(0 to MAX_LEN-1);
        variable resp    : word_t;
        variable rxw     : word_t;
        variable eb      : byte_t;
        variable n_short : natural := 0;
        variable n_exact : natural := 0;
        variable n_long  : natural := 0;
        variable n_stall : natural := 0;
        variable n_b2b   : natural := 0;

        procedure rnd(lo, hi : in integer; x : out integer) is
            variable t : integer;
        begin
            uniform(s1, s2, r);
            t := lo + integer(trunc(r * real(hi - lo + 1)));
            if t > hi then
                t := hi;
            end if;
            x := t;
        end procedure rnd;

        procedure cycles(c : in natural) is
        begin
            for i in 1 to c loop
                wait until rising_edge(clk);
            end loop;
        end procedure cycles;
    begin
        rst <= '1';
        cycles(10);
        rst <= '0';
        cycles(10);
        chk_on    <= '1';
        junk_en   <= '1';
        iso_check <= '1';

        for ph in 0 to 1 loop
            if ph = 1 then
                -- strap A as slave too, check that nobody drives the bus,
                -- then strap B as master
                iso_check <= '0';
                junk_en   <= '0';
                strap_a   <= '1';
                cycles(10);
                assert sclk_pad = 'L' and cs_n_pad = 'H' and mosi_pad = 'L' and miso_pad = 'L'
                    report "TB: pins still driven with both ports strapped as slave" severity error;
                assert a_dbg_o = '1' and b_dbg_o = '1'
                    report "TB: dbg_o does not follow the strap" severity error;
                swap <= '1';
                cycles(1);
                strap_b <= '0';
                cycles(10);
                junk_en   <= '1';
                iso_check <= '1';
                report "TB: roles swapped, A is slave and B is master" severity note;
            end if;

            for f in 1 to NUM_FRAMES loop
                rnd(1, MAX_LEN, n);
                for i in resp'range loop
                    rnd(0, 1, v);
                    if v = 1 then
                        resp(i) := '1';
                    else
                        resp(i) := '0';
                    end if;
                end loop;
                rxw := (others => '0');
                for k in 0 to n-1 loop
                    rnd(0, 255, v);
                    fb(k) := std_logic_vector(to_unsigned(v, 8));
                    plan_mtx(idx+k) <= fb(k);
                    for i in 7 downto 0 loop
                        rxw := rxw(S_WIDTH-2 downto 0) & fb(k)(i);
                        p := 8*k + 7 - i;
                        if p < S_WIDTH then
                            eb(i) := resp(S_WIDTH-1-p);
                        else
                            eb(i) := '0';
                        end if;
                    end loop;
                    plan_mexp(idx+k) <= eb;
                    if k = n-1 then
                        plan_last(idx+k) <= '1';
                    end if;
                end loop;
                plan_sresp(frame) <= resp;
                plan_srx(frame)   <= rxw;
                if 8*n < S_WIDTH then
                    plan_sbits(frame) <= 8*n;
                    n_short := n_short + 1;
                elsif 8*n = S_WIDTH then
                    plan_sbits(frame) <= 8*n;
                    n_exact := n_exact + 1;
                else
                    plan_sbits(frame) <= S_WIDTH+1;
                    n_long := n_long + 1;
                end if;
                plan_fend(frame) <= idx + n;
                plan_cnt  <= idx + n;
                plan_fcnt <= frame + 1;

                stalled := false;
                for k in 0 to n-1 loop
                    if k > 0 then
                        rnd(0, 9, v);
                        if v = 0 then
                            rnd(16*SCK_DIV + 1, 16*SCK_DIV + 40, g);
                            stalled := true;
                            n_stall := n_stall + 1;
                        else
                            rnd(0, 3, g);
                        end if;
                        if g > 0 then
                            m_tx_valid <= '0';
                            cycles(g);
                        end if;
                    end if;
                    m_tx_data  <= fb(k);
                    m_tx_valid <= '1';
                    if k = n-1 then
                        m_tx_last <= '1';
                    end if;
                    loop
                        wait until rising_edge(clk);
                        exit when m_tx_ready = '1';
                    end loop;
                end loop;
                m_tx_valid <= '0';
                m_tx_last  <= '0';
                if not stalled then
                    plan_dur(frame) <= 16 * n * SCK_DIV;
                end if;
                idx   := idx + n;
                frame := frame + 1;

                rnd(0, 3, v);
                if v = 0 and f < NUM_FRAMES then
                    plan_b2b(frame) <= '1';
                    n_b2b := n_b2b + 1;
                else
                    rnd(1, 30, g);
                    cycles(g);
                end if;
            end loop;

            loop
                wait until rising_edge(clk);
                exit when m_rx_cnt = idx and s_rx_cnt = frame;
            end loop;
            cycles(10);
        end loop;

        assert n_short > 0 and n_exact > 0 and n_long > 0 and n_stall > 0 and n_b2b > 0
            report "TB: coverage hole (short=" & integer'image(n_short) & ", exact=" & integer'image(n_exact) &
                   ", long=" & integer'image(n_long) & ", stalls=" & integer'image(n_stall) &
                   ", back-to-back=" & integer'image(n_b2b) & ")"
            severity error;
        report "TB: PASS - " & integer'image(frame) & " frames, " & integer'image(idx) & " bytes each way (" &
               integer'image(n_short) & " shorter than the word, " & integer'image(n_exact) & " exact, " &
               integer'image(n_long) & " longer, " & integer'image(n_stall) & " SCK stalls, " &
               integer'image(n_b2b) & " back-to-back frames)"
            severity note;
        sim_done <= '1';
        wait;
    end process stim_proc;

    ------------------------------------------------------------------
    -- Slave client: checks each received word, sets the next reply
    ------------------------------------------------------------------

    s_tx_data <= plan_sresp(s_rx_cnt);

    slave_proc: process
        variable i : natural := 0;
    begin
        wait until rising_edge(clk);
        if chk_on = '1' and s_rx_valid = '1' then
            assert i < plan_fcnt
                report "slave: unexpected word " & hexw(s_rx_data) severity error;
            assert m_rx_cnt >= plan_fend(i)
                report "slave: rx_valid for frame " & integer'image(i) & " before the frame ended" severity error;
            assert to_integer(unsigned(s_rx_bits)) = plan_sbits(i)
                report "slave: frame " & integer'image(i) & " reported " & integer'image(to_integer(unsigned(s_rx_bits))) &
                       " bits, expected " & integer'image(plan_sbits(i)) severity error;
            assert s_rx_data = plan_srx(i)
                report "slave: frame " & integer'image(i) & " word is " & hexw(s_rx_data) &
                       ", expected " & hexw(plan_srx(i)) severity error;
            i := i + 1;
            s_rx_cnt <= i;
        end if;
    end process slave_proc;

    ------------------------------------------------------------------
    -- Master receive checker
    ------------------------------------------------------------------

    master_rx_proc: process
        variable j    : natural   := 0;
        variable cs_p : std_logic := '1';
        variable exp  : byte_t;
    begin
        wait until rising_edge(clk);
        if chk_on = '1' and m_rx_valid = '1' then
            assert j < plan_cnt
                report "master: unexpected byte " & hex(m_rx_data) severity error;
            exp := plan_mexp(j);
            assert m_rx_data = exp
                report "master: byte " & integer'image(j) & " is " & hex(m_rx_data) &
                       ", expected " & hex(exp) severity error;
            if plan_last(j) = '1' then
                assert cs_n_in = '1' and cs_p = '0'
                    report "master: last byte of a frame not flagged in the first cycle with CS# high" severity error;
            else
                assert cs_n_in = '0'
                    report "master: byte " & integer'image(j) & " flagged with CS# high" severity error;
            end if;
            j := j + 1;
            m_rx_cnt <= j;
        end if;
        cs_p := cs_n_in;
    end process master_rx_proc;

    ------------------------------------------------------------------
    -- Bus monitor: protocol, timing, contention, role isolation
    ------------------------------------------------------------------

    bus_mon_proc: process
        variable sclk_p : std_logic;
        variable cs_p   : std_logic;
        variable mosi_p : std_logic;
        variable miso_p : std_logic;
        variable phase  : natural := 0;
        variable lo_cnt : natural := 0;
        variable hi_cnt : natural := CS_HIGH_CYCLES;
        variable frame  : natural := 0;
    begin
        wait until rising_edge(clk) and chk_on = '1';
        sclk_p := sclk_in;
        cs_p   := cs_n_in;
        mosi_p := mosi_in;
        miso_p := miso_in;
        loop
            wait until rising_edge(clk);

            assert sclk_in /= 'X' and cs_n_in /= 'X' and mosi_in /= 'X' and miso_in /= 'X'
                report "bus: contention on a pad" severity error;

            if cs_n_in = '1' then
                assert sclk_in = '0'
                    report "bus: SCK high while CS# is high" severity error;
                assert miso_pad = 'L'
                    report "bus: MISO driven while CS# is high" severity error;
            end if;

            -- frame boundaries
            if cs_p = '1' and cs_n_in = '0' then
                assert sclk_in = '0'
                    report "bus: SCK high when CS# falls" severity error;
                assert hi_cnt >= CS_HIGH_CYCLES
                    report "bus: CS# high for " & integer'image(hi_cnt) & " cycles before frame " &
                           integer'image(frame) severity error;
                if plan_b2b(frame) = '1' then
                    assert hi_cnt = CS_HIGH_CYCLES
                        report "bus: back-to-back frame " & integer'image(frame) & " waited " &
                               integer'image(hi_cnt) & " cycles with CS# high" severity error;
                end if;
                lo_cnt := 0;
                phase  := 0;
            elsif cs_p = '0' and cs_n_in = '1' then
                if plan_dur(frame) >= 0 then
                    assert lo_cnt = plan_dur(frame)
                        report "bus: frame " & integer'image(frame) & " had CS# low for " & integer'image(lo_cnt) &
                               " cycles, expected " & integer'image(plan_dur(frame)) severity error;
                end if;
                if sclk_p = '1' then
                    assert phase = SCK_DIV
                        report "bus: last SCK high phase lasted " & integer'image(phase) & " cycles" severity error;
                end if;
                frame  := frame + 1;
                hi_cnt := 0;
            end if;
            if cs_n_in = '0' then
                lo_cnt := lo_cnt + 1;
            else
                hi_cnt := hi_cnt + 1;
            end if;

            -- SCK phases and data changes inside a frame
            if cs_n_in = '0' then
                if sclk_in /= sclk_p and phase > 0 then
                    if sclk_p = '1' then
                        assert phase = SCK_DIV
                            report "bus: SCK high phase lasted " & integer'image(phase) & " cycles" severity error;
                    else
                        assert phase >= SCK_DIV
                            report "bus: SCK low phase lasted " & integer'image(phase) & " cycles" severity error;
                    end if;
                    phase := 1;
                else
                    phase := phase + 1;
                end if;
                if cs_p = '0' then
                    assert mosi_in = mosi_p or sclk_in = '0'
                        report "bus: MOSI changed while SCK is high" severity error;
                    assert miso_in = miso_p or sclk_in = '0'
                        report "bus: MISO changed while SCK is high" severity error;
                end if;
            end if;

            -- pins driven by the right port, unused roles silent
            if iso_check = '1' then
                assert (sclk_pad = '0' or sclk_pad = '1') and (cs_n_pad = '0' or cs_n_pad = '1') and
                       (mosi_pad = '0' or mosi_pad = '1')
                    report "bus: master pins not driven" severity error;
                if cs_n_in = '0' then
                    assert miso_pad = '0' or miso_pad = '1'
                        report "bus: MISO not driven by the slave while CS# is low" severity error;
                end if;
                if swap = '0' then
                    assert a_dbg_o = '0' and b_dbg_o = '1'
                        report "bus: dbg_o does not follow the strap" severity error;
                    assert a_s_rx_valid = '0'
                        report "bus: slave inside the master-strapped port A reported a frame" severity error;
                    assert b_m_rx_valid = '0'
                        report "bus: master inside the slave-strapped port B ran a frame" severity error;
                else
                    assert a_dbg_o = '1' and b_dbg_o = '0'
                        report "bus: dbg_o does not follow the strap" severity error;
                    assert b_s_rx_valid = '0'
                        report "bus: slave inside the master-strapped port B reported a frame" severity error;
                    assert a_m_rx_valid = '0'
                        report "bus: master inside the slave-strapped port A ran a frame" severity error;
                end if;
            end if;

            sclk_p := sclk_in;
            cs_p   := cs_n_in;
            mosi_p := mosi_in;
            miso_p := miso_in;
        end loop;
    end process bus_mon_proc;

    watchdog_proc: process
    begin
        wait until sim_done = '1' for TIMEOUT;
        assert sim_done = '1' report "TB: timeout" severity failure;
        wait;
    end process watchdog_proc;

end architecture sim;
