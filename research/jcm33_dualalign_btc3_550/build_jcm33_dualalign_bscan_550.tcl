set script_dir [file dirname [file normalize [info script]]]
set build_dir [file normalize [file join $script_dir build]]
set output_dir [file normalize [file join $script_dir output]]
set part xcvu33p-fsvh2104-2-e
set top miner_top_ii1_bscan_550

file mkdir $build_dir
file mkdir $output_dir
set_param general.maxThreads 8

create_project -force jcm33_dualalign_bscan_550 $build_dir -part $part

add_files [list \
    [file join $script_dir keccak_theta_parity.sv] \
    [file join $script_dir keccak_theta_apply_rhopi.sv] \
    [file join $script_dir keccak_chi.sv] \
    [file join $script_dir keccak_iota.sv] \
    [file join $script_dir keccak_f1600_ii1_pipeline.sv] \
    [file join $script_dir sha3t_ii1_pipeline.sv] \
    [file join $script_dir sha3t_ii1_miner_engine.sv] \
    [file join $script_dir fk33_bscan_transport.sv] \
    [file join $script_dir miner_top_ii1_bscan_550.sv] \
]

set_property file_type SystemVerilog [get_files *.sv]
add_files -fileset constrs_1 [file join $script_dir fk33_bscan_550.xdc]
set_property top $top [current_fileset]
update_compile_order -fileset sources_1

puts "============================================================"
puts "BEGIN JCM33 DUAL-ALIGN II1 BSCAN 550 MHZ SYNTHESIS"
puts "============================================================"

launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTHESIS STATUS: $synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis failed"
}

set impl_strategy Performance_ExplorePostRoutePhysOpt
set supported_strategies [list_property_value strategy [get_runs impl_1]]
if {[lsearch -exact $supported_strategies $impl_strategy] < 0} {
    error "Required implementation strategy is unavailable: $impl_strategy"
}
set_property strategy $impl_strategy [get_runs impl_1]
puts "IMPLEMENTATION STRATEGY: $impl_strategy"

# Run through write_bitstream so the selected strategy's post-route
# phys_opt_design stage is not skipped.  A separately named, explicitly
# uncompressed candidate is written after timing qualification below.
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPLEMENTATION STATUS: $impl_status"
if {![string match "*Complete*" $impl_status]} {
    error "Implementation failed"
}

open_run impl_1

report_route_status \
    -file [file join $output_dir route_status.rpt]
report_timing_summary \
    -delay_type min_max \
    -max_paths 50 \
    -file [file join $output_dir timing_routed.rpt]
report_utilization \
    -hierarchical \
    -hierarchical_depth 4 \
    -file [file join $output_dir utilization_hier_routed.rpt]
report_utilization \
    -file [file join $output_dir utilization_routed.rpt]
report_design_analysis \
    -congestion \
    -file [file join $output_dir congestion_routed.rpt]

set setup_paths [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_paths [get_timing_paths -quiet -delay_type min -max_paths 1]

if {[llength $setup_paths] != 1 || [llength $hold_paths] != 1} {
    error "Timing gate could not obtain setup and hold paths"
}

set setup_slack [get_property SLACK [lindex $setup_paths 0]]
set hold_slack [get_property SLACK [lindex $hold_paths 0]]

puts "FINAL SETUP WNS: $setup_slack ns"
puts "FINAL HOLD  WHS: $hold_slack ns"

if {$setup_slack < 0.0} {
    error "TIMING GATE FAILED: negative setup slack"
}
if {$hold_slack < 0.0} {
    error "TIMING GATE FAILED: negative hold slack"
}

puts "TIMING GATE PASS"

write_checkpoint -force \
    [file join $output_dir jcm33_dualalign_bscan_550_routed.dcp]

# The legacy SQRL raw-JTAG bridge requires an uncompressed image.  Set the
# property on the open routed design and explicitly generate the final file;
# do not copy an implementation-run bitstream created before this setting.
set_property BITSTREAM.GENERAL.COMPRESS FALSE [current_design]
set output_bit [file join $output_dir jcm33_dualalign_bscan_550.bit]
write_bitstream -force $output_bit

puts "============================================================"
puts "JCM33 DUAL-ALIGN II1 BSCAN 550 MHZ FULL BUILD COMPLETE"
puts "BITSTREAM: $output_bit"
puts "============================================================"

close_design
close_project
exit
