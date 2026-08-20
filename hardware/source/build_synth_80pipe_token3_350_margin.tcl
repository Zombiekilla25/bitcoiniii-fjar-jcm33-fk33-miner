set PART xcvu33p-fsvh2104-2-e

create_project -force \
    bc3_80pipe_token3_350_margin \
    ./bc3_80pipe_token3_350_margin \
    -part $PART

add_files [list \
    ./keccak_theta_parity.sv \
    ./keccak_theta_apply_rhopi.sv \
    ./keccak_chi.sv \
    ./keccak_iota.sv \
    ./sha3t_token4_core.sv \
    ./miner_top_80pipe_token3_350_margin.sv \
]

set_property file_type SystemVerilog [get_files *.sv]

add_files -fileset constrs_1 ./fk33_token350.xdc

set_property top \
    miner_top_80pipe_token3_350_margin \
    [current_fileset]

# Real VIO IP — same definition as validated 350 build.
create_ip \
    -name vio \
    -vendor xilinx.com \
    -library ip \
    -module_name vio_0

set_property -dict [list \
    CONFIG.C_NUM_PROBE_IN {3} \
    CONFIG.C_NUM_PROBE_OUT {5} \
    CONFIG.C_PROBE_IN0_WIDTH {41} \
    CONFIG.C_PROBE_IN1_WIDTH {256} \
    CONFIG.C_PROBE_IN2_WIDTH {32} \
    CONFIG.C_PROBE_OUT0_WIDTH {256} \
    CONFIG.C_PROBE_OUT1_WIDTH {256} \
    CONFIG.C_PROBE_OUT2_WIDTH {96} \
    CONFIG.C_PROBE_OUT3_WIDTH {256} \
    CONFIG.C_PROBE_OUT4_WIDTH {10} \
] [get_ips vio_0]

generate_target all [get_ips vio_0]

update_compile_order -fileset sources_1

puts "============================================================"
puts "BEGIN TOKEN3 80-PIPE 350-MHZ MARGIN SYNTHESIS"
puts "============================================================"

launch_runs synth_1 -jobs 8
wait_on_run synth_1

set ss [get_property STATUS [get_runs synth_1]]
puts "SYNTHESIS STATUS: $ss"

if {![string match "*Complete*" $ss]} {
    error "Synthesis failed"
}

open_run synth_1

report_utilization \
    -file token3_80pipe_350_margin_utilization_synth.rpt

report_utilization \
    -hierarchical \
    -hierarchical_depth 2 \
    -file token3_80pipe_350_margin_utilization_hier_synth.rpt

report_timing_summary \
    -delay_type max \
    -max_paths 20 \
    -file token3_80pipe_350_margin_timing_synth.rpt

puts "============================================================"
puts "TOKEN3 80-PIPE 350-MHZ MARGIN SYNTHESIS COMPLETE"
puts "============================================================"

close_design
close_project
exit
