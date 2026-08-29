set script_dir [file dirname [file normalize [info script]]]
set build_dir [file normalize [file join $script_dir build]]
set output_dir [file normalize [file join $script_dir output]]
set part xcvu33p-fsvh2104-2-e
set top miner_top_ii1_bscan_650

file mkdir $build_dir
file mkdir $output_dir
set_param general.maxThreads 8

create_project -force jcm33_dualalign_bscan_650 $build_dir -part $part

add_files [list \
    [file join $script_dir keccak_theta_parity.sv] \
    [file join $script_dir keccak_theta_apply_rhopi.sv] \
    [file join $script_dir keccak_chi.sv] \
    [file join $script_dir keccak_iota.sv] \
    [file join $script_dir keccak_f1600_ii1_pipeline.sv] \
    [file join $script_dir sha3t_ii1_pipeline.sv] \
    [file join $script_dir sha3t_ii1_miner_engine.sv] \
    [file join $script_dir fk33_bscan_transport.sv] \
    [file join $script_dir miner_top_ii1_bscan_650.sv] \
]

set_property file_type SystemVerilog [get_files *.sv]
add_files -fileset constrs_1 [file join $script_dir fk33_bscan_650.xdc]
set_property top $top [current_fileset]
update_compile_order -fileset sources_1

puts "============================================================"
puts "BEGIN JCM33 DUAL-ALIGN II1 BSCAN 650 MHZ SYNTHESIS"
puts "============================================================"

launch_runs synth_1 -jobs 8
wait_on_run synth_1

set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTHESIS STATUS: $synth_status"
if {![string match "*Complete*" $synth_status]} {
    error "Synthesis failed"
}

# Start with the strategy that closed timing at 575 MHz, then run every
# supported fallback. The measured 575 MHz setup margin predicts that 650
# MHz is near the route boundary, so an early stop is intentionally forbidden.
# Every implementation attempt starts from the same synthesis result.
set preferred_strategies [list \
    Performance_ExplorePostRoutePhysOpt \
    Performance_NetDelay_high \
    Performance_NetDelay_low \
    Performance_ExtraTimingOpt \
    Performance_Retiming \
    Performance_Explore \
]
set supported_strategies [list_property_value strategy [get_runs impl_1]]
set strategies [list]
foreach strategy $preferred_strategies {
    if {[lsearch -exact $supported_strategies $strategy] >= 0} {
        lappend strategies $strategy
    } else {
        puts "SKIP UNSUPPORTED STRATEGY: $strategy"
    }
}
if {[llength $strategies] == 0} {
    error "None of the required exhaustive implementation strategies is available"
}

set summary_path [file join $output_dir route-sweep-summary.tsv]
set summary_fh [open $summary_path w]
puts $summary_fh "candidate\tstrategy\tstatus\tsetup_wns_ns\thold_whs_ns"
flush $summary_fh

set best_score -999999.0
set best_setup -999999.0
set best_hold -999999.0
set best_strategy ""
set best_bit ""
set best_dcp ""
set candidate_index 0

foreach strategy $strategies {
    set candidate_name [format "route_%02d_%s" $candidate_index $strategy]
    set candidate_dir [file join $output_dir $candidate_name]
    file mkdir $candidate_dir

    if {$candidate_index > 0} {
        reset_run impl_1
    }
    set_property strategy $strategy [get_runs impl_1]

    puts "============================================================"
    puts "BEGIN ROUTE CANDIDATE: $candidate_name"
    puts "IMPLEMENTATION STRATEGY: $strategy"
    puts "============================================================"

    # Running through write_bitstream is required to execute strategies whose
    # final post-route physical-optimization step follows routing.
    launch_runs impl_1 -to_step write_bitstream -jobs 8
    wait_on_run impl_1

    set impl_status [get_property STATUS [get_runs impl_1]]
    puts "CANDIDATE STATUS: $candidate_name $impl_status"
    if {![string match "*Complete*" $impl_status]} {
        puts $summary_fh "$candidate_name\t$strategy\timplementation_failed\tNA\tNA"
        flush $summary_fh
        incr candidate_index
        continue
    }

    open_run impl_1

    report_route_status \
        -file [file join $candidate_dir route_status.rpt]
    report_timing_summary \
        -delay_type min_max \
        -max_paths 50 \
        -file [file join $candidate_dir timing_routed.rpt]
    report_utilization \
        -hierarchical \
        -hierarchical_depth 4 \
        -file [file join $candidate_dir utilization_hier_routed.rpt]
    report_utilization \
        -file [file join $candidate_dir utilization_routed.rpt]
    report_design_analysis \
        -congestion \
        -file [file join $candidate_dir congestion_routed.rpt]
    report_drc \
        -file [file join $candidate_dir drc_routed.rpt]

    set setup_paths [get_timing_paths -quiet -delay_type max -max_paths 1]
    set hold_paths [get_timing_paths -quiet -delay_type min -max_paths 1]
    if {[llength $setup_paths] != 1 || [llength $hold_paths] != 1} {
        puts $summary_fh "$candidate_name\t$strategy\tmissing_timing_path\tNA\tNA"
        flush $summary_fh
        close_design
        incr candidate_index
        continue
    }

    set setup_slack [get_property SLACK [lindex $setup_paths 0]]
    set hold_slack [get_property SLACK [lindex $hold_paths 0]]
    puts "CANDIDATE SETUP WNS: $candidate_name $setup_slack ns"
    puts "CANDIDATE HOLD  WHS: $candidate_name $hold_slack ns"

    if {$setup_slack < 0.0 || $hold_slack < 0.0} {
        puts "CANDIDATE TIMING FAIL: $candidate_name"
        puts $summary_fh "$candidate_name\t$strategy\ttiming_failed\t$setup_slack\t$hold_slack"
        flush $summary_fh
        close_design
        incr candidate_index
        continue
    }

    set candidate_dcp [file join $candidate_dir jcm33_dualalign_bscan_650_routed.dcp]
    set candidate_bit [file join $candidate_dir jcm33_dualalign_bscan_650.bit]
    write_checkpoint -force $candidate_dcp

    # The legacy SQRL raw-JTAG bridge requires an explicitly uncompressed
    # image. Failure here (including a blocking DRC error) disqualifies the
    # route even when its timing numbers are positive.
    set_property BITSTREAM.GENERAL.COMPRESS FALSE [current_design]
    if {[catch {write_bitstream -force $candidate_bit} bit_error]} {
        puts "CANDIDATE BITSTREAM FAIL: $candidate_name $bit_error"
        puts $summary_fh "$candidate_name\t$strategy\tbitstream_failed\t$setup_slack\t$hold_slack"
        flush $summary_fh
        close_design
        incr candidate_index
        continue
    }

    puts "CANDIDATE TIMING PASS: $candidate_name"
    puts $summary_fh "$candidate_name\t$strategy\tqualified\t$setup_slack\t$hold_slack"
    flush $summary_fh

    set candidate_score [expr {min($setup_slack, $hold_slack)}]
    if {$candidate_score > $best_score} {
        set best_score $candidate_score
        set best_setup $setup_slack
        set best_hold $hold_slack
        set best_strategy $strategy
        set best_bit $candidate_bit
        set best_dcp $candidate_dcp
    }

    close_design
    puts "EXHAUSTIVE ROUTE CONTINUE: remaining supported strategies will run"
    incr candidate_index
}

close $summary_fh

if {$best_strategy eq "" || $best_bit eq "" || $best_dcp eq ""} {
    error "TIMING GATE FAILED: no 650 MHz route had nonnegative setup and hold slack with a valid bitstream"
}

set output_bit [file join $output_dir jcm33_dualalign_bscan_650.bit]
set output_dcp [file join $output_dir jcm33_dualalign_bscan_650_routed.dcp]
file copy -force $best_bit $output_bit
file copy -force $best_dcp $output_dcp

puts "SELECTED IMPLEMENTATION STRATEGY: $best_strategy"
puts "FINAL SETUP WNS: $best_setup ns"
puts "FINAL HOLD  WHS: $best_hold ns"
puts "TIMING GATE PASS"
puts "============================================================"
puts "JCM33 DUAL-ALIGN II1 BSCAN 650 MHZ FULL BUILD COMPLETE"
puts "BITSTREAM: $output_bit"
puts "ROUTE SUMMARY: $summary_path"
puts "============================================================"

close_project
exit
