GHDL      ?= ghdl
YOSYS     ?= yosys
BUILD     := build
GHDLFLAGS := --std=93 --workdir=$(BUILD)
TOP       ?= spi_port

RTL_SRCS  := rtl/spi_master.vhdl rtl/spi_slave.vhdl rtl/spi_port.vhdl

.PHONY: all check synth clean

all: check

$(BUILD):
	mkdir -p $@

check: | $(BUILD)
	$(GHDL) -a $(GHDLFLAGS) $(RTL_SRCS)
	$(GHDL) -e $(GHDLFLAGS) $(TOP)

synth: $(RTL_SRCS) | $(BUILD)
	$(YOSYS) -m ghdl -q -l $(BUILD)/synth_$(TOP).log \
	  -p "ghdl --std=93 $(RTL_SRCS) -e $(TOP); \
	      synth -top $(TOP); \
	      write_verilog -noattr $(BUILD)/$(TOP).v; \
	      tee -q -o $(BUILD)/synth_$(TOP).stat stat"
	@sed -n '/=== $(TOP) ===/,$$p' $(BUILD)/synth_$(TOP).stat

clean:
	rm -rf $(BUILD) spi_master spi_slave spi_port *.o
