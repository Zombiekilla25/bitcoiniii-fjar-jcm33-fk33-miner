set PART xcvu33p-fsvh2104-2-e

create_project -force \
    bc3_80pipe_token3_350_margin_elab \
    ./bc3_80pipe_token3_350_margin_elab \
    -part $PART

add_files [list \
    ./keccak_theta_parity.sv \
    ./keccak_theta_apply_rhopi.sv \
    ./keccak_chi.sv \
    ./keccak_iota.sv \
    ./sha3t_token4_core.sv \
    ./miner_top_80pipe_token3_350_margin.sv \
    ./vio_0_elab_stub.sv \
]

set_property file_type SystemVerilog [get_files *.sv]

set_property top miner_top_80pipe_token3_350_margin [current_fileset]

update_compile_order -fileset sources_1

puts "============================================================"
puts "BEGIN TOKEN3 / 80-PIPE / 350-MHZ MARGIN RTL ELABORATION"
puts "============================================================"

synth_design \
    -rtl \
    -top miner_top_80pipe_token3_350_margin \
    -part $PART

puts "============================================================"
puts "TOKEN3 80-PIPE 350-MHZ MARGIN RTL ELABORATION PASS"
puts "============================================================"

close_design
close_project
exit
