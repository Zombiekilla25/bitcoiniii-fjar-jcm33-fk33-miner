set PART xcvu33p-fsvh2104-2-e
set TOP miner_top_80pipe_token3_350_margin
set PROJECT fk33_fjar_bscan_350

create_project -force $PROJECT ./$PROJECT -part $PART

add_files [list \
    ./keccak_theta_parity.sv \
    ./keccak_theta_apply_rhopi.sv \
    ./keccak_chi.sv \
    ./keccak_iota.sv \
    ./sha3t_token4_core.sv \
    ./fk33_bscan_transport.sv \
    ./miner_top_80pipe_token3_350_margin.sv \
]

set_property file_type SystemVerilog [get_files *.sv]
add_files -fileset constrs_1 ./fk33_token350.xdc
set_property top $TOP [current_fileset]
update_compile_order -fileset sources_1

puts "============================================================"
puts "BEGIN FK33 FJAR BSCAN 350-MHZ BUILD"
puts "============================================================"

launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTHESIS STATUS: $synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis failed"
}

launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPLEMENTATION STATUS: $impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "Implementation or bitstream generation failed"
}

open_run impl_1
report_route_status -file ./fk33_fjar_bscan_350_route_status.rpt
report_timing_summary -delay_type max -max_paths 20 \
    -file ./fk33_fjar_bscan_350_timing.rpt
report_utilization -file ./fk33_fjar_bscan_350_utilization.rpt

# Compatibility with the validated legacy SQRL raw-JTAG loader.
set_property BITSTREAM.GENERAL.COMPRESS FALSE [current_design]

set impl_dir [get_property DIRECTORY [get_runs impl_1]]
set source_bit [file join $impl_dir ${TOP}.bit]
if {$source_bit eq "" || ![file exists $source_bit]} {
    error "Vivado did not report a generated bitstream"
}

file copy -force $source_bit ./fk33_fjar_bscan_350.bit
puts "BITSTREAM: [file normalize ./fk33_fjar_bscan_350.bit]"
puts "FK33 FJAR BSCAN BUILD COMPLETE"

close_design
close_project
exit
