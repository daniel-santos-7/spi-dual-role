# spi

VHDL-93 SPI master and slave with byte interfaces, plus a port that shares one set of pins between them.

- SPI mode 0, MSB first, 8-bit transfers
- Master: SCK from a clock divider, ready/valid transmit, frame end marked by `tx_last`
- Slave: oversampled by the system clock (no second clock domain), ready/valid transmit with a one-byte buffer
- Port: one pin set, master or slave chosen by a strap input
- No tri-state: every pin is `_i`, `_o` and `_oe`

## Structure

```
rtl/spi_master.vhdl   master
rtl/spi_slave.vhdl    slave
rtl/spi_port.vhdl     master + slave on shared pins
Makefile              GHDL analysis and Yosys synthesis
```

`make check` analyses and elaborates the design with GHDL (`TOP=spi_master`, `spi_slave` or `spi_port`, default `spi_port`). `make synth` runs a generic Yosys synthesis of `TOP` with the GHDL plugin and prints the cell count.

## spi_master

| Generic | Default | Meaning |
|---------|---------|---------|
| `SCK_DIV` | 1 | SCK half-period in system cycles; SCK = clk / (2·`SCK_DIV`) |
| `CS_HIGH_CYCLES` | 2 | Minimum `CS#` high time between two frames, in system cycles (at least 2) |

SCK idles low, `CS#` falls together with the first MOSI bit, MOSI changes on SCK falling edges, and MISO is sampled in the system cycle in which SCK rises. SCK, MOSI and `CS#` all come straight from flip-flops.

- **Transmit:** a byte is taken when `tx_valid_i` and `tx_ready_o` are both high. `tx_last_i`, sampled with it, marks the last byte of the frame: `CS#` rises after it. `tx_ready_o` is high when the master can start a frame (idle and the `CS#` hold over) and, inside a frame, in the cycle of the falling edge that ends a byte, so a byte already offered goes out with no gap. If none is offered then, SCK stops low with `CS#` still low until one is.
- **Receive:** every byte clocked in comes out on `rx_data_o` with a one-cycle `rx_valid_o`. For the last byte of a frame, `rx_valid_o` is high in the first cycle with `CS#` high. There is no `ready`.

A frame of *n* bytes with no gaps takes `16·n·SCK_DIV` cycles with `CS#` low.

The master knows nothing about commands: the client decides the bytes and where the frame ends. A flash read, for example, is `03h`, three address bytes and as many dummy bytes as data bytes wanted, the last one marked `tx_last`; the data comes back on `rx_data_o` during the dummies.

## spi_slave

SCK, `CS#` and MOSI pass through two-flip-flop synchronisers, so the slave runs entirely in the system clock domain. SCK must stay at least 5 system cycles high and 5 low (SCK ≤ clk/10), which leaves time for MISO to update after a falling edge. MOSI is sampled on the SCK rising edge and MISO changes on the falling edge.

- **Receive:** `rx_data_o` with a one-cycle `rx_valid_o` per received byte. There is no `ready`, because SPI cannot be held back: the consumer must take the byte in that cycle.
- **Transmit:** ready/valid. A byte moves when `tx_valid_i` and `tx_ready_o` are both high, and `tx_data_i` must stay stable while `tx_valid_i` waits. The slave has a one-byte buffer, and `tx_ready_o` is high while it is empty. On the falling edge that ends a byte, the buffer goes to the shift register and empties. A byte offered in that very cycle to an empty buffer goes straight to the shift register. If nothing was offered by then, the next byte on MISO is `0x00`. The first byte of every frame is always `0x00`, since nothing is loaded before the first falling edge.
- **Frame:** `active_o` is high while the synchronised `CS#` is low. Raising `CS#` resets the bit counter and empties the buffer.

The byte for position *k* of a frame can only be offered once byte *k−1* has been received, and it must be in before the falling edge that follows: at least 5 system cycles later at the maximum SCK.

## spi_port

`spi_port` holds one `spi_master`, one `spi_slave` and the pin logic. The generics are passed to the master. The input `dbg_i` picks the role:

| `dbg_i` | Role | SCK, `CS#`, MOSI | MISO |
|---------|------|------------------|------|
| 0 | master | driven (`_oe` = 1) | input |
| 1 | slave | inputs | driven while `CS#` is low, released otherwise |

`dbg_i` goes through a two-flip-flop synchroniser, and `dbg_o` gives the synchronised value back to the client. It is a strap, not a run-time switch: change it only while the master is idle. While it is 1, the master's `tx_valid` is gated off, so no frame starts. While it is 0, the slave sees `CS#` as high, so master traffic never reaches it. The master byte interface has the `m_` prefix and the slave's the `s_` prefix.

## License

MIT
