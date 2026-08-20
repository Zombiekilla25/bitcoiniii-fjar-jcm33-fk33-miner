open_project ./bc3_80pipe_token3_350_margin/bc3_80pipe_token3_350_margin.xpr

# Same placement directive used by the proven 350 build.
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE Explore [get_runs impl_1]

puts "============================================================"
puts "BEGIN TOKEN3 80-PIPE 350-MHZ MARGIN PLACE-ONLY RUN"
puts "============================================================"

launch_runs impl_1 -to_step place_design -jobs 8
wait_on_run impl_1

set st [get_property STATUS [get_runs impl_1]]
puts "PLACE STATUS: $st"

if {![string match "*Complete*" $st]} {
    error "Placement failed"
}

open_run impl_1

report_utilization \
    -file token3_80pipe_350_margin_utilization_place.rpt

report_utilization \
    -hierarchical \
    -hierarchical_depth 2 \
    -file token3_80pipe_350_margin_utilization_hier_place.rpt

report_timing_summary \
    -delay_type min_max \
    -max_paths 30 \
    -file token3_80pipe_350_margin_timing_place.rpt

puts "============================================================"
puts "TOKEN3 80-PIPE 350-MHZ MARGIN PLACE COMPLETE"
puts "============================================================"

close_design
close_project
exit
