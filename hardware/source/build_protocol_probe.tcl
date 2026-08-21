set PART xcvu33p-fsvh2104-2L-e
set TOP fk33_bscan_protocol_probe_top
set PROJECT fk33_bscan_protocol_probe

create_project -force $PROJECT ./$PROJECT -part $PART
add_files [list \
    ./fk33_bscan_transport.sv \
    ./fk33_bscan_protocol_probe_top.sv \
]
set_property file_type SystemVerilog [get_files *.sv]
add_files -fileset constrs_1 ./fk33_token350.xdc
set_property top $TOP [current_fileset]
update_compile_order -fileset sources_1

synth_design -top $TOP -part $PART
opt_design
place_design
route_design

report_route_status -file ./fk33_bscan_protocol_probe_route_status.rpt
report_drc -file ./fk33_bscan_protocol_probe_drc.rpt
write_checkpoint -force ./fk33_bscan_protocol_probe_routed.dcp

# The validated 2021 SQRL loader crashes while opening highly compressed
# UltraScale+ bitstreams.  Keep the standalone transport image uncompressed;
# this matches the 28 MB handshake image proven on physical FK33 hardware.
set_property BITSTREAM.GENERAL.COMPRESS FALSE [current_design]
write_bitstream -force ./fk33_bscan_protocol_probe.bit

puts "PROTOCOL PROBE: [file normalize ./fk33_bscan_protocol_probe.bit]"
puts "FK33 BSCAN PROTOCOL PROBE BUILD COMPLETE"
exit
