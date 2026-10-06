# spi-dual-role

Dual-role SPI in VHDL-93: a master and a slave that each move one word per frame through the same shift core, plus a port that runs either one on the same set of pins.

- SPI mode 0, MSB first
- Shift core (`spi_shift`): one word each way per frame, loaded when `CS#` falls and reported when it rises, driven by edge strobes
- Master: generates SCK and `CS#` and runs one `WIDTH`-bit frame (default 64) per `start`
- Slave: detects the edges of an external SCK and `CS#`, words of up to `WIDTH` bits (default 32); oversampled by the system clock (no second clock domain)
- Port: one pin set, master or slave chosen by a strap input
- No tri-state: every pin is `_i`, `_o` and `_oe`

## Structure

```
rtl/bit_sync.vhdl     single-bit synchroniser (flip-flop chain)
rtl/spi_sync.vhdl     spi_port input synchronisers
rtl/spi_shift.vhdl    shift core shared by master and slave
rtl/spi_master.vhdl   master
rtl/spi_slave.vhdl    slave
rtl/spi_port.vhdl     master + slave on shared pins
tbs/tb_spi_port.vhdl  self-checking testbench: two ports on one bus
Makefile              GHDL analysis, simulation and Yosys synthesis
```

`make check` analyses and elaborates the design with GHDL (`TOP=spi_master`, `spi_slave` or `spi_port`, default `spi_port`). `make synth` runs a generic Yosys synthesis of `TOP` with the GHDL plugin and prints the cell count.

`make sim` runs the testbench, which wires two `spi_port` instances to one modelled bus (pull resistors, no tri-state inside the design), runs random frames with one as master and the other as slave, then swaps the roles. Every frame is `M_WIDTH` bits (testbench default 48) against a 32-bit slave word. It checks the word and bit count the slave reports once per frame, the word the master receives, frame boundaries and length, SCK and `CS#` timing, back-to-back frames, pad contention and that the unused role in each port stays silent. It stops at the first error and prints `PASS` at the end. `make test` runs it three times, with `M_WIDTH` = 16, 32 and 48, so frames shorter than, equal to and longer than the slave word. Generics go in `GENERICS`, e.g. `make sim GENERICS="-gSCK_DIV=7 -gCS_HIGH_CYCLES=4 -gSEED=3 -gNUM_FRAMES=200"` (`SCK_DIV` at least 5, because the slave needs SCK ≤ clk/10). `make wave` does the same and writes `build/tb_spi_port.ghw`.

## spi_shift

| Generic | Default | Meaning |
|---------|---------|---------|
| `WIDTH` | 32 | Word size in bits (at least 2) |
| `CNT_BITS` | 6 | Width of `rx_bits_o`; 2^`CNT_BITS` must exceed `WIDTH` |

The part master and slave share: a transmit and a receive shift register and a bit counter, moved by four one-cycle strobes. It does not know which side of the link it is on.

- `start_i` (`CS#` falls): loads `tx_data_i` into the transmit register and clears the receive register and the count.
- `rise_i` (SCK rises): shifts `din_i` into the receive register and counts the bit, up to `WIDTH` bits; later bits are ignored.
- `fall_i` (SCK falls): shifts the transmit register, so `dout_o` (its MSB) shows the next bit, and zeros after the `WIDTH`-th.
- `stop_i` (`CS#` rises): comes out as `rx_valid_o`, with the word right-aligned on `rx_data_o` and the count on `rx_bits_o`.

## spi_master

| Generic | Default | Meaning |
|---------|---------|---------|
| `SCK_DIV` | 1 | SCK half-period in system cycles; SCK = clk / (2·`SCK_DIV`) |
| `CS_HIGH_CYCLES` | 2 | Minimum `CS#` high time between two frames, in system cycles (at least 2) |
| `WIDTH` | 64 | Frame length in bits |
| `CNT_BITS` | 7 | Width of the shift core's bit count; 2^`CNT_BITS` must exceed `WIDTH` |

The master generates SCK and `CS#` and drives an `spi_shift` with strobes timed to its own clock, so no edge detection is involved. SCK idles low, `CS#` falls together with the first MOSI bit, MOSI changes on SCK falling edges, and MISO is sampled in the system cycle in which SCK rises. SCK, MOSI and `CS#` all come straight from flip-flops.

- **Start:** a frame starts when `start_i` and `ready_o` are both high; `tx_data_i` is loaded in that cycle and goes out MSB first. `ready_o` is high while the master is idle and the `CS#` hold is over.
- **Frame:** always `WIDTH` bits, with no gaps: `2·WIDTH·SCK_DIV` cycles with `CS#` low. `CS#` rises on the falling edge that ends the last bit.
- **Receive:** `rx_valid_o` pulses in the first cycle with `CS#` high, with the `WIDTH` bits received on `rx_data_o` (the first bit in the MSB).

The master knows nothing about commands. A flash read of one 32-bit word, for example, is a 64-bit frame of `03h`, the 24-bit address and 32 zeros; the data is in the low 32 bits of `rx_data_o`, the byte at the lowest address in `31 downto 24`.

## spi_slave

| Generic | Default | Meaning |
|---------|---------|---------|
| `WIDTH` | 32 | Word size in bits (at least 2) |
| `CNT_BITS` | 6 | Width of `rx_bits_o`; 2^`CNT_BITS` must exceed `WIDTH` |

The slave detects the edges of SCK and `CS#` and turns them into the `spi_shift` strobes. It runs entirely in the system clock domain: its SCK, `CS#` and MOSI inputs must already be synchronised to `clk`, which `spi_port` does with two-flip-flop synchronisers (`bit_sync`). SCK must stay at least 5 system cycles high and 5 low (SCK ≤ clk/10), which leaves time for MISO to update after a falling edge. MOSI is sampled on the SCK rising edge and MISO changes on the falling edge.

A frame (one `CS#` low) carries one word in each direction:

- **Receive:** the bits shift into a `WIDTH`-bit register, cleared when `CS#` falls. When `CS#` rises, `rx_valid_o` pulses for one cycle, with `rx_data_o` holding the word and `rx_bits_o` the number of bits (unsigned, `CNT_BITS` wide). The word is right-aligned: a frame of *n* < `WIDTH` bits leaves its bits in `n-1 downto 0` and zeros above. The register stops at `WIDTH` bits: in a longer frame `rx_data_o` holds the first `WIDTH` bits, `rx_bits_o` reads `WIDTH`, and the rest is ignored. Both outputs stay valid until the next frame starts. Every frame reports once, even one with no SCK edge, which comes out with `rx_bits_o` = 0. There is no `ready`: the client must take the word in that cycle.
- **Transmit:** `tx_data_i` is loaded into the shift register when `CS#` falls and goes out MSB first, so the host gets the first *n* bits of the word in a frame of *n* bits, and zeros after the `WIDTH`-th bit. The client keeps the next reply on `tx_data_i` between frames; there is no handshake.

The slave sees `CS#` through the synchroniser, so the edges are detected two to three cycles late. The host must keep at least 5 system cycles between `CS#` falling and the first SCK rise, so that the first bit is on MISO in time. The reply for the next frame must be on `tx_data_i` by the cycle in which the slave sees `CS#` fall: a client that updates it after `rx_valid_o` has two cycles when the host keeps `CS#` high for only two cycles, and the host's `CS#` high time beyond that is extra margin.

The slave knows nothing about commands: what the words mean, and whether a frame of the wrong length is used or dropped, is up to the client.

## spi_port

`spi_port` holds one `spi_master`, one `spi_slave` and the pin logic. `SCK_DIV`, `CS_HIGH_CYCLES`, `M_WIDTH` (default 64) and `M_CNT_BITS` (default 7) go to the master, `S_WIDTH` (default 32) and `S_CNT_BITS` (default 6) to the slave, as `WIDTH` and `CNT_BITS`. The input `dbg_i` picks the role:

| `dbg_i` | Role | SCK, `CS#`, MOSI | MISO |
|---------|------|------------------|------|
| 0 | master | driven (`_oe` = 1) | input |
| 1 | slave | inputs | driven while `CS#` is low, released otherwise |

Every asynchronous input goes through a two-flip-flop synchroniser (`bit_sync`), all grouped in `spi_sync`: `dbg_i`, and SCK, `CS#` and MOSI on the way to the slave. The master needs none, since it only samples MISO at its own SCK edge. `dbg_o` gives the synchronised strap back to the client. It is a strap, not a run-time switch: change it only while the master is idle. While it is 1, the master's `start` is gated off, so no frame starts. While it is 0, the slave sees `CS#` as high, so master traffic never reaches it. The master interface has the `m_` prefix and the slave's the `s_` prefix.

## License

MIT
