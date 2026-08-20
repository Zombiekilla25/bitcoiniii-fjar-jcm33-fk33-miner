set placed [glob -nocomplain \
    ./bc3_80pipe_token3_350_margin/bc3_80pipe_token3_350_margin.runs/impl_1/*_placed.dcp]

if {[llength $placed] == 0} {
    error "NO PLACED DCP FOUND"
}

set placed_dcp [lindex $placed 0]

puts "============================================================"
puts "OPENING PLACED DCP"
puts "$placed_dcp"
puts "============================================================"

open_checkpoint $placed_dcp

# ------------------------------------------------------------
# Physical optimization
# ------------------------------------------------------------
puts "============================================================"
puts "BEGIN PHYS_OPT_DESIGN -- THIS MAY TAKE A WHILE"
puts "============================================================"

phys_opt_design -directive AggressiveExplore

write_checkpoint -force \
    bc3_80pipe_token3_350_margin_physopt.dcp

report_timing_summary \
    -delay_type min_max \
    -max_paths 30 \
    -file token3_80pipe_350_margin_timing_physopt.rpt

set psetup [lindex [get_timing_paths -delay_type max -max_paths 1] 0]
if {[llength $psetup] != 0} {
    puts "POST-PHYS SETUP WNS: [get_property SLACK $psetup] ns"
}

puts "============================================================"
puts "BEGIN ROUTE_DESIGN -- THIS IS THE HOURS-LONG PART"
puts "============================================================"

route_design -directive Explore

puts "============================================================"
puts "ROUTE_DESIGN COMPLETE"
puts "============================================================"

write_checkpoint -force \
    bc3_80pipe_token3_350_margin_routed.dcp

report_utilization \
    -file token3_80pipe_350_margin_utilization_routed.rpt

report_utilization \
    -hierarchical \
    -hierarchical_depth 2 \
    -file token3_80pipe_350_margin_utilization_hier_routed.rpt

report_timing_summary \
    -delay_type min_max \
    -max_paths 50 \
    -file token3_80pipe_350_margin_timing_routed.rpt

report_route_status \
    -file token3_80pipe_350_margin_route_status.rpt

# ------------------------------------------------------------
# Final timing gate
# ------------------------------------------------------------
set setup_path [lindex \
    [get_timing_paths -delay_type max -max_paths 1] 0]

set hold_path [lindex \
    [get_timing_paths -delay_type min -max_paths 1] 0]

set setup_slack [get_property SLACK $setup_path]
set hold_slack  [get_property SLACK $hold_path]

puts "============================================================"
puts "FINAL SETUP WNS: $setup_slack ns"
puts "FINAL HOLD  WHS: $hold_slack ns"
puts "============================================================"

if {$setup_slack < 0.0} {
    puts "TIMING GATE FAILED: NEGATIVE SETUP SLACK"
    puts "BITSTREAM WILL NOT BE GENERATED"
    exit 2
}

if {$hold_slack < 0.0} {
    puts "TIMING GATE FAILED: NEGATIVE HOLD SLACK"
    puts "BITSTREAM WILL NOT BE GENERATED"
    exit 3
}

puts "============================================================"
puts "TIMING GATE PASSED"
puts "GENERATING BITSTREAM"
puts "============================================================"

write_bitstream -force \
    bc3_80pipe_token3_350_margin.bit

write_debug_probes -force \
    bc3_80pipe_token3_350_margin.ltx

puts "============================================================"
puts "BITSTREAM GENERATION COMPLETE"
puts "BC3 80-PIPE TOKEN3 350-MHZ MARGIN BUILD COMPLETE"
puts "============================================================"

close_design
exit
