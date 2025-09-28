# design files
vlog -work work ../rtl/tt_um_FG_TOP_Dominik_Brandstetter.v
vlog -work work FG_TOP_Dominik_Brandstetter_tb.v

vsim -t 1ps work.FG_TOP_Dominik_Brandstetter_tb

do wave.do
run 10ms