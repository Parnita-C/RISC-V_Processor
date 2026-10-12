IV  = iverilog -g2012 -I rtl
SRC = $(wildcard rtl/*.sv) tb/tb.sv

all: sim
	vvp sim

sim: $(SRC) rtl/defs.vh
	$(IV) -o sim $(SRC) 2>&1 | grep -v "sorry" ; test -f sim

wave: all
	gtkwave wave.vcd

clean:
	rm -f sim wave.vcd
